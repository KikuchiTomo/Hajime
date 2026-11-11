import Testing
@testable import HajimeDomain

@Suite("数字の書き方(R-27)")
struct NumberFormsTests {
    private let all = Set(NumberForms.Kind.allCases)

    @Test("白丸は 0〜50，黒丸は 0〜20 の境目で書き換え，範囲の外では出さない", arguments: [
        ("0", "⓪", "⓿"), ("1", "①", "❶"), ("10", "⑩", "❿"), ("11", "⑪", "⓫"), ("20", "⑳", "⓴"),
        ("21", "㉑", nil), ("35", "㉟", nil), ("36", "㊱", nil), ("50", "㊿", nil), ("51", nil, nil),
    ] as [(String, String?, String?)])
    func circled(reading: String, white: String?, black: String?) {
        let forms = NumberForms.candidates(for: reading, kinds: [.circled])
        #expect(forms == [white, black].compactMap { $0 })
    }

    @Test("括弧付きとピリオド付きは 1〜20", arguments: [
        ("0", [String]()), ("1", ["⑴", "⒈"]), ("20", ["⒇", "⒛"]), ("21", []),
    ])
    func parenthesized(reading: String, expected: [String]) {
        #expect(NumberForms.candidates(for: reading, kinds: [.parenthesized]) == expected)
    }

    @Test("漢数字は位取り・位付き・大字．1 桁の位取りは位付きと同じなので重ねない", arguments: [
        ("0", ["〇"]),
        ("1", ["一", "壱"]),
        ("10", ["一〇", "十", "壱拾"]),
        ("2026", ["二〇二六", "二千二十六", "弐千弐拾六"]),
        ("1000", ["一〇〇〇", "千", "壱千"]),
        ("11000", ["一一〇〇〇", "一万一千", "壱万壱千"]),
        ("100000000", ["一〇〇〇〇〇〇〇〇", "一億", "壱億"]),
        ("1234567890123456", ["一二三四五六七八九〇一二三四五六", "千二百三十四兆五千六百七十八億九千十二万三千四百五十六",
                              "壱千弐百参拾四兆五千六百七拾八億九千壱拾弐万参千四百五拾六"]),
    ])
    func kanji(reading: String, expected: [String]) {
        #expect(NumberForms.candidates(for: reading, kinds: [.kanji]) == expected)
    }

    @Test("ローマ数字は 1〜12 を 1 文字で，13〜3999 は文字を並べて書く．大文字と小文字", arguments: [
        ("0", [String]()), ("1", ["Ⅰ", "ⅰ"]), ("12", ["Ⅻ", "ⅻ"]), ("13", ["ⅩⅢ", "ⅹⅲ"]), ("40", ["ⅩⅬ", "ⅹⅼ"]),
        ("2026", ["ⅯⅯⅩⅩⅥ", "ⅿⅿⅹⅹⅵ"]), ("3999", ["ⅯⅯⅯⅭⅯⅩⅭⅨ", "ⅿⅿⅿⅽⅿⅹⅽⅸ"]), ("4000", []),
    ])
    func roman(reading: String, expected: [String]) {
        #expect(NumberForms.candidates(for: reading, kinds: [.roman]) == expected)
    }

    @Test("全角の数字も半角と同じに書き換える")
    func fullwidthDigits() {
        #expect(NumberForms.candidates(for: "２１", kinds: all) == NumberForms.candidates(for: "21", kinds: all))
        #expect(NumberForms.candidates(for: "２１", kinds: [.circled]) == ["㉑"])
    }

    @Test("数字だけでない読み・0 で始まる 2 桁以上・長すぎる数は書き換えない", arguments: [
        "01", "007", "1.5", "１．５", "-3", "+3", "3ー", "1,000", "いち", "", "12345678901234567",
    ])
    func notNumber(reading: String) {
        #expect(NumberForms.candidates(for: reading, kinds: all).isEmpty)
    }

    @Test("選んだ種類だけを，丸数字・括弧付き・漢数字・ローマ数字の順に並べる")
    func kindsAndOrder() {
        #expect(NumberForms.candidates(for: "1", kinds: all) == ["①", "❶", "⑴", "⒈", "一", "壱", "Ⅰ", "ⅰ"])
        #expect(NumberForms.candidates(for: "1", kinds: [.roman, .circled]) == ["①", "❶", "Ⅰ", "ⅰ"])
        #expect(NumberForms.candidates(for: "1", kinds: []).isEmpty)
    }
}
