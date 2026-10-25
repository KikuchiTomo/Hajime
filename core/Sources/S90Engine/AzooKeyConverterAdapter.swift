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
        converter.commitUpdateLearningData()
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
            learningType: .inputAndOutput,
            memoryDirectoryURL: memoryDirectory,
            sharedContainerURL: memoryDirectory,
            textReplacer: .withDefaultEmojiDictionary(),
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
    /// 返した候補をエンジンの候補に戻すための表．Candidate の id はこの表のキーで，入力を確定するまで使い回さない
    private var engineCandidates: [Int: KanaKanjiConverterModule.Candidate] = [:]
    private var nextID = 0
    private var cache: [String: Result] = [:]
    /// 入力位置の前にある文字列(左の文脈)．Zenzai が変換の手がかりに使う
    private var leftContext: String?

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

    func setLeftContext(_ text: String?) {
        guard text != leftContext else { return }
        leftContext = text
        cache = [:]
    }

    func didCommit(_ candidate: S90Domain.Candidate) {
        guard case .engine(let id) = candidate.origin, let engineCandidate = engineCandidates[id] else { return }
        _ = engine.withSession(sessionID) { converter in
            converter.setCompletedData(engineCandidate)
            converter.updateLearningData(engineCandidate)
        }
        // 確定すると学習で順位が変わるので，同じ読みでも求め直す
        cache = [:]
    }

    func endComposition() {
        _ = engine.withSession(sessionID) { $0.stopComposition() }
        _ = engine.withSession(scoringSessionID) { $0.stopComposition() }
        plausibilityCache = [:]
        engineCandidates = [:]
        cache = [:]
    }

    private func request(_ reading: String) -> Result? {
        guard !reading.isEmpty else { return nil }
        // ライブ変換の表示と候補一覧で同じ読みを続けて求めることが多いので，結果を使い回す
        if let cached = cache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        let options = engine.options(leftContext: leftContext)
        guard let result = engine.withSession(sessionID, { $0.requestCandidates(composing, options: options) }) else {
            return nil
        }
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
            score: Double(candidate.value)
        )
    }

    /// 入力を .direct で渡しているので，入力の数と読みの文字数は同じになる
    private static func readingCount(_ count: ComposingCount, readingLength: Int) -> Int {
        switch count {
        case .inputCount(let value), .surfaceCount(let value):
            return min(value, readingLength)
        case .composite(let lhs, let rhs):
            return min(readingCount(lhs, readingLength: readingLength) + readingCount(rhs, readingLength: readingLength), readingLength)
        }
    }
}
