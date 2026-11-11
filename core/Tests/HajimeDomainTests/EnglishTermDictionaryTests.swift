import Foundation
import HajimeDomain
import Testing

@Suite("英語の語の辞書")
struct EnglishTermDictionaryTests {
    private let dictionary = EnglishTermDictionary(terms: ["API", "OpenAI", "GitHub", "AWS", "macOS", "Python"])

    @Test("R-24: ローマ字として読めてしまう英字は，打ったときの読みで引ける")
    func readingOfRomaji() {
        #expect(dictionary.terms(forReading: "あぴ") == ["API"])
        #expect(dictionary.terms(forReading: "おぺない") == ["OpenAI"])
        // 読めない並びが英字のまま残った読み
        #expect(dictionary.terms(forReading: KeyEditSearch.rawReading(of: "github")) == ["GitHub"])
        #expect(dictionary.terms(forReading: "あws") == ["AWS"])
        #expect(dictionary.terms(forReading: "まこs") == ["macOS"])
    }

    @Test("R-24: 英字のまま確定させた読みは英字で引き，大文字を含む読みは引かない")
    func readingOfLetters() {
        #expect(dictionary.terms(forReading: "github") == ["GitHub"])
        #expect(dictionary.terms(forReading: "python") == ["Python"])
        #expect(dictionary.terms(forReading: "Github").isEmpty)
        #expect(dictionary.terms(forKeys: "GITHUB") == ["GitHub"])
    }

    @Test("R-24: かな入力では，英字を打ったときの読みでは引かない")
    func kanaInput() {
        #expect(dictionary.terms(forReading: "あぴ", includesRomajiReadings: false).isEmpty)
        #expect(dictionary.terms(forReading: "github", includesRomajiReadings: false) == ["GitHub"])
    }

    @Test("R-24: 文字列の中の小文字の英字の語だけを辞書の書き方にする")
    func applyingTerms() {
        #expect(dictionary.applyingTerms(to: "githubを使う") == "GitHubを使う")
        #expect(dictionary.applyingTerms(to: "pythonとgithub") == "PythonとGitHub")
        // 英字や数字が続く並び(識別子)は語の一部なので変えない
        #expect(dictionary.applyingTerms(to: "mygithub") == nil)
        #expect(dictionary.applyingTerms(to: "github2") == nil)
        // 打った人が大文字を入れたものはそのまま
        #expect(dictionary.applyingTerms(to: "Githubを使う") == nil)
        #expect(dictionary.applyingTerms(to: "pyてょn") == nil)
    }

    @Test("R-24: 語は英字だけで 2 文字以上．ファイルの空の行と「#」の行は飛ばす")
    func parsing() {
        #expect(EnglishTermDictionary.isValidTerm("OpenAI"))
        #expect(!EnglishTermDictionary.isValidTerm("C"))
        #expect(!EnglishTermDictionary.isValidTerm("C++"))
        #expect(!EnglishTermDictionary.isValidTerm("Node.js"))
        #expect(!EnglishTermDictionary.isValidTerm("GPT4"))
        let parsed = EnglishTermDictionary(text: "# 略語\n  API \n\nOpenAI\r\nC++\nAPI\n")
        #expect(parsed.count == 2)
        #expect(parsed.terms(forKeys: "api") == ["API"])
        #expect(parsed.description == "EnglishTermDictionary(count: 2)")
    }

    @Test("R-24: 設定の英語の語は既定でオン．利用者が足した語は，語にならないものと重なりを捨てて読み戻す")
    func settings() throws {
        #expect(Settings().englishTermCandidates)
        #expect(Settings().englishTerms.isEmpty)
        let json = #"{"englishTermCandidates": false, "englishTerms": ["OpenAI", "C++", "OpenAI", 3, "Hajime"]}"#
        let decoded = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(!decoded.englishTermCandidates)
        #expect(decoded.englishTerms == ["OpenAI", "Hajime"])
        #expect(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test("R-24: 利用者が足した語を 1 行 1 語のファイルに書き出し，読み込める")
    func ruleList() {
        var settings = Settings()
        settings.englishTerms = ["OpenAI"]
        #expect(RuleList.englishTerms.rows(in: settings) == [RuleListRow(key: "OpenAI", value: "")])
        let rows = ["Hajime", " Zenzai ", "C++", "OpenAI"].map { RuleListRow(key: $0, value: "") }
        #expect(RuleList.englishTerms.merge(rows, into: &settings) == 3)
        #expect(settings.englishTerms == ["OpenAI", "Hajime", "Zenzai"])
        #expect(RuleList.englishTerms.exportFileName == "english-terms.txt")
    }

    @Test("R-24: まとめた辞書は，先の辞書の語を先に出す")
    func merging() {
        let user = EnglishTermDictionary(terms: ["Api", "Hajime"])
        let merged = user.merging(dictionary)
        #expect(merged.terms(forReading: "あぴ") == ["Api", "API"])
        #expect(merged.terms(forReading: "はじめ") == ["Hajime"])
        #expect(merged.count == dictionary.count + 2)
    }
}
