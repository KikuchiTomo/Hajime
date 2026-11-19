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

    @Test("「更新お願いします」の「ん」を nn で打っても「更新の願いします」にしない", arguments: ["kousinnonegaisimasu", "koushinnonegaishimasu"])
    func requestAfterNasal(keys: String) throws {
        #expect(try commit(keys) == "更新お願いします")
    }

    @Test("「めちゃくちゃ」の途中(metyaku)で打鍵が止まって英単語(met)にしても，続きを打てば日本語に戻り，戻す前も候補に日本語が出る")
    func pauseInsideWord() throws {
        let path = try #require(ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-reported-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "reported", zenzai: try ZenzaiModel.verified(at: URL(fileURLWithPath: path)))
        func session() -> InputSession {
            InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(words: ["met"]), settings: FakeSettings())
        }
        func marked(_ actions: [ClientAction]) -> String? {
            actions.compactMap { if case .setMarkedText(let text) = $0 { text.text } else { nil } }.last
        }
        // 語の途中で止まると「met」+「役」になる．続きを打って確定すれば「めちゃくちゃ」
        let typing = session()
        for key in "metyaku" { _ = typing.handle(KeyEvent(.character(key)), context: InputContext()) }
        #expect(marked(typing.settle(context: InputContext()))?.hasPrefix("met") == true)
        for key in "tya" { _ = typing.handle(KeyEvent(.character(key)), context: InputContext()) }
        var committed = ""
        for action in typing.handle(KeyEvent(.enter), context: InputContext()).actions {
            if case .commit(let text) = action { committed += text }
        }
        #expect(committed == "めちゃくちゃ")
        // 止まったまま変換しても，英単語にした文節の上の枝にかな，下の枝に日本語の変換が出る
        let converting = session()
        for key in "metyaku" { _ = converting.handle(KeyEvent(.character(key)), context: InputContext()) }
        _ = converting.settle(context: InputContext())
        var column: LatticePanel.Column?
        for action in converting.handle(KeyEvent(.space), context: InputContext()).actions {
            if case .showLattice(let panel) = action { column = panel.columns.first }
        }
        #expect(column?.text.hasPrefix("met") == true)
        #expect(column?.variants.first == "めちゃく")
        #expect(column?.alternatives.contains { !$0.contains(where: \.isASCII) } == true)
    }

    @Test("「Cloudflareで取ったドメイン」")
    func cloudflare() throws {
        #expect(try commit("kuraudohureadetottadomeinn").contains("取った"))
    }
}
