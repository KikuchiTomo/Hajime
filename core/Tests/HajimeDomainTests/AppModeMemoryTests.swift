import HajimeDomain
import Testing

@Suite("アプリごとのモード")
struct AppModeMemoryTests {
    @Test("「IME のオンオフを記憶」はアプリで最後に使ったモードを返し，覚えていなければ切り替えない")
    func remembered() {
        var memory = AppModeMemory()
        #expect(memory.mode(entering: "com.example.a", profile: .remembersMode) == nil)
        memory.record(.direct, application: "com.example.a")
        memory.record(.japanese, application: "com.example.b")
        #expect(memory.mode(entering: "com.example.a", profile: .remembersMode) == .direct)
        #expect(memory.mode(entering: "COM.example.A", profile: .remembersMode) == .direct)
        #expect(memory.mode(entering: "com.example.a", profile: .standard) == nil)
        #expect(memory.lastMode == .japanese)
    }

    @Test("「IME をオフ」「IME をオン」は覚えたモードと関係なく決まったモードを返す")
    func fixed() {
        var memory = AppModeMemory()
        memory.record(.japanese, application: "off.exe")
        #expect(memory.mode(entering: "off.exe", profile: .imeOff) == .direct)
        #expect(memory.mode(entering: "on.exe", profile: .imeOn) == .japanese)
        #expect(memory.mode(entering: "x", profile: .direct) == nil)
    }

    @Test("同じアプリの中で入力欄を移っただけなら切り替えない．ほかのアプリから戻ったら切り替える")
    func sameApplication() {
        var memory = AppModeMemory()
        #expect(memory.enter("com.apple.Terminal", profile: .imeOff) == .direct)
        #expect(memory.enter("com.apple.Terminal", profile: .imeOff) == nil)
        memory.record(.japanese, application: "com.apple.Notes")
        #expect(memory.enter("com.apple.Notes", profile: .remembersMode) == .japanese)
        #expect(memory.enter("com.apple.Notes", profile: .remembersMode) == nil)
        #expect(memory.enter("com.apple.Terminal", profile: .imeOff) == .direct)
        #expect(memory.enter(nil, profile: .imeOff) == .direct)
        #expect(memory.enter("com.example.Other", profile: .standard) == nil)
    }

    @Test("覚えるアプリの数を超えたら，いちばん前に使ったアプリから忘れる")
    func capacity() {
        var memory = AppModeMemory(capacity: 2)
        memory.record(.direct, application: "a")
        memory.record(.direct, application: "b")
        memory.record(.direct, application: "a")
        memory.record(.direct, application: "c")
        #expect(memory.mode(of: "a") == .direct)
        #expect(memory.mode(of: "b") == nil)
        #expect(memory.mode(of: "c") == .direct)
    }

    @Test("アプリの決まりは大文字と小文字を区別しない")
    func caseInsensitiveRules() {
        var settings = DefaultSettings.settings
        settings.profileRules = [ProfileRule(applicationPrefix: "Code - Insiders.exe", profile: .imeOff)]
        #expect(settings.modeProfile(forApplication: "code - insiders.exe") == .imeOff)
        #expect(DefaultSettings.settings.profile(forApplication: "WindowsTerminal.exe") == .terminal)
    }

    @Test("実行ファイルの名前は空白・記号・日本語を含めてよい．区切りや式になる文字は入れない")
    func identifiers() {
        #expect(ProfileRuleCSV.isValidIdentifier("notepad++.exe"))
        #expect(ProfileRuleCSV.isValidIdentifier("Code - Insiders.exe"))
        #expect(ProfileRuleCSV.isValidIdentifier("秀丸.exe"))
        #expect(ProfileRuleCSV.isValidIdentifier("com.apple.Terminal"))
        #expect(!ProfileRuleCSV.isValidIdentifier("a,b"))
        #expect(!ProfileRuleCSV.isValidIdentifier("C:\\\\app.exe"))
        #expect(!ProfileRuleCSV.isValidIdentifier("=cmd"))
        #expect(!ProfileRuleCSV.isValidIdentifier(" a"))
        #expect(!ProfileRuleCSV.isValidIdentifier(""))
    }

    @Test("CSV では同じアプリに入力の扱いとモードの扱いを 1 つずつ読み，同じ種類は先の行を使う")
    func csvKinds() {
        let rules = ProfileRuleCSV.parse("a.exe,terminal\na.exe,imeOff\nA.exe,programming\n")
        #expect(rules.map(\.profile) == [.terminal, .imeOff])
    }

    @Test("CSV で新しい扱いを値でも画面の名前でも読む")
    func csv() {
        let rules = ProfileRuleCSV.parse("app_id,mode\na.exe,imeOff\nb.exe,IME をオン\nc.exe,IME のオンオフを記憶\n")
        #expect(rules.map(\.profile) == [.imeOff, .imeOn, .remembersMode])
    }
}
