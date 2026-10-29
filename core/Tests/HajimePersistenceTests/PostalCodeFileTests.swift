import Foundation
import Testing
@testable import HajimePersistence

@Suite("郵便番号の表(R-13)")
@MainActor
struct PostalCodeFileTests {
    @Test("「郵便番号<タブ>住所…」の行を読み，# の行と形の誤った行は飛ばす")
    func parse() {
        let table = PostalCodeFile.parse("# 説明\n1000001\t東京都千代田区千代田\n0600042\t北海道札幌市中央区大通西\t北海道札幌市中央区大通西二\nabc\tx\n")
        #expect(table["1000001"] == ["東京都千代田区千代田"])
        #expect(table["0600042"]?.count == 2)
        #expect(table.count == 2)
    }

    @Test("改行が CRLF の表も読む")
    func crlf() {
        let table = PostalCodeFile.parse("# 説明\r\n1000001\t東京都千代田区千代田\r\n0600042\t北海道札幌市中央区大通西\r\n")
        #expect(table["1000001"] == ["東京都千代田区千代田"])
        #expect(table["0600042"] == ["北海道札幌市中央区大通西"])
    }

    @Test("同梱する表から住所を引く")
    func bundledTable() {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("data/postal/postal-codes.tsv")
        let file = PostalCodeFile(url: url)
        #expect(file.addresses(for: "1000001") == ["東京都千代田区千代田"])
        #expect(file.addresses(for: "0000000").isEmpty)
    }
}
