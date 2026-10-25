import Foundation
import S90Application
import S90Domain
import S90Engine

// 入力メソッドとして入れずに，ターミナルで変換を試す(make try)．composition root のひとつ．
// ローマ字の行を打つと，ライブ変換・候補の一覧・文節格子の結果を出す．
// 学習データは一時ディレクトリに置き，終わったら消す(試した入力を残さないため)．

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

@MainActor
func run() throws {
    let memory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-playground-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: memory) }
    let engine = try AzooKeyConverterEngine(memoryDirectory: memory, versionString: "s90-playground")
    let lexicon = WordListLexicon()

    func session(_ presentation: CandidatePresentation) -> InputSession {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = presentation
        return InputSession(converter: engine.makeSession(), lexicon: lexicon, settings: StaticSettings(settings))
    }

    print("ローマ字を打って Enter．空の行で終わります．例: kyouhaiitenkidesune / pthon / konnnitiha")
    while true {
        print("s90> ", terminator: "")
        guard let line = readLine(), !line.isEmpty else { break }
        let list = session(.list)
        let lattice = session(.lattice)
        var marked = MarkedText.empty
        var panel: CandidatePanel?
        var grid: LatticePanel?
        for character in line {
            for action in list.handle(KeyEvent(.character(character)), context: InputContext()).actions {
                if case .setMarkedText(let text) = action { marked = text }
            }
            _ = lattice.handle(KeyEvent(.character(character)), context: InputContext())
        }
        let corrected = marked.segments.contains { $0.style == .correction }
        print("  ライブ変換: \(marked.text)\(corrected ? "  (補正しました．Space で入力のままに戻ります)" : "")")
        for action in list.handle(KeyEvent(.down), context: InputContext()).actions {
            if case .showCandidates(let value) = action { panel = value }
        }
        if let panel {
            let entries = panel.entries.enumerated().map { "\($0.offset + 1) \($0.element.text)" }
            print("  一覧:       \(entries.joined(separator: "  "))")
        }
        for action in lattice.handle(KeyEvent(.space), context: InputContext()).actions {
            if case .showLattice(let value) = action { grid = value }
        }
        if let grid {
            print("  文節格子:   \(grid.columns.map(\.text).joined(separator: " | "))")
            for (index, column) in grid.columns.enumerated() {
                let mark = column.showsAlternatives ? "候補を見せる" : "確信度が高いので畳む"
                print("    \(index + 1). \(column.alternatives.joined(separator: " / "))  (\(mark))")
            }
        }
    }
}

MainActor.assumeIsolated {
    do {
        try run()
    } catch {
        print("起動できませんでした: \(error)")
        exit(1)
    }
}
