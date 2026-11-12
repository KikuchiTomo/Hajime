import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimePersistence

/// 読みを打ったときに候補の窓へ出る候補を，出し方ごとに出す(足した候補がどの位置に見えるかを確かめるため)．
///
/// アプリと同じ InputSession に読みのキーを打ち，次を出す．どれも既定の設定に adjust を当てた設定(出し方だけを変える)で求める
/// - 入力中の候補の窓: 打ち終えたときに出ている候補．既定の設定ではライブ変換をオフにしたときだけ出るので，ライブ変換をオフにして打つ
/// - 分岐図・文節ごとの一覧: Space のあと，文節ごとに注目を移し，↓ で末尾まで選んだ候補．1 ページに見える数で「|」を入れる
/// - 文全体の一覧: Space のあと ↓ で末尾まで選んだ候補
/// 絵文字の候補には「*」を付ける
@MainActor
enum PanelDump {
    static func run(readings: [String], engine: AzooKeyConverterEngine, emoji: (any EmojiLooking)?, adjust: (inout Settings) -> Void = { _ in }) {
        let lexicon = WordListLexicon()
        var base = DefaultSettings.settings
        adjust(&base)
        func settings(_ presentation: CandidatePresentation, liveConversion: Bool? = nil) -> Settings {
            var settings = base
            settings.candidatePresentation = presentation
            if let liveConversion { settings.liveConversion = liveConversion }
            return settings
        }
        for reading in readings {
            print("== \(reading)")
            guard let keys = OperationEvaluation.typingKeys(for: reading) else {
                print("  打てない文字を含むので飛ばす")
                continue
            }
            let typing = Driver(engine: engine, lexicon: lexicon, settings: settings(.automatic, liveConversion: false), emoji: emoji)
            for key in keys { typing.press(key) }
            print("  入力中の候補の窓: \(format(typing.suggestions, perPage: nil))")
            for presentation in CandidatePresentation.allCases {
                let driver = Driver(engine: engine, lexicon: lexicon, settings: settings(presentation), emoji: emoji)
                for key in keys { driver.press(key) }
                driver.press(KeyEvent(.space))
                switch presentation {
                case .automatic, .segmentList:
                    let name = presentation == .automatic ? "分岐図" : "文節ごとの一覧"
                    let segments = driver.marked.segments.map(\.text)
                    print("  \(name): \(segments.joined(separator: "｜"))")
                    for index in segments.indices {
                        guard driver.focus(index) else { break }
                        let candidates = driver.walkCandidates()
                        print("    文節 \(index + 1): \(format(candidates, perPage: driver.perPage))")
                    }
                case .list:
                    print("  文全体の一覧: \(format(driver.walkCandidates(), perPage: driver.perPage))")
                }
            }
        }
    }

    /// 候補を番号付きで並べる．perPage ごとに「|」で区切り，絵文字に「*」を付ける
    private static func format(_ candidates: [String], perPage: Int?) -> String {
        guard !candidates.isEmpty else { return "(なし)" }
        var parts: [String] = []
        for (index, text) in candidates.enumerated() {
            if let perPage, index > 0, index % perPage == 0 { parts.append("|") }
            parts.append("\(index + 1).\(text)\(isEmoji(text) ? "*" : "")")
        }
        let emojiPositions = candidates.indices.filter { isEmoji(candidates[$0]) }.map { $0 + 1 }
        let note = emojiPositions.isEmpty ? "  絵文字なし" : "  絵文字: \(emojiPositions.map(String.init).joined(separator: ","))番目"
        return parts.joined(separator: " ") + note
    }

    private static func isEmoji(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.properties.isEmojiPresentation || $0 == "\u{FE0F}" }
    }

    @MainActor
    final class Driver {
        let session: InputSession
        let perPage: Int
        private(set) var marked = MarkedText.empty
        private(set) var suggestions: [String] = []
        private var lattice: LatticePanel?
        private var list: CandidatePanel?
        private let presentation: CandidatePresentation

        init(engine: AzooKeyConverterEngine, lexicon: WordListLexicon, settings: Settings, emoji: (any EmojiLooking)?) {
            presentation = settings.candidatePresentation
            perPage = presentation == .automatic ? settings.branchCandidatesPerPage : settings.listCandidatesPerPage
            let store = StaticSettings(settings)
            let terms = EnglishTerms(bundled: EnglishTermFile(url: EnglishTermCheck.bundledURL), settings: store)
            let engineSession = engine.makeSession()
            let converter = SupplementedConverter(engineSession, settings: store, calendar: SystemCalendar(clock: { Date() }), emoji: emoji,
                                                  englishTerms: terms)
            session = InputSession(converter: converter, lexicon: lexicon, settings: store, scorer: engineSession)
        }

        func press(_ event: KeyEvent) {
            apply(session.handle(event, context: InputContext()).actions)
            for step in session.followUps(context: InputContext()) { apply(step()) }
        }

        private func apply(_ actions: [ClientAction]) {
            for action in actions {
                switch action {
                case .setMarkedText(let text): marked = text
                case .showCandidates(let panel):
                    list = panel
                    // 番号を振らない窓は入力中の候補の窓
                    if !panel.showsNumbers { suggestions = panel.entries.map(\.text) }
                case .showLattice(let panel): lattice = panel
                case .hideCandidates:
                    list = nil
                    lattice = nil
                    suggestions = []
                default: break
                }
            }
        }

        private var focusedIndex: Int? { marked.segments.firstIndex { $0.style == .focused } }

        /// index の文節に注目を移す
        func focus(_ index: Int) -> Bool {
            var moves = 0
            while let current = focusedIndex, current != index, moves <= marked.segments.count {
                press(KeyEvent(current < index ? .right : .left))
                moves += 1
            }
            return focusedIndex == index
        }

        /// 今選んでいる候補の文字
        private var selected: String? {
            if presentation == .automatic, let column = lattice?.columns.first(where: \.isFocused) {
                return column.selectedAlternative.map { column.alternatives[$0] } ?? column.text
            }
            guard let list, let index = list.selectedEntry, list.entries.indices.contains(index) else { return nil }
            return list.entries[index].text
        }

        /// 候補の数
        private var total: Int { presentation == .automatic ? lattice?.total ?? 0 : list?.total ?? 0 }

        /// 注目している文節(一覧なら一覧)の候補を，↓ で末尾まで選んで集める．集めたあとは ↑ で先頭に戻す
        func walkCandidates() -> [String] {
            var texts: [String] = []
            if let first = selected { texts.append(first) }
            let count = total
            var pressed = 0
            while texts.count < count, pressed < count + 1 {
                press(KeyEvent(.down))
                pressed += 1
                guard let text = selected else { break }
                texts.append(text)
            }
            for _ in 0..<pressed { press(KeyEvent(.up)) }
            return texts
        }
    }
}
