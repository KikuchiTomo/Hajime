import Foundation
import S90Application
import S90Domain
import S90Engine

/// ローマ字の行を打つと，ライブ変換・候補の一覧・分岐図の結果を出す
@MainActor
enum Interactive {
    static func run(engine: AzooKeyConverterEngine) {
        let lexicon = WordListLexicon()
        func session(_ presentation: CandidatePresentation) -> InputSession {
            var settings = DefaultSettings.settings
            settings.candidatePresentation = presentation
            return InputSession(converter: SymbolSupplementedConverter(engine.makeSession()), lexicon: lexicon, settings: StaticSettings(settings))
        }

        print("ローマ字を打って Enter．空の行で終わります．例: kyouhaiitenkidesune / pthon / konnnitiha")
        while true {
            print("s90> ", terminator: "")
            guard let line = readLine(), !line.isEmpty else { break }
            let list = session(.list)
            let lattice = session(.automatic)
            var marked = MarkedText.empty
            for character in line {
                marked = markedText(in: list.handle(KeyEvent(.character(character)), context: InputContext())) ?? marked
                _ = lattice.handle(KeyEvent(.character(character)), context: InputContext())
            }
            let corrected = marked.segments.contains { $0.style == .correction }
            print("  ライブ変換: \(marked.text)\(corrected ? "  (補正しました．Space で入力のままに戻ります)" : "")")
            for action in list.handle(KeyEvent(.down), context: InputContext()).actions {
                guard case .showCandidates(let panel) = action else { continue }
                let entries = panel.entries.enumerated().map { "\($0.offset + 1) \($0.element.text)" }
                print("  一覧:       \(entries.joined(separator: "  "))")
            }
            for action in lattice.handle(KeyEvent(.space), context: InputContext()).actions {
                guard case .showLattice(let grid) = action else { continue }
                // 幹(文)を ─ でつなぎ，迷う文節に ⑂ を付ける．注目している文節の枝を下に並べる
                let trunk = grid.columns.map { ($0.isFocused ? "[\($0.text)]" : $0.text) + ($0.isUncertain ? "⑂" : "") }
                print("  分岐図:     \(trunk.joined(separator: " ─ "))")
                if let note = grid.note { print("    \(note)") }
                for column in grid.columns {
                    if column.isFocused {
                        print("    ↑ 字種: \(column.variants.joined(separator: " / "))")
                        print("    ↓ 候補: \(column.alternatives.enumerated().map { "\($0.offset + 1) \($0.element)" }.joined(separator: "  "))")
                    } else if let preview = column.preview {
                        print("    \(column.text) の次の候補: \(preview)")
                    }
                }
            }
        }
    }

    private static func markedText(in result: KeyResult) -> MarkedText? {
        result.actions.compactMap { action -> MarkedText? in
            if case .setMarkedText(let text) = action { return text }
            return nil
        }.last
    }
}
