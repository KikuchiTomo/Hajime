import Foundation
import HajimeDomain
import HajimePersistence
import Testing

@Suite("ユーザー辞書のファイル")
struct UserDictionaryFileTests {
    @Test("「読み<タブ>語」の行を読み，品詞などの 3 列目以降とコメントの行と形の誤った行は使わない")
    func parse() {
        let text = """
        !Microsoft IME Dictionary Tool
        えすきゅー\thajime\t固有名詞\t
        # コメント
        ABC\t読みがひらがなでない
        ひとつだけ
        かいしゃ\t会社
        """
        #expect(UserDictionaryFile.parse(text) == [
            UserDictionaryEntry(reading: "えすきゅー", word: "hajime"),
            UserDictionaryEntry(reading: "かいしゃ", word: "会社"),
        ])
    }

    @Test("書き出したファイルを読み戻すと同じになる")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-dictionary-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = [UserDictionaryEntry(reading: "えすきゅー", word: "hajime")]
        try UserDictionaryFile.write(entries, to: url)
        #expect(try UserDictionaryFile.read(from: url) == entries)
    }

    @Test("大きすぎるファイルは読まない")
    func tooLarge() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-dictionary-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: DefaultSettings.maximumUserDictionaryFileBytes + 1).write(to: url)
        #expect(throws: UserDictionaryFile.FileError.self) { try UserDictionaryFile.read(from: url) }
    }
}
