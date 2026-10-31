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
        let converter = FakeConverter(["かな": [("仮名", nil)]])
        self.settings = settings
        self.sent = sent
        self.opened = opened
        self.service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings) },
            settings: settings,
            ui: { sent.value.append($0) },
            openSettings: { opened.value += 1 }
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
        #expect(operations == [.setComposition(segments: [WireTextSegment(text: "かな", style: .reading)], caret: nil)])
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
        let service = EngineService(makeSession: { fatalError("セッションは作らない") }, settings: settings, ui: { _ in }, openSettings: {}, services: services)
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
        #expect(page.first == WireDictionaryEntry(reading: "よみ", word: "語句0"))
        guard case .userDictionary(let tail, _) = service.handle(WireRequest(id: 47, body: .readUserDictionary(offset: 1000, limit: 10)), from: id).body else {
            Issue.record("範囲の外を読めない")
            return
        }
        #expect(tail.isEmpty)
        #expect(service.handle(WireRequest(id: 48, body: .removeUserDictionaryEntry(entry: WireDictionaryEntry(reading: "えすきゅー", word: "hajime"))), from: id).body == .done)
        #expect(settings.current.userDictionary.count == 600)
        #expect(!settings.current.userDictionary.contains(UserDictionaryEntry(reading: "えすきゅー", word: "hajime")))
    }

    @Test("入力方式を切り替えたら，モードの札に入力方式を出す．出さない設定なら出さない")
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

    @Test("見た目の設定は設定の値を運ぶ")
    func presentation() {
        #expect(service.presentation.theme == settings.current.theme.rawValue)
        #expect(service.presentation.fontSize == settings.current.candidateFontSize)
        #expect(service.presentation.customTheme == nil)
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

    @Test("入力先から外れたら手書きの窓を閉じ，選んだ文字を入れない")
    func handwritingClosesOnDeactivate() throws {
        try settings.update { $0.handwriting = true }
        let id = greeted()
        let session = try open(id)
        _ = openHandwriting(session: session, from: id)
        _ = service.handle(WireRequest(id: 34, body: .deactivate(session: session)), from: id)
        #expect(sent.value.last == .hideHandwriting)
        _ = service.handle(WireRequest(id: 32, body: .handwritingChosen(text: "鬱")), from: candidateWindow())
        guard case .edit(_, let operations, let state) = wake(session, from: id) else {
            Issue.record("wake に答えない")
            return
        }
        #expect(operations.isEmpty)
        #expect(state.wakeAfterMilliseconds == nil)
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
