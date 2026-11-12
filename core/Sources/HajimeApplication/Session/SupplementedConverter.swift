import Foundation
import HajimeDomain

/// 変換エンジンの候補に，エンジンが出さない候補を足す．
///
/// - ユーザー辞書の語: 読みが一致すれば先頭に置く．登録した語は選びたい語なので．
///   エンジンにもユーザー辞書を渡している(文の中の語として使うため)が，エンジンは辞書の語の続きになる読みしか
///   たどらないので，辞書に無い読みの語は出ない．読み全体が一致する語はここで確実に出す(同じ語は重ねない)
/// - 記号(SymbolDictionary): 「やじるし」→「→」など
/// - 日付と時刻(DateExpressions): 「きょう」→「2026/10/26」など
/// - 数字の書き方(NumberForms): 「21」→「㉑」，「2026」→「二〇二六」など．読みが数字だけのとき
/// - 計算(Calculator): 「1+2*3=」→「7」「1+2*3=7」．結果を先頭に置く(式を打って「=」を打つのは計算したいときなので)
/// - よくある読み違い(Misreadings): 「ふいんき」→「雰囲気」を 2 番目に置く
/// - 送り仮名(Okurigana): 本則か許容の選んだ方を先に並べる
/// - LaTeX のコマンド(LatexCommands): 「らむだ」→「\lambda」．設定でオンにしたときだけ．記号と同じ位置に差し込む
/// - 郵便番号(PostalCode): 「100-0001」→「東京都千代田区千代田」．区切りがあれば先頭に，無ければ 2 番目に置く(7 桁の数字のこともあるので)
/// - ユーザー辞書のローマ字の読み(「gh」→ GitHub)と，入れるときに中身を決める語(TextTemplate．「にちじ」→ `{datetime:...}`)
///
/// 変換の一覧と分岐図の文節(listCandidates・segmentCandidates)にだけ足すもの．打っているあいだ(ライブ変換)には出さず，第 1 候補にもしない
/// - 絵文字(EmojiLooking．設定の「文節を絵文字に変換」「語を絵文字に変換」): 文節の読みと同じ読みの絵文字(「びーる」→ 🍺)と，
///   文節の先頭の語を絵文字にして付属語を付けたもの(「ねこが」→ 🐈が)．設定の位置(EmojiPlacement)にまとめて置く．
///   エンジンの辞書から来る絵文字を含む候補は，どこでも除く(位置が定まらず，学習で第 1 候補になり，OS が描けない絵文字も混じるため)．
///   確定した絵文字は，その読みで選んだことを覚える(EmojiLooking.didCommit)
/// - コマンド(LauncherCommand): 読みが一致すれば 2 番目に「▶ 名前」を置く．候補の窓では印の代わりにアイコンと札で見せる．選んで確定したときだけ動く(R-22)
/// - うろ覚えの語(LooseReadings): 「しゅみれーしょん」→「シミュレーション」
/// - 発音どおりに綴った英単語(PhoneticSpelling): 「ふぉと」→「photo」
///
/// - 英語の語の辞書の語(R-24．EnglishTerms): 「api」と打った読み「あぴ」→「API」，英字のまま確定させた「githubを使う」→「GitHubを使う」．
///   ローマ字として読めてしまった英語の語を英語で入れられるよう，読み全体がふつうの日本語の語(「そら」→ 空)でなければ第 1 候補にする．
///   ユーザー辞書と取り込んだ辞書の語(他の IME から取り込んだものを含む)よりは前に出さない
///
/// - 取り込んだ辞書の語(R-16): 読みの中の部分ごとに，効いている辞書から語を引いてエンジンに渡す(setAuxiliaryWords)．
///   どの辞書を効かせるかは DictionaryActivation が決める(アプリの条件，文脈の条件)
/// - 専門用語の辞書の語(R-29): 取り込んだ辞書と同じく，読みの中の部分ごとに，設定で使う分野の語を引いてエンジンに渡す．
///   点数は取り込んだ辞書の語より低く(DefaultSettings.termWordCost)，読みが通常の辞書の語と重なる語はさらに低くする(termOverlappingWordCost)．
///   同じ語が取り込んだ辞書にもあれば取り込んだ辞書の方を使う
///
/// 記号・日付・数字の書き方は上から DefaultSettings.symbolCandidateOffset 番目に差し込む．
/// 第 1 候補(ライブ変換で見える文字)は変えず，よく使う語より前に並ばないようにする
@MainActor
public final class SupplementedConverter: KanaKanjiConverting {
    private let base: any KanaKanjiConverting
    private let settings: any SettingsReading
    private let calendar: any CalendarReading
    private let postalCodes: (any PostalCodeLooking)?
    private let emoji: (any EmojiLooking)?
    /// 発音どおりに綴った英単語を確かめる英単語の辞書．無ければ探さない
    private let lexicon: (any EnglishLexicon)?
    /// 英語の語の辞書(R-24)．無ければ英語の語を足さない
    private let englishTerms: EnglishTerms?
    /// 読みごとに見つけたうろ覚えの語と英単語．入力を終えたときに捨てる
    private var listExtrasCache: [String: (loose: [String], phonetic: [String])] = [:]
    /// 候補に足した絵文字の候補の文字ごとに，絵文字と引いた読み．確定したときにどの読みで選んだかを知るため．入力を終えたときに捨てる
    private var emojiSources: [String: [EmojiSource]] = [:]
    /// 今の入力を終えるまで学ばない(suspendLearningUntilEnd)．選んだ絵文字も覚えない
    private var learningSuspended = false
    /// ユーザー辞書を読みで引く表．設定のユーザー辞書が変わったときだけ作り直す
    private var dictionaryIndex: (source: [UserDictionaryEntry], words: [String: [(word: String, comment: String)]]) = ([], [:])
    /// 取り込んだ辞書を引くもの．無ければ取り込んだ辞書は使わない
    private let lookup: (any DictionaryLookup)?
    /// 専門用語の辞書を引くもの．無ければ専門用語の辞書は使わない
    private let terms: (any TermDictionaryLookup)?
    private var applicationID: String?
    /// 最近確定した，取り込んだ辞書の語の辞書の id(新しいものが後ろ)．文脈の条件に使う
    private var recentDictionaryCommits: [String] = []
    /// 今エンジンに渡している語と，その語の辞書の名前
    private var auxiliary: [AuxiliaryWord] = []
    private var auxiliarySources: [DictionaryWord: Source] = [:]
    /// 読みごとに引いた語と，その語の辞書．効いている辞書か専門用語の分野が変わったときと，入力を終えたときに捨てる
    private var auxiliaryCache: (active: [DictionaryActivation.Active], fields: Set<TermField>, lookups: [String: Lookup]) = ([], [], [:])

    private struct Source {
        /// 取り込んだ辞書の id．専門用語の辞書なら nil(文脈の条件に数えない)
        var id: String?
        var name: String
        /// 読み全体と一致するときに，候補の前の方に差し込む位置．専門用語の辞書の，通常の辞書に同じ読みの語がある語は nil(差し込まない)
        var wholeReadingOffset: Int?
    }

    /// 絵文字の候補(「🐈が」)の元の絵文字(🐈)と，その絵文字を引いた読み(ねこ)
    private struct EmojiSource: Equatable {
        var emoji: String
        var reading: String
        /// 候補の読みの長さ(「ねこが」なら 3)
        var readingCount: Int
    }

    private struct Lookup {
        var words: [AuxiliaryWord]
        var sources: [DictionaryWord: Source]
    }

    public init(_ base: any KanaKanjiConverting, settings: any SettingsReading, calendar: any CalendarReading,
                postalCodes: (any PostalCodeLooking)? = nil, dictionaries: (any DictionaryLookup)? = nil, terms: (any TermDictionaryLookup)? = nil,
                emoji: (any EmojiLooking)? = nil, lexicon: (any EnglishLexicon)? = nil, englishTerms: EnglishTerms? = nil) {
        self.base = base
        self.terms = terms
        self.lexicon = lexicon
        self.englishTerms = englishTerms
        self.settings = settings
        self.calendar = calendar
        self.postalCodes = postalCodes
        self.emoji = emoji
        self.lookup = dictionaries
    }

    public func candidates(for reading: String) -> [Candidate] {
        prepareAuxiliaryWords(for: reading)
        return supplement(base.candidates(for: reading), reading: reading)
    }

    public func clauseCandidates(for reading: String) -> [Candidate] {
        prepareAuxiliaryWords(for: reading)
        // 文節の候補は読みの先頭の一部なので，足す候補は読み全体と一致するときだけ足す
        return supplement(base.clauseCandidates(for: reading), reading: reading)
    }

    /// 文節の読みは文全体の読みの一部で，取り込んだ辞書の語は文全体の読みの部分ごとに引いてあるので，引き直さない．
    /// 引き直すとエンジンに渡す語が入れ替わり，ライブ変換の変換の状態が捨てられて遅くなる
    public func segmentCandidates(for reading: String) -> [Candidate] {
        supplement(base.segmentCandidates(for: reading), reading: reading, forList: true)
    }

    public func listCandidates(for reading: String) -> [Candidate] {
        prepareAuxiliaryWords(for: reading)
        return supplement(base.candidates(for: reading), reading: reading, forList: true)
    }

    public func setApplication(_ identifier: String?) {
        applicationID = identifier
        base.setApplication(identifier)
    }

    /// 「🐈が」のように語を絵文字にした候補は，元の絵文字(🐈)の名前
    public func emojiName(of text: String) -> String? { emoji?.name(of: emojiSources[text]?.first?.emoji ?? text) }

    public func sourceName(of text: String, reading: String) -> String? {
        auxiliary.first { text.contains($0.word.word) && reading.contains($0.word.reading) }
            .flatMap { auxiliarySources[$0.word]?.name }
    }

    // MARK: - 取り込んだ辞書(R-16)

    /// 読みの中の部分ごとに効いている辞書と専門用語の辞書から語を引き，変わっていればエンジンに渡す
    private func prepareAuxiliaryWords(for reading: String) {
        guard lookup != nil || terms != nil else { return }
        let current = settings.current
        let hits = Dictionary(recentDictionaryCommits.map { ($0, 1) }, uniquingKeysWith: +)
        let active = lookup == nil ? [] : DictionaryActivation.active(current.importedDictionaries, applicationID: applicationID, recentHits: hits)
        let fields = terms != nil && current.termDictionary ? current.termFields.enabledFields : []
        if active != auxiliaryCache.active || fields != auxiliaryCache.fields { auxiliaryCache = (active, fields, [:]) }
        let found = auxiliaryCache.lookups[reading] ?? Self.lookUp(reading, in: active, lookup: lookup, fields: fields, terms: terms)
        auxiliaryCache.lookups[reading] = found
        auxiliarySources = found.sources
        guard found.words != auxiliary else { return }
        auxiliary = found.words
        base.setAuxiliaryWords(found.words)
    }

    /// reading の中の部分(長さ DefaultSettings.maximumImportedReadingLength まで)を，効いている辞書と専門用語の辞書の使う分野で引く．
    /// 同じ語が複数の辞書にあれば，優先度の高い方を使う(専門用語の辞書は取り込んだ辞書より低い)
    private static func lookUp(_ reading: String, in active: [DictionaryActivation.Active], lookup: (any DictionaryLookup)?,
                               fields: Set<TermField>, terms: (any TermDictionaryLookup)?) -> Lookup {
        let terms = fields.isEmpty ? nil : terms
        guard (!active.isEmpty && lookup != nil) || terms != nil else { return Lookup(words: [], sources: [:]) }
        let characters = Array(reading)
        var best: [DictionaryWord: Float] = [:]
        var sources: [DictionaryWord: Source] = [:]
        for start in characters.indices {
            for length in 1...min(DefaultSettings.maximumImportedReadingLength, characters.count - start) {
                let part = String(characters[start..<(start + length)])
                if let lookup {
                    for entry in active {
                        for word in lookup.words(reading: part, in: entry.dictionary) where best[word].map({ entry.costOffset > $0 }) ?? true {
                            best[word] = entry.costOffset
                            sources[word] = Source(id: entry.dictionary.id, name: entry.dictionary.displayName,
                                                   wholeReadingOffset: DefaultSettings.importedWordCandidateOffset)
                        }
                    }
                }
                for term in terms?.words(reading: part) ?? [] where fields.contains(term.field) && best[term.word] == nil {
                    let cost = term.overlap == .none ? DefaultSettings.termWordCost : DefaultSettings.termOverlappingWordCost
                    best[term.word] = cost - DefaultSettings.importedWordCost
                    sources[term.word] = Source(id: nil, name: term.field.name,
                                                wholeReadingOffset: term.overlap == .sameReading ? nil : DefaultSettings.termWordCandidateOffset)
                }
            }
        }
        let words = best.map { AuxiliaryWord(word: $0.key, costOffset: $0.value) }
            .sorted { ($0.word.reading, $0.word.word) < ($1.word.reading, $1.word.word) }
        return Lookup(words: words, sources: sources)
    }

    /// 確定した候補に取り込んだ辞書の語があれば，その辞書を最近使ったものとして数える
    private func recordDictionaryCommit(_ candidate: Candidate) {
        let ids = Set(auxiliary.filter { candidate.text.contains($0.word.word) }.compactMap { auxiliarySources[$0.word]?.id })
        guard !ids.isEmpty else { return }
        recentDictionaryCommits.append(contentsOf: ids.sorted())
        recentDictionaryCommits = Array(recentDictionaryCommits.suffix(DefaultSettings.importedDictionaryContextWindow))
    }

    public func plausibility(of reading: String) -> Double { base.plausibility(of: reading) }
    public func languageModelScores(forKeys keys: [String]) -> [Double?] { base.languageModelScores(forKeys: keys) }
    /// 打っているあいだの予測にも，エンジンの辞書から来る絵文字は出さない
    public func predictions(for reading: String) -> [Candidate] { base.predictions(for: reading).filter { !EmojiPlacement.containsEmoji($0.text) } }
    public func dictionaryCandidates(for reading: String) -> [Candidate] { base.dictionaryCandidates(for: reading) }
    public func segmentationWords(for reading: String) -> [Candidate.Word] { base.segmentationWords(for: reading) }
    public func typoCorrections(forKeys keys: String) -> [ReadingCorrection] { base.typoCorrections(forKeys: keys) }
    public func setLeftContext(_ text: String?) { base.setLeftContext(text) }
    public func setTyping(_ typing: Bool) { base.setTyping(typing) }
    public var hasDeferredConversion: Bool { base.hasDeferredConversion }
    public func performDeferredConversion() { base.performDeferredConversion() }
    public func didCommit(_ candidate: Candidate) {
        if candidate.origin == .emoji {
            // 読みは候補を足したときに覚えたもの．同じ絵文字を長さの違う読みで足したときは，候補の読みの長さで選ぶ
            if !learningSuspended, let source = emojiSources[candidate.text]?.first(where: { $0.readingCount == candidate.readingCount }) {
                emoji?.didCommit(source.emoji, reading: source.reading)
            }
            return
        }
        recordDictionaryCommit(candidate)
        base.didCommit(candidate)
    }
    public func setAuxiliaryWords(_ words: [AuxiliaryWord]) { base.setAuxiliaryWords(words) }
    public func endComposition() {
        auxiliaryCache.lookups = [:]
        listExtrasCache = [:]
        emojiSources = [:]
        learningSuspended = false
        base.endComposition()
    }
    public func forget(_ candidate: Candidate) { base.forget(candidate) }
    public func forget(_ candidate: Candidate, readingRange range: Range<Int>) { base.forget(candidate, readingRange: range) }
    public func forgetLastCommit() -> Bool { base.forgetLastCommit() }
    public func reopenLastCommit() { base.reopenLastCommit() }
    public func suspendLearningUntilEnd() {
        learningSuspended = true
        base.suspendLearningUntilEnd()
    }

    private func supplement(_ candidates: [Candidate], reading: String, forList: Bool = false) -> [Candidate] {
        let current = settings.current
        // エンジンの辞書から来る絵文字を含む候補を除く．ユーザー辞書の語より先に除き，登録した絵文字は消さない
        var result = Okurigana.reorder(candidates.filter { !Self.isEngineEmoji($0) }, style: current.okuriganaStyle)
        var userWords = userDictionaryWords(for: reading, in: current.userDictionary)
        if current.dynamicDictionary, userWords.contains(where: { TextTemplate.containsPlaceholder($0.word) }) {
            let values = templateValues()
            userWords = userWords.map { (TextTemplate.expand($0.word, values: values), $0.comment) }
        }
        insert(userWords.map(\.word), into: &result, at: 0, reading: reading, origin: .userDictionary)
        attachComments(userWords, to: &result, reading: reading)
        // 読み全体と一致する取り込んだ辞書の語は，エンジンの候補の順に関わらず前の方に出るようにここで足す．
        // 既定の 1 番目は変えず，その次に優先度の順で並べる
        // 専門用語の辞書の語は取り込んだ辞書の語より下に足し，同音の語は足さない
        let whole = auxiliary.filter { $0.word.reading == reading }.sorted { $0.costOffset > $1.costOffset }
        for offset in Set(whole.compactMap { auxiliarySources[$0.word]?.wholeReadingOffset }).sorted() {
            let words = whole.filter { auxiliarySources[$0.word]?.wholeReadingOffset == offset }.map(\.word.word)
            insert(words, into: &result, at: offset, reading: reading, origin: .userDictionary)
        }
        var extra: [String] = []
        if current.symbolConversion { extra += SymbolDictionary.symbols(for: reading, rules: current.symbolRules) }
        if current.latexConversion { extra += LatexCommands.commands(for: reading) }
        if current.dateConversion {
            extra += DateExpressions.candidates(for: reading, now: calendar.now(), day: calendar.day(offsetFromToday:))
        }
        let numberForms = NumberForms.candidates(for: reading, kinds: current.numberFormKinds)
        if !numberForms.isEmpty, result.isEmpty {
            // 書き換えた数字を第 1 候補にしない．エンジンが候補を出さなかったときも，打った数字を先頭に置く
            result.append(Candidate(text: reading, readingCount: reading.count, origin: .variant(.hiragana)))
        }
        extra += numberForms
        insert(extra, into: &result, at: DefaultSettings.symbolCandidateOffset, reading: reading, origin: .symbol)
        if current.misreadings, let entry = Misreadings.entry(for: reading) {
            insert([entry.word], into: &result, at: 1, reading: reading, origin: .symbol)
        }
        if current.postalCodeConversion, let postalCodes, let query = PostalCode.query(for: reading) {
            insert(postalCodes.addresses(for: query.code), into: &result, at: query.hasSeparator ? 0 : 1, reading: reading, origin: .symbol)
        }
        if current.calculation, let calculation = Calculator.evaluate(reading: reading) {
            insert([calculation.result, calculation.expression + "=" + calculation.result], into: &result, at: 0, reading: reading, origin: .symbol)
        }
        if current.prefersKatakana { Self.preferKatakana(&result, reading: reading) }
        if current.wordLanguage.avoidsOffensive { Self.demoteOffensive(&result, reading: reading) }
        // カタカナを先に出す並べ替え(かなで打った外来語のため)のあとに足す．ローマ字で打った「api」の「アピ」を「API」より先にしない
        if let dictionary = englishTerms?.dictionary { addEnglishTerms(from: dictionary, to: &result, reading: reading, settings: current) }
        if forList { addListExtras(to: &result, reading: reading, settings: current) }
        // 絵文字は変換したときの候補(一覧と分岐図の文節)にだけ出す．打っているあいだの表示と入力中の候補の窓には出さない
        if forList, let placement = current.emojiPlacement { addEmoji(to: &result, reading: reading, placement: placement, settings: current) }
        return result
    }

    /// 文節の読みと同じ読みの絵文字(「びーる」→ 🍺)と，文節の先頭の語を絵文字にして付属語を付けたもの(「ねこが」→ 🐈が)を足し，
    /// 置き場所(placement)にまとめる．2 つは別々の設定で切れ，数の上限は合わせて数える．ほかに候補が無ければ，読みのかなを第 1 候補にする
    private func addEmoji(to result: inout [Candidate], reading: String, placement: EmojiPlacement, settings current: Settings) {
        guard let emoji else { return }
        var found: [(text: String, source: EmojiSource)] = []
        if current.emojiConversion, reading.count >= DefaultSettings.minimumEmojiReadingLength {
            found += emoji.emoji(for: reading, limit: placement.count).map { ($0, EmojiSource(emoji: $0, reading: reading, readingCount: reading.count)) }
        }
        if current.emojiWordConversion, let split = wordEmojiSplit(reading, emoji: emoji) {
            found += emoji.emoji(for: split.head, limit: placement.count)
                .map { ($0 + split.tail, EmojiSource(emoji: $0, reading: split.head, readingCount: reading.count)) }
        }
        var seen = Set(result.map(\.text))
        let added = found.filter { seen.insert($0.text).inserted }.prefix(placement.count)
        guard !added.isEmpty else { return }
        if result.isEmpty { result.append(Candidate(text: reading, readingCount: reading.count, origin: .variant(.hiragana))) }
        for item in added where !(emojiSources[item.text] ?? []).contains(item.source) { emojiSources[item.text, default: []].append(item.source) }
        result = placement.placed(result + added.map { Candidate(text: $0.text, readingCount: reading.count, origin: .emoji) })
    }

    /// 文節の先頭の名詞を絵文字にできるときの，名詞の読み(ねこ)と後ろの付属語の字(が)．文節が名詞で始まり，絵文字の読みと同じ名詞 1 語の後ろに
    /// 付属語だけが続くときに限る．辞書には「猫が」のように名詞と助詞をつないだ語もあるので，語の並びの切れ目に頼らず，
    /// 長い方から読みを切って，前が絵文字の読みの名詞，後ろが付属語だけになる切れ目を探す
    private func wordEmojiSplit(_ reading: String, emoji: any EmojiLooking) -> (head: String, tail: String)? {
        let words = base.segmentationWords(for: reading)
        guard let first = words.first, first.startsWithNoun, words.reduce(0, { $0 + $1.readingCount }) == reading.count else { return nil }
        let characters = Array(reading)
        for length in stride(from: characters.count - 1, through: DefaultSettings.minimumEmojiReadingLength, by: -1) {
            let head = String(characters[..<length])
            guard !emoji.emoji(for: head, limit: 1).isEmpty else { continue }
            let tailReading = String(characters[length...])
            let tail = base.segmentationWords(for: tailReading)
            guard EmojiPlacement.isFunctionWords(tail, readingCount: tailReading.count) else { continue }
            let headWords = base.segmentationWords(for: head)
            guard headWords.count == 1, headWords[0].startsWithNoun, headWords[0].readingCount == length else { continue }
            return (head, tail.map(\.text).joined())
        }
        return nil
    }

    /// エンジンの辞書から来る絵文字を含む候補(エンジンの語と，それをつないだ・切り出したもの．「🐱」「🐱が」)
    private static func isEngineEmoji(_ candidate: Candidate) -> Bool {
        switch candidate.origin {
        case .engine, .combined, .sentencePart: EmojiPlacement.containsEmoji(candidate.text)
        default: false
        }
    }

    /// 一覧と文節の候補にだけ足す候補(うろ覚えの語・発音どおりの英単語・コマンド)．どれも第 1 候補は変えない
    private func addListExtras(to result: inout [Candidate], reading: String, settings current: Settings) {
        guard current.looseReadings || current.phoneticSpelling || current.launcherCommands else { return }
        if result.isEmpty { result.append(Candidate(text: reading, readingCount: reading.count, origin: .variant(.hiragana))) }
        let extras = listExtras(for: reading, settings: current)
        insert(extras.loose, into: &result, at: DefaultSettings.looseReadingCandidateOffset, reading: reading, origin: .symbol)
        insert(extras.phonetic, into: &result, at: DefaultSettings.phoneticCandidateOffset, reading: reading, origin: .symbol)
        guard current.launcherCommands else { return }
        let commands = LauncherCommands.matching(reading, in: current.commands)
            .map { Candidate(text: $0.candidateText, readingCount: reading.count, origin: .command(id: $0.id, kind: $0.kind)) }
        result.insert(contentsOf: commands, at: min(max(DefaultSettings.commandCandidateOffset, 1), result.count))
    }

    private func listExtras(for reading: String, settings current: Settings) -> (loose: [String], phonetic: [String]) {
        if let cached = listExtrasCache[reading] { return cached }
        let found = (loose: current.looseReadings ? looseReadingWords(for: reading) : [],
                     phonetic: current.phoneticSpelling ? phoneticWords(for: reading) : [])
        listExtrasCache[reading] = found
        return found
    }

    /// うろ覚えの読みを組み替えた読みのうち，辞書の 1 語になるものの語．元の読みが 1 語になるなら探さない(正しく打っている)
    private func looseReadingWords(for reading: String) -> [String] {
        guard reading.unicodeScalars.allSatisfy({ (0x3041...0x3096).contains($0.value) || $0 == "ー" }), dictionaryWord(for: reading) == nil else { return [] }
        var words: [String] = []
        for variant in LooseReadings.variants(of: reading) {
            if let word = dictionaryWord(for: variant), !words.contains(word) { words.append(word) }
            if words.count >= DefaultSettings.maximumLooseReadingWords { break }
        }
        return words
    }

    /// 読み全体が辞書の 1 語(ひらがなだけの語は除く)になれば，その語．語の並びの分からない候補は使わない
    private func dictionaryWord(for reading: String) -> String? {
        base.dictionaryCandidates(for: reading).first { candidate in
            candidate.readingCount == reading.count && candidate.words.count == 1 && candidate.words[0].readingCount == reading.count
                && candidate.text != reading
        }?.text
    }

    /// 読みをローマ字に直した綴り(「ふぉと」→ foto)の音を変えない置き換えのうち，英単語の辞書にあるもの
    private func phoneticWords(for reading: String) -> [String] {
        guard let lexicon, let keys = KanaRomanizer.keys(for: reading) else { return [] }
        if lexicon.isWord(keys) { return [] }
        return Array(PhoneticSpelling.variants(of: keys).lazy.filter { lexicon.isWord($0) }.prefix(DefaultSettings.maximumPhoneticWords))
    }

    /// 英語の語の辞書の語を足す(R-24)．
    /// 1. 読み全体が辞書の語になれば(「あぴ」→ API，「ぎてゅb」→ GitHub)，その語を足す．英字の残る読みは英語として打ったものなので第 1 候補に，
    ///    かなになり切った読みは，ふつうの日本語の語でなければ(「そら」→ 空 は日本語)第 1 候補にする．
    ///    設定の「いつも日本語にする語」「いつも英語にする語」に入れた語はそれに従う
    /// 2. 第 1 候補の中の，小文字の英字のまま確定させた語(「githubを使う」)を辞書の書き方にした候補を先に出す
    /// どちらも，先頭のユーザー辞書と取り込んだ辞書の語より後ろに置く．打ったままの候補(あぴ・アピ・github)は消さない
    private func addEnglishTerms(from dictionary: EnglishTermDictionary, to result: inout [Candidate], reading: String, settings current: Settings) {
        let head = result.prefix { $0.origin == .userDictionary }.count
        let terms = dictionary.terms(forReading: reading, includesRomajiReadings: current.inputStyle != .kana)
        if let keys = terms.first?.lowercased() {
            let words = current.wordLanguage
            let japaneseFirst = words.japaneseWords.contains(keys)
                || (!words.englishWords.contains(keys) && !reading.contains(where: Self.isLatinLetter) && readsAsJapaneseWord(reading))
            // エンジンがすでに出している語(「あい」→ AI)は，学習に使えるようエンジンの候補のまま前に移す
            var added: [Candidate] = []
            for term in terms where !result.prefix(head).contains(where: { $0.text == term }) {
                if let index = result.firstIndex(where: { $0.text == term && $0.readingCount == reading.count }) {
                    added.append(result.remove(at: index))
                } else {
                    added.append(Candidate(text: term, readingCount: reading.count, origin: .symbol))
                }
            }
            result.insert(contentsOf: added, at: min(head + (japaneseFirst ? DefaultSettings.englishTermCandidateOffset : 0), result.count))
        }
        guard result.indices.contains(head), let applied = dictionary.applyingTerms(to: result[head].text) else { return }
        var candidate = result[head]
        candidate.text = applied
        candidate.origin = .symbol
        candidate.words = Self.words(candidate.words, renamedTo: applied)
        candidate.learnedParts = []
        guard !result.contains(where: { $0.text == applied }) else { return }
        result.insert(candidate, at: head)
    }

    /// 読み全体が，漢字を含む辞書の 1 語になるか(「そら」→ 空，「あい」→ 愛)．英語の語を日本語の語より後ろに出すかを決める．
    /// カタカナだけの語(「アピ」)は英語の語を書き換えた外来語のことが多いので，日本語の語とはみなさない
    private func readsAsJapaneseWord(_ reading: String) -> Bool {
        base.dictionaryCandidates(for: reading).contains { candidate in
            candidate.readingCount == reading.count && candidate.words.count == 1 && candidate.words[0].readingCount == reading.count
                && candidate.text.unicodeScalars.contains(where: Self.isKanji)
        }
    }

    private static func isKanji(_ scalar: Unicode.Scalar) -> Bool {
        (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value) || scalar == "々"
    }

    /// 語の並びの文字を，文字数の同じ text の文字に置き換える(英字の大文字小文字だけを変えた候補の語の並び)．
    /// 語をつないだものが text と同じ長さでなければ空にする
    private static func words(_ words: [Candidate.Word], renamedTo text: String) -> [Candidate.Word] {
        guard words.reduce(0, { $0 + $1.text.count }) == text.count else { return [] }
        var rest = Substring(text)
        return words.map { word in
            var renamed = word
            renamed.text = String(rest.prefix(word.text.count))
            rest = rest.dropFirst(word.text.count)
            return renamed
        }
    }

    /// 入れるときに中身を決める語(TextTemplate)に渡す値
    private func templateValues() -> TextTemplate.Values {
        TemplateValueSource(calendar: calendar).values()
    }

    /// かなで打った読みの第 1 候補が英語のつづり(「Live変換」)を含み，その部分をカタカナにした候補(「ライブ変換」)があれば，
    /// カタカナの候補を先に出す．外来語はカタカナで書くのがふつうで，英語のつづりは選べば使えるようにする(設定で切れる)
    static func preferKatakana(_ candidates: inout [Candidate], reading: String) {
        guard let first = candidates.first, first.text.contains(where: Self.isLatinLetter),
              !reading.contains(where: { $0.isASCII }) else { return }
        let pattern = Self.runs(of: first.text)
        guard let index = candidates.firstIndex(where: {
            $0.readingCount == first.readingCount && !$0.text.contains(where: Self.isLatinLetter) && Self.matches(Array($0.text), pattern)
        }) else { return }
        candidates.insert(candidates.remove(at: index), at: 0)
    }

    private static func isLatinLetter(_ character: Character) -> Bool { character.isASCII && character.isLetter }

    private static func isKatakana(_ character: Character) -> Bool {
        character == "ー" || character.unicodeScalars.allSatisfy { (0x30A1...0x30FA).contains($0.value) }
    }

    /// 英字の並び(nil)と，それ以外の字の並び
    private static func runs(of text: String) -> [String?] {
        var runs: [String?] = []
        for character in text {
            if isLatinLetter(character) {
                if case .some(nil) = runs.last { continue }
                runs.append(nil)
            } else if case .some(.some(let last)) = runs.last {
                runs[runs.count - 1] = last + String(character)
            } else {
                runs.append(String(character))
            }
        }
        return runs
    }

    /// text が，英字の並びを 1 字以上のカタカナに置き換えた形か
    private static func matches(_ text: [Character], _ pattern: [String?]) -> Bool {
        guard let head = pattern.first else { return text.isEmpty }
        let rest = Array(pattern.dropFirst())
        if let literal = head {
            let characters = Array(literal)
            return text.starts(with: characters) && matches(Array(text.dropFirst(characters.count)), rest)
        }
        var length = 0
        while length < text.count, isKatakana(text[length]) {
            length += 1
            if matches(Array(text.dropFirst(length)), rest) { return true }
        }
        return false
    }

    /// 第 1 候補が不適切な語(「しね」→「死ね」)なら，ほかの候補を先に出す．
    /// 英語の語がローマ字として読めてしまったとき(「shine」)に，意図しない語をライブ変換で見せないため
    static func demoteOffensive(_ candidates: inout [Candidate], reading: String) {
        guard let first = candidates.first, OffensiveWords.isOffensive(text: first.text) else { return }
        if let index = candidates.firstIndex(where: { $0.readingCount == first.readingCount && !OffensiveWords.isOffensive(text: $0.text) }) {
            candidates.insert(candidates.remove(at: index), at: 0)
        } else {
            let slice = String(reading.prefix(first.readingCount))
            candidates.insert(Candidate(text: slice, readingCount: first.readingCount, origin: .variant(.hiragana)), at: 0)
        }
    }

    private func userDictionaryWords(for reading: String, in entries: [UserDictionaryEntry]) -> [(word: String, comment: String)] {
        // 設定を写しても配列の中身は共有されるので，変わっていなければ比べるのはすぐ済む
        if dictionaryIndex.source != entries {
            // ローマ字の読み(「gh」「toyota」)は，打ったときと同じ読みにそろえて引く(ReadingNormalization)
            let valid = entries.compactMap { entry in entry.isValid ? entry.lookupReading.map { ($0, entry) } : nil }
            dictionaryIndex = (entries, Dictionary(grouping: valid, by: \.0).mapValues { $0.map { (word: $0.1.word, comment: $0.1.comment) } })
        }
        return dictionaryIndex.words[reading] ?? []
    }

    /// 読み全体と一致したユーザー辞書の語のコメントを，同じ語の候補に付ける．
    /// 変換エンジンが同じ語を先に出していれば(文の中の語として渡しているため)，その候補に付ける
    private func attachComments(_ words: [(word: String, comment: String)], to candidates: inout [Candidate], reading: String) {
        for (word, comment) in words where !comment.isEmpty {
            for index in candidates.indices where candidates[index].text == word && candidates[index].readingCount == reading.count && candidates[index].comment == nil {
                candidates[index].comment = comment
            }
        }
    }

    private func insert(_ texts: [String], into candidates: inout [Candidate], at position: Int, reading: String, origin: CandidateOrigin) {
        var seen = Set(candidates.map(\.text))
        let added = texts.filter { seen.insert($0).inserted }.map { Candidate(text: $0, readingCount: reading.count, origin: origin) }
        guard !added.isEmpty else { return }
        candidates.insert(contentsOf: added, at: min(position, candidates.count))
    }
}
