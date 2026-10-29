import Foundation
import HajimeApplication
@testable import HajimeDomain
@testable import HajimePersistence
import Testing

@MainActor
@Suite("設定の画面から頼まれたファイルの読み書き(R-16，バックアップ，除外設定，決まりの一覧)")
struct SettingsFilesTests {
    private let root = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-files-\(UUID().uuidString)", isDirectory: true)
    private let settings: FileSettingsStore
    private let dictionaries: ImportedDictionaryStore
    private let files: SettingsFiles

    init() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        settings = FileSettingsStore(fileURL: root.appendingPathComponent("settings.json"))
        dictionaries = ImportedDictionaryStore(directory: root.appendingPathComponent("dictionaries", isDirectory: true))
        files = SettingsFiles(settings: settings, dictionaries: dictionaries)
    }

    private func file(_ name: String, _ text: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url.path
    }

    @Test("辞書を取り込んで一覧に足し，引ける．取り込み直すと名前はそのまま，消すと索引も消える")
    func importDictionary() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try file("電気.txt", "でんあつ\t電圧\t名詞\nでんりゅう\t電流\t名詞\n")
        let imported = try await files.importDictionary(from: path, replacing: nil)
        #expect(imported.name == "電気")
        #expect(imported.wordCount == 2)
        #expect(imported.revision != nil)
        #expect(settings.current.importedDictionaries == [imported])
        #expect(dictionaries.words(reading: "でんあつ", in: imported).map(\.word) == ["電圧"])

        try settings.update { $0.importedDictionaries[0].name = "電気の語" }
        let again = try await files.importDictionary(from: try file("新しい.txt", "でんあつ\t電圧\n"), replacing: imported.id)
        #expect(again.name == "電気の語")
        #expect(again.wordCount == 1)
        #expect(settings.current.importedDictionaries.count == 1)

        try files.removeDictionary(id: imported.id)
        #expect(settings.current.importedDictionaries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dictionaries.url(for: imported).path))
    }

    @Test("連想の辞書を取り込んで一覧に足し，引ける．取り込み直すと名前はそのまま，消すと索引も消える．同梱の辞書は消せない")
    func importAssociationDictionary() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let associations = AssociationDictionaryStore(directory: root.appendingPathComponent("associations", isDirectory: true))
        let files = SettingsFiles(settings: settings, dictionaries: dictionaries, associations: associations)
        let imported = try await files.importAssociationDictionary(from: try file("似た語.txt", "速い\t早い\t迅速\n大きい,巨大\n"), replacing: nil)
        #expect(imported.name == "似た語")
        #expect(imported.groupCount == 2)
        #expect(settings.current.associationDictionaries.last == imported)
        #expect(associations.groups(for: "迅速", in: imported).first?.words.contains("早い") == true)

        try settings.update { $0.associationDictionaries[$0.associationDictionaries.count - 1].name = "類語" }
        let again = try await files.importAssociationDictionary(from: try file("新しい.txt", "大きい,巨大\n"), replacing: imported.id)
        #expect(again.name == "類語")
        #expect(again.groupCount == 1)

        try files.removeAssociationDictionary(id: imported.id)
        #expect(!settings.current.associationDictionaries.contains { $0.id == imported.id })
        #expect(!FileManager.default.fileExists(atPath: associations.url(for: imported).path))
        #expect(throws: SettingsFileFailure.unknownDictionary) { try files.removeAssociationDictionary(id: DefaultSettings.bundledAssociationDictionary.id) }
        // 連想の辞書の索引が無ければ取り込めない
        await #expect(throws: SettingsFileFailure.unreadable) {
            try await self.files.importAssociationDictionary(from: try self.file("x.txt", "a,b\n"), replacing: nil)
        }
    }

    @Test("取り込めない辞書の理由を分ける", arguments: [
        ("無い.txt", nil as String?, SettingsFileFailure.notFound),
        ("空.txt", "# コメントだけ\n", .empty),
        ("relative.txt", nil, .invalidPath),
    ])
    func dictionaryFailures(name: String, contents: String?, expected: SettingsFileFailure) async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let path = name == "relative.txt" ? name : (try contents.map { try file(name, $0) } ?? root.appendingPathComponent(name).path)
        await #expect(throws: expected) { try await files.importDictionary(from: path, replacing: nil) }
        #expect(settings.current.importedDictionaries.isEmpty)
    }

    @Test("一覧に無い辞書の取り込み直しと削除は断り，数の上限を超える取り込みも断る")
    func dictionaryLimits() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try file("電気.txt", "でんあつ\t電圧\n")
        await #expect(throws: SettingsFileFailure.unknownDictionary) {
            try await files.importDictionary(from: path, replacing: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B")
        }
        #expect(throws: SettingsFileFailure.unknownDictionary) { try files.removeDictionary(id: "6F1C2B0A-3D4E-4F50-8A9B-0C1D2E3F4A5B") }
        try settings.update { current in
            current.importedDictionaries = (0..<DefaultSettings.maximumImportedDictionaries).map {
                ImportedDictionary(id: UUID().uuidString, name: "\($0)", wordCount: 1)
            }
        }
        await #expect(throws: SettingsFileFailure.tooMany) { try await files.importDictionary(from: path, replacing: nil) }
    }

    @Test("すべての設定を書き出して読み込むと元に戻り，設定のファイルでないものは読み込まない")
    func backup() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try settings.update { $0.liveConversion = false; $0.userDictionary = [UserDictionaryEntry(reading: "えすきゅー", word: "hajime")] }
        let path = root.appendingPathComponent("backup.json").path
        try await files.exportSettings(to: path)
        try settings.update { $0 = DefaultSettings.settings }
        try await files.importSettings(from: path)
        #expect(settings.current.liveConversion == false)
        #expect(settings.current.userDictionary.map(\.word) == ["hajime"])
        let notSettings = try file("list.json", "[1, 2]")
        await #expect(throws: SettingsFileFailure.notSettings) { try await files.importSettings(from: notSettings) }
    }

    @Test("除外設定の CSV を読み込み，読めなかった行を数える．書き出すと同じ規則が読める")
    func profileRules() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try file("rules.csv", "app_id,mode\n# メモ\nWindowsTerminal.exe,terminal\ncode.exe,programming\nbad id,terminal\nx.exe,unknown\n")
        let counts = try await files.importProfileRules(from: path)
        #expect(counts.added == 2)
        #expect(counts.skipped == 2)
        #expect(settings.current.profileRules.prefix(2).map(\.applicationPrefix) == ["WindowsTerminal.exe", "code.exe"])
        let exported = root.appendingPathComponent("out.csv")
        try await files.exportProfileRules(to: exported.path)
        #expect(try ProfileRuleFile.read(from: exported) == settings.current.profileRules)
    }

    @Test("決まりの一覧を読み込み，足せなかった行を数える．書き出しは macOS と同じ形")
    func ruleLists() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let path = try file("replacements.tsv", "teh\tthe\n# コメント\na1\tx\nadn\tand\n")
        let counts = try await files.importRuleList(.correctionRules, from: path)
        #expect(counts.added == 2)
        #expect(counts.skipped == 1)
        let exported = root.appendingPathComponent("out.tsv")
        try await files.exportRuleList(.correctionRules, to: exported.path)
        #expect(try String(contentsOf: exported, encoding: .utf8) == "teh\tthe\nadn\tand\n")
    }

    @Test("ユーザー辞書を取り込み，すでにある語は足さず，形の誤った行を数える．書き出すと同じ語が読める")
    func userDictionary() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try settings.update { $0.userDictionary = [UserDictionaryEntry(reading: "えすきゅー", word: "hajime")] }
        let path = try file("user.txt", "! コメント\nえすきゅー\thajime\nでんあつ\t電圧\nabc\t形が誤り\n1 列だけ\n")
        let counts = try await files.importUserDictionary(from: path)
        #expect(counts.added == 1)
        #expect(counts.skipped == 2)
        #expect(settings.current.userDictionary.map(\.word).contains("電圧"))
        let exported = root.appendingPathComponent("out.txt")
        try await files.exportUserDictionary(to: exported.path)
        #expect(try UserDictionaryFile.read(from: exported) == settings.current.userDictionary)
    }

    @Test("書き出し先がフォルダなら writeFailed")
    func writeFailure() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        await #expect(throws: SettingsFileFailure.writeFailed) { try await files.exportSettings(to: root.path) }
    }
}

#if os(Windows)
private let pathCases: [(String, Bool)] = [
    (#"C:\Users\a\dict.txt"#, true), ("d:/dict.txt", true), (#"\\server\share\dict.txt"#, false), (#"\\.\pipe\hajime"#, false),
    (#"\\?\C:\dict.txt"#, false), ("dict.txt", false), (#"C:dict.txt"#, false), (#"C:\a\..\b"#, false), (#"C:\a\b.txt:stream"#, false), ("", false),
]
#else
private let pathCases: [(String, Bool)] = [
    ("/Users/a/dict.txt", true), ("relative/dict.txt", false), ("", false), ("/a/../b", false), ("/a/b\0c", false),
]
#endif

@Suite("設定の画面から受け取るパス")
struct LocalFilePathTests {
    @Test("ローカルのドライブの絶対パスだけを受け付ける", arguments: pathCases)
    func accepts(path: String, expected: Bool) {
        #expect((LocalFilePath.url(path) != nil) == expected)
    }
}
