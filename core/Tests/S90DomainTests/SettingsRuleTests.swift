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

@Suite("除外設定の CSV")
struct ProfileRuleCSVTests {
    @Test("「アプリの ID,扱い」の行を読む．扱いは英語の値と画面の名前のどちらでもよく，形の誤った行は読み飛ばす")
    func parse() {
        let text = """
        app_id,mode
        # コメント
        com.apple.Terminal,terminal
        com.example.Game, IME を使わない
        com.example.Editor,記号を半角
        bad id with space,terminal
        com.example.Unknown,なにか
        com.apple.Terminal,direct
        """
        #expect(ProfileRuleCSV.parse(text) == [
            ProfileRule(applicationPrefix: "com.apple.Terminal", profile: .terminal),
            ProfileRule(applicationPrefix: "com.example.Game", profile: .direct),
            ProfileRule(applicationPrefix: "com.example.Editor", profile: .programming),
        ])
    }
}

@Suite("カスタムテーマと設定の範囲")
struct CustomThemeTests {
    @Test("色は #RRGGBB の形で読み書きする")
    func hexColor() {
        #expect(HexColor("#FF6600") == HexColor(red: 255, green: 102, blue: 0))
        #expect(HexColor("ff6600")?.hex == "#FF6600")
        #expect(HexColor("#FF66") == nil)
        #expect(HexColor("#GG6600") == nil)
    }

    @Test("使っているテーマが無くなったら既成のテーマに戻す")
    func missingActiveTheme() {
        var settings = Settings()
        settings.customThemeID = "gone"
        settings.clampToValidRanges()
        #expect(settings.customThemeID == nil)
        #expect(settings.activeCustomTheme == nil)
    }

    @Test("打ち間違いを直す基準で，直す差と示す差が変わる")
    func sensitivity() {
        let typed = ReadingCorrection(keys: "you", reading: "ヨウ", score: -9, cost: 0)
        let fixed = ReadingCorrection(keys: "yoi", reading: "ヨイ", score: -6.5, cost: 2)
        #expect(ReadingCorrectionRule(level: .standard, sensitivity: .standard).decision(among: [fixed, typed], reading: "よう") == .suggest(fixed))
        #expect(ReadingCorrectionRule(level: .standard, sensitivity: .aggressive).decision(among: [fixed, typed], reading: "よう") == .apply(fixed))
        #expect(ReadingCorrectionRule(level: .standard, sensitivity: .cautious).decision(among: [fixed, typed], reading: "よう") == nil)
        #expect(ReadingCorrectionRule(level: .standard, suggests: false).decision(among: [fixed, typed], reading: "よう") == nil)
    }
}

@Suite("使い分けと誤用の注釈")
struct UsageGuideTests {
    @Test("同音異義語は，活用した形でも読みと漢字の部分で当てはめる", arguments: [
        ("撮った", "とった", "撮る: 写真や動画を写す　ほかに 取る・採る・執る・捕る"),
        ("会えて", "あえて", "会う: 人と顔を合わせる　ほかに 合う・遭う"),
        ("精算", "せいさん", "精算: 料金などを細かく計算し直す　ほかに 清算・成算"),
    ])
    func homophone(text: String, reading: String, expected: String) {
        #expect(UsageGuide.homophoneNote(for: text, reading: reading) == expected)
    }

    @Test("送り仮名のある語は，漢字の部分のあとが送り仮名のときだけ当てはめる(「取引」には出さない)")
    func homophoneNeedsOkurigana() {
        #expect(UsageGuide.homophoneNote(for: "取引", reading: "とりひき") == nil)
        #expect(UsageGuide.homophoneNote(for: "天気", reading: "てんき") == nil)
    }

    @Test("誤用の言い回しには本来の形を添える")
    func misuse() {
        #expect(UsageGuide.misuseNote(for: "汚名挽回する") == "「汚名挽回」は「汚名返上」か「名誉挽回」が本来の形です")
        #expect(UsageGuide.misuseNote(for: "名誉挽回する") == nil)
    }
}

@Suite("取り込んだ辞書の設定(R-16)")
struct ImportedDictionarySettingTests {
    @Test("保存して読み直せ，条件も残る")
    func roundTrip() throws {
        var settings = Settings()
        settings.importedDictionaries = [
            ImportedDictionary(id: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B", name: "法律", field: "法律", condition: .apps(["com.microsoft.Word"]), wordCount: 3,
                               revision: String(repeating: "ab", count: 32)),
            ImportedDictionary(id: "7A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9", name: "電気", isEnabled: false, condition: .context, wordCount: 5),
        ]
        let decoded = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(settings))
        #expect(decoded.importedDictionaries == settings.importedDictionaries)
    }

    @Test("同期のファイルから来た設定でも，UUID の形でない id と 16 進でない版の辞書は捨てる(パスを差し込ませない)")
    func dropsUnsafeIdentity() throws {
        var settings = Settings()
        settings.importedDictionaries = [
            ImportedDictionary(id: "../../Library/x", name: "a", wordCount: 1),
            ImportedDictionary(id: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B", name: "b", wordCount: 1, revision: "../x"),
            ImportedDictionary(id: "7A2B3C4D-5E6F-4071-8293-A4B5C6D7E8F9", name: "c", wordCount: 1),
        ]
        let decoded = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(settings))
        #expect(decoded.importedDictionaries.map(\.name) == ["c"])
    }
}
