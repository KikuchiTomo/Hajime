import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimePersistence

/// 期待する文に着くまでの操作の数を測る(使い勝手の指標)．
///
/// 読みを打って Space で変換し，期待する文になるまで，アプリと同じ InputSession に次のキーを押す．
/// - 候補を選ぶ: ↓
/// - 文節を移る: ← →
/// - 文節の長さを変える: ⇧← ⇧→
/// 押した数を操作の数とする(読みを打つキー・Space・Enter は数えない)．左から順に，期待する文と食い違う最初の文節へ移って直す．
/// 候補に無ければ文節の長さを変えて探す．上限まで押しても着かなければ「着かない」とする．
/// 第 1 候補の正解率(AJIMEE-Bench の Accuracy@1)は文全体の第 1 候補しか見ないので，文節ごとに選び直す使い方でどれだけ手間がかかるかを別に測る
@MainActor
enum OperationEvaluation {
    /// 1 つの文節で ↓ を押して探す数の上限
    static let maximumDown = 30
    /// 文節の長さを変えて探す文字数の上限(短く・長くのそれぞれ)
    static let maximumResize = 3
    /// 1 文で押す数の上限．これを超えたら着かないとする
    static let maximumOperations = 60

    static func run(cases: [EvaluationCase], engine: AzooKeyConverterEngine, presentations: [CandidatePresentation]) {
        // 単語の一覧の読み込みは重いので，文ごとに作らず使い回す
        let lexicon = WordListLexicon()
        for presentation in presentations {
            print("== 候補の出し方: \(presentation.rawValue)")
            var counts: [Int?] = []
            for item in cases {
                guard let keys = typingKeys(for: item.reading) else {
                    print("-  \(item.reading)  打てない文字を含むので飛ばす")
                    continue
                }
                let driver = Driver(engine: engine, lexicon: lexicon, presentation: presentation, leftContext: item.leftContext)
                for key in keys { driver.press(key) }
                // ライブ変換を切って打つので，組み立て中の文字がそのまま読み
                guard driver.text == item.reading else {
                    print("-  \(item.reading)  打った読みが違う(\(driver.text))ので飛ばす")
                    continue
                }
                driver.press(KeyEvent(.space))
                let first = driver.segments.map(\.text).joined(separator: "｜")
                let operations = reach(driver, expected: item.expected)
                counts.append(operations)
                let mark = operations == 0 ? "○" : operations == nil ? "×" : "△"
                let detail = operations.map { $0 == 0 ? "" : "  操作 \($0)" } ?? "  着かない"
                print("\(mark)  \(item.reading)  → \(first)\(detail)" + (operations == 0 ? "" : "   期待: \(item.expected.joined(separator: " か "))"))
            }
            summarize(counts)
        }
    }

    /// 結果のまとめ．第 1 候補で正解・3 操作以内・着いた割合と，着いた文の操作の数の平均
    private static func summarize(_ counts: [Int?]) {
        let total = Double(counts.count)
        guard total > 0 else { return }
        let reached = counts.compactMap { $0 }
        func rate(_ limit: Int) -> Double { Double(reached.filter { $0 <= limit }.count) / total * 100 }
        let mean = reached.isEmpty ? 0 : Double(reached.reduce(0, +)) / Double(reached.count)
        // 着かなかった文は上限の数とみなして平均に入れる(着かないことを手間として数える)
        let penalized = Double(reached.reduce(0, +) + (counts.count - reached.count) * maximumOperations) / total
        print(String(format: "第 1 候補で正解: %.1f%%  3 操作以内: %.1f%%  着いた: %.1f%%  操作の平均(着いた文): %.2f  操作の平均(着かない文を %d とする): %.2f",
                     rate(0), rate(3), Double(reached.count) / total * 100, mean, maximumOperations, penalized))
    }

    /// 期待する文になるまで押した数．着かなければ nil
    private static func reach(_ driver: Driver, expected: [String]) -> Int? {
        var operations = 0
        // 同じ文節を何度も直そうとして回り続けないよう，直す回数を文節の数で抑える
        var attempts = 0
        while operations <= maximumOperations, attempts <= driver.segments.count * 2 {
            attempts += 1
            let texts = driver.segments.map(\.text)
            if expected.contains(texts.joined()) { return operations }
            guard let wrong = firstWrongSegment(texts, expected: expected) else { return nil }
            let prefix = texts.prefix(wrong).joined()
            guard let moves = driver.focus(wrong) else { return nil }
            operations += moves
            guard let fixes = fixFocused(driver, prefix: prefix, expected: expected) else { return nil }
            operations += fixes
        }
        return expected.contains(driver.text) ? operations : nil
    }

    /// 先頭からつないで，期待する文の先頭と合わなくなる最初の文節
    private static func firstWrongSegment(_ texts: [String], expected: [String]) -> Int? {
        var prefix = ""
        for (index, text) in texts.enumerated() {
            prefix += text
            let isLast = index == texts.count - 1
            if !expected.contains(where: { isLast ? $0 == prefix : $0.hasPrefix(prefix) }) { return index }
        }
        return nil
    }

    /// 注目している文節を，期待する文の続きに合う候補にするまでに押した数．文節の長さを変えて探す．見つからなければ nil
    private static func fixFocused(_ driver: Driver, prefix: String, expected: [String]) -> Int? {
        func fits() -> Bool {
            guard let index = driver.focusedIndex else { return false }
            let texts = driver.segments.map(\.text)
            let upTo = prefix + texts[index]
            let isLast = index == texts.count - 1
            return expected.contains { isLast ? $0 == upTo : $0.hasPrefix(upTo) }
        }
        if let downs = searchDown(driver, until: fits) { return downs }
        for length in 1...maximumResize {
            for (key, back) in [(KeyEvent.Key.left, KeyEvent.Key.right), (.right, .left)] {
                let before = driver.text
                var pressed = 0
                for _ in 0..<length {
                    driver.press(KeyEvent(key, modifiers: .shift))
                    pressed += 1
                }
                if driver.text == before { continue }
                if fits() { return length }
                if let downs = searchDown(driver, until: fits) { return length + downs }
                for _ in 0..<pressed { driver.press(KeyEvent(back, modifiers: .shift)) }
            }
        }
        return nil
    }

    /// ↓ を押して，fits を満たす候補になるまでの数．見つからなければ押した分 ↑ で戻して nil
    private static func searchDown(_ driver: Driver, until fits: () -> Bool) -> Int? {
        let start = driver.focusedText
        var pressed = 0
        for count in 1...maximumDown {
            driver.press(KeyEvent(.down))
            pressed = count
            if fits() { return count }
            // 一周して元の候補に戻った
            if count > 1, driver.focusedText == start { break }
        }
        for _ in 0..<pressed { driver.press(KeyEvent(.up)) }
        return nil
    }

    /// 読みを打つキー．かなはローマ字に，記号はその記号になるキー(「（」は「(」，「…」は「z.」)に，ほかの字はそのまま打つ．
    /// 「ん」は「xn」で打つ(「nn」のあとの母音は「んな」行にも読まれるため)．ローマ字で打てない並びがあれば nil
    static func typingKeys(for reading: String) -> [KeyEvent]? {
        var keys: [KeyEvent] = []
        var run = ""
        func flush() -> Bool {
            guard !run.isEmpty else { return true }
            guard let romaji = KanaRomanizer.keys(for: run) else { return false }
            keys += romaji.map { KeyEvent(.character($0)) }
            run = ""
            return true
        }
        for character in reading {
            if character != "ん", character == "ー" || character.unicodeScalars.allSatisfy({ (0x3041...0x309F).contains($0.value) }) {
                run.append(character)
                continue
            }
            guard flush() else { return nil }
            let typed = character == "ん" ? "xn" : symbolKeys[character] ?? String(character)
            keys += typed.map { KeyEvent(.character($0)) }
        }
        return flush() ? keys : nil
    }

    /// 記号になるキー(ローマ字表と記号の表を逆に引いたもの)
    private static let symbolKeys: [Character: String] = [
        "、": ",", "。": ".", "「": "[", "」": "]", "・": "/", "…": "z.", "‥": "z,", "『": "z[", "』": "z]", "〜": "~",
        "！": "!", "？": "?", "（": "(", "）": ")", "：": ":", "；": ";", "＆": "&", "％": "%", "＃": "#", "＝": "=", "＋": "+",
    ]

    /// アプリと同じ InputSession にキーを押し，組み立て中の文字を覚える
    @MainActor
    final class Driver {
        let session: InputSession
        private var context: InputContext
        private(set) var marked = MarkedText.empty

        init(engine: AzooKeyConverterEngine, lexicon: WordListLexicon, presentation: CandidatePresentation, leftContext: String?) {
            var settings = DefaultSettings.settings
            settings.candidatePresentation = presentation
            // 打つたびに変換すると遅いので，ライブ変換を切って打つ．Space の変換は読み全体から求めるので結果は変わらない
            settings.liveConversion = false
            let store = StaticSettings(settings)
            // 英語の語の辞書(R-24)は，リポジトリの頭で動かしたときに data/ から読む(make try と同じ)
            let terms = EnglishTerms(bundled: EnglishTermFile(url: EnglishTermCheck.bundledURL), settings: store)
            let converter = SupplementedConverter(engine.makeSession(), settings: store, calendar: SystemCalendar(clock: { Date() }), emoji: engine,
                                                  englishTerms: terms)
            session = InputSession(converter: converter, lexicon: lexicon, settings: store)
            context = InputContext(precedingText: leftContext)
        }

        func press(_ event: KeyEvent) {
            let result = session.handle(event, context: context)
            apply(result.actions)
            for step in session.followUps(context: context) { apply(step()) }
            // 左の文脈は打ち始めのときだけ渡す(アプリと同じ)
            context = InputContext()
        }

        private func apply(_ actions: [ClientAction]) {
            for action in actions {
                if case .setMarkedText(let text) = action { marked = text }
            }
        }

        var segments: [MarkedText.Segment] { marked.segments }
        var text: String { marked.text }
        var focusedIndex: Int? { segments.firstIndex { $0.style == .focused } }
        var focusedText: String? { focusedIndex.map { segments[$0].text } }

        /// index の文節に注目を移すまで ← → を押した数．移れなければ nil
        func focus(_ index: Int) -> Int? {
            var moves = 0
            while let current = focusedIndex, current != index {
                guard moves <= segments.count else { return nil }
                press(KeyEvent(current < index ? .right : .left))
                moves += 1
                if focusedIndex == current { return nil }
            }
            return focusedIndex == index ? moves : nil
        }
    }
}
