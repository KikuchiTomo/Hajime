import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine

/// macOS に入っている単語の一覧を英単語の辞書として使う．補正の候補は編集距離で探す．
///
/// アプリの辞書(macOS の NSSpellChecker)は AppKit にあり，ここでは使えない．単語の一覧には語の頻度が無いので，
/// 打ち間違いの起こり方で並べて NSSpellChecker の候補に近づける．
/// - 編集距離の近い順
/// - 最初の文字が同じもの．最初の文字はあまり打ち間違えない
/// - 打った綴りより短くならないもの．1 文字打ち落とした(pthon → python)か，入れ替えた(pyhton → python)ことが多い．
///   短くなるもの(pthon → phon)は打った文字を捨てるので後ろに回す
/// 頻度が無いので，同じ順位のもの(pyhton に対する phyton と python)は区別できない．
/// また一覧に無い語(javascript)は候補に出ない
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
        func rank(_ word: String, _ distance: Int) -> (Int, Int, Int, String) {
            (distance, word.first == target.first ? 0 : 1, word.count < target.count ? 1 : 0, word)
        }
        return words.filter { abs($0.count - target.count) <= DefaultSettings.maximumCorrectionDistance }
            .map { ($0, EditDistance.damerauLevenshtein($0, target)) }
            .filter { $0.1 <= DefaultSettings.maximumCorrectionDistance }
            .sorted { rank($0.0, $0.1) < rank($1.0, $1.1) }
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
    /// アプリと同じく，打ち間違いの訂正を別の変換器で求めるもの(Zenzai があるときだけ)
    let typoService: ZenzaiTypoService?
    private let memory: URL

    /// - Parameters:
    ///   - fastZenzaiPath: 速さを優先するモデル(xsmall)の場所．併用(zenzaiChoice)を試すときに渡す
    ///   - zenzaiChoice: 設定の「Zenzai のモデル」．渡したときだけ既定の設定にこれを入れてエンジンに渡す(渡さなければ今までどおり設定を渡さない)
    init(zenzaiPath: String?, zenzaiVariant: ZenzaiModel.Variant = .small, fastZenzaiPath: String? = nil, zenzaiChoice: ZenzaiModelChoice? = nil,
         dictionaryPath: String?) throws {
        memory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-playground-\(UUID().uuidString)")
        let zenzai = try zenzaiPath.map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0), variant: zenzaiVariant) }
        let fastZenzai = try fastZenzaiPath.map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0), variant: .xsmall) }
        engine = try AzooKeyConverterEngine(memoryDirectory: memory, versionString: "hajime-playground", zenzai: zenzai, fastZenzai: fastZenzai,
                                            dictionaryDirectory: dictionaryPath.map { URL(fileURLWithPath: $0, isDirectory: true) })
        if let zenzaiChoice {
            var settings = DefaultSettings.settings
            settings.zenzaiModel = zenzaiChoice
            engine.apply(settings)
        }
        let directory = memory
        typoService = zenzai.map { ZenzaiTypoService(zenzai: $0, memoryDirectory: directory, versionString: "hajime-playground") }
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
