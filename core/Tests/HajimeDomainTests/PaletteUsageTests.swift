import Foundation
import Testing
@testable import HajimeDomain

@Suite("パレットの使い方")
struct PaletteUsageTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private let day = 24.0 * 60 * 60

    @Test("使うたびに度合いを足し，半減期がたつと半分にする")
    func decay() {
        var usage = PaletteUsage()
        usage.record("🙇", at: start)
        usage.record("🙇", at: start)
        #expect(usage.score(of: "🙇", at: start) == 2)
        let later = start.addingTimeInterval(DefaultSettings.paletteUsageHalfLife)
        #expect(abs(usage.score(of: "🙇", at: later) - 1) < 1e-9)
        // 時計が戻っても増やさない
        #expect(usage.score(of: "🙇", at: start.addingTimeInterval(-day)) == 2)
        #expect(usage.score(of: "👍", at: start) == 0)
    }

    @Test("最近 1 回使った文字は，ずっと前に 2 回使った文字より上に来る")
    func recencyAndFrequency() {
        var usage = PaletteUsage()
        usage.record("👍", at: start)
        usage.record("👍", at: start)
        let now = start.addingTimeInterval(DefaultSettings.paletteUsageHalfLife * 2)
        usage.record("🙇", at: now)
        let scores = usage.scores(at: now)
        #expect(scores["🙇", default: 0] > scores["👍", default: 0])
    }

    @Test("同じ語で 2 回選んだ文字を覚える．打ったままの英数字を鍵にする")
    func learnedChoices() {
        var usage = PaletteUsage()
        let query = PaletteSearch.Query(typed: "Bo", kana: "ぼ")
        usage.record("🎳", query: query, at: start)
        #expect(usage.learnedChoices(for: query).isEmpty)
        usage.record("🎳", query: PaletteSearch.Query(typed: "bo"), at: start)
        #expect(usage.learnedChoices(for: query) == ["🎳"])
        #expect(usage.learnedChoices(for: PaletteSearch.Query(typed: "b")).isEmpty)
        #expect(PaletteSearch.Query(typed: "", kana: "ねこ").learningKey == "ねこ")
    }

    @Test("よく使う行は，残る文字を同じ位置に置き，外れた位置に新しい文字を入れる")
    func frequentRowKeepsPositions() {
        var usage = PaletteUsage()
        for (text, count) in [("A", 5), ("B", 4), ("C", 3)] {
            for _ in 0..<count { usage.record(text, at: start) }
        }
        var row = usage.refreshFrequentRow(count: 3, at: start)
        #expect(row == ["A", "B", "C"])
        // D を A より多く使っても，A・B・C の位置は動かさず，外れる B の位置に入れる
        for _ in 0..<10 { usage.record("D", at: start) }
        for _ in 0..<3 { usage.record("C", at: start) }
        row = usage.refreshFrequentRow(count: 3, at: start)
        #expect(row == ["A", "D", "C"])
    }

    @Test("新しい文字の度合いが外れる文字の 1.2 倍を超えないうちは入れ替えない")
    func frequentRowHysteresis() {
        var usage = PaletteUsage()
        for (text, count) in [("A", 5), ("B", 5)] {
            for _ in 0..<count { usage.record(text, at: start) }
        }
        var row = usage.refreshFrequentRow(count: 1, at: start)
        #expect(row == ["A"])
        usage.record("B", at: start)
        // B は 6，A は 5．6 は 5 × 1.2 を超えない
        row = usage.refreshFrequentRow(count: 1, at: start)
        #expect(row == ["A"])
        usage.record("B", at: start)
        row = usage.refreshFrequentRow(count: 1, at: start)
        #expect(row == ["B"])
    }

    @Test("ピン留めした文字はよく使う行に入れない．行が足りなければ後ろに足す")
    func frequentRowExcludesPins() {
        var usage = PaletteUsage()
        usage.record("A", at: start)
        usage.record("B", at: start)
        let pinned = usage.pin("A")
        #expect(pinned)
        var row = usage.refreshFrequentRow(count: 3, at: start, excluding: Set(usage.pinned))
        #expect(row == ["B"])
        usage.unpin("A")
        row = usage.refreshFrequentRow(count: 3, at: start)
        #expect(row == ["B", "A"])
    }

    @Test("ピン留めは上限まで．履歴を消してもピン留めと肌の色は残す")
    func pinsAndClear() {
        var usage = PaletteUsage()
        for index in 0..<DefaultSettings.maximumPalettePins {
            let pinned = usage.pin("\(index)")
            #expect(pinned)
        }
        let over = usage.pin("over")
        #expect(!over)
        usage.setSkinTone(.dark, for: "👍")
        usage.record("👍", query: PaletteSearch.Query(typed: "up"), at: start)
        usage.clearHistory()
        #expect(usage.score(of: "👍", at: start) == 0)
        #expect(usage.learnedChoices(for: PaletteSearch.Query(typed: "up")).isEmpty)
        #expect(usage.pinned.count == DefaultSettings.maximumPalettePins)
        #expect(usage.skinTone(for: "👍") == .dark)
    }

    @Test("絵文字ごとに選んだ肌の色が無ければ既定の肌の色を使う")
    func effectiveSkinTone() {
        var usage = PaletteUsage()
        usage.defaultSkinTone = .mediumDark
        usage.setSkinTone(.light, for: "👍")
        #expect(usage.effectiveSkinTone(for: "👍") == .light)
        #expect(usage.effectiveSkinTone(for: "👋") == .mediumDark)
        usage.setSkinTone(nil, for: "👍")
        #expect(usage.effectiveSkinTone(for: "👍") == .mediumDark)
    }

    @Test("1 つの文字を忘れると，度合いと語の記録とよく使う行から消す")
    func forget() {
        var usage = PaletteUsage()
        let query = PaletteSearch.Query(typed: "up")
        usage.record("👍", query: query, at: start)
        usage.record("👍", query: query, at: start)
        _ = usage.refreshFrequentRow(count: 3, at: start)
        usage.forget("👍")
        #expect(usage.score(of: "👍", at: start) == 0)
        #expect(usage.learnedChoices(for: query).isEmpty)
        #expect(usage.frequentRow.isEmpty)
    }

    @Test("覚える文字の数を上限に収め，度合いの低いものから捨てる")
    func prune() {
        var usage = PaletteUsage()
        usage.record("keep", at: start)
        usage.record("keep", at: start)
        for index in 0..<DefaultSettings.maximumPaletteUsageRecords {
            usage.record("\(index)", at: start)
        }
        #expect(usage.scores(at: start).count == DefaultSettings.maximumPaletteUsageRecords)
        #expect(usage.score(of: "keep", at: start) == 2)
    }

    @Test("書き出して読み直せる．壊れた項目があっても読める項目だけで始める")
    func coding() throws {
        var usage = PaletteUsage()
        usage.record("🙇", query: PaletteSearch.Query(typed: "bow"), at: start)
        _ = usage.pin("★")
        usage.setSkinTone(.medium, for: "👍")
        usage.defaultSkinTone = .light
        usage.lastKind = .symbol
        let data = try JSONEncoder().encode(usage)
        #expect(try JSONDecoder().decode(PaletteUsage.self, from: data) == usage)

        let broken = Data(#"{"records": "壊れた", "pinned": ["★"], "lastKind": "unknown"}"#.utf8)
        let decoded = try JSONDecoder().decode(PaletteUsage.self, from: broken)
        #expect(decoded.pinned == ["★"])
        #expect(decoded.scores(at: start).isEmpty)
        #expect(decoded.lastKind == nil)
    }

    @Test("ログに選んだ文字や探した語を出さない")
    func redacted() {
        var usage = PaletteUsage()
        usage.record("🙇", query: PaletteSearch.Query(typed: "secret"), at: start)
        #expect(!"\(usage)".contains("🙇"))
        #expect(!"\(PaletteSearch.Query(typed: "secret"))".contains("secret"))
    }
}
