import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

@MainActor
@Suite("英語の語の辞書(R-24)")
struct EnglishTermScenarioTests {
    private static let bundled = ["API", "OpenAI", "GitHub", "AI", "Sora"]

    private static let table: [String: [(text: String, readingCount: Int?)]] = [
        "あぴ": [("アピ", nil), ("あぴ", nil)],
        "おぺない": [("オペ内", nil), ("オペない", nil)],
        "そら": [("空", nil), ("そら", nil), ("ソラ", nil)],
        "あい": [("愛", nil), ("藍", nil), ("AI", nil), ("あい", nil)],
        "はじめ": [("初め", nil), ("はじめ", nil)],
        "githubをつかう": [("githubを使う", nil), ("githubをつかう", nil)],
    ]

    private static func converter() -> FakeConverter {
        let converter = FakeConverter(table)
        // 読み全体が漢字を含む 1 語になる読み(ふつうの日本語の語)
        for (text, reading) in [("空", 2), ("愛", 2), ("藍", 2), ("初め", 3)] {
            converter.candidateWords[text] = [Candidate.Word(text: text, readingCount: reading)]
        }
        return converter
    }

    private func converter(_ change: (inout Settings) -> Void = { _ in }) -> SupplementedConverter {
        var settings = DefaultSettings.settings
        change(&settings)
        let store = FakeSettings(settings)
        return SupplementedConverter(Self.converter(), settings: store, calendar: FakeCalendar(),
                                     englishTerms: EnglishTerms(bundled: FakeEnglishTermProvider(Self.bundled), settings: store))
    }

    private func texts(_ reading: String, _ change: (inout Settings) -> Void = { _ in }) -> [String] {
        converter(change).listCandidates(for: reading).map(\.text)
    }

    @Test("R-24: ローマ字として読めてしまった英語の語を第 1 候補にし，かなの候補も残す")
    func readsAsRomaji() {
        #expect(texts("あぴ") == ["API", "アピ", "あぴ"])
        #expect(texts("おぺない") == ["OpenAI", "オペ内", "オペない"])
    }

    @Test("R-24: 読み全体がふつうの日本語の語なら，日本語を先にして英語の語を 2 番目に出す")
    func japaneseWordFirst() {
        #expect(texts("そら") == ["空", "Sora", "そら", "ソラ"])
        // エンジンが出している語は，その候補のまま 2 番目に移す(学習に使えるように)
        let candidates = converter().listCandidates(for: "あい")
        #expect(candidates.map(\.text) == ["愛", "AI", "藍", "あい"])
        #expect(candidates[1].isFromEngine)
    }

    @Test("R-24: 英字の残る読みは英語として打ったものなので，英語の語を第 1 候補にする")
    func lettersRemain() {
        let reading = KeyEditSearch.rawReading(of: "github")
        #expect(converter().listCandidates(for: reading).first?.text == "GitHub")
    }

    @Test("R-24: 英字のまま確定させた語は，辞書の書き方にした候補を先に出し，打ったとおりの候補も残す")
    func appliesToFrozenLetters() {
        #expect(texts("githubをつかう").prefix(3) == ["GitHubを使う", "githubを使う", "githubをつかう"])
    }

    @Test("R-24: ユーザー辞書の語(他の IME から取り込んだ語を含む)を英語の語より先に出す")
    func userDictionaryFirst() {
        let found = texts("あぴ") { $0.userDictionary = [UserDictionaryEntry(reading: "あぴ", word: "亜飛")] }
        #expect(found.prefix(2) == ["亜飛", "API"])
    }

    @Test("R-24: 「いつも日本語にする語」「いつも英語にする語」に入れた語はそれに従う")
    func wordLanguageSettings() {
        #expect(texts("あぴ") { $0.wordLanguage.japaneseWords = ["api"] }.prefix(2) == ["アピ", "API"])
        #expect(texts("そら") { $0.wordLanguage.englishWords = ["sora"] }.first == "Sora")
    }

    @Test("R-24: 利用者が足した語も引き，同梱の語より先に出す")
    func userTerms() {
        #expect(texts("はじめ") { $0.englishTerms = ["Hajime"] } == ["初め", "Hajime", "はじめ"])
        #expect(texts("あぴ") { $0.englishTerms = ["Api"] }.prefix(2) == ["Api", "API"])
    }

    @Test("R-24: かな入力では英字を打ったときの読みで引かず，設定でオフにすれば足さない")
    func kanaInputAndSwitch() {
        #expect(texts("あぴ") { $0.inputStyle = .kana } == ["アピ", "あぴ"])
        #expect(texts("あぴ") { $0.englishTermCandidates = false } == ["アピ", "あぴ"])
        #expect(texts("githubをつかう") { $0.englishTermCandidates = false }.first == "githubを使う")
    }

    @Test("R-24: openai と打って止まると OpenAI を見せ，Space の一覧にはかなの候補も並ぶ")
    func typing() throws {
        var settings = Settings.listPresentation
        settings.liveConversionSkipLength = 0
        let harness = Harness(converter: Self.converter(), settings: settings, wrap: {
            SupplementedConverter($0, settings: $1, calendar: FakeCalendar(), englishTerms: EnglishTerms(bundled: FakeEnglishTermProvider(Self.bundled), settings: $1))
        })
        harness.type("openai")
        harness.settle()
        #expect(harness.marked.text == "OpenAI")
        harness.press(.space)
        let panel = try #require(harness.panel)
        #expect(panel.entries.map(\.text).prefix(3) == ["OpenAI", "オペ内", "オペない"])
        harness.press(.down)
        harness.press(.enter)
        #expect(harness.committed == "オペ内")
    }

    // MARK: 英単語の補正(R-02)

    private func lexicon(_ change: (inout Settings) -> Void = { _ in }) -> EnglishTermLexicon {
        var settings = DefaultSettings.settings
        change(&settings)
        let store = FakeSettings(settings)
        return EnglishTermLexicon(FakeLexicon(words: ["python"]), terms: EnglishTerms(bundled: FakeEnglishTermProvider(Self.bundled), settings: store))
    }

    @Test("R-24: 英語の語の辞書の語も英単語とみなし，小文字で打った語だけを辞書の書き方にする")
    func termLexicon() {
        let lexicon = lexicon()
        #expect(lexicon.isWord("openai") && lexicon.isWord("OpenAI") && lexicon.isWord("python"))
        #expect(!lexicon.isWord("opena"))
        #expect(lexicon.spelling(of: "openai") == "OpenAI")
        #expect(lexicon.spelling(of: "Openai") == nil)
        #expect(lexicon.spelling(of: "python") == nil)
        let off = self.lexicon { $0.englishTermCandidates = false }
        #expect(!off.isWord("openai") && off.isWord("python"))
        #expect(off.spelling(of: "openai") == nil)
    }

    private func correctingHarness(_ table: [String: [(text: String, readingCount: Int?)]] = [:]) -> Harness {
        var settings = DefaultSettings.settings
        settings.liveConversionSkipLength = 0
        let terms = Self.bundled + ["ChatGPT", "Claude"]
        return Harness(converter: FakeConverter(table), settings: settings,
                       wrap: { SupplementedConverter($0, settings: $1, calendar: FakeCalendar(), englishTerms: EnglishTerms(bundled: FakeEnglishTermProvider(terms), settings: $1)) },
                       wrapLexicon: { EnglishTermLexicon($0, terms: EnglishTerms(bundled: FakeEnglishTermProvider(terms), settings: $1)) })
    }

    @Test("R-24: スペルチェッカーが知らない語(claude)も英単語の補正で辞書の書き方にする")
    func correctsToTermSpelling() {
        let harness = correctingHarness()
        harness.type("claude")
        #expect(harness.marked.segments == [.init("Claude", style: .correction)])
    }

    @Test("R-24: 英単語にした語に日本語を続けると，辞書の書き方のまま文の中に確定させる")
    func termInSentence() {
        // 「chatgpt」+「wo」は「two」がとぉと読めてしまう．後ろだけを日本語として読んだ方がもっともらしいので英単語にする
        let harness = correctingHarness(["を": [("を", nil)], "ChatGPTをつかう": [("ChatGPTを使う", nil)]])
        harness.type("chatgptwotukau")
        harness.settle()
        #expect(harness.marked.text == "ChatGPTを使う")
        harness.press(.enter)
        #expect(harness.committed == "ChatGPTを使う")
    }
}
