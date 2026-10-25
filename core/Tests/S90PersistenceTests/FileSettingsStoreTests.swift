import Foundation
import S90Domain
import S90Persistence
import Testing

@Suite("設定の保存")
@MainActor
struct FileSettingsStoreTests {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("s90-tests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("settings.json")
    }

    @Test("ファイルが無ければ既定値")
    func defaults() {
        #expect(FileSettingsStore(fileURL: temporaryFile()).current == DefaultSettings.settings)
    }

    @Test("保存した設定を読み直せ，本人だけが読み書きできる")
    func roundTrip() throws {
        let url = temporaryFile()
        let store = FileSettingsStore(fileURL: url)
        try store.update { $0.liveConversion = false }
        try store.update { $0.yenKey = .alwaysYen }
        #expect(FileSettingsStore(fileURL: url).current.liveConversion == false)
        #expect(FileSettingsStore(fileURL: url).current.yenKey == .alwaysYen)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
    }

    @Test("壊れたファイルなら既定値で始める")
    func broken() throws {
        let url = temporaryFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{".utf8).write(to: url)
        #expect(FileSettingsStore(fileURL: url).current == DefaultSettings.settings)
    }

    @Test("大きすぎるファイルは読まない")
    func tooLarge() throws {
        let url = temporaryFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x20, count: DefaultSettings.maximumSettingsFileBytes + 1).write(to: url)
        #expect(FileSettingsStore(fileURL: url).current == DefaultSettings.settings)
    }

    @Test("読めないファイルは脇に置き，既定値で上書きして消さない")
    func unreadableFileIsKept() throws {
        let url = temporaryFile()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("壊れた設定".utf8).write(to: url)
        let store = FileSettingsStore(fileURL: url)
        #expect(store.current == DefaultSettings.settings)
        let kept = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path).filter { $0.contains("unreadable") }
        #expect(kept.count == 1)
    }

    @Test("ユーザー辞書を上限いっぱいに登録しても，保存して読み直せる")
    func largestDictionary() throws {
        let url = temporaryFile()
        let store = FileSettingsStore(fileURL: url)
        let reading = String(repeating: "あ", count: DefaultSettings.maximumUserDictionaryReadingLength - 5)
        let word = String(repeating: "𠀋", count: DefaultSettings.maximumUserDictionaryWordLength)
        try store.update { settings in
            settings.userDictionary = (0..<DefaultSettings.maximumUserDictionaryEntries).map {
                UserDictionaryEntry(reading: reading + String(String($0).map { "あいうえおかきくけこ".map { $0 }[Int(String($0))!] }), word: word)
            }
        }
        #expect(FileSettingsStore(fileURL: url).current.userDictionary.count == DefaultSettings.maximumUserDictionaryEntries)
    }

    @Test("変更を知らせる")
    func observe() throws {
        let store = FileSettingsStore(fileURL: temporaryFile())
        var received: Settings?
        store.observe { received = $0 }
        try store.update { $0.liveConversion = false }
        #expect(received?.liveConversion == false)
    }
}

@Suite("設定の読み込みの強さ")
@MainActor
struct SettingsRobustnessTests {
    @Test("ユーザー辞書の崩れた語だけを飛ばし，ほかの語は残す")
    func lossyDictionary() throws {
        let json = #"{"userDictionary": [{"reading": "あ", "word": "亜"}, {"reading": 1}, {"reading": "い", "word": "井"}]}"#
        let settings = try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
        #expect(settings.userDictionary.map(\.word) == ["亜", "井"])
    }

    @Test("シンボリックリンクの先が上限を超えるファイルは読まない")
    func symlinkSize() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-link-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let target = directory.appendingPathComponent("big.txt")
        try Data(count: DefaultSettings.maximumUserDictionaryFileBytes + 10).write(to: target)
        let link = directory.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        #expect(throws: UserDictionaryFile.FileError.fileTooLarge(maximumBytes: DefaultSettings.maximumUserDictionaryFileBytes)) {
            try UserDictionaryFile.read(from: link)
        }
    }

    @Test("読めなかったファイルを脇に置いたことを知らせる")
    func reportsSetAside() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("s90-aside-\(UUID().uuidString)/settings.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        try Data("{".utf8).write(to: url)
        #expect(FileSettingsStore(fileURL: url).setAsideFile != nil)
        #expect(FileSettingsStore(fileURL: url).setAsideFile == nil)
    }
}
