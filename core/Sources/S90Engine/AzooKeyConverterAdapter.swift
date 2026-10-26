import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import S90Application
import S90Domain

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

    /// - Parameters:
    ///   - memoryDirectory: 学習データとユーザー辞書を置くディレクトリ．本人だけが読み書きできる権限で作る
    ///   - versionString: エンジンに渡すアプリの版の文字列
    ///   - zenzai: 確かめ済みの Zenzai のモデル．nil なら Zenzai を使わない
    public init(memoryDirectory: URL, versionString: String, zenzai: ZenzaiModel? = nil) throws {
        try FileManager.default.createDirectory(
            at: memoryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.memoryDirectory = memoryDirectory
        self.versionString = versionString
        self.zenzai = zenzai
        self.converter = KanaKanjiConverter.withDefaultDictionary()
    }

    public func makeSession() -> any KanaKanjiConverting {
        // 読みのもっともらしさを測る変換は，表示する変換と状態を混ぜないよう別のセッションで行う
        AzooKeyConverterSession(engine: self, sessionID: converter.createSession(), scoringSessionID: converter.createSession())
    }

    /// 最初の変換で Zenzai のモデルの準備が走るので，起動時に一度変換しておく．入力内容は使わない
    public func warmUp() {
        let session = makeSession()
        _ = session.candidates(for: Self.warmUpReading)
        session.endComposition()
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

/// 入力欄ひとつぶんの変換の状態．
@MainActor
final class AzooKeyConverterSession: KanaKanjiConverting {
    private struct Result {
        var all: [S90Domain.Candidate]
        var clauses: [S90Domain.Candidate]
    }

    private let engine: AzooKeyConverterEngine
    private let sessionID: KanaKanjiConverter.ConversionSessionID
    private let scoringSessionID: KanaKanjiConverter.ConversionSessionID
    private var plausibilityCache: [String: Double] = [:]
    private var predictionCache: [String: [S90Domain.Candidate]] = [:]
    private var dictionaryCache: [String: [S90Domain.Candidate]] = [:]
    private var segmentationCache: [String: [S90Domain.Candidate.Word]] = [:]
    /// 返した候補をエンジンの候補に戻すための表．Candidate の id はこの表のキーで，入力を確定するまで使い回さない
    private var engineCandidates: [Int: KanaKanjiConverterModule.Candidate] = [:]
    private var nextID = 0
    private var cache: [String: Result] = [:]
    /// 前に変換を求めた読み．続きの読みなら azooKey の差分の変換を使える
    private var lastRequested: String?
    /// 入力位置の前にある文字列(左の文脈)．Zenzai が変換の手がかりに使う
    private var leftContext: String?
    /// 学習を使わずに変換しているか(suspendLearningUntilEnd)．入力を終えると戻す
    private var learningSuspended = false
    /// 今の入力で確定して学んだ候補．入力を終えたら lastCommitted に移す
    private var committedInComposition: [KanaKanjiConverterModule.Candidate] = []
    /// 最後に終えた入力で確定して学んだ候補(最後の学習を取り消すときに使う)
    private var lastCommitted: [KanaKanjiConverterModule.Candidate] = []

    init(engine: AzooKeyConverterEngine, sessionID: KanaKanjiConverter.ConversionSessionID, scoringSessionID: KanaKanjiConverter.ConversionSessionID) {
        self.engine = engine
        self.sessionID = sessionID
        self.scoringSessionID = scoringSessionID
    }

    deinit {
        // deinit はどのスレッドで動くか決まっていないので，エンジンへの操作はメインアクターに頼む．
        // isolated deinit は Swift 6.2 からで，CI の Swift 6.1 では使えない
        let engine = engine
        let sessionIDs = [sessionID, scoringSessionID]
        Task { @MainActor in sessionIDs.forEach(engine.removeSession) }
    }

    func candidates(for reading: String) -> [S90Domain.Candidate] {
        request(reading)?.all ?? []
    }

    func clauseCandidates(for reading: String) -> [S90Domain.Candidate] {
        request(reading)?.clauses ?? []
    }

    func dictionaryCandidates(for reading: String) -> [S90Domain.Candidate] {
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

    func predictions(for reading: String) -> [S90Domain.Candidate] {
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
            return S90Domain.Candidate(text: candidate.text, readingCount: reading.count, origin: .engine(id: id))
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

    func segmentationWords(for reading: String) -> [S90Domain.Candidate.Word] {
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
    private static func words(of data: [DicdataElement]) -> [S90Domain.Candidate.Word] {
        data.map {
            .init(text: $0.word, readingCount: $0.ruby.count, startsWithParticle: CIDData.isJoshi(cid: $0.lcid),
                  endsWithParticle: CIDData.isJoshi(cid: $0.rcid), startsWithNoun: nounIDs.contains($0.lcid))
        }
    }

    private static let nounIDs = 1280...1316

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

    func didCommit(_ candidate: S90Domain.Candidate) {
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

    func forget(_ candidate: S90Domain.Candidate) {
        guard case .engine(let id) = candidate.origin, let engineCandidate = engineCandidates[id] else { return }
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
    }

    /// 取り込んだ辞書の語が変わったら，前の結果は使えないので捨て，次は差分ではなく一から変換する
    func setAuxiliaryWords(_ words: [AuxiliaryWord]) {
        guard engine.setAuxiliaryWords(words) else { return }
        cache = [:]
        lastRequested = nil
    }

    func endComposition() {
        lastRequested = nil
        learningSuspended = false
        if !committedInComposition.isEmpty { lastCommitted = committedInComposition }
        committedInComposition = []
        _ = engine.withSession(sessionID) { $0.stopComposition() }
        _ = engine.withSession(scoringSessionID) { $0.stopComposition() }
        plausibilityCache = [:]
        predictionCache = [:]
        dictionaryCache = [:]
        segmentationCache = [:]
        engineCandidates = [:]
        cache = [:]
    }

    private func request(_ reading: String) -> Result? {
        guard !reading.isEmpty else { return nil }
        // ライブ変換の表示と候補一覧で同じ読みを続けて求めることが多いので，結果を使い回す
        if let cached = cache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        var options = engine.options(leftContext: leftContext)
        if learningSuspended { options.learningType = .nothing }
        // azooKey は前に求めた読みからの差分で変換を進める．前の読みの続きでない読み(文節ごとの残りの読みなど)を
        // そのまま渡すと前の結果が混ざる(「ひとだ」→「非とだ」)ので，続きでなければ状態を捨ててから求める
        let continues = lastRequested.map(reading.hasPrefix) ?? false
        guard let result = engine.withSession(sessionID, { converter in
            if !continues { converter.stopComposition() }
            return converter.requestCandidates(composing, options: options)
        }) else {
            return nil
        }
        lastRequested = reading
        var seen = Set<String>()
        var all: [S90Domain.Candidate] = []
        for candidate in result.mainResults + result.firstClauseResults where seen.insert(candidate.text).inserted {
            all.append(register(candidate, readingLength: reading.count))
        }
        var clauseSeen = Set<String>()
        var clauses: [S90Domain.Candidate] = []
        for candidate in result.firstClauseResults where clauseSeen.insert(candidate.text).inserted {
            clauses.append(register(candidate, readingLength: reading.count))
        }
        let value = Result(all: all, clauses: clauses)
        cache[reading] = value
        return value
    }

    private func register(_ candidate: KanaKanjiConverterModule.Candidate, readingLength: Int) -> S90Domain.Candidate {
        let id = nextID
        nextID += 1
        engineCandidates[id] = candidate
        return S90Domain.Candidate(
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
