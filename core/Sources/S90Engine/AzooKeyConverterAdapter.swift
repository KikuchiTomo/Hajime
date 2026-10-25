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
    private let engine: AzooKeyConverterEngine
    private let sessionID: KanaKanjiConverter.ConversionSessionID
    /// 直前に返した候補．Candidate の id はこの配列の位置
    private var lastCandidates: [KanaKanjiConverterModule.Candidate] = []
    private var lastReading = ""
    private var lastResult: [S90Domain.Candidate] = []

    init(engine: AzooKeyConverterEngine, sessionID: KanaKanjiConverter.ConversionSessionID) {
        self.engine = engine
        self.sessionID = sessionID
    }

    isolated deinit {
        engine.removeSession(sessionID)
    }

    func candidates(for reading: String) -> [S90Domain.Candidate] {
        guard !reading.isEmpty else { return [] }
        // 同じ読みで続けて呼ばれることが多い(ライブ変換の表示と候補一覧)ので，直前の結果を使い回す
        if reading == lastReading { return lastResult }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        let options = engine.options
        guard let result = engine.withSession(sessionID, { $0.requestCandidates(composing, options: options) }) else {
            return []
        }
        var seen = Set<String>()
        var engineCandidates: [KanaKanjiConverterModule.Candidate] = []
        for candidate in result.mainResults + result.firstClauseResults where seen.insert(candidate.text).inserted {
            engineCandidates.append(candidate)
        }
        lastCandidates = engineCandidates
        lastReading = reading
        lastResult = engineCandidates.enumerated().map { index, candidate in
            S90Domain.Candidate(
                text: candidate.text,
                readingCount: Self.readingCount(candidate.composingCount, readingLength: reading.count),
                origin: .engine(id: index)
            )
        }
        return lastResult
    }

    func didCommit(_ candidate: S90Domain.Candidate) {
        guard case .engine(let id) = candidate.origin, lastCandidates.indices.contains(id) else { return }
        let engineCandidate = lastCandidates[id]
        _ = engine.withSession(sessionID) { converter in
            converter.setCompletedData(engineCandidate)
            converter.updateLearningData(engineCandidate)
        }
        clearCache()
    }

    func endComposition() {
        _ = engine.withSession(sessionID) { $0.stopComposition() }
        clearCache()
    }

    private func clearCache() {
        lastCandidates = []
        lastReading = ""
        lastResult = []
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
