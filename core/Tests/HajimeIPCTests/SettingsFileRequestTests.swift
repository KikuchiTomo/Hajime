import Foundation
import HajimeApplication
import HajimeDomain
import HajimeIPC
import HajimeTestSupport
import Testing

@MainActor
@Suite("設定の画面から頼まれる同期とファイルの読み書き(R-15・R-16)")
struct SettingsFileRequestTests {
    @MainActor
    final class FakeSync: SyncControlling {
        var state = SyncState()
        var syncCount = 0
        var status: SyncStatus { SyncStatus(state: state, problem: nil, isSyncing: false) }
        func chooseFolder(path: String) throws {
            guard path.hasPrefix("/") else { throw SettingsFileFailure.invalidPath }
            state.isEnabled = true
            state.folderPath = path
            state.folderName = "同期"
        }
        func setEnabled(_ enabled: Bool) throws { state.isEnabled = enabled }
        func setScope(_ scope: SyncScope, for group: SyncGroup) throws { state.scopes[group] = scope }
        func setLocal(_ isLocal: Bool, field: String) throws {
            if isLocal { state.localFields.insert(field) } else { state.localFields.remove(field) }
        }
        func syncNow() { syncCount += 1 }
    }

    @MainActor
    final class FakeFiles: SettingsFileHandling {
        var calls: [String] = []
        /// 取り込みを止めておく(同時に頼まれたときを確かめる)
        var gate: CheckedContinuation<Void, Never>?
        var holds = false

        func importDictionary(from path: String, replacing id: String?) async throws(SettingsFileFailure) -> ImportedDictionary {
            calls.append("importDictionary \(path) \(id ?? "-")")
            if holds { await withCheckedContinuation { gate = $0 } }
            guard path.hasSuffix(".txt") else { throw .unreadable }
            return ImportedDictionary(id: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B", name: "電気", wordCount: 3)
        }
        func removeDictionary(id: String) throws(SettingsFileFailure) { calls.append("removeDictionary \(id)") }
        func importAssociationDictionary(from path: String, replacing id: String?) async throws(SettingsFileFailure) -> AssociationDictionary {
            calls.append("importAssociationDictionary \(path) \(id ?? "-")")
            return AssociationDictionary(id: "a", name: "related", groupCount: 12)
        }
        func removeAssociationDictionary(id: String) throws(SettingsFileFailure) { calls.append("removeAssociationDictionary \(id)") }
        func importUserDictionary(from path: String) async throws(SettingsFileFailure) -> (added: Int, skipped: Int) {
            calls.append("importUserDictionary \(path)")
            return (4, 2)
        }
        func exportUserDictionary(to path: String) async throws(SettingsFileFailure) { calls.append("exportUserDictionary \(path)") }
        func exportSettings(to path: String) async throws(SettingsFileFailure) { calls.append("exportSettings \(path)") }
        func importSettings(from path: String) async throws(SettingsFileFailure) { calls.append("importSettings \(path)") }
        func importProfileRules(from path: String) async throws(SettingsFileFailure) -> (added: Int, skipped: Int) {
            calls.append("importProfileRules \(path)")
            return (2, 1)
        }
        func exportProfileRules(to path: String) async throws(SettingsFileFailure) { calls.append("exportProfileRules \(path)") }
        func importRuleList(_ list: RuleList, from path: String) async throws(SettingsFileFailure) -> (added: Int, skipped: Int) {
            calls.append("importRuleList \(list.rawValue) \(path)")
            return (5, 0)
        }
        func exportRuleList(_ list: RuleList, to path: String) async throws(SettingsFileFailure) {
            calls.append("exportRuleList \(list.rawValue) \(path)")
        }
    }

    private let sync = FakeSync()
    private let files = FakeFiles()
    private let service: EngineService

    init() {
        let settings = FakeSettings(DefaultSettings.settings)
        let converter = FakeConverter([:])
        service = EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings) },
            settings: settings, ui: { _ in }, openSettings: {}, sync: sync, files: files
        )
    }

    private func greeted() -> EngineService.ConnectionID {
        let id = service.connect()
        _ = service.handle(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), from: id)
        return id
    }

    private func answer(_ body: WireRequestBody, from id: EngineService.ConnectionID) async -> WireResponseBody {
        switch service.reply(to: WireRequest(id: 7, body: body), from: id) {
        case .now(let response): response.body
        case .later(let work): await work().body
        }
    }

    @Test("同期の様子にまとまりごとの範囲と項目の名前を入れて返す")
    func readSync() async {
        let id = greeted()
        guard case .syncStatus(let status) = await answer(.readSync, from: id) else {
            Issue.record("同期の様子が返らない")
            return
        }
        #expect(!status.isEnabled)
        #expect(status.groups.count == SyncGroup.syncableCases.count)
        #expect(status.groups.first { $0.group == "appearance" }?.scope == "local")
        #expect(status.groups.first { $0.group == "dictionary" }?.fields == ["userDictionary"])
    }

    @Test("フォルダ・範囲・項目ごとの指定を変え，変えたあとの様子を返す")
    func changeSync() async {
        let id = greeted()
        guard case .syncStatus(let status) = await answer(.setSyncFolder(path: "/Users/a/Dropbox"), from: id) else {
            Issue.record("同期の様子が返らない")
            return
        }
        #expect(status.isEnabled && status.folderPath == "/Users/a/Dropbox")
        #expect(await answer(.setSyncFolder(path: "relative"), from: id) == .fileFailed(reason: .invalidPath))
        _ = await answer(.setSyncScope(group: "appearance", scope: "synced"), from: id)
        #expect(sync.state.scopes[.appearance] == .synced)
        _ = await answer(.setSyncLocalField(field: "theme", isLocal: true), from: id)
        #expect(sync.state.localFields == ["theme"])
        _ = await answer(.syncNow, from: id)
        #expect(sync.syncCount == 1)
    }

    @Test("知らないまとまり・範囲・項目は malformed")
    func rejectsUnknownNames() async {
        let id = greeted()
        #expect(await answer(.setSyncScope(group: "nothing", scope: "synced"), from: id) == .error(code: .malformed))
        #expect(await answer(.setSyncScope(group: "input", scope: "everywhere"), from: id) == .error(code: .malformed))
        #expect(await answer(.setSyncLocalField(field: "../secret", isLocal: true), from: id) == .error(code: .malformed))
    }

    @Test("ファイルの読み書きを頼み，結果を返す")
    func fileRequests() async {
        let id = greeted()
        #expect(await answer(.importDictionary(path: "/d/電気.txt", replacing: nil), from: id)
            == .dictionaryImported(dictionary: WireImportedDictionaryInfo(id: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B", name: "電気", wordCount: 3)))
        #expect(await answer(.importDictionary(path: "/d/壊れた.bin", replacing: nil), from: id) == .fileFailed(reason: .unreadable))
        #expect(await answer(.importAssociationDictionary(path: "/d/related.txt", replacing: nil), from: id)
            == .associationImported(dictionary: WireAssociationDictionaryInfo(id: "a", name: "related", groupCount: 12)))
        #expect(await answer(.removeAssociationDictionary(id: "a"), from: id) == .done)
        #expect(await answer(.importProfileRules(path: "/d/rules.csv"), from: id) == .imported(added: 2, skipped: 1))
        #expect(await answer(.importRuleList(list: .symbolReadings, path: "/d/s.tsv"), from: id) == .imported(added: 5, skipped: 0))
        #expect(await answer(.exportRuleList(list: .romaji, path: "/d/r.tsv"), from: id) == .done)
        #expect(await answer(.exportSettings(path: "/d/s.json"), from: id) == .done)
        #expect(await answer(.importSettings(path: "/d/s.json"), from: id) == .done)
        #expect(await answer(.exportProfileRules(path: "/d/r.csv"), from: id) == .done)
        #expect(await answer(.removeDictionary(id: "x"), from: id) == .done)
        #expect(await answer(.importUserDictionary(path: "/d/u.txt"), from: id) == .imported(added: 4, skipped: 2))
        #expect(await answer(.exportUserDictionary(path: "/d/u.txt"), from: id) == .done)
        #expect(files.calls.contains("importRuleList symbolReadings /d/s.tsv"))
        #expect(files.calls.contains("exportRuleList romaji /d/r.tsv"))
    }

    @Test("挨拶の前のファイルの要求は断り，読み書きはしない")
    func requiresGreeting() async {
        let id = service.connect()
        #expect(await answer(.exportSettings(path: "/d/s.json"), from: id) == .error(code: .unsupportedVersion))
        #expect(files.calls.isEmpty)
    }

    @Test("ファイルの読み書きは同時に 1 つだけ．動いているあいだに頼まれたら busy")
    func oneAtATime() async {
        let id = greeted()
        files.holds = true
        guard case .later(let first) = service.reply(to: WireRequest(id: 1, body: .importDictionary(path: "/d/a.txt", replacing: nil)), from: id) else {
            Issue.record("時間のかかる仕事にならない")
            return
        }
        let running = Task { await first() }
        while files.gate == nil { await Task.yield() }
        #expect(await answer(.exportSettings(path: "/d/s.json"), from: id) == .fileFailed(reason: .busy))
        // 入力の要求は待たずに答える
        #expect(await answer(.readSync, from: id) != .fileFailed(reason: .busy))
        files.gate?.resume()
        _ = await running.value
        files.holds = false
        #expect(await answer(.exportSettings(path: "/d/s.json"), from: id) == .done)
    }

    @Test("記号の一覧は既定の決まりに利用者の決まりを重ね，1 回のメッセージに収まる")
    func symbolItems() async throws {
        let id = greeted()
        let body = await answer(.readSymbolItems(kind: .reading), from: id)
        guard case .symbolItems(let readings) = body else {
            Issue.record("記号の一覧が返らない")
            return
        }
        #expect(readings.contains { $0.input == "やじるし" && $0.output.hasPrefix("→ ← ↑ ↓") && $0.origin == .standard })
        #expect(readings.count == SymbolDictionary.defaultEntries.count)
        let encoded = try JSONEncoder().encode(WireResponse(id: 1, body: body))
        #expect(encoded.count < WireProtocol.maximumMessageBytes)
    }

    @Test("カスタムテーマの読みにくい組み合わせとコントラスト比を返す．読めないテーマは malformed")
    func customThemeReport() async throws {
        let id = greeted()
        let theme = CustomTheme(id: "t", name: "夕焼け", base: .automatic, surface: HexColor("#FFFFFF")!, text: HexColor("#000000")!,
                                textMuted: HexColor("#EEEEEE")!, selection: HexColor("#0000FF")!, selectionText: HexColor("#FFFFFF")!,
                                correction: HexColor("#FF0000")!, line: HexColor("#CCCCCC")!)
        let text = String(decoding: try JSONEncoder().encode(theme), as: UTF8.self)
        guard case .themeReport(let issues) = await answer(.checkCustomTheme(theme: text), from: id) else {
            Issue.record("読みやすさが返らない")
            return
        }
        #expect(issues.map(\.pair) == [.textMuted])
        #expect(issues.first.map { $0.ratio < $0.minimum } == true)
        #expect(await answer(.checkCustomTheme(theme: "{}"), from: id) == .error(code: .malformed))
    }

    @Test("記号の決まりを書き換え・無効にし，消すと既定に戻る")
    func symbolRuleEditing() async throws {
        let id = greeted()
        let saved = await answer(.saveSymbolRule(kind: .sequence, input: "->", output: "⇒", isEnabled: true, replacing: nil), from: id)
        #expect(saved == .symbolSaved(result: .saved))
        let added = await answer(.saveSymbolRule(kind: .sequence, input: "=>>", output: "⇛", isEnabled: false, replacing: nil), from: id)
        #expect(added == .symbolSaved(result: .saved))
        guard case .symbolItems(let items) = await answer(.readSymbolItems(kind: .sequence), from: id) else {
            Issue.record("記号の一覧が返らない")
            return
        }
        #expect(items.first { $0.input == "->" } == WireSymbolItem(input: "->", output: "⇒", isEnabled: true, origin: .changed))
        #expect(items.last == WireSymbolItem(input: "=>>", output: "⇛", isEnabled: false, origin: .added))
        let invalid = await answer(.saveSymbolRule(kind: .sequence, input: "", output: "⇒", isEnabled: true, replacing: nil), from: id)
        #expect(invalid == .symbolSaved(result: .invalid))
        #expect(await answer(.removeSymbolRules(kind: .sequence, inputs: ["->", "=>>"]), from: id) == .done)
        guard case .symbolItems(let restored) = await answer(.readSymbolItems(kind: .sequence), from: id) else {
            Issue.record("記号の一覧が返らない")
            return
        }
        #expect(restored.first { $0.input == "->" } == WireSymbolItem(input: "->", output: "→", isEnabled: true, origin: .standard))
        #expect(!restored.contains { $0.input == "=>>" })
    }
}
