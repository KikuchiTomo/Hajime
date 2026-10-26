import Testing
@testable import S90Domain

private func compose(_ keys: String) -> Composition {
    var composition = Composition()
    for key in keys { composition.insertRomaji(key) }
    return composition
}

@Suite("ローマ字の組み立て")
struct CompositionTests {
    @Test("R-02: 英字として入れた部分(打ったとおりの英単語・Shift の英字)の直後の区切りから，日本語の打ち間違いを見直す")
    func boundaryAfterEnglish() throws {
        var composition = compose("python")
        composition.freeze(rawStart: 0, kanaStart: 0, keys: "python", as: "python", replaying: "ga")
        #expect(composition.boundaryAfterEnglish == Composition.Boundary(rawCount: 6, kanaCount: 6))
        let prefix = composition.truncated(to: try #require(composition.boundaryAfterEnglish))
        #expect(prefix.displayReading == "python")
        #expect(prefix.rawKeys == "python")

        var shifted = compose("kono")
        for key in "IME" { shifted.insertLiteral(String(key), rawKey: key) }
        for key in "ha" { shifted.insertRomaji(key) }
        #expect(shifted.boundaryAfterEnglish == Composition.Boundary(rawCount: 7, kanaCount: 5))

        // 綴りを直した語(「sride」→「bride」)は日本語の打ち間違いかもしれないので，見直しから外さない
        var corrected = compose("gakusride")
        corrected.freeze(rawStart: 4, kanaStart: 2, keys: "sride", as: "bride", replaying: "")
        #expect(corrected.boundaryAfterEnglish == Composition.Boundary(rawCount: 0, kanaCount: 0))
        // ローマ字として読めずに残った英字(打ち間違い)も外さない
        #expect(compose("simsu").boundaryAfterEnglish == Composition.Boundary(rawCount: 0, kanaCount: 0))
    }

    @Test("よく使う綴り", arguments: [
        ("konnnitiha", "こんにちは"),
        ("hunniki", "ふんいき"),
        ("hannei", "はんえい"),
        ("onnna", "おんな"),
        ("kanji", "かんじ"),
        ("shinnnyuu", "しんにゅう"),
        ("gakkou", "がっこう"),
        ("matcha", "まっちゃ"),
        ("kyou", "きょう"),
        ("thi-", "てぃー"),
        ("fami", "ふぁみ"),
        ("ltu", "っ"),
        ("n'a", "んあ"),
        ("minnna", "みんな"),
        ("tannnin", "たんにん"),
        ("henkann", "へんかん"),
    ])
    func spelling(keys: String, expected: String) {
        #expect(compose(keys).conversionReading == expected)
    }

    @Test("nn は必ず ん．次の母音と組ませない")
    func doubleNIsAlwaysNasal() {
        #expect(compose("onna").conversionReading == "おんあ")
        #expect(compose("konnichiha").conversionReading == "こんいちは")
        #expect(compose("hunniki").displayReading == "ふんいき")
    }

    @Test("末尾の n は表示では n のまま，変換では ん")
    func trailingN() {
        let composition = compose("henkan")
        #expect(composition.displayReading == "へんかn")
        #expect(composition.conversionReading == "へんかん")
    }

    @Test("R-02: ローマ字として読めない並びは英字のまま残し，印を付ける")
    func invalidRomaji() {
        let composition = compose("python")
        #expect(composition.displayReading == "pyてょn")
        #expect(composition.containsInvalidRomaji)
        #expect(composition.rawKeys == "python")
    }

    @Test("ふつうの綴りには印を付けない")
    func validRomaji() {
        #expect(!compose("sake").containsInvalidRomaji)
    }

    @Test("Backspace で打ったキーとの対応が外れる")
    func backspace() {
        var composition = compose("kya")
        composition.deleteBackward()
        #expect(composition.displayReading == "き")
        #expect(composition.rawKeys == nil)
        composition.deleteBackward()
        #expect(composition.isEmpty)
    }

    @Test("先頭だけ確定すると残りの読みになる")
    func dropPrefix() {
        var composition = compose("kyouhaame")
        composition.dropReadingPrefix(3)
        #expect(composition.conversionReading == "はあめ")
    }

    @Test("末尾の ん まで確定するとローマ字の残りも消える")
    func dropPrefixWithNasal() {
        var composition = compose("kan")
        composition.dropReadingPrefix(2)
        #expect(composition.isEmpty)
    }
}

@Suite("nn のあとの母音の読み")
struct NasalAmbiguityTests {
    private func compose(_ keys: String) -> Composition {
        var composition = Composition()
        for key in keys { composition.insertRomaji(key) }
        return composition
    }

    @Test("nn のあとの母音の位置を記録する")
    func records() {
        let composition = compose("onna")
        #expect(composition.nasalAmbiguities.map(\.kanaIndex) == [2])
        #expect(composition.conversionReading == "おんあ")
    }

    @Test("ん+な行 に切り替えられる")
    func switchToNaRow() {
        var composition = compose("onna")
        composition.setNasalReading(at: 0, usesNaRow: true)
        #expect(composition.conversionReading == "おんな")
        composition.setNasalReading(at: 0, usesNaRow: false)
        #expect(composition.conversionReading == "おんあ")
    }

    @Test("nny は や と にゃ を切り替え，後ろの位置をずらす")
    func yRow() {
        var composition = compose("konnyakuminna")
        #expect(composition.nasalAmbiguities.map(\.kanaIndex) == [2, 6])
        composition.setNasalReading(at: 0, usesNaRow: true)
        #expect(composition.conversionReading == "こんにゃくみんあ")
        #expect(composition.nasalAmbiguities.map(\.kanaIndex) == [2, 7])
        composition.setNasalReading(at: 1, usesNaRow: true)
        #expect(composition.conversionReading == "こんにゃくみんな")
    }

    @Test("な行で読んだところに n を足し，ローマ字表だけで同じ読みになるキーにする(打ち間違いの訂正に渡す)")
    func unambiguousKeys() {
        var composition = compose("konnyakuhonnoyomu")
        let start = composition.boundaries[0]
        #expect(composition.unambiguousKeys(from: start) == "konnyakuhonnoyomu")
        composition.setNasalReading(at: 1, usesNaRow: true)
        #expect(composition.unambiguousKeys(from: start) == "konnyakuhonnnoyomu")
        composition.setNasalReading(at: 0, usesNaRow: true)
        let keys = composition.unambiguousKeys(from: start)
        #expect(keys == "konnnyakuhonnnoyomu")
        #expect(compose(keys ?? "").conversionReading == composition.conversionReading)
    }

    @Test("nnn は に が確かなので記録しない")
    func tripleN() {
        #expect(compose("konnnitiha").nasalAmbiguities.isEmpty)
    }

    @Test("n のあとの子音は記録しない")
    func consonant() {
        #expect(compose("kannji").nasalAmbiguities.isEmpty)
    }

    @Test("消したり確定したりすると，位置を外すかずらす")
    func deleteAndDrop() {
        var composition = compose("hannei")
        composition.deleteBackward()
        composition.deleteBackward()
        #expect(composition.nasalAmbiguities.isEmpty)
        var dropped = compose("kyouhaonna")
        dropped.dropReadingPrefix(4)
        #expect(dropped.nasalAmbiguities.map(\.kanaIndex) == [2])
    }
}

@Suite("文字の種類")
struct ScriptVariantTests {
    @Test("R-03: 5 つの種類に変える")
    func variants() {
        let composition = compose("tokyo")
        #expect(ScriptVariant.hiragana.apply(to: composition) == "ときょ")
        #expect(ScriptVariant.katakana.apply(to: composition) == "トキョ")
        #expect(ScriptVariant.halfwidthKatakana.apply(to: composition) == "ﾄｷｮ")
        #expect(ScriptVariant.fullwidthRoman.apply(to: composition) == "ｔｏｋｙｏ")
        #expect(ScriptVariant.halfwidthRoman.apply(to: composition) == "tokyo")
    }

    @Test("濁点は半角では 2 文字")
    func voiced() {
        #expect(KanaWidth.halfwidthKatakana(from: "ガッコウ") == "ｶﾞｯｺｳ")
    }

    @Test("打ったキーが分からないときは英数にできない")
    func romanNeedsRawKeys() {
        var composition = compose("kya")
        composition.deleteBackward()
        #expect(ScriptVariant.halfwidthRoman.apply(to: composition) == nil)
    }
}

@Suite("記号の入力")
struct SymbolInputTests {
    @Test("z と組み合わせて記号を入れる", arguments: [("zh", "←"), ("zj", "↓"), ("zk", "↑"), ("zl", "→"), ("z-", "〜"), ("z.", "…"), ("z,", "‥"), ("z/", "・"), ("z[", "『"), ("z]", "』")])
    func zCombination(keys: String, expected: String) {
        #expect(compose(keys).conversionReading == expected)
    }

    @Test("z のあとに母音を打てば，ざ行のまま")
    func zStillRomaji() {
        #expect(compose("zazu").conversionReading == "ざず")
    }

    @Test("続けて打った記号を 1 つにまとめる", arguments: [("ー＞", "→"), ("＜ー", "←"), ("＝＞", "⇒"), ("＜＝", "⇐"), ("＜ー＞", "↔"), ("＜＝＞", "⇔")])
    func sequence(typed: String, expected: String) {
        var composition = Composition()
        composition.insertRomaji("a")
        for character in typed {
            if character == "ー" {
                composition.insertRomaji("-")
            } else {
                composition.insertLiteral(String(character))
            }
        }
        #expect(composition.conversionReading == "あ" + expected)
    }

    @Test("まとめた記号は Backspace 1 回で消える")
    func deleteMerged() {
        var composition = Composition()
        composition.insertRomaji("-")
        composition.insertLiteral("＞")
        composition.deleteBackward()
        #expect(composition.isEmpty)
    }
}

@Suite("読みから引く記号")
struct SymbolDictionaryTests {
    @Test("矢印・図形・単位などを引ける", arguments: [("やじるし", "→"), ("ほし", "★"), ("こめ", "※"), ("まるいち", "①"), ("ど", "℃"), ("むげんだい", "∞")])
    func lookup(reading: String, symbol: String) {
        #expect(SymbolDictionary.symbols(for: reading).contains(symbol))
    }
}

@Suite("かな入力")
struct KanaInputTests {
    @Test("JIS かな配列のキーの刻印からかなを引く", arguments: [("q", false, "た"), ("3", false, "あ"), ("3", true, "ぁ"), ("z", true, "っ"), (",", true, "、"), ("_", false, "ろ"), ("¥", false, "ー")])
    func layout(key: String, shift: Bool, kana: String) {
        #expect(KanaLayout.kana(forKey: key, shift: shift) == kana)
    }

    @Test("濁点と半濁点は前のかなと合わせる")
    func voicedMarks() {
        var composition = Composition()
        composition.insertKana("か")
        composition.insertKana("゛")
        composition.insertKana("は")
        composition.insertKana("゜")
        composition.insertKana("゛")
        #expect(composition.conversionReading == "がぱ゛")
    }
}
