import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import HajimeApplication
import HajimeDomain

/// 渡された辞書のディレクトリが辞書として読めない(louds/charID.chid が無い)
public enum DictionaryDirectoryError: Error, Equatable {
    case notFound
}

/// 辞書と学習データを持つ変換エンジン．アプリ全体で 1 つ作り，入力欄ごとのセッションを渡す．
///
/// azooKey の型はこのモジュールの外に出さない(docs/dev/ARCHITECTURE.md)．
@MainActor
public final class AzooKeyConverterEngine {
    private let converter: KanaKanjiConverter
    private let memoryDirectory: URL
    private let versionString: String
    private let zenzai: ZenzaiModel?
    /// 変換に効く設定(学習・日付・絵文字)．apply(_:) で入れ替える
    private var learningType: LearningType = .inputAndOutput
    /// 絵文字の辞書は読み込みが重いので，一度だけ作って使い回す
    private lazy var emojiReplacer = TextReplacer.withDefaultEmojiDictionary()
    private var usesEmoji = true
    private var userDictionary: [UserDictionaryEntry] = []
    /// 取り込んだ辞書から引いた語(R-16)．ユーザー辞書と合わせて動的な辞書としてエンジンに渡す
    private var auxiliaryWords: [AuxiliaryWord] = []
    /// Zenzai を使った変換にかかった時間の移動平均(秒)．まだ測っていなければ nil
    private var zenzaiCost: Double?

    /// - Parameters:
    ///   - memoryDirectory: 学習データとユーザー辞書を置くディレクトリ．本人だけが読み書きできる権限で作る
    ///   - versionString: エンジンに渡すアプリのバージョンの文字列
    ///   - zenzai: 確かめ済みの Zenzai のモデル．nil なら Zenzai を使わない
    ///   - dictionaryDirectory: かな漢字変換の辞書(louds/・cb/・p/・mm.binary を持つディレクトリ)．nil なら azooKey に同梱の辞書を使う
    public init(memoryDirectory: URL, versionString: String, zenzai: ZenzaiModel? = nil, dictionaryDirectory: URL? = nil) throws {
        // 辞書の場所を誤ると，エンジンは何も言わずに語の無い状態で動き，変換がほぼすべて読みのままになる．作る前に止める
        if let dictionaryDirectory {
            let charID = dictionaryDirectory.appendingPathComponent("louds/charID.chid", isDirectory: false)
            guard FileManager.default.fileExists(atPath: charID.path) else { throw DictionaryDirectoryError.notFound }
        }
        try FileManager.default.createDirectory(
            at: memoryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.memoryDirectory = memoryDirectory
        self.versionString = versionString
        self.zenzai = zenzai
        self.converter = dictionaryDirectory.map { KanaKanjiConverter(dicdataStore: DicdataStore(dictionaryURL: $0)) } ?? KanaKanjiConverter.withDefaultDictionary()
    }

    /// 読みに合う絵文字(EmojiLooking)．肌の色などを変えた形は除く
    public func emoji(for reading: String) -> [String] {
        emojiReplacer.getSearchResult(query: reading, target: [.emoji], ignoreNonBaseEmoji: true).map(\.text)
    }

    public func makeSession() -> any KanaKanjiConverting {
        // 読みのもっともらしさを測る変換は，表示する変換と状態を混ぜないよう別のセッションで行う
        AzooKeyConverterSession(engine: self, sessionID: converter.createSession(), scoringSessionID: converter.createSession(),
                                typingSessionID: converter.createSession(), restSessionID: converter.createSession())
    }

    /// 最初の変換で Zenzai のモデルの準備が走るので，起動時に一度変換しておく．入力内容は使わない
    /// 入力中の表示で Zenzai を使わないか．Zenzai の変換が 1 キーの時間に収まらない環境(GPU の無い Windows など)だけ true
    var skipsZenzaiWhileTyping: Bool {
        Self.exceedsTypingBudget(zenzaiCost)
    }

    /// Zenzai を使った変換の時間を覚える(打鍵が止まったときや Space の変換も測り，速い環境に戻ったら入力中にも使う)
    func recordZenzaiCost(_ duration: Duration) {
        zenzaiCost = Self.smoothedCost(zenzaiCost, adding: duration)
    }

    nonisolated static func smoothedCost(_ current: Double?, adding duration: Duration) -> Double {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        guard let current else { return seconds }
        return current + (seconds - current) * DefaultSettings.zenzaiCostSmoothing
    }

    nonisolated static func exceedsTypingBudget(_ cost: Double?) -> Bool {
        (cost ?? 0) > DefaultSettings.zenzaiTypingBudget
    }

    public func warmUp() {
        let session = makeSession()
        _ = session.candidates(for: Self.warmUpReading)
        session.endComposition()
        // 最初の変換はモデルの準備の時間を含むので，Zenzai の時間として数えない
        zenzaiCost = nil
    }

    private static let warmUpReading = "きょうはいいてんきです"

    /// 学習データをファイルに書き出す．入力欄からフォーカスが外れたときなどに呼ぶ
    public func flushLearning() {
        guard learningType == .inputAndOutput else { return }
        converter.commitUpdateLearningData()
    }

    /// 学んだことをすべて消す
    public func resetLearning() {
        converter.resetMemory()
    }

    /// 変換に効く設定を入れる．設定が変わるたびに呼ぶ
    public func apply(_ settings: Settings) {
        learningType = switch settings.learning {
        case .enabled: .inputAndOutput
        case .readOnly: .onlyOutput
        case .disabled: .nothing
        }
        usesEmoji = settings.emojiConversion
        let entries = settings.userDictionary.filter(\.isValid).prefix(DefaultSettings.maximumUserDictionaryEntries)
        if Array(entries) != userDictionary {
            userDictionary = Array(entries)
            importDynamicUserDictionary()
        }
    }

    /// 取り込んだ辞書から引いた語を入れ替える．変わったら true
    fileprivate func setAuxiliaryWords(_ words: [AuxiliaryWord]) -> Bool {
        guard words != auxiliaryWords else { return false }
        auxiliaryWords = words
        importDynamicUserDictionary()
        return true
    }

    /// ユーザー辞書と取り込んだ辞書の語を，動的な辞書としてエンジンに渡す
    private func importDynamicUserDictionary() {
        // ユーザー辞書の語は固有名詞として登録する
        let user = userDictionary.map {
            DicdataElement(word: $0.word, ruby: KanaWidth.katakana(from: $0.reading), cid: CIDData.固有名詞.cid, mid: MIDData.一般.mid,
                           value: DefaultSettings.userDictionaryWordCost)
        }
        let imported = auxiliaryWords.map {
            DicdataElement(word: $0.word.word, ruby: KanaWidth.katakana(from: $0.word.reading), cid: Self.cid(for: $0.word.wordClass),
                           mid: MIDData.一般.mid, value: DefaultSettings.importedWordCost + $0.costOffset)
        }
        converter.importDynamicUserDictionary(user + imported)
    }

    private static func cid(for wordClass: WordClass) -> Int {
        switch wordClass {
        case .noun: CIDData.一般名詞.cid
        case .properNoun: CIDData.固有名詞.cid
        case .personName: CIDData.人名一般.cid
        case .surname: CIDData.人名姓.cid
        case .givenName: CIDData.人名名.cid
        case .organization: CIDData.固有名詞組織.cid
        case .place: CIDData.地名一般.cid
        case .symbol: CIDData.記号.cid
        }
    }

    fileprivate func withSession<Result>(_ id: KanaKanjiConverter.ConversionSessionID, _ body: (KanaKanjiConverter) -> Result) -> Result? {
        try? converter.withSession(id) { body(converter) }
    }

    fileprivate func removeSession(_ id: KanaKanjiConverter.ConversionSessionID) {
        converter.removeSession(id)
    }

    public var usesZenzai: Bool { zenzai != nil }

    private func zenzaiMode(leftContext: String?) -> ConvertRequestOptions.ZenzaiMode {
        guard let zenzai else { return .off }
        return .on(
            weight: zenzai.url,
            inferenceLimit: DefaultSettings.zenzaiInferenceLimit,
            personalizationMode: nil,
            versionDependentMode: .v3(.init(
                leftSideContext: leftContext,
                maxLeftSideContextLength: DefaultSettings.maximumLeftContextLength
            ))
        )
    }

    fileprivate func options(leftContext: String?, usesZenzai: Bool = true, candidateCount: Int = DefaultSettings.engineCandidateCount) -> ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: candidateCount,
            requireJapanesePrediction: .disabled,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: false,
            fullWidthRomanCandidate: false,
            halfWidthKanaCandidate: false,
            learningType: learningType,
            memoryDirectoryURL: memoryDirectory,
            sharedContainerURL: memoryDirectory,
            textReplacer: usesEmoji ? emojiReplacer : .empty,
            // 和暦と西暦の読み替え(「れいわ8ねん」→「2026年」)や数の桁区切りは azooKey が出す．
            // 「きょう」→ 日付の候補は SupplementedConverter が出す(設定の dateConversion)
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            zenzaiMode: usesZenzai ? zenzaiMode(leftContext: leftContext) : .off,
            metadata: .init(versionString: versionString)
        )
    }
}

extension AzooKeyConverterEngine: EmojiLooking {}

/// 入力欄ひとつぶんの変換の状態．
@MainActor
final class AzooKeyConverterSession: KanaKanjiConverting {
    private struct Result {
        var all: [HajimeDomain.Candidate]
        var clauses: [HajimeDomain.Candidate]
    }

    private let engine: AzooKeyConverterEngine
    private let sessionID: KanaKanjiConverter.ConversionSessionID
    private let scoringSessionID: KanaKanjiConverter.ConversionSessionID
    /// Zenzai が遅い環境で，打鍵が止まる前の表示を Zenzai なしで求めるセッション．azooKey は前の読みからの差分で変換するので，
    /// Zenzai を使う変換(止まったとき・Space)と同じセッションで交互に求めると，差分が使えず毎回一から変換して遅くなる
    private let typingSessionID: KanaKanjiConverter.ConversionSessionID
    /// 打っている文の続きでない読み(分岐図の文節より後ろの残りの読み・Backspace で戻った読み)を Zenzai で求めるセッション．
    /// 同じセッションで求めると，打っている文の差分の変換の状態が捨てられ，次の打鍵で文を一から変換し直して遅くなる
    private let restSessionID: KanaKanjiConverter.ConversionSessionID
    private var plausibilityCache: [String: Double] = [:]
    private var predictionCache: [String: [HajimeDomain.Candidate]] = [:]
    private var dictionaryCache: [String: [HajimeDomain.Candidate]] = [:]
    private var segmentCandidateCache: [String: [HajimeDomain.Candidate]] = [:]
    private var segmentationCache: [String: [HajimeDomain.Candidate.Word]] = [:]
    /// 返した候補をエンジンの候補に戻すための表．Candidate の id はこの表のキーで，入力を確定するまで使い回さない
    private var engineCandidates: [Int: KanaKanjiConverterModule.Candidate] = [:]
    private var nextID = 0
    private var cache: [String: Result] = [:]
    /// 打鍵が止まる前の表示を求めているか(setTyping)．Zenzai が遅い環境では，そのあいだ Zenzai を使わない
    private var typing = false
    /// 前に変換を求めた読み．続きの読みなら azooKey の差分の変換を使える
    private var lastRequested: String?
    /// 入力中の表示のセッション(typingSessionID)で前に変換を求めた読み
    private var lastTypingRequested: String?
    /// 残りの読みのセッション(restSessionID)で前に変換を求めた読み
    private var lastRestRequested: String?
    /// 入力中の表示を Zenzai なしで求めた最後の読み．打鍵の合間に Zenzai で求めておく(performDeferredConversion)
    private var deferredReading: String?
    /// 入力位置の前にある文字列(左の文脈)．Zenzai が変換の手がかりに使う
    private var leftContext: String?
    /// 学習を使わずに変換しているか(suspendLearningUntilEnd)．入力を終えると戻す
    private var learningSuspended = false
    /// 今の入力で確定して学んだ候補．入力を終えたら lastCommitted に移す
    private var committedInComposition: [KanaKanjiConverterModule.Candidate] = []
    /// 最後に終えた入力で確定して学んだ候補(最後の学習を取り消すときに使う)
    private var lastCommitted: [KanaKanjiConverterModule.Candidate] = []

    init(engine: AzooKeyConverterEngine, sessionID: KanaKanjiConverter.ConversionSessionID, scoringSessionID: KanaKanjiConverter.ConversionSessionID,
         typingSessionID: KanaKanjiConverter.ConversionSessionID, restSessionID: KanaKanjiConverter.ConversionSessionID) {
        self.engine = engine
        self.sessionID = sessionID
        self.scoringSessionID = scoringSessionID
        self.typingSessionID = typingSessionID
        self.restSessionID = restSessionID
    }

    deinit {
        // deinit はどのスレッドで動くか決まっていないので，エンジンへの操作はメインアクターに頼む．
        // isolated deinit は Swift 6.2 からで，CI の Swift 6.1 では使えない
        let engine = engine
        let sessionIDs = [sessionID, scoringSessionID, typingSessionID, restSessionID]
        Task { @MainActor in sessionIDs.forEach(engine.removeSession) }
    }

    func candidates(for reading: String) -> [HajimeDomain.Candidate] {
        request(reading)?.all ?? []
    }

    func setTyping(_ typing: Bool) {
        self.typing = typing
    }

    var hasDeferredConversion: Bool {
        deferredReading.map { cache[$0] == nil } ?? false
    }

    /// Zenzai を使うセッションで求める．前に Zenzai で求めた読みの続きなら差分で進むので，1 打鍵分の時間で済む
    func performDeferredConversion() {
        guard let reading = deferredReading else { return }
        deferredReading = nil
        let wasTyping = typing
        typing = false
        defer { typing = wasTyping }
        _ = request(reading)
    }

    func clauseCandidates(for reading: String) -> [HajimeDomain.Candidate] {
        request(reading)?.clauses ?? []
    }

    func segmentCandidates(for reading: String) -> [HajimeDomain.Candidate] {
        guard !reading.isEmpty else { return [] }
        if let cached = segmentCandidateCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        // ライブ変換の状態を捨てないよう採点用の変換器で求める．文脈が無いので Zenzai は使わない
        var options = engine.options(leftContext: nil, usesZenzai: false)
        options.typoCorrectionMode = .disabled
        if learningSuspended { options.learningType = .nothing }
        let results = engine.withSession(scoringSessionID) { converter -> [KanaKanjiConverterModule.Candidate] in
            converter.stopComposition()
            defer { converter.stopComposition() }
            let result = converter.requestCandidates(composing, options: options)
            return result.mainResults + result.firstClauseResults
        } ?? []
        var seen = Set<String>()
        let candidates = results.filter { seen.insert($0.text).inserted }.map { register($0, readingLength: reading.count) }
        segmentCandidateCache[reading] = candidates
        return candidates
    }

    func dictionaryCandidates(for reading: String) -> [HajimeDomain.Candidate] {
        guard !reading.isEmpty else { return [] }
        if let cached = dictionaryCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        var options = engine.options(leftContext: nil, usesZenzai: false, candidateCount: DefaultSettings.headWordAlternativeCount * 2)
        options.typoCorrectionMode = .disabled
        options.learningType = .nothing
        let results = engine.withSession(scoringSessionID) { converter -> [KanaKanjiConverterModule.Candidate] in
            converter.stopComposition()
            defer { converter.stopComposition() }
            return converter.requestCandidates(composing, options: options).mainResults
        } ?? []
        var seen = Set<String>()
        let candidates = results.filter { seen.insert($0.text).inserted }.map { register($0, readingLength: reading.count) }
        dictionaryCache[reading] = candidates
        return candidates
    }

    func predictions(for reading: String) -> [HajimeDomain.Candidate] {
        guard !reading.isEmpty else { return [] }
        if let cached = predictionCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        // 予測は Zenzai を使わない軽い変換で求める(打つたびに求めるため)．表示の変換と状態を混ぜないよう，採点用の変換器で求める
        var options = engine.options(leftContext: leftContext, usesZenzai: false, candidateCount: DefaultSettings.suggestionCount)
        options.requireJapanesePrediction = .manualMix
        options.typoCorrectionMode = .disabled
        let results = engine.withSession(scoringSessionID) { converter -> [KanaKanjiConverterModule.Candidate] in
            converter.stopComposition()
            defer { converter.stopComposition() }
            return converter.requestCandidates(composing, options: options).predictionResults
        } ?? []
        var seen = Set<String>()
        let predictions = results.filter { seen.insert($0.text).inserted }.prefix(DefaultSettings.suggestionCount).map { candidate in
            // 予測は打った読み全体を置き換える
            let id = nextID
            nextID += 1
            engineCandidates[id] = candidate
            return HajimeDomain.Candidate(text: candidate.text, readingCount: reading.count, origin: .engine(id: id))
        }
        predictionCache[reading] = Array(predictions)
        return Array(predictions)
    }

    func plausibility(of reading: String) -> Double {
        guard !reading.isEmpty else { return -.infinity }
        if let cached = plausibilityCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        // 点数だけを使うので，Zenzai・絵文字・特別な候補・打ち間違いの補正を使わず，候補も 1 つだけ求める
        var options = engine.options(leftContext: nil, usesZenzai: false, candidateCount: 1)
        options.textReplacer = .empty
        options.specialCandidateProviders = []
        options.typoCorrectionMode = .disabled
        options.learningType = .nothing
        let best = engine.withSession(scoringSessionID) { converter in
            converter.requestCandidates(composing, options: options).mainResults
                .first { Self.readingCount($0.composingCount, readingLength: reading.count) == reading.count }
                .map { Double($0.value) }
        }
        let score = (best ?? nil) ?? -.infinity
        plausibilityCache[reading] = score
        return score
    }

    func segmentationWords(for reading: String) -> [HajimeDomain.Candidate.Word] {
        guard !reading.isEmpty else { return [] }
        if let cached = segmentationCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        // 語の区切りだけを使うので，Zenzai・絵文字・特別な候補・打ち間違いの補正を使わない(plausibility と同じ軽い変換)
        var options = engine.options(leftContext: nil, usesZenzai: false, candidateCount: 1)
        options.textReplacer = .empty
        options.specialCandidateProviders = []
        options.typoCorrectionMode = .disabled
        options.learningType = .nothing
        let data = engine.withSession(scoringSessionID) { converter -> [DicdataElement]? in
            converter.stopComposition()
            return converter.requestCandidates(composing, options: options).mainResults
                .first { Self.readingCount($0.composingCount, readingLength: reading.count) == reading.count }?.data
        }
        let words = Self.words(of: (data ?? nil) ?? [])
        segmentationCache[reading] = words
        return words
    }

    /// 語の品詞の ID から，文節に分けるための印を付ける．名詞の ID は azooKey の CIDData(一般名詞 1285〜数 1295)の並びの範囲
    private static func words(of data: [DicdataElement]) -> [HajimeDomain.Candidate.Word] {
        data.map { element in
            .init(text: element.word, readingCount: element.ruby.count, startsWithParticle: CIDData.isJoshi(cid: element.lcid),
                  endsWithParticle: CIDData.isJoshi(cid: element.rcid), startsWithNoun: nounIDs.contains(element.lcid),
                  startsWithPredicate: predicateIDs.contains { $0.contains(element.lcid) },
                  startsWithConjunctiveParticle: conjunctiveParticleIDs.contains(element.lcid),
                  endsWithSentenceFinalParticle: sentenceFinalParticleIDs.contains(element.rcid))
        }
    }

    /// 変換で語にならず，かなのまま残った部分の位置(読みの文字数の範囲)．助詞・助動詞(かなで書くのがふつうの語)は除く．
    /// かなの単位の訂正(KanaEditSearch)を試す場所に使う．隣どうしの部分はつなげる(「そう」「ゆう」→「そうゆう」)
    nonisolated static func unconvertedSpans(of data: [DicdataElement], minimumLength: Int = DefaultSettings.minimumUnconvertedSpanLength) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var position = 0
        for element in data {
            let length = element.ruby.count
            defer { position += length }
            let isFunctionWord = functionWordIDs.contains(element.lcid)
            guard !isFunctionWord, element.word == KanaWidth.hiragana(from: element.ruby) else { continue }
            if let last = spans.last, last.upperBound == position {
                spans[spans.count - 1] = last.lowerBound..<(position + length)
            } else {
                spans.append(position..<(position + length))
            }
        }
        return spans.filter { $0.count >= minimumLength }
    }

    /// 助詞(147〜368)と助動詞(369〜554)．かなで書くのがふつうなので，かなのまま残っても語にならなかったとはみなさない
    private nonisolated static let functionWordIDs = 147...554

    private static let nounIDs = 1280...1316
    /// 名詞のほかの自立語の品詞の ID の範囲．azooKey の品詞の ID は品詞の名前の順に並ぶ．hajime-playground --words で語ごとの ID を見て確かめた
    /// (形容詞 19・20・35・43，接続詞 555，動詞 619・772・817，副詞 1281・1282，連体詞 1315)．助詞は 147〜368，助動詞は 369〜554
    private static let predicateIDs: [ClosedRange<Int>] = [10...146, 555...1279, 1280...1284, 1315...1315]
    /// 助詞のうち，終助詞(ね 279・よ 288・わ 291)と接続助詞(て 307・で 308・ので 316・ば 318)の範囲．同じく語ごとの ID を見て決めた
    private static let sentenceFinalParticleIDs = 263...295
    private static let conjunctiveParticleIDs = 296...330

    func typoCorrections(forKeys keys: String) -> [ReadingCorrection] {
        guard engine.usesZenzai, !keys.isEmpty else { return [] }
        var composing = ComposingText()
        composing.insertAtCursorPosition(keys, inputStyle: .roman2kana)
        let options = engine.options(leftContext: leftContext)
        let config = ExperimentalTypoCorrectionConfig(
            beamSize: DefaultSettings.typoCorrectionBeamSize, topK: DefaultSettings.typoCorrectionTopK, nBest: DefaultSettings.typoCorrectionCandidateCount)
        // 訂正は表示する変換と状態を混ぜないよう，求めたあとに変換の状態を捨てる
        lastRequested = nil
        let corrections = engine.withSession(sessionID) { converter -> [ZenzaiTypoCandidate] in
            defer { converter.stopComposition() }
            return converter.experimentalRequestTypoCorrection(
                leftSideContext: leftContext ?? "", composingText: composing, options: options, inputStyle: .roman2kana, config: config)
        } ?? []
        let beam = corrections.map {
            ReadingCorrection(keys: $0.correctedInput, reading: $0.convertedText, score: Double($0.score), cost: Double($0.channelCost))
        }
        // Zenzai の探索が拾わない誤り(かなの書き誤りなど)を，1 か所の打ち間違いを全部試して補う
        let edits = KeyEditSearch.corrections(of: keys, plausibility: plausibility(of:), languageModel: languageModelScores(forKeys:))
        return KeyEditSearch.withPlausibility(KeyEditSearch.merge(beam, edits), typedKeys: keys, plausibility: plausibility(of:))
    }

    func languageModelScores(forKeys keys: [String]) -> [Double?] {
        guard engine.usesZenzai, !keys.isEmpty else { return keys.map { _ in nil } }
        let inputs = keys.map { key -> ComposingText in
            var composing = ComposingText()
            composing.insertAtCursorPosition(key, inputStyle: .roman2kana)
            return composing
        }
        let options = engine.options(leftContext: leftContext)
        lastRequested = nil
        let scores = engine.withSession(sessionID) { converter -> [Float?] in
            defer { converter.stopComposition() }
            return converter.experimentalScoreTypoInputs(leftSideContext: leftContext ?? "", inputs: inputs, options: options, inputStyle: .roman2kana)
        } ?? keys.map { _ in nil }
        return scores.map { $0.map(Double.init) }
    }

    func setLeftContext(_ text: String?) {
        guard text != leftContext else { return }
        leftContext = text
        cache = [:]
    }

    func didCommit(_ candidate: HajimeDomain.Candidate) {
        guard case .engine(let id) = candidate.origin, let engineCandidate = engineCandidates[id] else { return }
        let learns = !learningSuspended
        _ = engine.withSession(sessionID) { converter in
            converter.setCompletedData(engineCandidate)
            if learns { converter.updateLearningData(engineCandidate) }
        }
        if learns { committedInComposition.append(engineCandidate) }
        // 確定すると学習で順位が変わるので，同じ読みでも求め直す
        cache = [:]
    }

    func forget(_ candidate: HajimeDomain.Candidate) {
        guard case .engine(let id) = candidate.origin, let engineCandidate = engineCandidates[id] else { return }
        _ = engine.withSession(sessionID) { $0.forgetMemory(engineCandidate) }
        cache = [:]
    }

    func forget(_ candidate: HajimeDomain.Candidate, readingRange range: Range<Int>) {
        guard case .engine(let id) = candidate.origin, var engineCandidate = engineCandidates[id] else { return }
        // 読みの range に掛かる語だけを残す(語の読みはカタカナで，字の数はひらがなの読みと同じ)
        var start = 0
        engineCandidate.data = engineCandidate.data.filter { element in
            defer { start += element.ruby.count }
            return start < range.upperBound && start + element.ruby.count > range.lowerBound
        }
        guard !engineCandidate.data.isEmpty else { return }
        _ = engine.withSession(sessionID) { $0.forgetMemory(engineCandidate) }
        cache = [:]
    }

    func forgetLastCommit() -> Bool {
        guard !lastCommitted.isEmpty else { return false }
        let targets = lastCommitted
        lastCommitted = []
        _ = engine.withSession(sessionID) { converter in targets.forEach(converter.forgetMemory) }
        cache = [:]
        return true
    }

    func suspendLearningUntilEnd() {
        guard !learningSuspended else { return }
        learningSuspended = true
        // 学習を使った結果を使い回さないよう，前の結果を捨てて一から変換する
        cache = [:]
        lastRequested = nil
        lastTypingRequested = nil
        lastRestRequested = nil
        deferredReading = nil
    }

    /// 取り込んだ辞書の語が変わったら，前の結果は使えないので捨て，次は差分ではなく一から変換する
    func setAuxiliaryWords(_ words: [AuxiliaryWord]) {
        guard engine.setAuxiliaryWords(words) else { return }
        cache = [:]
        segmentCandidateCache = [:]
        lastRequested = nil
        lastTypingRequested = nil
        lastRestRequested = nil
        deferredReading = nil
    }

    func endComposition() {
        lastRequested = nil
        lastTypingRequested = nil
        lastRestRequested = nil
        deferredReading = nil
        learningSuspended = false
        if !committedInComposition.isEmpty { lastCommitted = committedInComposition }
        committedInComposition = []
        _ = engine.withSession(sessionID) { $0.stopComposition() }
        _ = engine.withSession(scoringSessionID) { $0.stopComposition() }
        _ = engine.withSession(typingSessionID) { $0.stopComposition() }
        _ = engine.withSession(restSessionID) { $0.stopComposition() }
        plausibilityCache = [:]
        predictionCache = [:]
        dictionaryCache = [:]
        segmentationCache = [:]
        segmentCandidateCache = [:]
        engineCandidates = [:]
        cache = [:]
    }

    private func request(_ reading: String) -> Result? {
        guard !reading.isEmpty else { return nil }
        // Zenzai が遅い環境では，打鍵が止まる前の表示を Zenzai なしで求める．その結果は止まったときに求め直すので，
        // Zenzai を使った結果とは別のキーで覚える(Zenzai を使った結果があればそれを使う)
        let skipsZenzai = typing && engine.usesZenzai && engine.skipsZenzaiWhileTyping
        // ライブ変換の表示と候補一覧で同じ読みを続けて求めることが多いので，結果を使い回す
        if let cached = cache[reading] { return cached }
        let key = skipsZenzai ? Self.typingCacheKey(reading) : reading
        if let cached = cache[key] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        var options = engine.options(leftContext: leftContext, usesZenzai: !skipsZenzai)
        if learningSuspended { options.learningType = .nothing }
        // azooKey は前に求めた読みからの差分で変換を進める．前の読みの続きでない読み(文節ごとの残りの読みなど)を
        // そのまま渡すと前の結果が混ざる(「ひとだ」→「非とだ」)ので，続きでなければ状態を捨ててから求める
        let stream = stream(for: reading, skipsZenzai: skipsZenzai)
        let previous = switch stream {
        case .typing: lastTypingRequested
        case .sentence: lastRequested
        case .rest: lastRestRequested
        }
        let continues = previous.map(reading.hasPrefix) ?? false
        let session = switch stream {
        case .typing: typingSessionID
        case .sentence: sessionID
        case .rest: restSessionID
        }
        let started = ContinuousClock.now
        guard let result = engine.withSession(session, { converter in
            if !continues { converter.stopComposition() }
            return converter.requestCandidates(composing, options: options)
        }) else {
            return nil
        }
        switch stream {
        case .typing:
            lastTypingRequested = reading
            deferredReading = reading
        case .sentence:
            lastRequested = reading
        case .rest:
            lastRestRequested = reading
        }
        if stream != .typing, engine.usesZenzai { engine.recordZenzaiCost(ContinuousClock.now - started) }
        var seen = Set<String>()
        var all: [HajimeDomain.Candidate] = []
        for candidate in result.mainResults + result.firstClauseResults where seen.insert(candidate.text).inserted {
            all.append(register(candidate, readingLength: reading.count))
        }
        var clauseSeen = Set<String>()
        var clauses: [HajimeDomain.Candidate] = []
        for candidate in result.firstClauseResults where clauseSeen.insert(candidate.text).inserted {
            clauses.append(register(candidate, readingLength: reading.count))
        }
        let value = Result(all: all, clauses: clauses)
        cache[key] = value
        return value
    }

    /// 変換を求めるセッションの流れ
    private enum Stream {
        /// 打鍵が止まる前の表示(Zenzai なし)
        case typing
        /// 打っている文．前の読みの続きを差分で変換する
        case sentence
        /// 打っている文の続きでない読み
        case rest
    }

    private func stream(for reading: String, skipsZenzai: Bool) -> Stream {
        if skipsZenzai { return .typing }
        return lastRequested.map(reading.hasPrefix) ?? true ? .sentence : .rest
    }

    /// Zenzai を使わずに求めた入力中の表示を覚えるキー(読みの前に読みには出ない文字を付ける)
    nonisolated static func typingCacheKey(_ reading: String) -> String {
        "\u{0}" + reading
    }

    private func register(_ candidate: KanaKanjiConverterModule.Candidate, readingLength: Int) -> HajimeDomain.Candidate {
        let id = nextID
        nextID += 1
        engineCandidates[id] = candidate
        return HajimeDomain.Candidate(
            text: candidate.text,
            readingCount: Self.readingCount(candidate.composingCount, readingLength: readingLength),
            origin: .engine(id: id),
            score: Double(candidate.value),
            trailingWord: candidate.data.last.map { .init(readingCount: $0.ruby.count, textCount: $0.word.count) },
            words: Self.words(of: candidate.data)
        )
    }

    /// 入力を .direct で渡しているので，入力の数と読みの文字数は同じになる
    nonisolated static func readingCount(_ count: ComposingCount, readingLength: Int) -> Int {
        switch count {
        case .inputCount(let value), .surfaceCount(let value):
            return min(value, readingLength)
        case .composite(let lhs, let rhs):
            return min(readingCount(lhs, readingLength: readingLength) + readingCount(rhs, readingLength: readingLength), readingLength)
        }
    }
}
