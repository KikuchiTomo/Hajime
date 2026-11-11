import Testing
@testable import HajimeDomain

@Suite("数字と英字に続く記号の表(R-28)")
struct SymbolTableTests {
    @Test("数字のあとの「.」「,」は数字と同じ幅のピリオドとカンマ", arguments: [
        (Character("."), Character("3"), "."), (",", "0", ","), (".", "３", "．"), (",", "９", "，"),
    ] as [(Character, Character, String)])
    func numberSeparator(character: Character, previous: Character, expected: String) {
        #expect(SymbolTable.numberSeparator(for: character, after: previous, settings: DefaultSettings.settings) == expected)
    }

    @Test("数字のあとでなければ句読点のまま(nil)", arguments: [Character("あ"), "a", "ー", "、"])
    func notAfterDigit(previous: Character) {
        #expect(SymbolTable.numberSeparator(for: ".", after: previous, settings: DefaultSettings.settings) == nil)
        #expect(SymbolTable.numberSeparator(for: ".", after: nil, settings: DefaultSettings.settings) == nil)
        #expect(SymbolTable.numberSeparator(for: "/", after: "3", settings: DefaultSettings.settings) == nil)
    }

    @Test("英数字のあとの「-」は，その文字と同じ幅のハイフン．かなと記号のあとは長音(nil)", arguments: [
        (Character("3"), "-"), ("A", "-"), ("z", "-"), ("３", "－"), ("Ａ", "－"),
    ] as [(Character, String?)])
    func hyphen(previous: Character, expected: String?) {
        #expect(SymbolTable.hyphen(after: previous, settings: DefaultSettings.settings) == expected)
    }

    @Test("かな・記号のあと・読みの先頭では長音にする", arguments: [Character("あ"), "ー", "＞", "、"])
    func longVowel(previous: Character) {
        #expect(SymbolTable.hyphen(after: previous, settings: DefaultSettings.settings) == nil)
        #expect(SymbolTable.hyphen(after: nil, settings: DefaultSettings.settings) == nil)
    }

    @Test("設定をオフにすると，いつも句読点と長音にする")
    func settingsOff() {
        var settings = DefaultSettings.settings
        settings.numberSeparators = false
        settings.alphanumericHyphen = false
        #expect(SymbolTable.numberSeparator(for: ".", after: "3", settings: settings) == nil)
        #expect(SymbolTable.hyphen(after: "3", settings: settings) == nil)
        #expect(SymbolTable.sign(before: "3", settings: settings) == nil)
    }

    @Test("数字の前の符号は数字と同じ幅")
    func sign() {
        #expect(SymbolTable.sign(before: "3", settings: DefaultSettings.settings) == "-")
        #expect(SymbolTable.sign(before: "３", settings: DefaultSettings.settings) == "－")
        #expect(SymbolTable.sign(before: "a", settings: DefaultSettings.settings) == nil)
    }

    @Test("読みが「-」で打った長音だけのときだけ，符号に置き換える")
    func replaceLeadingLongVowel() {
        var composition = Composition()
        composition.insertRomaji("-")
        let replaced = composition.replaceLeadingLongVowel(with: "-")
        #expect(replaced)
        #expect(composition.conversionReading == "-")
        var longer = Composition()
        for key in "ra-" { longer.insertRomaji(key) }
        let replacedLonger = longer.replaceLeadingLongVowel(with: "-")
        #expect(!replacedLonger)
        #expect(longer.conversionReading == "らー")
    }
}
