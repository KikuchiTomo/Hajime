import Foundation
import Testing
@testable import S90Domain

@Suite("¥ キー")
struct YenKeyPolicyTests {
    @Test("R-04: 既定は \\")
    func defaultIsBackslash() {
        #expect(DefaultSettings.settings.yenKey.character(profile: .standard, optionPressed: false) == "\\")
    }

    @Test("R-04: Option で逆の文字")
    func optionInverts() {
        #expect(YenKeyPolicy.alwaysBackslash.character(profile: .standard, optionPressed: true) == "¥")
        #expect(YenKeyPolicy.alwaysYen.character(profile: .standard, optionPressed: true) == "\\")
    }

    @Test("R-04: プログラミング用のアプリだけ \\")
    func programmingOnly() {
        #expect(YenKeyPolicy.backslashInProgramming.character(profile: .standard, optionPressed: false) == "¥")
        #expect(YenKeyPolicy.backslashInProgramming.character(profile: .terminal, optionPressed: false) == "\\")
    }
}

@Suite("プロファイルと記号")
struct ProfileTests {
    @Test("R-06: アプリの識別子からプロファイルを決める")
    func profiles() {
        let settings = DefaultSettings.settings
        #expect(settings.profile(forApplication: "com.microsoft.VSCode") == .programming)
        #expect(settings.profile(forApplication: "com.jetbrains.intellij") == .programming)
        #expect(settings.profile(forApplication: "com.apple.Terminal") == .terminal)
        #expect(settings.profile(forApplication: "com.apple.TextEdit") == .standard)
        #expect(settings.profile(forApplication: nil) == .standard)
    }

    @Test("R-06: プログラミングでは括弧を半角のまま，句読点は全角")
    func symbols() {
        let settings = Settings()
        #expect(SymbolTable.text(for: "(", profile: .programming, settings: settings) == "(")
        #expect(SymbolTable.text(for: "(", profile: .standard, settings: settings) == "（")
        #expect(SymbolTable.text(for: ",", profile: .programming, settings: settings) == "、")
    }

    @Test("句読点・括弧・スラッシュは設定の文字にする")
    func symbolSettings() {
        var settings = Settings()
        settings.punctuation = .commaPeriod
        settings.brackets = .square
        settings.slash = .slash
        #expect(SymbolTable.text(for: ",", profile: .standard, settings: settings) == "，")
        #expect(SymbolTable.text(for: ".", profile: .standard, settings: settings) == "．")
        #expect(SymbolTable.text(for: "[", profile: .standard, settings: settings) == "［")
        #expect(SymbolTable.text(for: "/", profile: .standard, settings: settings) == "／")
        #expect(SymbolTable.text(for: "[", profile: .programming, settings: settings) == "[")
    }

    @Test("ユーザー辞書の語は，読みがひらがなで，長さが上限以内のときだけ使える")
    func userDictionaryEntry() {
        #expect(UserDictionaryEntry(reading: "えすきゅーじゅう", word: "s90").isValid)
        #expect(!UserDictionaryEntry(reading: "S90", word: "s90").isValid)
        #expect(!UserDictionaryEntry(reading: "", word: "s90").isValid)
        #expect(!UserDictionaryEntry(reading: "あ", word: String(repeating: "a", count: 65)).isValid)
    }
}

@Suite("タイプミスの補正の判定")
struct TypoCorrectionRuleTests {
    private func compose(_ keys: String) -> Composition {
        var composition = Composition()
        for key in keys { composition.insertRomaji(key) }
        return composition
    }

    @Test("R-02: 読めない並びは補正の対象")
    func tails() {
        let rule = TypoCorrectionRule(level: .standard)
        #expect(rule.tails(in: compose("python")).map(\.keys) == ["python"])
        #expect(rule.tails(in: compose("sakana")).isEmpty)
        #expect(rule.tails(in: compose("pyt")).isEmpty)
    }

    @Test("R-02: 打ちかけのローマ字(まだかなでない文字)は読めない並びに数えない")
    func pendingIsNotInvalid() {
        let rule = TypoCorrectionRule(level: .standard)
        #expect(rule.tails(in: compose("konob")).isEmpty)
        #expect(rule.tails(in: compose("hunnik")).isEmpty)
    }

    @Test("R-02: 文の途中に打った英単語も，区切りから末尾までの部分として見つける")
    func tailsInSentence() {
        let tails = TypoCorrectionRule(level: .standard).tails(in: compose("konobanopython"))
        #expect(tails.contains { $0.keys == "python" && $0.kanaStart == 4 })
    }

    @Test("R-02: 綴りの誤りは近い単語に直す")
    func spelling() {
        let rule = TypoCorrectionRule(level: .standard)
        #expect(rule.correction(for: "pthon", isWord: false, suggestions: ["python"]) == "python")
        #expect(rule.correction(for: "pthon", isWord: false, suggestions: ["marathon"]) == nil)
    }

    @Test("控えめの設定では綴りの誤りを直さない")
    func conservative() {
        let rule = TypoCorrectionRule(level: .conservative)
        #expect(rule.correction(for: "python", isWord: true, suggestions: []) == "python")
        #expect(rule.correction(for: "pthon", isWord: false, suggestions: ["python"]) == nil)
    }

    @Test("切る設定では何もしない")
    func off() {
        #expect(TypoCorrectionRule(level: .off).tails(in: compose("python")).isEmpty)
    }

    @Test("入れ替えは 1 回と数える")
    func distance() {
        #expect(EditDistance.damerauLevenshtein("pyhton", "python") == 1)
        #expect(EditDistance.damerauLevenshtein("pthon", "python") == 1)
    }
}

@Suite("候補ウィンドウの位置")
struct PanelPlacementTests {
    let screen = Rect(x: 0, y: 0, width: 1000, height: 800)
    let size = Rect(x: 0, y: 0, width: 200, height: 150)

    @Test("入力位置の下に出す")
    func below() {
        let origin = PanelPlacement.origin(caret: Rect(x: 100, y: 500, width: 2, height: 20), size: size, screen: screen)
        #expect(origin.x == 100)
        #expect(origin.y == 500 - PanelPlacement.gap - 150)
    }

    @Test("下に入らなければ上に出す")
    func above() {
        let origin = PanelPlacement.origin(caret: Rect(x: 100, y: 50, width: 2, height: 20), size: size, screen: screen)
        #expect(origin.y == 70 + PanelPlacement.gap)
    }

    @Test("右端で切れないようにずらす")
    func rightEdge() {
        let origin = PanelPlacement.origin(caret: Rect(x: 950, y: 500, width: 2, height: 20), size: size, screen: screen)
        #expect(origin.x == 800)
    }
}

@Suite("設定の読み込み")
struct SettingsDecodingTests {
    @Test("古い設定ファイルに無い項目は既定値で埋める")
    func missingKeys() throws {
        let json = #"{"liveConversion": false}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.liveConversion == false)
        #expect(settings.candidatePresentation == DefaultSettings.settings.candidatePresentation)
        #expect(settings.yenKey == DefaultSettings.settings.yenKey)
    }

    @Test("読めない値の項目だけを既定値にし，ほかの項目は読む")
    func invalidValue() throws {
        let json = #"{"liveConversion": false, "punctuation": "unknown", "spaceWidth": "fullwidth"}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.liveConversion == false)
        #expect(settings.punctuation == .toutenKuten)
        #expect(settings.spaceWidth == .fullwidth)
    }

    @Test("書き出した設定を読み戻すと同じになる")
    func roundTrip() throws {
        var settings = Settings()
        settings.learning = .readOnly
        settings.userDictionary = [UserDictionaryEntry(reading: "えすきゅーじゅう", word: "s90")]
        settings.numberWidth = .fullwidth
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings))
        #expect(decoded == settings)
    }
}

@Suite("候補の出し方の設定")
struct CandidatePresentationTests {
    @Test("古い版が保存した文節格子(lattice)は，分岐図として読む")
    func legacyLattice() throws {
        let decoded = try JSONDecoder().decode([CandidatePresentation].self, from: Data(#"["lattice","list"]"#.utf8))
        #expect(decoded == [CandidatePresentation.automatic, .list])
    }
}

@Suite("日本語の打ち間違いを直すかの判定")
struct ReadingCorrectionRuleTests {
    private let typed = ReadingCorrection(keys: "you", reading: "ヨウ", score: -9, cost: 0)
    private let fixed = ReadingCorrection(keys: "yoi", reading: "ヨイ", score: -5, cost: 2)

    @Test("十分にもっともらしければ直す")
    func corrects() {
        #expect(ReadingCorrectionRule(level: .standard).correction(among: [fixed, typed], reading: "よう") == fixed)
    }

    @Test("控えめ・切るの設定では直さない")
    func levels() {
        #expect(ReadingCorrectionRule(level: .conservative).correction(among: [fixed, typed], reading: "よう") == nil)
        #expect(ReadingCorrectionRule(level: .off).correction(among: [fixed, typed], reading: "よう") == nil)
    }

    @Test("打ったままの読みがこちらの読みと違えば直さない(nn の読み方の違いなど)")
    func differentReading() {
        #expect(ReadingCorrectionRule(level: .standard).correction(among: [fixed, typed], reading: "よー") == nil)
    }

    @Test("差が中くらいなら示すだけにする")
    func suggests() {
        let close = ReadingCorrection(keys: "yoi", reading: "ヨイ", score: -6.5, cost: 2)
        #expect(ReadingCorrectionRule(level: .standard).decision(among: [close, typed], reading: "よう") == .suggest(close))
        #expect(ReadingCorrectionRule(level: .standard).correction(among: [close, typed], reading: "よう") == nil)
    }

    @Test("同じキーの重なりは，母音の 2 回と 3 回以上の重なりだけを 1 回にして試す", arguments: [
        ("koonnichiha", ["konnichiha"]),
        ("kitte", []),
        ("konnnichiha", []),
        ("aaaru", ["aaru"]),
        ("ookii", ["okii", "ooki"]),
    ])
    func repeatedKeys(keys: String, expected: [String]) {
        #expect(ReadingCorrectionRule.repeatedKeyVariants(of: keys) == expected)
    }

    @Test("打ったままの読みが候補に無ければ，最後の候補より下とみなす")
    func typedMissing() {
        let other = ReadingCorrection(keys: "yoe", reading: "ヨエ", score: -9, cost: 2)
        #expect(ReadingCorrectionRule(level: .standard).correction(among: [fixed, other], reading: "よう") == fixed)
    }
}

@Suite("使い方の記録")
struct UsageCountsTests {
    @Test("候補を開かずに確定したものと，開いて選び直さなかったものを，第 1 候補のまま確定した割合に数える")
    func firstCandidateRate() {
        var counts = UsageCounts()
        #expect(counts.firstCandidateRate == nil)
        counts.record(.committed(changedSegments: 0, viaConversion: false))
        counts.record(.committed(changedSegments: 0, viaConversion: true))
        counts.record(.committed(changedSegments: 2, viaConversion: true))
        counts.record(.committed(changedSegments: 0, viaConversion: false))
        #expect(counts.firstCandidateRate == 0.75)
        #expect(counts.segmentsChanged == 2)
    }
}

@Suite("文節の区切り")
struct ClauseSplitterTests {
    private typealias Word = Candidate.Word

    @Test("漢字で始まる語から文節を始め，語の中のひらがなのあとの漢字でも分ける(「非常な人だ」)")
    func splitsInsideWord() {
        let clauses = ClauseSplitter.clauses(of: [Word(text: "非常", readingCount: 4), Word(text: "な人だ", readingCount: 4)])
        #expect(clauses == [.init(text: "非常な", readingCount: 5), .init(text: "人だ", readingCount: 3)])
    }

    @Test("「お茶」「ご飯」の接頭辞は分けない")
    func keepsHonorificPrefix() {
        let clauses = ClauseSplitter.clauses(of: [
            Word(text: "今日", readingCount: 3), Word(text: "は", readingCount: 1, startsWithParticle: true, endsWithParticle: true),
            Word(text: "お茶", readingCount: 3), Word(text: "を", readingCount: 1, startsWithParticle: true, endsWithParticle: true),
        ])
        #expect(clauses.map(\.text) == ["今日は", "お茶を"])
    }

    @Test("ひらがなの名詞から文節を始める(「ないという｜ところですかね」)")
    func startsAtKanaNoun() {
        let clauses = ClauseSplitter.clauses(of: [
            Word(text: "ないという", readingCount: 5),
            Word(text: "ところ", readingCount: 3, startsWithNoun: true),
            Word(text: "ですかね", readingCount: 4),
        ])
        #expect(clauses.map(\.text) == ["ないという", "ところですかね"])
    }

    @Test("1 文字の助詞のあとのひらがなの自立語で分ける(「今日は｜いい｜天気ですね」)")
    func splitsAfterParticle() {
        let clauses = ClauseSplitter.clauses(of: [
            Word(text: "今日", readingCount: 3),
            Word(text: "はいい", readingCount: 3, startsWithParticle: true),
            Word(text: "天気です", readingCount: 5),
            Word(text: "ね", readingCount: 1, startsWithParticle: true, endsWithParticle: true),
        ])
        #expect(clauses.map(\.text) == ["今日は", "いい", "天気ですね"])
        #expect(clauses.map(\.readingCount) == [4, 2, 6])
    }

    @Test("1 文字の助詞のあとで分け，助詞と助動詞だけの語は前の文節に付ける(「問題点が｜あれば」「天気ですね」)")
    func attachesFunctionWords() {
        let clauses = ClauseSplitter.clauses(of: [
            Word(text: "問題点", readingCount: 6),
            Word(text: "があれば", readingCount: 4, startsWithParticle: true, endsWithParticle: true),
            Word(text: "GitHub", readingCount: 5),
        ])
        #expect(clauses.map(\.text) == ["問題点が", "あれば", "GitHub"])
    }
}

@Suite("キー配列の設定")
struct KeyboardLayoutSettingTests {
    @Test("保存して読み直せ，知らない値は既定に戻す")
    func roundTrip() throws {
        var settings = Settings()
        settings.keyboardLayout = .dvorak
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(Settings.self, from: data).keyboardLayout == .dvorak)
        let unknown = Data(#"{"keyboardLayout":"workman"}"#.utf8)
        #expect(try JSONDecoder().decode(Settings.self, from: unknown).keyboardLayout == .system)
    }
}
