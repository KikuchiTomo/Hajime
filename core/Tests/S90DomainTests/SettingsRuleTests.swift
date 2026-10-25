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
        #expect(SymbolTable.text(for: "(", profile: .programming) == "(")
        #expect(SymbolTable.text(for: "(", profile: .standard) == "（")
        #expect(SymbolTable.text(for: ",", profile: .programming) == "、")
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

    @Test("打ったままの読みが候補に無ければ，最後の候補より下とみなす")
    func typedMissing() {
        let other = ReadingCorrection(keys: "yoe", reading: "ヨエ", score: -9, cost: 2)
        #expect(ReadingCorrectionRule(level: .standard).correction(among: [fixed, other], reading: "よう") == fixed)
    }
}
