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

    /// - Parameters:
    ///   - memoryDirectory: 学習データとユーザー辞書を置くディレクトリ．本人だけが読み書きできる権限で作る
    ///   - versionString: エンジンに渡すアプリの版の文字列
    public init(memoryDirectory: URL, versionString: String) throws {
        try FileManager.default.createDirectory(
            at: memoryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.memoryDirectory = memoryDirectory
        self.versionString = versionString
        self.converter = KanaKanjiConverter.withDefaultDictionary()
    }

    public func makeSession() -> any KanaKanjiConverting {
        AzooKeyConverterSession(engine: self, sessionID: converter.createSession())
    }

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

    fileprivate var options: ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: DefaultSettings.engineCandidateCount,
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
    /// 返した候補をエンジンの候補に戻すための表．Candidate の id はこの表のキーで，入力を確定するまで使い回さない
    private var engineCandidates: [Int: KanaKanjiConverterModule.Candidate] = [:]
    private var nextID = 0
    private var cache: [String: Result] = [:]

    init(engine: AzooKeyConverterEngine, sessionID: KanaKanjiConverter.ConversionSessionID) {
        self.engine = engine
        self.sessionID = sessionID
    }

    deinit {
        // deinit はどのスレッドで動くか決まっていないので，エンジンへの操作はメインアクターに頼む．
        // isolated deinit は Swift 6.2 からで，CI の Swift 6.1 では使えない
        let engine = engine
        let sessionID = sessionID
        Task { @MainActor in engine.removeSession(sessionID) }
    }

    func candidates(for reading: String) -> [S90Domain.Candidate] {
        request(reading)?.all ?? []
    }

    func clauseCandidates(for reading: String) -> [S90Domain.Candidate] {
        request(reading)?.clauses ?? []
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
        engineCandidates = [:]
        cache = [:]
    }

    private func request(_ reading: String) -> Result? {
        guard !reading.isEmpty else { return nil }
        // ライブ変換の表示と候補一覧で同じ読みを続けて求めることが多いので，結果を使い回す
        if let cached = cache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        let options = engine.options
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
