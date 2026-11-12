import Foundation
import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

@MainActor
@Suite("エンジンのプロセスの要求の扱い")
struct EngineServiceTests {
    private let settings: FakeSettings
    private let service: EngineService
    private let sent: Box<[WireUiCommand]>
    private let opened: Box<Int>
    /// 設定の画面を開いたときの引数
    private let launched: Box<[[String]]>

    final class Box<Value> {
        var value: Value
        init(_ value: Value) { self.value = value }
    }

    init() {
        var initial = DefaultSettings.settings
        initial.liveConversion = false
        let settings = FakeSettings(initial)
        let sent = Box<[WireUiCommand]>([])
        let opened = Box(0)
        let launched = Box<[[String]]>([])
        let converter = FakeConverter(["かな": [("仮名", nil)]])
        self.settings = settings
        self.sent = sent
        self.opened = opened
        self.launched = launched
        self.service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings) },
            settings: settings,
            ui: { sent.value.append($0) },
            openSettings: { arguments in
                opened.value += 1
                launched.value.append(arguments)
            }
        )
    }

    private static let plain = WireModifiers(shift: false, control: false, alt: false)
    private static let field = WireFieldContext(applicationId: "notepad.exe", isSecure: false, caret: WireRect(x: 10, y: 20, width: 1, height: 16))

    private func greeted() -> EngineService.ConnectionID {
        let id = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        return id
    }

    private func open(_ id: EngineService.ConnectionID) throws -> UInt32 {
        let response = service.handle(WireRequest(id: 2, body: .openSession), from: id)
        guard case .sessionOpened(let session, _) = response.body else {
            Issue.record("セッションを作れない: \(response.body)")
            throw CancellationError()
        }
        return session
    }

    private func type(_ text: String, session: UInt32, from id: EngineService.ConnectionID) -> [WireResponseBody] {
        text.map { character in
            service.handle(WireRequest(id: 3, body: .key(session: session, input: WireKeyInput(key: .character(text: String(character)), modifiers: Self.plain, isKeypad: false),
                                                         context: Self.field)), from: id).body
        }
    }

    private func press(_ key: WireKey, session: UInt32, from id: EngineService.ConnectionID) -> WireResponseBody {
        service.handle(WireRequest(id: 4, body: .key(session: session, input: WireKeyInput(key: key, modifiers: Self.plain, isKeypad: false), context: Self.field)), from: id).body
    }

    @Test("版を確かめる前の要求と，版の違う DLL は断る")
    func version() {
        let id = service.connect()
        #expect(service.handle(WireRequest(id: 1, body: .openSession), from: id).body == .error(code: .unsupportedVersion))
        #expect(service.handle(WireRequest(id: 2, body: .hello(protocolVersion: WireProtocol.version + 1)), from: id).body == .error(code: .unsupportedVersion))
        let response = service.handle(WireRequest(id: 3, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        #expect(response == WireResponse(id: 3, body: .hello(protocolVersion: WireProtocol.version)))
    }

    @Test("DLL が知らせた組み立て中の文字全体の位置を，候補ウィンドウに送る(予測の窓を組み立て中の文字の右に置くため)")
    func compositionRect() throws {
        let id = greeted()
        let session = try open(id)
        let rect = WireRect(x: 30, y: 20, width: 12, height: 16)
        let composition = WireRect(x: 10, y: 20, width: 60, height: 16)
        #expect(service.handle(WireRequest(id: 5, body: .caret(session: session, rect: rect, composition: composition)), from: id).body == .done)
        #expect(sent.value.last == .move(anchor: rect, composition: composition))
        // 全体の位置を知らせない古い DLL でも動く
        _ = service.handle(WireRequest(id: 6, body: .caret(session: session, rect: rect, composition: nil)), from: id)
        #expect(sent.value.last == .move(anchor: rect, composition: nil))
    }

    @Test("打った読みを組み立て中の文字にし，変換して確定する")
    func compose() throws {
        let id = greeted()
        let session = try open(id)
        let typed = type("kana", session: session, from: id)
        guard case .edit(let handled, let operations, let state) = typed.last else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(handled)
        #expect(operations == [.setComposition(segments: [WireTextSegment(text: "かな", style: .reading)], caret: nil, panelAnchor: nil, replacedLength: nil)])
        #expect(state.isComposing)
        #expect(state.consumedKeys.isEmpty)

        guard case .edit(_, _, _) = press(.space, session: session, from: id) else {
            Issue.record("変換できない")
            return
        }
        #expect(sent.value.contains {
            switch $0 {
            case .showCandidates(_, let anchor), .showBranchMap(_, let anchor): anchor == Self.field.caret
            default: false
            }
        })

        guard case .edit(_, let committed, let after) = press(.enter, session: session, from: id) else {
            Issue.record("確定できない")
            return
        }
        #expect(committed.contains(.commit(text: "仮名")))
        #expect(!after.isComposing)
        #expect(sent.value.last == .hide)
    }

    @Test("ほかの接続のセッションは使えない")
    func otherConnection() throws {
        let first = greeted()
        let second = greeted()
        let session = try open(first)
        #expect(press(.space, session: session, from: second) == .error(code: .unknownSession))
        #expect(service.handle(WireRequest(id: 5, body: .closeSession(session: session)), from: second).body == .error(code: .unknownSession))
    }

    @Test("接続が切れたらその接続のセッションを捨てる")
    func disconnect() throws {
        let id = greeted()
        _ = try open(id)
        _ = try open(id)
        #expect(service.sessionCount == 2)
        service.disconnect(id)
        #expect(service.sessionCount == 0)
    }

    @Test("1 つの接続が作れるセッションには上限がある")
    func sessionLimit() throws {
        let id = greeted()
        for _ in 0..<EngineService.maximumSessionsPerConnection {
            _ = try open(id)
        }
        #expect(service.handle(WireRequest(id: 6, body: .openSession), from: id).body == .error(code: .tooManySessions))
    }

    private func activate(_ application: String, session: UInt32, from id: EngineService.ConnectionID) -> WireInputMode? {
        let body = service.handle(WireRequest(id: 8, body: .activate(session: session, context: WireFieldContext(applicationId: application, isSecure: false))), from: id).body
        guard case .edit(_, _, let state) = body else { return nil }
        return state.mode
    }

    private func setMode(_ mode: WireInputMode, session: UInt32, from id: EngineService.ConnectionID) {
        _ = service.handle(WireRequest(id: 9, body: .setMode(session: session, mode: mode)), from: id)
    }

    @Test("除外設定の「IME のオンオフを記憶」のアプリは，入力先を戻すと最後に使ったモードになる．決まりの無いアプリはほかのアプリで最後に使ったモードに揃う")
    func remembersModePerApplication() throws {
        try settings.update { $0.profileRules = [ProfileRule(applicationPrefix: "a.exe", profile: .remembersMode)] }
        let id = greeted()
        let first = try open(id)
        let second = try open(id)
        #expect(activate("A.exe", session: first, from: id) == .japanese)
        _ = service.handle(WireRequest(id: 10, body: .deactivate(session: first)), from: id)
        #expect(activate("b.exe", session: second, from: id) == .japanese)
        setMode(.direct, session: second, from: id)
        _ = service.handle(WireRequest(id: 10, body: .deactivate(session: second)), from: id)
        #expect(activate("a.exe", session: first, from: id) == .japanese)
        _ = service.handle(WireRequest(id: 10, body: .deactivate(session: first)), from: id)
        #expect(activate("b.exe", session: second, from: id) == .japanese)
    }

    @Test("入力先が移ってモードを変えたら，OS の入力モードも変えさせる")
    func activateSelectsMode() throws {
        try settings.update { $0.profileRules = [ProfileRule(applicationPrefix: "off.exe", profile: .imeOff)] }
        let id = greeted()
        let session = try open(id)
        let body = service.handle(WireRequest(id: 8, body: .activate(session: session, context: WireFieldContext(applicationId: "off.exe", isSecure: false))), from: id).body
        guard case .edit(_, let operations, let state) = body else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(state.mode == .direct)
        #expect(operations.contains(.selectMode(mode: .direct)))
        // もう同じモードなら何も送らない
        _ = service.handle(WireRequest(id: 10, body: .deactivate(session: session)), from: id)
        let again = service.handle(WireRequest(id: 8, body: .activate(session: session, context: WireFieldContext(applicationId: "off.exe", isSecure: false))), from: id).body
        guard case .edit(_, let none, _) = again else { return }
        #expect(none.isEmpty)
    }

    @Test("前のアプリの deactivate より先に次のアプリの activate が届いても，その次のアプリは移ったときのモードにそろう")
    func activateBeforeDeactivate() throws {
        try settings.update { $0.profileRules = [ProfileRule(applicationPrefix: "b.exe", profile: .imeOff)] }
        let id = greeted()
        let a = try open(id), b = try open(id), c = try open(id)
        #expect(activate("a.exe", session: a, from: id) == .japanese)
        #expect(activate("b.exe", session: b, from: id) == .direct)
        #expect(activate("c.exe", session: c, from: id) == .direct)
    }

    @Test("同じアプリに入力の扱いとモードの扱いを両方付けられる")
    func profileAndModeRules() throws {
        try settings.update {
            $0.profileRules = [ProfileRule(applicationPrefix: "windowsterminal.exe", profile: .imeOff),
                               ProfileRule(applicationPrefix: "windowsterminal.exe", profile: .terminal)]
        }
        #expect(settings.current.profile(forApplication: "WindowsTerminal.exe") == .terminal)
        #expect(settings.current.modeProfile(forApplication: "WindowsTerminal.exe") == .imeOff)
        let id = greeted()
        let session = try open(id)
        #expect(activate("WindowsTerminal.exe", session: session, from: id) == .direct)
    }

    @Test("除外設定の「IME をオフ」「IME をオン」のアプリは，入力先を移すたびにそのモードになる")
    func fixedModePerApplication() throws {
        try settings.update {
            $0.profileRules = [ProfileRule(applicationPrefix: "off.exe", profile: .imeOff), ProfileRule(applicationPrefix: "on.exe", profile: .imeOn)]
        }
        let id = greeted()
        let off = try open(id)
        let on = try open(id)
        #expect(activate("off.exe", session: off, from: id) == .direct)
        setMode(.japanese, session: off, from: id)
        #expect(activate("on.exe", session: on, from: id) == .japanese)
        setMode(.direct, session: on, from: id)
        #expect(activate("off.exe", session: off, from: id) == .direct)
        #expect(activate("on.exe", session: on, from: id) == .japanese)
    }

    @Test("パスワード欄では何もしない")
    func secure() throws {
        let id = greeted()
        let session = try open(id)
        let body = service.handle(WireRequest(id: 7, body: .key(session: session, input: WireKeyInput(key: .character(text: "k"), modifiers: Self.plain, isKeypad: false),
                                                               context: WireFieldContext(isSecure: true))), from: id).body
        guard case .edit(let handled, let operations, _) = body else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(!handled)
        #expect(operations.isEmpty)
    }

    @Test("ライブ変換を待つ時間を返し，wake で表示を変える")
    func wake() throws {
        try settings.update { $0.liveConversion = true }
        let id = greeted()
        let session = try open(id)
        guard case .edit(_, _, let state) = type("kana", session: session, from: id).last else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(state.wakeAfterMilliseconds == UInt32((settings.current.liveConversionDelay * 1000).rounded()))
        let woke = service.handle(WireRequest(id: 8, body: .wake(session: session, context: Self.field)), from: id).body
        guard case .edit(let handled, _, _) = woke else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(handled)
    }

    @Test("ライブ変換で待つ時間は設定の値に従う", arguments: [DefaultSettings.liveConversionDelayRange.lowerBound, DefaultSettings.liveConversionDelayRange.upperBound])
    func wakeFollowsDelay(delay: Double) throws {
        try settings.update {
            $0.liveConversion = true
            $0.liveConversionDelay = delay
        }
        let id = greeted()
        let session = try open(id)
        guard case .edit(_, _, let state) = type("kana", session: session, from: id).last else {
            Issue.record("編集の応答にならない")
            return
        }
        let wait = try #require(state.wakeAfterMilliseconds)
        // 打鍵から応答までにかかった時間だけ短くなる
        #expect(wait <= UInt32((delay * 1000).rounded()))
        #expect(wait > UInt32((delay * 1000).rounded()) - 50)
    }

    @Test("設定の画面から設定を読み書きし，範囲の外の値は直し，知らない値は変えない")
    func writeSettings() {
        let id = greeted()
        guard case .settings(var snapshot) = service.handle(WireRequest(id: 9, body: .readSettings), from: id).body else {
            Issue.record("設定を読めない")
            return
        }
        snapshot.theme = "washi"
        snapshot.inputStyle = "unknown"
        snapshot.liveConversion = true
        snapshot.candidateFontSize = 1000
        guard case .settings(let written) = service.handle(WireRequest(id: 10, body: .writeSettings(settings: snapshot)), from: id).body else {
            Issue.record("設定を書けない")
            return
        }
        #expect(settings.current.theme == .washi)
        #expect(settings.current.inputStyle == DefaultSettings.settings.inputStyle)
        #expect(settings.current.liveConversion)
        #expect(written.candidateFontSize < 1000)
    }

    @Test("入力メニューでライブ変換と設定の画面を選べる")
    func menu() {
        let id = greeted()
        #expect(service.handle(WireRequest(id: 31, body: .menu(command: .toggleLiveConversion)), from: id).body == .done)
        #expect(settings.current.liveConversion)
        #expect(service.handle(WireRequest(id: 32, body: .menu(command: .openSettings)), from: id).body == .done)
        #expect(opened.value == 1)
    }

    private func fields(_ body: WireRequestBody, from id: EngineService.ConnectionID) -> [String: JSONValue]? {
        guard case .settingsFields(let values) = service.handle(WireRequest(id: 20, body: body), from: id).body,
              let data = values.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: JSONValue].self, from: data)
    }

    @Test("設定の項目を設定のファイルと同じ名前と形で読む．知らない名前は断る")
    func readSettingsFields() {
        let id = greeted()
        let read = fields(.readSettingsFields(names: ["liveConversion", "listCandidatesPerPage"], defaults: false), from: id)
        #expect(read == ["liveConversion": .bool(false), "listCandidatesPerPage": .number(Double(DefaultSettings.settings.listCandidatesPerPage))])
        #expect(fields(.readSettingsFields(names: ["liveConversion"], defaults: true), from: id) == ["liveConversion": .bool(true)])
        #expect(fields(.readSettingsFields(names: [], defaults: false), from: id)?.keys.count == Settings.fieldNames.count)
        let unknown = service.handle(WireRequest(id: 21, body: .readSettingsFields(names: ["password"], defaults: false)), from: id)
        #expect(unknown.body == .error(code: .malformed))
    }

    @Test("設定の項目を書き，範囲の外の値は直し，書かない項目は変えない")
    func writeSettingsFields() {
        let id = greeted()
        settings.current.userDictionary = [UserDictionaryEntry(reading: "えすきゅー", word: "hajime")]
        let written = fields(.writeSettingsFields(values: #"{"theme":"washi","listCandidatesPerPage":1000,"keymap":[{"state":"idle","key":"Ctrl 7","command":"openSettings"}]}"#),
                             from: id)
        #expect(settings.current.theme == .washi)
        #expect(settings.current.listCandidatesPerPage == DefaultSettings.candidatesPerPageRange.upperBound)
        #expect(settings.current.keymap.entries == [KeymapEntry(.idle, KeyStroke(.character("7"), control: true), .openSettings)])
        #expect(settings.current.userDictionary.count == 1)
        #expect(!settings.current.liveConversion)
        #expect(written?.keys.sorted() == ["keymap", "listCandidatesPerPage", "theme"])
        #expect(written?["listCandidatesPerPage"] == .number(Double(DefaultSettings.candidatesPerPageRange.upperBound)))
        for broken in [#"{"theme":"washi","password":1}"#, "[1]", "not json"] {
            #expect(service.handle(WireRequest(id: 22, body: .writeSettingsFields(values: broken)), from: id).body == .error(code: .malformed))
        }
        #expect(settings.current.theme == .washi)
    }

    @Test("設定の画面で選び始めるキーとキーの案内の表示を変えると，入力中の候補の窓の案内が変わる")
    func suggestionNoteFollowsWrittenSettings() throws {
        let id = greeted()
        func suggestionNote() throws -> WireNote? {
            sent.value.removeAll()
            _ = type("kana", session: try open(id), from: id)
            let lists = sent.value.compactMap { if case .showCandidates(let list, _) = $0 { list } else { nil } }
            #expect(!lists.isEmpty)
            return lists.last?.note
        }
        let initial = try suggestionNote()
        #expect(initial?.key == "↓ Tab")
        #expect(initial?.keyAction == "選択")

        _ = fields(.writeSettingsFields(values: #"{"keymap":[{"state":"composing","key":"Ctrl n","command":"nextCandidate"},{"state":"composing","key":"Ctrl j","command":"acceptSuggestion"}]}"#),
                   from: id)
        #expect(try suggestionNote()?.key == "⌃N ⌃J")

        _ = fields(.writeSettingsFields(values: #"{"showsKeyHints":false}"#), from: id)
        #expect(try suggestionNote() == nil)
    }

    @Test("送れない大きさの設定は tooLarge で断る")
    func settingsFieldsTooLarge() {
        let id = greeted()
        settings.current.userDictionary = (0..<20_000).map { UserDictionaryEntry(reading: "よみ\($0)", word: "語句\($0)") }
        let response = service.handle(WireRequest(id: 23, body: .readSettingsFields(names: ["userDictionary"], defaults: false)), from: id)
        #expect(response.body == .error(code: .tooLarge))
        #expect(fields(.readSettingsFields(names: ["theme"], defaults: false), from: id) != nil)
    }

    @Test("キー設定のひな形を keymap の項目として返す")
    func keymapPreset() {
        let id = greeted()
        guard case .settingsFields(let values) = service.handle(WireRequest(id: 24, body: .readKeymapPreset(preset: "vim")), from: id).body,
              let merged = try? SettingsFields.merge(values, into: DefaultSettings.settings) else {
            Issue.record("ひな形を読めない")
            return
        }
        #expect(merged.settings.keymap == KeymapPreset.vim.keymap)
        #expect(service.handle(WireRequest(id: 25, body: .readKeymapPreset(preset: "unknown")), from: id).body == .error(code: .malformed))
    }

    @Test("キー設定の表の使われない行・文字を打てなくなる行・キーの無い確定と取り消しを知らせる")
    func checkKeymap() {
        let id = greeted()
        let values = #"{"keymap":[{"state":"composing","key":"Enter","command":"commit"},{"state":"composing","key":"Enter","command":"cancel"},{"state":"idle","key":"q","command":"openSettings"}]}"#
        guard case .keymapReport(let report) = service.handle(WireRequest(id: 26, body: .checkKeymap(values: values)), from: id).body else {
            Issue.record("表を調べられない")
            return
        }
        #expect(report.rows == [
            WireKeymapRowIssue(row: 0, hiddenBy: [1], hiddenStates: [], blocksTyping: false),
            WireKeymapRowIssue(row: 2, hiddenBy: [], hiddenStates: [], blocksTyping: true),
        ])
        #expect(report.missing.contains(WireKeymapMissing(state: "composing", command: "commit")))
        #expect(report.missing.contains(WireKeymapMissing(state: "converting", command: "cancel")))
        #expect(!report.missing.contains(WireKeymapMissing(state: "composing", command: "cancel")))
    }

    final class Usage: UsageReading {
        var counts = UsageCounts()
        func reset() { counts = UsageCounts() }
    }

    private func serviceWith(_ services: SettingsServices) -> (EngineService, EngineService.ConnectionID) {
        let service = EngineService(makeSession: { fatalError("セッションは作らない") }, settings: settings, ui: { _ in }, openSettings: { _ in }, services: services)
        let id = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        return (service, id)
    }

    @Test("学習を消す・使い方の記録を読んで消す")
    func learningAndUsage() {
        let resets = Box(0)
        let usage = Usage()
        usage.counts.commits = 4
        usage.counts.commitsWithoutConversion = 3
        let (service, id) = serviceWith(SettingsServices(resetLearning: { resets.value += 1 }, usage: usage))
        #expect(service.handle(WireRequest(id: 40, body: .resetLearning), from: id).body == .done)
        #expect(resets.value == 1)
        guard case .usage(let values, let rate) = service.handle(WireRequest(id: 41, body: .readUsage), from: id).body,
              let counts = try? JSONDecoder().decode(UsageCounts.self, from: Data(values.utf8)) else {
            Issue.record("使い方の記録を読めない")
            return
        }
        #expect(counts.commits == 4)
        #expect(rate == 0.75)
        guard case .usage(_, let cleared) = service.handle(WireRequest(id: 42, body: .resetUsage), from: id).body else {
            Issue.record("使い方の記録を消せない")
            return
        }
        #expect(cleared == nil)
        #expect(usage.counts.commits == 0)
    }

    @Test("英語と日本語の「試す」は語ごとに見せる文字と言語を返す")
    func previewLanguage() {
        let received = Box<(String, String?)?>(nil)
        let (service, id) = serviceWith(SettingsServices(previewLanguage: { text, preceding in
            received.value = (text, preceding)
            return [WordLanguagePreview.Word(typed: "make", language: .english, shown: "make")]
        }))
        let body = service.handle(WireRequest(id: 43, body: .previewLanguage(text: "make", precedingText: "I")), from: id).body
        #expect(body == .languagePreview(words: [WirePreviewWord(typed: "make", shown: "make", language: "english")]))
        #expect(received.value?.0 == "make")
        #expect(received.value?.1 == "I")
    }

    @Test("R-22: 変換マクロの「試す」は見本の語・読み・書いている途中の形を渡し，結果を返す")
    func previewMacros() {
        let received = Box<(String, String, String?)?>(nil)
        let (service, id) = serviceWith(SettingsServices(previewMacros: { text, reading, pattern in
            received.value = (text, reading, pattern)
            return ["【東京】"]
        }))
        let body = service.handle(WireRequest(id: 44, body: .previewMacros(text: "東京", reading: "とうきょう", pattern: "【{text}】")), from: id).body
        #expect(body == .macroPreview(results: ["【東京】"]))
        #expect(received.value?.0 == "東京")
        #expect(received.value?.1 == "とうきょう")
        #expect(received.value?.2 == "【{text}】")
    }

    @Test("ユーザー辞書の語を足す・消す・取り込む・ページごとに読む")
    func userDictionary() {
        let id = greeted()
        func add(_ reading: String, _ word: String) -> WireResponseBody {
            service.handle(WireRequest(id: 44, body: .addUserDictionaryEntry(entry: WireDictionaryEntry(reading: reading, word: word))), from: id).body
        }
        #expect(add("えすきゅー", "hajime") == .dictionaryAdded(result: .added))
        #expect(add("えすきゅー", "hajime") == .dictionaryAdded(result: .alreadyRegistered))
        #expect(add("漢字", "hajime") == .dictionaryAdded(result: .invalid))
        let merged = service.handle(WireRequest(id: 45, body: .mergeUserDictionary(entries: (0..<600).map { WireDictionaryEntry(reading: "よみ", word: "語句\($0)") })), from: id).body
        #expect(merged == .dictionaryMerged(added: 600))
        guard case .userDictionary(let page, let total) = service.handle(WireRequest(id: 46, body: .readUserDictionary(offset: 1, limit: 10_000)), from: id).body else {
            Issue.record("ユーザー辞書を読めない")
            return
        }
        #expect(total == 601)
        #expect(page.count == EngineService.maximumDictionaryPage)
        #expect(page.first == WireDictionaryEntry(reading: "よみ", word: "語句0", wordClass: .noun))
        guard case .userDictionary(let tail, _) = service.handle(WireRequest(id: 47, body: .readUserDictionary(offset: 1000, limit: 10)), from: id).body else {
            Issue.record("範囲の外を読めない")
            return
        }
        #expect(tail.isEmpty)
        #expect(service.handle(WireRequest(id: 48, body: .removeUserDictionaryEntry(entry: WireDictionaryEntry(reading: "えすきゅー", word: "hajime"))), from: id).body == .done)
        #expect(settings.current.userDictionary.count == 600)
        #expect(!settings.current.userDictionary.contains(UserDictionaryEntry(reading: "えすきゅー", word: "hajime")))
    }

    @Test("ユーザー辞書の語を品詞つきで足し，読み返す．品詞を送らなければ名詞，同じ語を別の品詞で足すと品詞を書き換え，消すときは品詞を問わない")
    func userDictionaryWordClass() {
        let id = greeted()
        func add(_ entry: WireDictionaryEntry) -> WireResponseBody {
            service.handle(WireRequest(id: 44, body: .addUserDictionaryEntry(entry: entry)), from: id).body
        }
        #expect(add(WireDictionaryEntry(reading: "やまだ", word: "山田", wordClass: .surname)) == .dictionaryAdded(result: .added))
        #expect(add(WireDictionaryEntry(reading: "かいしゃ", word: "会社")) == .dictionaryAdded(result: .added))
        #expect(settings.current.userDictionary.map(\.wordClass) == [.surname, .noun])
        #expect(add(WireDictionaryEntry(reading: "やまだ", word: "山田", wordClass: .place)) == .dictionaryAdded(result: .added))
        guard case .userDictionary(let page, _) = service.handle(WireRequest(id: 45, body: .readUserDictionary(offset: 0, limit: 10)), from: id).body else {
            Issue.record("ユーザー辞書を読めない")
            return
        }
        #expect(page.map(\.wordClass) == [.place, .noun])
        let removed = service.handle(WireRequest(id: 46, body: .removeUserDictionaryEntry(entry: WireDictionaryEntry(reading: "やまだ", word: "山田"))), from: id).body
        #expect(removed == .done)
        #expect(settings.current.userDictionary.map(\.word) == ["会社"])
    }

    @Test("ユーザー辞書の語のコメントを足して読み返す．コメントの無い語は送らない")
    func userDictionaryComment() {
        let id = greeted()
        let added = service.handle(WireRequest(id: 44, body: .addUserDictionaryEntry(entry: WireDictionaryEntry(reading: "かいしゃ", word: "会社", comment: "本社"))),
                                   from: id).body
        #expect(added == .dictionaryAdded(result: .added))
        _ = service.handle(WireRequest(id: 45, body: .addUserDictionaryEntry(entry: WireDictionaryEntry(reading: "あ", word: "亜"))), from: id)
        #expect(settings.current.userDictionary.map(\.comment) == ["本社", ""])
        guard case .userDictionary(let page, _) = service.handle(WireRequest(id: 46, body: .readUserDictionary(offset: 0, limit: 10)), from: id).body else {
            Issue.record("ユーザー辞書を読めない")
            return
        }
        #expect(page.map(\.comment) == ["本社", nil])
    }

    @Test("単語の登録: DLL が送った語と読みを持っておき，設定の画面をユーザー辞書の登録で開き，設定の画面にだけ一度渡す")
    func wordRegistration() {
        let dll = greeted()
        let opened = service.handle(WireRequest(id: 50, body: .openWordRegistration(text: "山田", reading: "やまだ")), from: dll).body
        #expect(opened == .done)
        #expect(launched.value.last == EngineService.settingsDictionaryArguments + [EngineService.settingsRegistrationArgument])
        #expect(service.handle(WireRequest(id: 51, body: .takeWordRegistration), from: dll).body == .error(code: .malformed))
        let app = service.connect(isSettingsApp: true)
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: app)
        #expect(service.handle(WireRequest(id: 52, body: .takeWordRegistration), from: app).body == .wordRegistration(word: "山田", reading: "やまだ"))
        #expect(service.handle(WireRequest(id: 53, body: .takeWordRegistration), from: app).body == .wordRegistration(word: nil, reading: nil))
        #expect(service.handle(WireRequest(id: 54, body: .openWordRegistration(text: "x", reading: nil)), from: app).body == .error(code: .malformed))
    }

    @Test("入力メニューの「ユーザー辞書…」は，設定の画面をユーザー辞書のページで開く")
    func openUserDictionary() {
        let dll = greeted()
        #expect(service.handle(WireRequest(id: 55, body: .menu(command: .openUserDictionary)), from: dll).body == .done)
        #expect(launched.value.last == EngineService.settingsDictionaryArguments)
    }

    @Test("入力メニューと選んでいる文字の読み取りは，扱えると知らせた DLL にだけ頼む")
    func menuAndRegistrationRouting() {
        let routed = RoutedActions([.openMenu, .openWordRegistration(word: nil, reading: nil), .openWordRegistration(word: "会社", reading: "かいしゃ"), .openUserDictionary],
                                   anchor: nil)
        #expect(routed.edits == [.showMenu, .requestWordRegistration(maximumLength: UInt32(DefaultSettings.maximumUserDictionaryWordLength))])
        #expect(routed.host == [.openWordRegistration(word: "会社", reading: "かいしゃ"), .openUserDictionary])
        let old = InputContext(WireFieldContext(applicationId: "notepad.exe", isSecure: false), settings: DefaultSettings.settings)
        #expect(!old.canOpenMenu)
        #expect(!old.canReadSelectionForRegistration)
        let new = InputContext(WireFieldContext(applicationId: "notepad.exe", isSecure: false, canShowMenu: true, canRequestWordRegistration: true),
                               settings: DefaultSettings.settings)
        #expect(new.canOpenMenu)
        #expect(new.canReadSelectionForRegistration)
    }

    @Test("通信の品詞は core の品詞と同じ名前を同じ順に持つ")
    func wordClassCases() {
        #expect(WireWordClass.allCases.map(\.rawValue) == WordClass.allCases.map(\.rawValue))
    }

    @Test("入力方式を切り替えたら，モード表示に入力方式を出す．出さない設定なら出さない")
    func styleIndicator() throws {
        let id = greeted()
        let session = try open(id)
        // 入力方式はメニューではなくキー(既定は Option+かな で順に切り替える)と設定の画面で変える
        let nextStyle = WireKeyInput(key: .kana, modifiers: WireModifiers(shift: false, control: false, alt: true), isKeypad: false)
        sent.value.removeAll()
        _ = service.handle(WireRequest(id: 40, body: .key(session: session, input: nextStyle, context: Self.field)), from: id)
        #expect(sent.value.contains { command in
            if case .showMode(_, _, let label) = command { return label == "かな" }
            return false
        })
        try settings.update { $0.showsModeIndicator = false }
        sent.value.removeAll()
        _ = service.handle(WireRequest(id: 41, body: .key(session: session, input: nextStyle, context: Self.field)), from: id)
        #expect(!sent.value.contains { command in
            if case .showMode = command { return true }
            return false
        })
    }

    @Test("見た目の設定は設定の値を運ぶ．変えたら変えた値を運ぶ")
    func presentation() throws {
        #expect(service.presentation.theme == settings.current.theme.rawValue)
        #expect(service.presentation.fontSize == settings.current.candidateFontSize)
        #expect(service.presentation.customTheme == nil)
        try settings.update {
            $0.theme = .terminal
            $0.candidateFontSize = DefaultSettings.candidateFontSizeRange.upperBound
            $0.modeIndicatorDuration = DefaultSettings.modeIndicatorDurationRange.upperBound
        }
        #expect(service.presentation.theme == ThemePreference.terminal.rawValue)
        #expect(service.presentation.fontSize == DefaultSettings.candidateFontSizeRange.upperBound)
        #expect(service.presentation.modeIndicatorMilliseconds == UInt32(DefaultSettings.modeIndicatorDurationRange.upperBound * 1000))
    }

    @Test("使っているカスタムテーマの色と形を運ぶ")
    func customThemePresentation() throws {
        let theme = CustomTheme(id: "sunset", name: "夕焼け", base: .washi, surface: HexColor("#2B1B17")!, text: HexColor("#FFE8D6")!,
                                textMuted: HexColor("#C9A68F")!, selection: HexColor("#FF7A3D")!, selectionText: HexColor("#1A0E0A")!,
                                correction: HexColor("#FFD23F")!, line: HexColor("#6B4A3E")!, fontName: "Yu Mincho", cornerRadius: 4, branchStyle: .straight)
        try settings.update {
            $0.customThemes = [theme]
            $0.customThemeID = theme.id
        }
        let custom = try #require(service.presentation.customTheme)
        #expect(custom.base == "washi")
        #expect(custom.surface == WireColor(red: 0x2B, green: 0x1B, blue: 0x17))
        #expect(custom.line == WireColor(red: 0x6B, green: 0x4A, blue: 0x3E))
        #expect(custom.fontName == "Yu Mincho")
        #expect(custom.cornerRadius == 4)
        #expect(custom.straightBranches)
    }
    @Test("Windows の設定の画面がカスタムテーマの色を書き換えた customThemes を書くと，そのテーマの色が変わり候補の窓に運ぶ")
    func customThemeColorFromSettingsApp() throws {
        let id = greeted()
        // Windows の設定の画面(themes::edited)は，テーマの配列をまるごと書く
        func themes(text: String) -> String {
            ##"{"customThemes":[{"id":"sunset","name":"夕焼け","base":"automatic","surface":"#2B1B17","text":"\##(text)","textMuted":"#C9A68F","##
                + ##""selection":"#FF7A3D","selectionText":"#1A0E0A","correction":"#FFD23F","line":"#6B4A3E","cornerRadius":4.0,"branchStyle":"curved"}]"##
        }
        _ = fields(.writeSettingsFields(values: themes(text: "#FFE8D6") + #","customThemeID":"sunset"}"#), from: id)
        #expect(settings.current.activeCustomTheme?.text == HexColor("#FFE8D6"))
        let written = fields(.writeSettingsFields(values: themes(text: "#336699") + "}"), from: id)
        #expect(written?.keys.sorted() == ["customThemes"])
        #expect(settings.current.customThemes.map(\.text) == [HexColor("#336699")!])
        #expect(settings.current.customThemeID == "sunset")
        #expect(try #require(service.presentation.customTheme).text == WireColor(red: 0x33, green: 0x66, blue: 0x99))
    }

    // MARK: 手書き入力(R-14)

    private static let handwritingKey = WireKeyInput(key: .character(text: "h"), modifiers: WireModifiers(shift: false, control: true, alt: true), isKeypad: false)

    private func openHandwriting(session: UInt32, from id: EngineService.ConnectionID) -> WireResponseBody {
        service.handle(WireRequest(id: 30, body: .key(session: session, input: Self.handwritingKey, context: Self.field)), from: id).body
    }

    private func candidateWindow() -> EngineService.ConnectionID {
        let id = service.connect(isCandidateWindow: true)
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        return id
    }

    private func wake(_ session: UInt32, from id: EngineService.ConnectionID) -> WireResponseBody {
        service.handle(WireRequest(id: 31, body: .wake(session: session, context: Self.field)), from: id).body
    }

    @Test("入力メニューの手書き入力は，組み立て中の文字を確定する edit を返して窓を開く．使わない設定なら開かない")
    func handwritingFromMenu() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let session = try open(id)
        _ = type("kana", session: session, from: id)
        sent.value.removeAll()
        guard case .edit(true, let operations, _) = service.handle(WireRequest(id: 60, body: .openHandwriting(session: session, context: Self.field)), from: id).body else {
            Issue.record("手書きを開く要求に edit で答えない")
            return
        }
        #expect(operations.contains { if case .commit = $0 { true } else { false } })
        #expect(sent.value.contains(.showHandwriting(anchor: Self.field.caret, recognitionDelayMilliseconds: 600, recognitionTimeoutMilliseconds: 3000)))
        #expect(service.snapshot.handwriting == true)
        try settings.update { $0.handwriting = false }
        sent.value.removeAll()
        _ = service.handle(WireRequest(id: 61, body: .openHandwriting(session: session, context: Self.field)), from: id)
        #expect(!sent.value.contains { if case .showHandwriting = $0 { true } else { false } })
        #expect(service.snapshot.handwriting == false)
    }

    @Test("候補ウィンドウで押した候補は，候補を出しているセッションの次の wake でキーで選んだのと同じに処理する")
    func chooseCandidate() throws {
        var current = settings.current
        current.candidatePresentation = .list
        try settings.update { $0 = current }
        let id = greeted()
        let session = try open(id)
        _ = type("kyou", session: session, from: id)
        _ = press(.space, session: session, from: id)
        // 候補を出しているあいだは，押した候補を取りに来るよう短い間隔で起こしてもらう
        guard case .edit(_, _, let state) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(state.wakeAfterMilliseconds.map { $0 <= EngineService.candidateClickPollMilliseconds } == true)
        // 候補ウィンドウの接続からだけ受ける
        #expect(service.handle(WireRequest(id: 70, body: .chooseCandidate(target: .entry(index: 0))), from: id).body == .error(code: .malformed))
        let window = candidateWindow()
        #expect(service.handle(WireRequest(id: 71, body: .chooseCandidate(target: .entry(index: 0))), from: window).body == .done)
        guard case .edit(_, let operations, _) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(operations.contains { if case .commit = $0 { true } else { false } })
    }

    @Test("再変換のキーで DLL に選んでいる文字を読ませ，送られた文字と読みで変換し直す")
    func reconversion() throws {
        let id = greeted()
        let session = try open(id)
        guard case .edit(true, let operations, _) = press(.henkan, session: session, from: id) else {
            Issue.record("再変換のキーを受けない")
            return
        }
        #expect(operations.contains(.requestReconversion(maximumLength: UInt32(DefaultSettings.maximumReconversionLength))))
        sent.value.removeAll()
        guard case .edit(true, _, let state) = service.handle(
            WireRequest(id: 80, body: .reconvert(session: session, text: "変換", reading: "へんかん", context: Self.field)), from: id).body else {
            Issue.record("再変換の要求に edit で答えない")
            return
        }
        #expect(state.isComposing)
        #expect(sent.value.contains { if case .showBranchMap = $0 { true } else if case .showCandidates = $0 { true } else { false } })
        // 読みが無ければ何もしない
        let other = try open(id)
        guard case .edit(_, let none, let idle) = service.handle(
            WireRequest(id: 81, body: .reconvert(session: other, text: "変換", reading: nil, context: Self.field)), from: id).body else {
            Issue.record("再変換の要求に答えない")
            return
        }
        #expect(none.isEmpty && !idle.isComposing)
    }

    @Test("手書きの窓を開き，選んだ文字を開いたセッションの wake で確定する")
    func handwriting() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let session = try open(id)
        guard case .edit(true, _, let state) = openHandwriting(session: session, from: id) else {
            Issue.record("手書きのキーを受けない")
            return
        }
        #expect(sent.value.contains(.showHandwriting(anchor: Self.field.caret, recognitionDelayMilliseconds: 600, recognitionTimeoutMilliseconds: 3000)))
        #expect(state.wakeAfterMilliseconds == EngineService.handwritingPollMilliseconds)
        // 選ぶ前の wake は何も入れず，取りに来続ける
        guard case .edit(_, let none, let waiting) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(none.isEmpty)
        #expect(waiting.wakeAfterMilliseconds == EngineService.handwritingPollMilliseconds)

        let window = candidateWindow()
        #expect(service.handle(WireRequest(id: 32, body: .handwritingChosen(text: "鬱")), from: window).body == .done)
        guard case .edit(_, let operations, let after) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(operations == [.commit(text: "鬱")])
        #expect(after.wakeAfterMilliseconds == nil)
        // 一度入れたら，もう入れない
        guard case .edit(_, let again, _) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(again.isEmpty)
    }

    @Test("組み立て中の文字は先に確定してから，選んだ文字を入れる")
    func handwritingAfterComposition() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let session = try open(id)
        _ = type("kana", session: session, from: id)
        _ = openHandwriting(session: session, from: id)
        _ = service.handle(WireRequest(id: 32, body: .handwritingChosen(text: "鬱")), from: candidateWindow())
        guard case .edit(_, let operations, _) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(operations.contains(.commit(text: "鬱")))
        #expect(!operations.contains(.commit(text: "かな鬱")))
    }

    @Test("設定がオフなら手書きの窓を開かない")
    func handwritingOff() throws {
        try settings.update { $0.handwriting = false }
        let id = greeted()
        let session = try open(id)
        _ = openHandwriting(session: session, from: id)
        #expect(!sent.value.contains(.showHandwriting(anchor: Self.field.caret, recognitionDelayMilliseconds: 600, recognitionTimeoutMilliseconds: 3000)))
        guard case .edit(_, _, let state) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(state.wakeAfterMilliseconds == nil)
    }

    @Test("選んだ文字は窓を開いたセッションにだけ入る")
    func handwritingOtherSession() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let owner = try open(id)
        let other = try open(id)
        _ = openHandwriting(session: owner, from: id)
        _ = service.handle(WireRequest(id: 32, body: .handwritingChosen(text: "鬱")), from: candidateWindow())
        guard case .edit(_, let operations, let state) = wake(other, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(operations.isEmpty)
        #expect(state.wakeAfterMilliseconds == nil)
    }

    @Test("候補ウィンドウでない接続からの文字と，空・長すぎる・制御文字の文字は断る")
    func handwritingRejects() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let session = try open(id)
        _ = openHandwriting(session: session, from: id)
        #expect(service.handle(WireRequest(id: 32, body: .handwritingChosen(text: "鬱")), from: id).body == .error(code: .malformed))
        let window = candidateWindow()
        for text in ["", String(repeating: "あ", count: DefaultSettings.maximumHandwritingTextLength + 1), "a\n", "\u{202E}a"] {
            #expect(service.handle(WireRequest(id: 33, body: .handwritingChosen(text: text)), from: window).body == .error(code: .malformed))
        }
        guard case .edit(_, let operations, _) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(operations.isEmpty)
    }

    @Test("入力欄の中で注目が動いた deactivate では手書きの窓を閉じず，選んだ文字を次の wake で入れる")
    func handwritingSurvivesDeactivate() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let session = try open(id)
        _ = openHandwriting(session: session, from: id)
        sent.value.removeAll()
        guard case .edit(_, _, let state) = service.handle(WireRequest(id: 34, body: .deactivate(session: session)), from: id).body else {
            Issue.record("deactivate に答えない")
            return
        }
        #expect(!sent.value.contains(.hideHandwriting))
        // 文字を取りに来続けてもらう
        #expect(state.wakeAfterMilliseconds == EngineService.handwritingPollMilliseconds)
        _ = service.handle(WireRequest(id: 32, body: .handwritingChosen(text: "鬱")), from: candidateWindow())
        guard case .edit(_, let operations, let after) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(operations == [.commit(text: "鬱")])
        #expect(after.wakeAfterMilliseconds == nil)
    }

    @Test("手書きの窓を開いていないときの deactivate では，来てもらわない")
    func deactivateWithoutHandwriting() throws {
        let id = greeted()
        let session = try open(id)
        _ = type("kana", session: session, from: id)
        guard case .edit(_, _, let state) = service.handle(WireRequest(id: 34, body: .deactivate(session: session)), from: id).body else {
            Issue.record("deactivate に答えない")
            return
        }
        #expect(state.wakeAfterMilliseconds == nil)
    }

    @Test("ほかのアプリに入力先が移ったら，選んだ文字は移った先に入れる")
    func handwritingFollowsActivation() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let owner = try open(id)
        let other = try open(id)
        _ = openHandwriting(session: owner, from: id)
        _ = service.handle(WireRequest(id: 34, body: .deactivate(session: owner)), from: id)
        _ = service.handle(WireRequest(id: 32, body: .handwritingChosen(text: "鬱")), from: candidateWindow())
        guard case .edit(_, let operations, _) = service.handle(
            WireRequest(id: 36, body: .activate(session: other, context: Self.field)), from: id).body else {
            Issue.record("activate に答えない")
            return
        }
        #expect(operations.contains(.commit(text: "鬱")))
        guard case .edit(_, let none, _) = wake(owner, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(none.isEmpty)
    }

    @Test("入力先のセッションが閉じたら手書きの窓を閉じる")
    func handwritingClosesWithSession() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let session = try open(id)
        _ = openHandwriting(session: session, from: id)
        _ = service.handle(WireRequest(id: 37, body: .closeSession(session: session)), from: id)
        #expect(sent.value.last == .hideHandwriting)
    }

    @Test("窓を閉じたら取りに来るのをやめる")
    func handwritingClosed() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let session = try open(id)
        _ = openHandwriting(session: session, from: id)
        #expect(service.handle(WireRequest(id: 35, body: .handwritingClosed), from: candidateWindow()).body == .done)
        guard case .edit(_, _, let state) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(state.wakeAfterMilliseconds == nil)
    }
}
