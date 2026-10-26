import Foundation
import S90Application
@testable import S90Domain
@testable import S90Persistence
import Testing

private func fixture(_ name: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/\(name)"))
}

@Suite("設定の形式の版(TODO 49)")
struct SettingsSchemaTests {
    @Test("版を書いていない古い設定のファイル(版 1)を読め，今の版で書き戻す")
    func readsVersion1() throws {
        let settings = try SettingsCoding.decode(fixture("settings-v1.json"))
        #expect(settings.inputStyle == .kana)
        #expect(settings.liveConversion == false)
        #expect(settings.punctuation == .commaPeriod)
        #expect(settings.userDictionary == [UserDictionaryEntry(reading: "えすきゅー", word: "s90")])
        #expect(settings.customRomaji.first?.keys == "wyi")
        #expect(settings.profileRules.first?.applicationPrefix == "com.example.editor")
        #expect(settings.candidateFontSize == 18)
        // 書いていない項目は既定値
        #expect(settings.initialFocus == DefaultSettings.settings.initialFocus)
        let written = try SettingsCoding.object(of: settings)
        #expect(written[SettingsSchema.versionKey] == .number(Double(SettingsSchema.currentVersion)))
    }

    @Test("新しい版で書いた設定を開いて保存しても，知らない項目と版を失わない")
    func keepsUnknownFields() throws {
        let settings = try SettingsCoding.decode(fixture("settings-v9.json"))
        #expect(settings.schemaVersion == 9)
        #expect(settings.unknownFields["futureOption"] == .object(["enabled": .bool(true), "level": .number(3)]))
        var changed = settings
        changed.liveConversion = false
        let again = try SettingsCoding.decode(SettingsCoding.encode(changed))
        #expect(again.unknownFields == settings.unknownFields)
        #expect(again.schemaVersion == 9)
        #expect(again.liveConversion == false)
    }

    @Test("移し替えは古い版から順に当て，今より新しい版には当てない")
    func migrate() {
        var old: [String: JSONValue] = ["inputStyle": .string("kana")]
        SettingsSchema.migrate(&old)
        #expect(old[SettingsSchema.versionKey] == .number(Double(SettingsSchema.currentVersion)))
        var future: [String: JSONValue] = [SettingsSchema.versionKey: .number(9)]
        SettingsSchema.migrate(&future)
        #expect(future[SettingsSchema.versionKey] == .number(9))
    }

    @Test("設定の項目はどれも，同期のまとまりのどれか 1 つだけに入る")
    func everyFieldHasOneGroup() {
        let grouped = SyncGroup.allCases.flatMap(\.fieldNames)
        #expect(Set(grouped) == Settings.fieldNames)
        #expect(grouped.count == Set(grouped).count)
    }
}

@Suite("同期の突き合わせ(TODO 43・49)")
struct SyncMergeTests {
    private let t0 = Date(timeIntervalSince1970: 1_000)
    private let t1 = Date(timeIntervalSince1970: 2_000)
    private let t2 = Date(timeIntervalSince1970: 3_000)

    private func object(_ change: (inout Settings) -> Void = { _ in }) throws -> [String: JSONValue] {
        var settings = Settings()
        change(&settings)
        return try SettingsCoding.object(of: settings)
    }

    @Test("同期のファイルの方が新しいまとまりは取り込み，この Mac の方が新しいまとまりは書き出す")
    func newerWins() throws {
        var remote = SyncDocument()
        remote.groups[.input] = .init(modifiedAt: t2, values: SyncMerge.values(of: .input, in: try object { $0.liveConversion = false }))
        remote.groups[.conversion] = .init(modifiedAt: t0, values: SyncMerge.values(of: .conversion, in: try object()))
        var ledger = SyncLedger()
        ledger.groupModifiedAt[.input] = t1
        ledger.groupModifiedAt[.conversion] = t1
        let local = try object { $0.calculation = false }
        let result = SyncMerge.merge(local: local, ledger: ledger, remote: remote, scopes: [:], now: t2)
        let merged = try SettingsCoding.settings(from: result.settings)
        #expect(merged.liveConversion == false)
        #expect(merged.calculation == false)
        #expect(result.document.groups[.conversion]?.values["calculation"] == .bool(false))
        #expect(result.document.groups[.conversion]?.modifiedAt == t1)
        #expect(result.changedLocal && result.changedRemote)
    }

    @Test("この Mac だけのまとまりは，取り込みも書き出しもしない")
    func localScope() throws {
        var remote = SyncDocument()
        remote.groups[.appearance] = .init(modifiedAt: t2, values: SyncMerge.values(of: .appearance, in: try object { $0.theme = .neon }))
        var ledger = SyncLedger()
        ledger.groupModifiedAt[.appearance] = t1
        let result = SyncMerge.merge(local: try object { $0.theme = .washi }, ledger: ledger, remote: remote, scopes: [:], now: t2)
        #expect(try SettingsCoding.settings(from: result.settings).theme == .washi)
        #expect(result.document.groups[.appearance]?.values["theme"] == .string("neon"))
    }

    @Test("ユーザー辞書は和集合にし，墓標より前に登録した語は消し，あとで登録し直した語は残す")
    func dictionary() throws {
        var remote = SyncDocument()
        remote.dictionary = [
            .init(reading: "あ", word: "A", addedAt: t0),
            .init(reading: "い", word: "I", addedAt: t0),
            .init(reading: "う", word: "U", addedAt: t2),
        ]
        var ledger = SyncLedger()
        // この Mac で「い」を消し，「う」も消したが，ほかの Mac で「う」を消したあとに登録し直した
        ledger.dictionaryTombstones = [SyncMerge.key(reading: "い", word: "I"): t1, SyncMerge.key(reading: "う", word: "U"): t1]
        ledger.dictionaryAddedAt[SyncMerge.key(reading: "え", word: "E")] = t1
        let local = try object { $0.userDictionary = [UserDictionaryEntry(reading: "え", word: "E")] }
        let result = SyncMerge.merge(local: local, ledger: ledger, remote: remote, scopes: [:], now: t2)
        let words = try SettingsCoding.settings(from: result.settings).userDictionary.map(\.word)
        #expect(Set(words) == ["E", "A", "U"])
        #expect(result.document.tombstones[SyncMerge.key(reading: "い", word: "I")] == t1)
    }

    @Test("古い墓標は捨てる")
    func prunesTombstones() throws {
        var ledger = SyncLedger()
        ledger.dictionaryTombstones = ["old\tO": t0]
        let later = t0.addingTimeInterval(SyncMerge.tombstoneLifetime + 1)
        let result = SyncMerge.merge(local: try object(), ledger: ledger, remote: nil, scopes: [:], now: later)
        #expect(result.document.tombstones.isEmpty)
    }

    @Test("この Mac で変えたまとまりに時刻を記し，辞書の登録と削除を記す")
    func noteChange() throws {
        var ledger = SyncLedger()
        let old = try object { $0.userDictionary = [UserDictionaryEntry(reading: "あ", word: "A")] }
        let new = try object { $0.liveConversion = false; $0.userDictionary = [UserDictionaryEntry(reading: "い", word: "I")] }
        SyncMerge.noteChange(from: old, to: new, ledger: &ledger, now: t1)
        #expect(ledger.groupModifiedAt[.input] == t1)
        #expect(ledger.groupModifiedAt[.appearance] == nil)
        #expect(ledger.dictionaryAddedAt[SyncMerge.key(reading: "い", word: "I")] == t1)
        #expect(ledger.dictionaryTombstones[SyncMerge.key(reading: "あ", word: "A")] == t1)
    }
}

/// 同期のファイルを覚えておくだけの置き場所
private final class MemoryBackend: SyncBackend, @unchecked Sendable {
    var data: Data?
    func read() throws -> Data? { data }
    func write(_ data: Data) throws { self.data = data }
}

@MainActor
private final class MemoryStateStore: SyncStateStoring {
    var state = SyncState()
    func save(_ state: SyncState) throws { self.state = state }
}

@MainActor
@Suite("2 台の Mac の同期")
struct SettingsSynchronizerTests {
    private func mac(_ directory: URL, _ name: String, clock: @escaping () -> Date) -> (FileSettingsStore, SettingsSynchronizer) {
        let store = FileSettingsStore(fileURL: directory.appendingPathComponent("\(name).json"))
        return (store, SettingsSynchronizer(settings: store, stateStore: MemoryStateStore(), clock: clock))
    }

    @Test("A で変えた設定と登録した語が B に届き，B で消した語は A でも消える")
    func twoMacs() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var time = Date(timeIntervalSince1970: 10_000)
        let clock = { time }
        let backend = MemoryBackend()
        let (a, syncA) = mac(directory, "a", clock: clock)
        let (b, syncB) = mac(directory, "b", clock: clock)

        try a.update { $0.liveConversion = false; $0.userDictionary = [UserDictionaryEntry(reading: "えすきゅー", word: "s90")] }
        try a.update { $0.theme = .neon }
        try syncA.sync(with: backend)
        time += 10
        try syncB.sync(with: backend)
        #expect(b.current.liveConversion == false)
        #expect(b.current.userDictionary.map(\.word) == ["s90"])
        // 外観はこの Mac だけ
        #expect(b.current.theme == DefaultSettings.settings.theme)

        time += 10
        try b.update { $0.userDictionary = [] }
        try syncB.sync(with: backend)
        time += 10
        try syncA.sync(with: backend)
        #expect(a.current.userDictionary.isEmpty)
        #expect(a.current.theme == .neon)
    }

    @Test("同期のファイルが壊れていれば上書きせずに止める")
    func unreadable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let backend = MemoryBackend()
        backend.data = Data("not json".utf8)
        let (_, sync) = mac(directory, "a", clock: Date.init)
        #expect(throws: SettingsSynchronizer.SyncError.unreadableDocument) { try sync.sync(with: backend) }
        #expect(backend.data == Data("not json".utf8))
    }

    @Test("フォルダの同期先は s90-sync.json に書いて読む")
    func folderBackend() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let backend = FolderSyncBackend(folder: directory)
        #expect(try backend.read() == nil)
        try backend.write(Data("{}".utf8))
        #expect(try backend.read() == Data("{}".utf8))
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(FolderSyncBackend.fileName).path))
    }
}
