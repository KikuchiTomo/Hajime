import Foundation
import S90Application
import S90Domain
import S90Engine
import S90Persistence

/// ローマ字の行を打つと，ライブ変換・候補の一覧・分岐図の結果を出す
@MainActor
enum Interactive {
    static func run(engine: AzooKeyConverterEngine) {
        let lexicon = WordListLexicon()
        func session(_ presentation: CandidatePresentation) -> InputSession {
            var settings = DefaultSettings.settings
            settings.candidatePresentation = presentation
            let store = StaticSettings(settings)
            return InputSession(converter: SupplementedConverter(engine.makeSession(), settings: store, calendar: SystemCalendar(clock: { Date() })), lexicon: lexicon, settings: store)
        }

        print("ローマ字を打って Enter．空の行で終わります．例: kyouhaiitenkidesune / pthon / konnnitiha")
        while true {
            print("s90> ", terminator: "")
            guard let line = readLine(), !line.isEmpty else { break }
            let list = session(.list)
            let lattice = session(.automatic)
            var marked = MarkedText.empty
            // 2 つのセッションを 1 キーずつ交互に動かすと，同じエンジンの状態を行き来して実機と違う結果になるので，順に打つ
            for character in line {
                marked = markedText(in: list.handle(KeyEvent(.character(character)), context: InputContext())) ?? marked
            }
            let corrected = marked.segments.contains { $0.style == .correction }
            print("  ライブ変換: \(marked.text)\(corrected ? "  (補正しました．Space で入力のままに戻ります)" : "")")
            for action in list.handle(KeyEvent(.down), context: InputContext()).actions {
                guard case .showCandidates(let panel) = action else { continue }
                let entries = panel.entries.enumerated().map { "\($0.offset + 1) \($0.element.text)" }
                print("  一覧:       \(entries.joined(separator: "  "))")
            }
            for character in line {
                _ = lattice.handle(KeyEvent(.character(character)), context: InputContext())
            }
            for action in lattice.handle(KeyEvent(.space), context: InputContext()).actions {
                guard case .showLattice(let grid) = action else { continue }
                // 幹(文)を ─ でつなぎ，迷う文節に ⑂ を付ける．注目している文節の枝を下に並べる
                let trunk = grid.columns.map { ($0.isFocused ? "[\($0.text)]" : $0.text) + ($0.isUncertain ? "⑂" : "") }
                print("  分岐図:     \(trunk.joined(separator: " ─ "))")
                if let note = grid.note { print("    \(note.text)") }
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
