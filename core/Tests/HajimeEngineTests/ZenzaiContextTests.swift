import Foundation
@testable import HajimeEngine
import Testing

/// 打ち間違いの訂正は，表示の変換とは別の推論の文脈で Zenzai を使う(訂正のあいだ打鍵の変換を待たせない)
@Suite("Zenzai の推論の文脈")
struct ZenzaiContextTests {
    @Test("訂正に使う場所は，同じファイルを指す別の場所になる")
    func separateContext() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime zenzai", isDirectory: true)
        let model = ZenzaiModel(url: directory.appendingPathComponent(ZenzaiModel.fileName))
        let separate = model.separateContextURL
        // azooKey は URL の文字列ごとに文脈を作るので，文字列は違う
        #expect(separate.absoluteString != model.url.absoluteString)
        // 読むファイルとモデルの重み(path ごとに共有)は同じ
        #expect(separate.path == model.url.path)
        #expect(separate.isFileURL)
        #expect(separate.fragment == ZenzaiModel.separateContextFragment)
    }

    @Test("Zenzai の変換が 1 キーの時間に収まらない環境だけ，入力中の表示に Zenzai を使わない")
    func typingBudget() {
        // まだ測っていなければ使う
        #expect(!AzooKeyConverterEngine.exceedsTypingBudget(nil))
        let fast = AzooKeyConverterEngine.smoothedCost(nil, adding: .milliseconds(8))
        #expect(!AzooKeyConverterEngine.exceedsTypingBudget(fast))
        // 遅い変換が続けば使わなくなり，速い変換が続けばまた使う
        var cost: Double? = fast
        for _ in 0..<5 { cost = AzooKeyConverterEngine.smoothedCost(cost, adding: .milliseconds(70)) }
        #expect(AzooKeyConverterEngine.exceedsTypingBudget(cost))
        for _ in 0..<15 { cost = AzooKeyConverterEngine.smoothedCost(cost, adding: .milliseconds(8)) }
        #expect(!AzooKeyConverterEngine.exceedsTypingBudget(cost))
    }

    @Test("Zenzai を使わずに求めた表示は，読みと別のキーで覚える")
    func typingCacheKey() {
        #expect(AzooKeyConverterSession.typingCacheKey("きょう") != "きょう")
        #expect(AzooKeyConverterSession.typingCacheKey("きょう").hasSuffix("きょう"))
    }

    @Test("推論のバッチに入りきらない長さの読みでも止まらず，候補を返す(250 字を超える読みを確定せずに打ち続けたとき)",
          .enabled(if: ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil), arguments: [200, 256, 300, 600])
    @MainActor
    func longReadingDoesNotOverflowBatch(length: Int) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-context-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = try ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"].map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0)) }
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "context", zenzai: model)
        let session = engine.makeSession()
        // 前に求めた読みの続きではない長い読みを求める(読みと候補のトークン列をまるごと評価する)
        let reading = String(repeating: "あ", count: length)
        #expect(!session.candidates(for: reading).isEmpty)
        // 検証木の採点も，プロンプトを置けないときは採点できなかったものとして返す
        #expect(session.scores(of: [reading, "嗚呼" + String(reading.dropFirst(2))], reading: reading, before: "", after: "").count == 2)
        session.endComposition()
    }
}
