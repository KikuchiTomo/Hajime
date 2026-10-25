import Foundation
import S90Application
import S90Domain
import S90Engine
import S90TestSupport
import Testing

/// 本物の変換エンジンにキーの列を流し込み，確定する文字を確かめる．OS の部分を除いた端から端までの確認
@Suite("キーから確定まで(本物のエンジン)")
@MainActor
struct EndToEndInputTests {
    private func run(_ keys: String, then finalKeys: [KeyEvent.Key] = [.enter], settings: Settings = DefaultSettings.settings) throws -> (committed: String, marked: String) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-e2e-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "e2e")
        let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(words: ["python"]), settings: FakeSettings(settings))
        var committed = ""
        var marked = ""
        func apply(_ result: KeyResult) {
            for action in result.actions {
                if case .commit(let text) = action { committed += text }
                if case .setMarkedText(let text) = action { marked = text.text }
            }
        }
        for key in keys { apply(session.handle(KeyEvent(.character(key)), context: InputContext())) }
        let markedBeforeFinal = marked
        for key in finalKeys { apply(session.handle(KeyEvent(key), context: InputContext())) }
        return (committed, markedBeforeFinal)
    }

    @Test("R-01: ライブ変換の結果を Enter で確定する")
    func liveConversion() throws {
        let result = try run("kyouhaiitenkidesune")
        #expect(result.committed == result.marked)
        #expect(result.committed.contains("天気"))
    }

    @Test("Space と Enter で第 1 候補を確定する")
    func spaceThenEnter() throws {
        let result = try run("henkann", then: [.space, .enter])
        #expect(result.committed == "変換")
    }

    @Test("R-02: ローマ字のまま打った英単語は英単語で確定する")
    func correction() throws {
        #expect(try run("python").committed == "python")
    }

    @Test("R-01: konnnitiha で こんにちは")
    func konnichiha() throws {
        #expect(try run("konnnitiha").committed == "こんにちは")
    }

    @Test("文節格子: 本物のエンジンで文を文節に分け，Space と Enter で確定する")
    func lattice() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-e2e-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "e2e")
        let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(), settings: FakeSettings())
        var lattice: LatticePanel?
        var committed = ""
        for key in "watashinonamaehanakanodesu" { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        for action in session.handle(KeyEvent(.space), context: InputContext()).actions {
            if case .showLattice(let panel) = action { lattice = panel }
        }
        let columns = try #require(lattice?.columns)
        #expect(columns.count >= 2)
        #expect(columns.allSatisfy { !$0.alternatives.isEmpty })
        for action in session.handle(KeyEvent(.enter), context: InputContext()).actions {
            if case .commit(let text) = action { committed += text }
        }
        #expect(committed == columns.map(\.text).joined())
        print("S90_LATTICE", columns.map { "\($0.text)[\($0.alternatives.prefix(3).joined(separator: ","))]" }.joined(separator: " | "))
    }
}
