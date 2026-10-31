import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeTestSupport
import Testing

/// 利用者から報告された例を，本物の Zenzai でキーから確定まで確かめる．
/// モデルが要るので，環境変数 HAJIME_ZENZAI_MODEL にモデルの場所があるときだけ動かす
@Suite("報告された例(Zenzai)", .serialized, .enabled(if: ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil))
@MainActor
struct ReportedExamplesTests {
    private func commit(_ keys: String, precedingText: String? = nil) throws -> String {
        let path = try #require(ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-reported-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "reported", zenzai: try ZenzaiModel.verified(at: URL(fileURLWithPath: path)))
        let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(words: ["python"]), settings: FakeSettings())
        var committed = ""
        let context = InputContext(precedingText: precedingText)
        for key in keys {
            for action in session.handle(KeyEvent(.character(key)), context: context).actions {
                if case .commit(let text) = action { committed += text }
            }
        }
        for action in session.handle(KeyEvent(.enter), context: context).actions {
            if case .commit(let text) = action { committed += text }
        }
        return committed
    }

    @Test("「pythonがすごい」を Enter 1 回で打てる")
    func pythonGa() throws {
        #expect(try commit("pythongasugoi").hasPrefix("pythonが"))
    }

    @Test("「AAA」のあとの「まで」は「間で」にしない")
    func madeAfterAAA() throws {
        #expect(try commit("made", precedingText: "AAA") == "まで")
    }

    @Test("辞書に無いカタカナ語(ubuntu → うぶんつ)を，分岐図で「ウブ｜ンツ」「ウブン｜ツ」と切らない")
    func katakanaWordStaysTogether() throws {
        let path = try #require(ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-reported-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "reported", zenzai: try ZenzaiModel.verified(at: URL(fileURLWithPath: path)))
        var settings = DefaultSettings.settings
        settings.typoCorrection = .off
        let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(), settings: FakeSettings(settings))
        for key in "ubuntuwoireru" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        var columns: [String] = []
        for action in session.handle(KeyEvent(.space), context: InputContext()).actions {
            if case .showLattice(let panel) = action { columns = panel.columns.map(\.text) }
        }
        #expect(columns.count > 0)
        #expect(!columns.contains { $0.first.map { !ClauseSplitter.canStartClause(with: $0) } ?? false })
        #expect(!zip(columns, columns.dropFirst()).contains { SegmentSplitter.cutsWord(before: $0, after: $1) })
    }

    @Test("「Cloudflareで取ったドメイン」")
    func cloudflare() throws {
        #expect(try commit("kuraudohureadetottadomeinn").contains("取った"))
    }
}
