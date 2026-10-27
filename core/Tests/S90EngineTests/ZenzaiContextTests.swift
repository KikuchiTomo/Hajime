import Foundation
@testable import S90Engine
import Testing

/// 打ち間違いの訂正は，表示の変換とは別の推論の文脈で Zenzai を使う(訂正のあいだ打鍵の変換を待たせない)
@Suite("Zenzai の推論の文脈")
struct ZenzaiContextTests {
    @Test("訂正に使う場所は，同じファイルを指す別の場所になる")
    func separateContext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90 zenzai", isDirectory: true)
        let model = ZenzaiModel(url: directory.appendingPathComponent(ZenzaiModel.fileName))
        let separate = model.separateContextURL
        // azooKey は URL の文字列ごとに文脈を作るので，文字列は違う
        #expect(separate.absoluteString != model.url.absoluteString)
        // 読むファイルとモデルの重み(path ごとに共有)は同じ
        #expect(separate.path == model.url.path)
        #expect(separate.isFileURL)
        #expect(separate.fragment == ZenzaiModel.separateContextFragment)
    }
}
