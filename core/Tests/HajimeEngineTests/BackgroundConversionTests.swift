import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeTestSupport
import Testing

/// 打っているあいだの変換を変換用のスレッドで求める作り(AzooKeyConverterSession の裏の変換)を，本物の変換エンジンで確かめる．
/// キーの処理の中で待って求める作りと，確定する文が同じになること
@Suite("変換用のスレッドで求める変換(本物のエンジン)")
@MainActor
struct BackgroundConversionTests {
    private struct Typed {
        var committed = ""
        var marked = ""
        var arrivals = 0
        /// キーを処理した直後に，変換を待っていた回数
        var awaited = 0
    }

    /// keys を打って Enter で確定する．waitsForArrival なら，キーごとに裏の変換が届くのを待ってから次のキーを打つ
    /// (時間で待つと，テストを動かすマシンの速さで届く・届かないが変わる)
    private func type(_ keys: String, defers: Bool, waitsForArrival: Bool = false, lexicon: FakeLexicon = FakeLexicon(words: ["python", "git"])) async throws -> Typed {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-background-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "background")
        let session = InputSession(converter: engine.makeSession(), lexicon: lexicon, settings: FakeSettings(DefaultSettings.settings))
        let box = Box()
        func apply(_ actions: [ClientAction]) {
            for action in actions {
                if case .commit(let text) = action { box.value.committed += text }
                if case .setMarkedText(let text) = action { box.value.marked = text.text }
            }
        }
        if defers {
            session.setConversionArrivalHandler {
                box.value.arrivals += 1
                apply(session.conversionDidArrive(context: InputContext()))
            }
        }
        for key in keys {
            apply(session.handle(KeyEvent(.character(key)), context: InputContext()).actions)
            if session.awaitsConversion { box.value.awaited += 1 }
            if waitsForArrival {
                for _ in 0..<2000 where session.awaitsConversion { try await Task.sleep(for: .milliseconds(2)) }
            }
        }
        apply(session.handle(KeyEvent(.enter), context: InputContext()).actions)
        return box.value
    }

    @MainActor
    private final class Box {
        var value = Typed()
    }

    private nonisolated static let sentences = [
        "kyouhaiitenkidesune", "watasihaasitatoukyoudekaigininisyussekisimasu", "minnnanoikennwohannneisuru", "onnnanohitogaimasu",
        "pythongasugoi", "gitwotukau", "konnnitiha", "sinnkannsenndeoosakaniikimasu",
    ]

    @Test("待たずに打ち進めても，待って求めたときと同じ文を確定する", arguments: sentences)
    func commitsSameTextWithoutWaiting(keys: String) async throws {
        let deferred = try await type(keys, defers: true)
        let blocking = try await type(keys, defers: false)
        #expect(deferred.committed == blocking.committed)
    }

    @Test("キーごとに変換が届いてから打っても，待って求めたときと同じ文を確定する", arguments: sentences)
    func commitsSameTextWithArrivals(keys: String) async throws {
        let deferred = try await type(keys, defers: true, waitsForArrival: true)
        let blocking = try await type(keys, defers: false)
        #expect(deferred.committed == blocking.committed)
        // 裏の変換が届いて，表示を出し直している
        #expect(deferred.arrivals > 0)
    }

    @Test("キーの処理の中では変換を待たない(打った直後は変換を待つ表示になる)")
    func keysDoNotWait() async throws {
        let deferred = try await type("kyouhaiitenkidesune", defers: true)
        #expect(deferred.awaited > 0)
    }

    @Test("届いたあとの表示は，待って求めた表示と同じになる")
    func displayMatchesAfterArrival() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-background-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "background")
        func marked(defers: Bool) async throws -> String {
            let session = InputSession(converter: engine.makeSession(), lexicon: FakeLexicon(), settings: FakeSettings(DefaultSettings.settings))
            let box = Box()
            if defers {
                session.setConversionArrivalHandler {
                    for action in session.conversionDidArrive(context: InputContext()) {
                        if case .setMarkedText(let text) = action { box.value.marked = text.text }
                    }
                }
            }
            for key in "kyouhaiitenkidesune" {
                for action in session.handle(KeyEvent(.character(key)), context: InputContext()).actions {
                    if case .setMarkedText(let text) = action { box.value.marked = text.text }
                }
            }
            // 裏の変換が届くのを待つ
            for _ in 0..<200 where session.awaitsConversion { try await Task.sleep(for: .milliseconds(5)) }
            _ = session.handle(KeyEvent(.escape), context: InputContext())
            return box.value.marked
        }
        let deferred = try await marked(defers: true)
        let blocking = try await marked(defers: false)
        #expect(deferred == blocking)
    }
}
