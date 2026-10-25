import Foundation
import S90Application
import S90Domain
import S90Engine

/// macOS に入っている単語の一覧を英単語の辞書として使う．補正の候補は編集距離で探す
@MainActor
final class WordListLexicon: EnglishLexicon {
    private let words: Set<String>

    init(path: String = "/usr/share/dict/words") {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        words = Set(text.split(separator: "\n").map { $0.lowercased() })
    }

    func isWord(_ text: String) -> Bool { words.contains(text.lowercased()) }

    func suggestions(for text: String) -> [String] {
        let target = text.lowercased()
        return words.filter { abs($0.count - target.count) <= DefaultSettings.maximumCorrectionDistance }
            .map { ($0, EditDistance.damerauLevenshtein($0, target)) }
            .filter { $0.1 <= DefaultSettings.maximumCorrectionDistance }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .prefix(3)
            .map(\.0)
    }
}

@MainActor
final class StaticSettings: SettingsReading {
    let current: Settings
    init(_ settings: Settings) { current = settings }
}

/// 試す・測るためのエンジンを作る．学習データは一時ディレクトリに置き，終わったら消す(試した入力を残さないため)
@MainActor
struct PlaygroundEngine {
    let engine: AzooKeyConverterEngine
    private let memory: URL

    init(zenzaiPath: String?) throws {
        memory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-playground-\(UUID().uuidString)")
        let zenzai = try zenzaiPath.map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0)) }
        engine = try AzooKeyConverterEngine(memoryDirectory: memory, versionString: "s90-playground", zenzai: zenzai)
    }

    func removeMemory() {
        try? FileManager.default.removeItem(at: memory)
    }
}

/// コマンドラインの「--名前 値」を読む
struct Arguments {
    private let values: [String]

    init(_ values: [String] = CommandLine.arguments) {
        self.values = values
    }

    func value(of name: String) -> String? {
        guard let index = values.firstIndex(of: name), values.indices.contains(index + 1) else { return nil }
        return values[index + 1]
    }
}
