import Foundation
import S90Application
import S90Domain
import S90Engine

/// ローマ字の行を打つと，ライブ変換・候補の一覧・文節格子の結果を出す
@MainActor
enum Interactive {
    static func run(engine: AzooKeyConverterEngine) {
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
                print("  文節格子:   \(grid.columns.map(\.text).joined(separator: " | "))")
                for (index, column) in grid.columns.enumerated() {
                    let mark = column.showsAlternatives ? "候補を見せる" : "確信度が高いので畳む"
                    print("    \(index + 1). \(column.alternatives.joined(separator: " / "))  (\(mark))")
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
