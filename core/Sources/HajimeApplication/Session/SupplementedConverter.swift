import Foundation
import HajimeDomain

/// 変換エンジンの候補に，エンジンが出さない候補を足す．
///
/// - ユーザー辞書の語: 読みが一致すれば先頭に置く．登録した語は選びたい語なので．
///   エンジンにもユーザー辞書を渡している(文の中の語として使うため)が，エンジンは辞書の語の続きになる読みしか
///   たどらないので，辞書に無い読みの語は出ない．読み全体が一致する語はここで確実に出す(同じ語は重ねない)
/// - 記号(SymbolDictionary): 「やじるし」→「→」など
/// - 日付と時刻(DateExpressions): 「きょう」→「2026/10/26」など
/// - 計算(Calculator): 「1+2*3=」→「7」「1+2*3=7」．結果を先頭に置く(式を打って「=」を打つのは計算したいときなので)
/// - よくある読み違い(Misreadings): 「ふいんき」→「雰囲気」を 2 番目に置く
/// - 送り仮名(Okurigana): 本則か許容の選んだ方を先に並べる
/// - LaTeX のコマンド(LatexCommands): 「らむだ」→「\lambda」．設定でオンにしたときだけ．記号と同じ位置に差し込む
/// - 絵文字(EmojiLooking): 「なく」→ 😢．読みで引き，上から DefaultSettings.emojiCandidateOffset 番目に差し込む
/// - 郵便番号(PostalCode): 「100-0001」→「東京都千代田区千代田」．区切りがあれば先頭に，無ければ 2 番目に置く(7 桁の数字のこともあるので)
/// - ユーザー辞書のローマ字の読み(「gh」→ GitHub)と，入れるときに中身を決める語(TextTemplate．「にちじ」→ `{datetime:...}`)
///
/// 変換の一覧と分岐図の文節(listCandidates・segmentCandidates)にだけ足すもの．打っているあいだ(ライブ変換)には出さず，第 1 候補にもしない
/// - コマンド(LauncherCommand): 読みが一致すれば 2 番目に「▶ 名前」を置く．候補の窓では印の代わりにアイコンと札で見せる．選んで確定したときだけ動く(R-22)
/// - うろ覚えの語(LooseReadings): 「しゅみれーしょん」→「シミュレーション」
/// - 発音どおりに綴った英単語(PhoneticSpelling): 「ふぉと」→「photo」
///
/// - 取り込んだ辞書の語(R-16): 読みの中の部分ごとに，効いている辞書から語を引いてエンジンに渡す(setAuxiliaryWords)．
///   どの辞書を効かせるかは DictionaryActivation が決める(アプリの条件，文脈の条件)
///
/// 記号と日付は上から DefaultSettings.symbolCandidateOffset 番目に差し込む．
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
    /// 読みごとに見つけたうろ覚えの語と英単語．入力を終えたときに捨てる
    private var listExtrasCache: [String: (loose: [String], phonetic: [String])] = [:]
    /// ユーザー辞書を読みで引く表．設定のユーザー辞書が変わったときだけ作り直す
    private var dictionaryIndex: (source: [UserDictionaryEntry], words: [String: [String]]) = ([], [:])
    /// 取り込んだ辞書を引くもの．無ければ取り込んだ辞書は使わない
    private let lookup: (any DictionaryLookup)?
    private var applicationID: String?
    /// 最近確定した，取り込んだ辞書の語の辞書の id(新しいものが後ろ)．文脈の条件に使う
    private var recentDictionaryCommits: [String] = []
    /// 今エンジンに渡している語と，その語の辞書の名前
    private var auxiliary: [AuxiliaryWord] = []
    private var auxiliarySources: [DictionaryWord: Source] = [:]
    /// 読みごとに引いた語と，その語の辞書．効いている辞書が変わったときと，入力を終えたときに捨てる
    private var auxiliaryCache: (active: [DictionaryActivation.Active], lookups: [String: Lookup]) = ([], [:])

    private struct Source {
        var id: String
        var name: String
    }

    private struct Lookup {
        var words: [AuxiliaryWord]
        var sources: [DictionaryWord: Source]
    }

    public init(_ base: any KanaKanjiConverting, settings: any SettingsReading, calendar: any CalendarReading,
                postalCodes: (any PostalCodeLooking)? = nil, dictionaries: (any DictionaryLookup)? = nil, emoji: (any EmojiLooking)? = nil,
                lexicon: (any EnglishLexicon)? = nil) {
        self.base = base
        self.lexicon = lexicon
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

    public func sourceName(of text: String, reading: String) -> String? {
        auxiliary.first { text.contains($0.word.word) && reading.contains($0.word.reading) }
            .flatMap { auxiliarySources[$0.word]?.name }
    }

    // MARK: - 取り込んだ辞書(R-16)

    /// 読みの中の部分ごとに効いている辞書から語を引き，変わっていればエンジンに渡す
    private func prepareAuxiliaryWords(for reading: String) {
        guard let lookup else { return }
        let dictionaries = settings.current.importedDictionaries
        let hits = Dictionary(recentDictionaryCommits.map { ($0, 1) }, uniquingKeysWith: +)
        let active = DictionaryActivation.active(dictionaries, applicationID: applicationID, recentHits: hits)
        if active != auxiliaryCache.active { auxiliaryCache = (active, [:]) }
        let found = auxiliaryCache.lookups[reading] ?? Self.lookUp(reading, in: active, lookup: lookup)
        auxiliaryCache.lookups[reading] = found
        auxiliarySources = found.sources
        guard found.words != auxiliary else { return }
        auxiliary = found.words
        base.setAuxiliaryWords(found.words)
    }

    /// reading の中の部分(長さ DefaultSettings.maximumImportedReadingLength まで)を，効いている辞書で引く．
    /// 同じ語が複数の辞書にあれば，優先度の高い方を使う
    private static func lookUp(_ reading: String, in active: [DictionaryActivation.Active], lookup: any DictionaryLookup) -> Lookup {
        guard !active.isEmpty else { return Lookup(words: [], sources: [:]) }
        let characters = Array(reading)
        var best: [DictionaryWord: Float] = [:]
        var sources: [DictionaryWord: Source] = [:]
        for start in characters.indices {
            for length in 1...min(DefaultSettings.maximumImportedReadingLength, characters.count - start) {
                let part = String(characters[start..<(start + length)])
                for entry in active {
                    for word in lookup.words(reading: part, in: entry.dictionary) where best[word].map({ entry.costOffset > $0 }) ?? true {
                        best[word] = entry.costOffset
                        sources[word] = Source(id: entry.dictionary.id, name: entry.dictionary.displayName)
                    }
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
    public func predictions(for reading: String) -> [Candidate] { base.predictions(for: reading) }
    public func dictionaryCandidates(for reading: String) -> [Candidate] { base.dictionaryCandidates(for: reading) }
    public func segmentationWords(for reading: String) -> [Candidate.Word] { base.segmentationWords(for: reading) }
    public func typoCorrections(forKeys keys: String) -> [ReadingCorrection] { base.typoCorrections(forKeys: keys) }
    public func setLeftContext(_ text: String?) { base.setLeftContext(text) }
    public func setTyping(_ typing: Bool) { base.setTyping(typing) }
    public var hasDeferredConversion: Bool { base.hasDeferredConversion }
    public func performDeferredConversion() { base.performDeferredConversion() }
    public func didCommit(_ candidate: Candidate) {
        recordDictionaryCommit(candidate)
        base.didCommit(candidate)
    }
    public func setAuxiliaryWords(_ words: [AuxiliaryWord]) { base.setAuxiliaryWords(words) }
    public func endComposition() {
        auxiliaryCache.lookups = [:]
        listExtrasCache = [:]
        base.endComposition()
    }
    public func forget(_ candidate: Candidate) { base.forget(candidate) }
    public func forget(_ candidate: Candidate, readingRange range: Range<Int>) { base.forget(candidate, readingRange: range) }
    public func forgetLastCommit() -> Bool { base.forgetLastCommit() }
    public func suspendLearningUntilEnd() { base.suspendLearningUntilEnd() }

    private func supplement(_ candidates: [Candidate], reading: String, forList: Bool = false) -> [Candidate] {
        let current = settings.current
        var result = Okurigana.reorder(candidates, style: current.okuriganaStyle)
        var userWords = userDictionaryWords(for: reading, in: current.userDictionary)
        if current.dynamicDictionary, userWords.contains(where: TextTemplate.containsPlaceholder) {
            let values = templateValues()
            userWords = userWords.map { TextTemplate.expand($0, values: values) }
        }
        insert(userWords, into: &result, at: 0, reading: reading, origin: .userDictionary)
        // 読み全体と一致する取り込んだ辞書の語は，エンジンの候補の順に関わらず前の方に出るようにここで足す．
        // 既定の 1 番目は変えず，その次に優先度の順で並べる
        let importedWords = auxiliary.filter { $0.word.reading == reading }.sorted { $0.costOffset > $1.costOffset }.map(\.word.word)
        insert(importedWords, into: &result, at: DefaultSettings.importedWordCandidateOffset, reading: reading, origin: .userDictionary)
        var extra: [String] = []
        if current.symbolConversion { extra += SymbolDictionary.symbols(for: reading, rules: current.symbolRules) }
        if current.latexConversion { extra += LatexCommands.commands(for: reading) }
        if current.dateConversion {
            extra += DateExpressions.candidates(for: reading, now: calendar.now(), day: calendar.day(offsetFromToday:))
        }
        insert(extra, into: &result, at: DefaultSettings.symbolCandidateOffset, reading: reading, origin: .symbol)
        if current.emojiConversion, let emoji {
            insert(Array(emoji.emoji(for: reading).prefix(DefaultSettings.emojiCandidateCount)), into: &result,
                   at: DefaultSettings.emojiCandidateOffset, reading: reading, origin: .symbol)
        }
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
        if forList { addListExtras(to: &result, reading: reading, settings: current) }
        return result
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

    /// 入れるときに中身を決める語(TextTemplate)に渡す値
    private func templateValues() -> TextTemplate.Values {
        TextTemplate.Values(now: calendar.now(), day: { [calendar] in calendar.day(offsetFromToday: $0) },
                            uuid: { UUID().uuidString }, random: { Int.random(in: $0) })
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

    private func userDictionaryWords(for reading: String, in entries: [UserDictionaryEntry]) -> [String] {
        // 設定を写しても配列の中身は共有されるので，変わっていなければ比べるのはすぐ済む
        if dictionaryIndex.source != entries {
            // ローマ字の読み(「gh」「toyota」)は，打ったときと同じ読みにそろえて引く(ReadingNormalization)
            let valid = entries.compactMap { entry in entry.isValid ? entry.lookupReading.map { ($0, entry.word) } : nil }
            dictionaryIndex = (entries, Dictionary(grouping: valid, by: \.0).mapValues { $0.map(\.1) })
        }
        return dictionaryIndex.words[reading] ?? []
    }

    private func insert(_ texts: [String], into candidates: inout [Candidate], at position: Int, reading: String, origin: CandidateOrigin) {
        var seen = Set(candidates.map(\.text))
        let added = texts.filter { seen.insert($0).inserted }.map { Candidate(text: $0, readingCount: reading.count, origin: origin) }
        guard !added.isEmpty else { return }
        candidates.insert(contentsOf: added, at: min(position, candidates.count))
    }
}
