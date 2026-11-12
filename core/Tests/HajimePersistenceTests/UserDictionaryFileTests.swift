import Foundation
import HajimeDomain
import HajimePersistence
import Testing

@Suite("ユーザー辞書のファイル")
struct UserDictionaryFileTests {
    @Test("「読み<タブ>語<タブ>品詞<タブ>コメント」の行を読み，品詞の無い行は名詞にし，長すぎるコメントは切る．コメントの行と形の誤った行は使わない")
    func parse() {
        let text = """
        !Microsoft IME Dictionary Tool
        えすきゅー\thajime\t固有名詞\t
        # コメント
        漢字\t読みがひらがなでない
        gh\tGitHub
        ひとつだけ
        かいしゃ\t会社
        やまだ\t山田\t姓\tコメント
        おつ\tお疲れさまでした\t短縮よみ
        じゅうしょ\t住所\t名詞\t\(String(repeating: "長", count: DefaultSettings.maximumUserDictionaryCommentLength + 5))
        """
        #expect(UserDictionaryFile.parse(text) == [
            UserDictionaryEntry(reading: "えすきゅー", word: "hajime", wordClass: .properNoun),
            UserDictionaryEntry(reading: "gh", word: "GitHub", wordClass: .noun),
            UserDictionaryEntry(reading: "かいしゃ", word: "会社", wordClass: .noun),
            UserDictionaryEntry(reading: "やまだ", word: "山田", wordClass: .surname, comment: "コメント"),
            UserDictionaryEntry(reading: "おつ", word: "お疲れさまでした", wordClass: .abbreviation),
            UserDictionaryEntry(reading: "じゅうしょ", word: "住所", wordClass: .noun,
                                comment: String(repeating: "長", count: DefaultSettings.maximumUserDictionaryCommentLength)),
        ])
    }

    @Test("書き出したファイルを読み戻すと，品詞とコメントまで同じになる")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-dictionary-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let entries = WordClass.allCases.enumerated().map { UserDictionaryEntry(reading: "よみ", word: "語\($0.offset)", wordClass: $0.element) }
            + [UserDictionaryEntry(reading: "じゅうしょ", word: "住所", comment: "東京都千代田区")]
        try UserDictionaryFile.write(entries, to: url)
        #expect(try UserDictionaryFile.read(from: url) == entries)
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("よみ\t語0\t名詞\n"))
    }

    @Test("大きすぎるファイルは読まない")
    func tooLarge() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-dictionary-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: DefaultSettings.maximumUserDictionaryFileBytes + 1).write(to: url)
        #expect(throws: UserDictionaryFile.FileError.self) { try UserDictionaryFile.read(from: url) }
    }
}
