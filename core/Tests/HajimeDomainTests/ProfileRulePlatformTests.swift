import Testing
@testable import HajimeDomain

@Suite("除外設定の決まりを OS ごとに出す")
struct ProfileRulePlatformTests {
    private func rule(_ name: String, _ profile: AppProfile = .terminal) -> ProfileRule {
        ProfileRule(applicationPrefix: name, profile: profile)
    }

    @Test("実行ファイルの名前は Windows，固有 ID は macOS，点を含まない名前は両方に出す")
    func splitsByName() {
        #expect(rule("com.apple.Terminal").isShown(on: .macOS))
        #expect(!rule("com.apple.Terminal").isShown(on: .windows))
        #expect(rule("com.jetbrains.").isShown(on: .macOS))
        #expect(!rule("cmd.exe").isShown(on: .macOS))
        #expect(rule("cmd.exe").isShown(on: .windows))
        #expect(!rule("Code.EXE").isShown(on: .macOS))
        #expect(rule("Code - Insiders.exe").isShown(on: .windows))
        #expect(rule("notepad").isShown(on: .macOS))
        #expect(rule("notepad").isShown(on: .windows))
    }

    @Test("既定の一覧は，macOS では固有 ID だけ，Windows では実行ファイルの名前だけを出す．どの決まりもどちらかに出る")
    func defaults() {
        let settings = DefaultSettings.settings
        let mac = settings.profileRules.shown(on: .macOS)
        let windows = settings.profileRules.shown(on: .windows)
        #expect(!mac.isEmpty && !windows.isEmpty)
        #expect(mac.allSatisfy { !$0.applicationPrefix.hasSuffix(".exe") })
        #expect(windows.allSatisfy { $0.applicationPrefix.hasSuffix(".exe") })
        #expect(mac.count + windows.count == settings.profileRules.count)
        // 判定(入力先のアプリの扱い)は今までどおり，すべての決まりを使う
        #expect(settings.profile(forApplication: "WindowsTerminal.exe") == .terminal)
        #expect(settings.profile(forApplication: "com.apple.Terminal") == .terminal)
    }

    @Test("並びを動かすときは出している決まりどうしを入れ替え，出していない決まりの位置は変えない")
    func movesAmongShown() {
        var rules = [rule("com.a"), rule("a.exe"), rule("b.exe"), rule("com.b"), rule("com.c")]
        #expect(!rules.canMove(rule("com.a"), by: -1, shownOn: .macOS))
        #expect(rules.canMove(rule("com.a"), by: 1, shownOn: .macOS))
        rules.move(rule("com.a"), by: 1, shownOn: .macOS)
        #expect(rules.map(\.applicationPrefix) == ["com.b", "a.exe", "b.exe", "com.a", "com.c"])
        rules.move(rule("com.c"), by: -1, shownOn: .macOS)
        #expect(rules.map(\.applicationPrefix) == ["com.b", "a.exe", "b.exe", "com.c", "com.a"])
        #expect(!rules.canMove(rule("com.a"), by: 1, shownOn: .macOS))
        // 出していない決まりは動かさない
        #expect(!rules.canMove(rule("a.exe"), by: 1, shownOn: .macOS))
        rules.move(rule("a.exe"), by: 1, shownOn: .macOS)
        #expect(rules.map(\.applicationPrefix) == ["com.b", "a.exe", "b.exe", "com.c", "com.a"])
    }
}
