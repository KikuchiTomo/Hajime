#if os(Linux) || os(macOS)
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation
import S90Application
import S90Domain
@testable import S90IPC
import S90TestSupport
import Testing

@Suite("Unix ドメインソケットの往復(Linux のエンジン)")
struct UnixSocketTests {
    /// sun_path に収まる短い場所
    private static func uniquePath() -> String {
        NSTemporaryDirectory() + "s90-\(UUID().uuidString.prefix(8)).sock"
    }

    @MainActor
    private static func makeService() -> EngineService {
        var initial = DefaultSettings.settings
        initial.liveConversion = false
        let settings = FakeSettings(initial)
        let converter = FakeConverter(["かな": [("仮名", nil)]])
        return EngineService(
            makeSession: { InputSession(converter: converter, lexicon: FakeLexicon(), settings: settings) },
            settings: settings, ui: { _ in }, openSettings: {}
        )
    }

    private static func exchange(_ request: WireRequest, over connection: UnixSocketConnection, reader: inout MessageFraming.Reader) throws -> WireResponse {
        try connection.write(MessageFraming.encode(request))
        while true {
            if let response = try reader.next(WireResponse.self) { return response }
            let bytes = try connection.read()
            guard !bytes.isEmpty else { throw UnixSocketError(.read, code: ECONNRESET) }
            reader.append(bytes)
        }
    }

    @Test("置き場所のフォルダは本人だけが読み書きでき，ソケットの名前は役ごとに分ける")
    func path() throws {
        let engine = try UnixSocketPath.engine()
        #expect(engine.hasSuffix("/engine.sock"))
        #expect(try UnixSocketPath.candidateWindow().hasSuffix("/candidate-window.sock"))
        var status = stat()
        let directory = (engine as NSString).deletingLastPathComponent
        #expect(lstat(directory, &status) == 0)
        #expect(status.st_uid == getuid())
        #expect(status.st_mode & 0o077 == 0)
    }

    @Test("同じ場所で 2 つ目は待ち受けられない(なりすましを防ぐ)．前のエンジンが残したファイルは作り直す")
    func firstInstance() throws {
        let path = Self.uniquePath()
        // 前のエンジンが落ちて残したファイル
        FileManager.default.createFile(atPath: path, contents: Data())
        let first = try UnixSocketListener(path: path)
        #expect(throws: UnixSocketError.self) { try UnixSocketListener(path: path) }
        do {
            _ = try UnixSocketListener(path: path)
        } catch {
            #expect(error.isAlreadyRunning)
        }
        _ = first
    }

    @Test("長すぎる場所は作らない")
    func tooLong() {
        #expect(throws: UnixSocketError.self) { try UnixSocketListener(path: "/tmp/" + String(repeating: "a", count: 200)) }
    }

    @Test("つないできた相手のユーザーは自分")
    func peer() throws {
        let path = Self.uniquePath()
        let listener = try UnixSocketListener(path: path)
        let client = try UnixSocketConnection.connect(path: path)
        defer { client.close() }
        let server = try listener.accept()
        defer { server.close() }
        #expect(try server.peerUserID() == getuid())
        #expect(server.peerProcessID() == getpid())
    }

    @Test("キーを送り，組み立て中の文字と確定の操作を受け取る")
    func roundTrip() async throws {
        let path = Self.uniquePath()
        let listener = try UnixSocketListener(path: path)
        let service = await MainActor.run { Self.makeService() }
        EngineSocketServer.start(listener: listener, service: service, candidateWindowPath: nil)

        let connection = try UnixSocketConnection.connect(path: path)
        defer { connection.close() }
        var reader = MessageFraming.Reader()
        let plain = WireModifiers(shift: false, control: false, alt: false)
        let context = WireFieldContext(applicationId: "org.example.editor", isSecure: false)

        let hello = try Self.exchange(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), over: connection, reader: &reader)
        #expect(hello.body == .hello(protocolVersion: WireProtocol.version))
        let opened = try Self.exchange(WireRequest(id: 2, body: .openSession), over: connection, reader: &reader)
        guard case .sessionOpened(let session, _) = opened.body else {
            Issue.record("セッションを作れない")
            return
        }
        var last: WireResponse?
        for (index, character) in "kana".enumerated() {
            let input = WireKeyInput(key: .character(text: String(character)), modifiers: plain, isKeypad: false)
            last = try Self.exchange(WireRequest(id: UInt32(10 + index), body: .key(session: session, input: input, context: context)), over: connection, reader: &reader)
        }
        guard case .edit(true, let operations, _) = last?.body else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(operations == [.setComposition(segments: [WireTextSegment(text: "かな", style: .reading)])])
        _ = try Self.exchange(WireRequest(id: 20, body: .key(session: session, input: WireKeyInput(key: .space, modifiers: plain, isKeypad: false), context: context)),
                              over: connection, reader: &reader)
        let enter = try Self.exchange(WireRequest(id: 21, body: .key(session: session, input: WireKeyInput(key: .enter, modifiers: plain, isKeypad: false), context: context)),
                                      over: connection, reader: &reader)
        guard case .edit(_, let committed, _) = enter.body else {
            Issue.record("確定できない")
            return
        }
        #expect(committed.contains(.commit(text: "仮名")))
    }

    @Test("相手が閉じたら読みは空になり，書くと失敗する(プロセスは止まらない)")
    func closedPeer() throws {
        let path = Self.uniquePath()
        let listener = try UnixSocketListener(path: path)
        let client = try UnixSocketConnection.connect(path: path)
        let server = try listener.accept()
        client.close()
        #expect(try server.read().isEmpty)
        var failed = false
        for _ in 0..<64 {
            do { try server.write(Array(repeating: 0, count: 1024)) } catch { failed = true; break }
        }
        #expect(failed)
        server.close()
    }
}
#endif
