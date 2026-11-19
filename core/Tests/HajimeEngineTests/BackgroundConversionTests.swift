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

/// 打鍵が止まったあとの処理に使う変換を裏で求める(KanaKanjiConverting.prefetchCandidates)
extension BackgroundConversionTests {
    private func makeEngine() throws -> (engine: AzooKeyConverterEngine, directory: URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-background-\(UUID().uuidString)")
        return (try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "background"), directory)
    }

    @Test("裏で求めておいた変換は，待って求めた変換と同じ候補になる", arguments: ["きょうはいいてんきですね", "みんなのいけんをはんえいする", "あ"])
    func prefetchedCandidatesMatchBlocking(reading: String) async throws {
        let (engine, directory) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: directory) }
        let prefetching = engine.makeSession()
        let box = Box()
        prefetching.setArrivalObserver { box.value.arrivals += 1 }
        // 頼んだ時点では手元に無く，待たずに返る
        #expect(!prefetching.prefetchCandidates(for: reading))
        // 表示が変換を待っているとは見なさない(止まったあとの処理のための変換なので)
        #expect(!prefetching.consumeDeferredMiss())
        for _ in 0..<2000 where !prefetching.prefetchCandidates(for: reading) { try await Task.sleep(for: .milliseconds(2)) }
        #expect(prefetching.prefetchCandidates(for: reading))
        #expect(box.value.arrivals > 0)
        let blocking = engine.makeSession()
        #expect(prefetching.candidates(for: reading).map(\.text) == blocking.candidates(for: reading).map(\.text))
        prefetching.endComposition()
        blocking.endComposition()
    }

    @Test("裏で求め終える前に待って求めても，同じ候補になる(同じ読みを二重に求めない)")
    func candidatesBeforePrefetchArrives() throws {
        let (engine, directory) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: directory) }
        let reading = "きょうはいいてんきですね"
        let prefetching = engine.makeSession()
        #expect(!prefetching.prefetchCandidates(for: reading))
        let early = prefetching.candidates(for: reading).map(\.text)
        #expect(prefetching.prefetchCandidates(for: reading))
        let blocking = engine.makeSession()
        #expect(early == blocking.candidates(for: reading).map(\.text))
        prefetching.endComposition()
        blocking.endComposition()
    }

    @Test("打っている途中の変換を裏で求めているあいだに頼んでも，どちらも届く")
    func prefetchWhileTypingConversionRuns() async throws {
        let (engine, directory) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = engine.makeSession()
        // 打鍵の経路: 待たずに裏へ回す
        session.setTyping(true)
        session.setDeferring(true)
        #expect(session.candidates(for: "きょうはいいてんき").isEmpty)
        session.setDeferring(false)
        session.setTyping(false)
        #expect(!session.prefetchCandidates(for: "きょうはいいてんきですね"))
        for _ in 0..<2000 where !session.prefetchCandidates(for: "きょうはいいてんきですね") { try await Task.sleep(for: .milliseconds(2)) }
        #expect(session.prefetchCandidates(for: "きょうはいいてんきですね"))
        let blocking = engine.makeSession()
        #expect(session.candidates(for: "きょうはいいてんきですね").map(\.text) == blocking.candidates(for: "きょうはいいてんきですね").map(\.text))
        session.endComposition()
        blocking.endComposition()
    }

    @Test("空の読みは求めるものが無い")
    func emptyReadingNeedsNoPrefetch() throws {
        let (engine, directory) = try makeEngine()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(engine.makeSession().prefetchCandidates(for: ""))
    }
}
