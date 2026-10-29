import Foundation
import HajimeDomain
import HajimePersistence
import Testing

@Suite("決まりの一覧のファイル")
struct RuleListFileTests {
    @Test("「左<タブ>右」の行を読み，コメントと空の行は読まない．右の無い行は右を空にする")
    func parse() {
        let text = """
        # 置き換え
        teh\tthe\tメモ

        recieve\treceive
        ひとつだけ
        """
        #expect(RuleListFile.parse(text) == [
            RuleListFile.Row(key: "teh", value: "the"),
            RuleListFile.Row(key: "recieve", value: "receive"),
            RuleListFile.Row(key: "ひとつだけ", value: ""),
        ])
    }

    @Test("書き出したファイルを読み戻すと同じになる．中身のタブと改行は空白にする")
    func roundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-rules-\(UUID().uuidString).tsv")
        defer { try? FileManager.default.removeItem(at: url) }
        try RuleListFile.write([.init(key: "teh", value: "the"), .init(key: "python", value: ""), .init(key: "a\tb", value: "c\nd")], to: url)
        #expect(try RuleListFile.read(from: url) == [.init(key: "teh", value: "the"), .init(key: "python", value: ""), .init(key: "a b", value: "c d")])
    }

    @Test("大きすぎるファイルは読まない")
    func tooLarge() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-rules-\(UUID().uuidString).tsv")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(count: DefaultSettings.maximumRuleListFileBytes + 1).write(to: url)
        #expect(throws: RuleListFile.FileError.self) { try RuleListFile.read(from: url) }
    }
}
