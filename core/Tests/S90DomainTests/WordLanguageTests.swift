import Foundation
import Testing
@testable import S90Domain

@Suite("英語か日本語かの見分け")
struct WordLanguageTests {
    private func evidence(_ keys: String, english: Bool, reading: String? = "よみ", plausibility: Double = -4, offensive: Bool = false) -> WordLanguageJudge.Evidence {
        .init(keys: keys, isEnglishWord: english, reading: reading, plausibilityPerCharacter: plausibility, isOffensive: offensive)
    }

    @Test("R-05: 英字入力(自動)の見分け．読めない語は英語，辞書にない語はもっともらしさ，両方に読める語は前の語")
    func englishFirst() {
        let judge = WordLanguageJudge(settings: WordLanguageSettings(), mode: .englishFirst)
        #expect(judge.decide(evidence("hello", english: true, reading: nil), context: .afterJapanese) == .english)
        #expect(judge.decide(evidence("kyou", english: false), context: .sentenceStart) == .japanese)
        #expect(judge.decide(evidence("kathio", english: false, plausibility: -12), context: .sentenceStart) == .english)
        #expect(judge.decide(evidence("make", english: true), context: .sentenceStart) == .english)
        #expect(judge.decide(evidence("make", english: true), context: .afterEnglish) == .english)
        #expect(judge.decide(evidence("make", english: true), context: .afterJapanese) == .japanese)
    }

    @Test("R-02: ローマ字入力の見分け．辞書にない語は日本語，両方に読める語は前が英語のときだけ英語")
    func japaneseFirst() {
        let judge = WordLanguageJudge(settings: WordLanguageSettings(), mode: .japaneseFirst)
        #expect(judge.decide(evidence("kathio", english: false, plausibility: -12), context: .afterEnglish) == .japanese)
        #expect(judge.decide(evidence("make", english: true), context: .sentenceStart) == .japanese)
        #expect(judge.decide(evidence("make", english: true), context: .afterEnglish) == .english)
        // 短い語(「no」)は前が英語でも日本語．利用者が英語に決めた語は英語
        #expect(judge.decide(evidence("no", english: true, reading: "の"), context: .afterEnglish) == .japanese)
        var settings = WordLanguageSettings()
        settings.englishWords = ["no"]
        #expect(WordLanguageJudge(settings: settings, mode: .japaneseFirst).decide(evidence("no", english: true, reading: "の"), context: .afterEnglish) == .english)
        // 英字入力(自動)では今までどおり
        #expect(WordLanguageJudge(settings: WordLanguageSettings(), mode: .englishFirst).decide(evidence("no", english: true, reading: "の"), context: .afterEnglish) == .english)
    }

    @Test("R-05: 英字入力のライブ変換は，英語の辞書の語だけを英語にする")
    func dictionaryOnly() {
        let judge = WordLanguageJudge(settings: WordLanguageSettings(), mode: .dictionaryOnly)
        #expect(judge.decide(evidence("make", english: true), context: .afterJapanese) == .english)
        #expect(judge.decide(evidence("kathio", english: false, plausibility: -12), context: .afterEnglish) == .japanese)
    }

    @Test("R-02: 不適切な語は，前の手がかりが無ければ日本語にしない．設定で切れる")
    func offensive() {
        var settings = WordLanguageSettings()
        let shine = evidence("shine", english: true, reading: "しね", offensive: true)
        #expect(WordLanguageJudge(settings: settings, mode: .japaneseFirst).decide(shine, context: .sentenceStart) == .english)
        #expect(WordLanguageJudge(settings: settings, mode: .japaneseFirst).decide(shine, context: .afterJapanese) == .japanese)
        settings.avoidsOffensive = false
        #expect(WordLanguageJudge(settings: settings, mode: .japaneseFirst).decide(shine, context: .sentenceStart) == .japanese)
    }

    @Test("R-02: 利用者の語と決まりは，ほかの手がかりより先に使う")
    func userEntries() {
        var settings = WordLanguageSettings()
        settings.englishWords = ["kore"]
        settings.japaneseWords = ["make"]
        settings.rules = [WordLanguageRule(word: "same", context: .afterJapanese, language: .english)]
        let judge = WordLanguageJudge(settings: settings, mode: .englishFirst)
        #expect(judge.decide(evidence("kore", english: false), context: .afterJapanese) == .english)
        #expect(judge.decide(evidence("Make", english: true), context: .afterEnglish) == .japanese)
        #expect(judge.decide(evidence("same", english: true), context: .afterJapanese) == .english)
        #expect(judge.decide(evidence("same", english: true), context: .sentenceStart) == .english)
    }

    @Test("前の文字列から手がかりを決める", arguments: [
        (nil, WordLanguageContext.sentenceStart), ("", .sentenceStart), ("Let's ", .afterEnglish), ("v2", .afterEnglish),
        ("試合に", .afterJapanese), ("カタカナ　", .afterJapanese), ("「", .sentenceStart),
    ] as [(String?, WordLanguageContext)])
    func context(text: String?, expected: WordLanguageContext) {
        #expect(WordLanguageContext.of(precedingText: text) == expected)
    }

    @Test("設定は崩れた語と決まりを捨て，小文字にそろえ，同じものを重ねない")
    func decoding() throws {
        let json = """
        {"englishWords": ["Make", "make", "日本", ""], "japaneseWords": ["kore"],
         "rules": [{"word": "same", "context": "afterJapanese", "language": "english"}, {"word": 1},
                   {"word": "same", "context": "afterJapanese", "language": "japanese"}],
         "usesContext": false}
        """
        let settings = try JSONDecoder().decode(WordLanguageSettings.self, from: Data(json.utf8))
        #expect(settings.englishWords == ["make"])
        #expect(settings.japaneseWords == ["kore"])
        #expect(settings.rules == [WordLanguageRule(word: "same", context: .afterJapanese, language: .japanese)])
        #expect(!settings.usesContext)
        #expect(settings.avoidsOffensive)
        let round = try JSONDecoder().decode(WordLanguageSettings.self, from: JSONEncoder().encode(settings))
        #expect(round == settings)
    }
}
