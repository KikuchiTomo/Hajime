#if os(Windows)
import Foundation
import S90Application
import S90Domain
@testable import S90IPC
import S90TestSupport
import Testing
import WinSDK

@Suite("名前付きパイプの往復")
struct NamedPipeTests {
    private static func uniqueName() -> String {
        #"\\.\pipe\s90.tokyo-ime.test.\#(UUID().uuidString)"#
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

    private static func exchange(_ request: WireRequest, over connection: NamedPipeConnection, reader: inout MessageFraming.Reader) throws -> WireResponse {
        try connection.write(MessageFraming.encode(request))
        while true {
            if let response = try reader.next(WireResponse.self) { return response }
            let bytes = try connection.read()
            guard !bytes.isEmpty else { throw NamedPipeError(.read, code: 109) }
            reader.append(bytes)
        }
    }

    @Test("パイプの名前にユーザーの SID とセッションを入れる")
    func pipeName() throws {
        let name = try NamedPipeName.engine()
        #expect(name.hasPrefix(#"\\.\pipe\s90.tokyo-ime.S-1-"#))
        #expect(name.hasSuffix(".engine"))
    }

    @Test("同じ名前のパイプは 2 つ目を作れない(なりすましを防ぐ)")
    func firstInstance() throws {
        let name = Self.uniqueName()
        let first = try NamedPipeListener(name: name)
        #expect(throws: NamedPipeError.self) { try NamedPipeListener(name: name) }
        _ = first
    }

    @Test("キーを送り，組み立て中の文字と確定の操作を受け取る")
    func roundTrip() async throws {
        let name = Self.uniqueName()
        let listener = try NamedPipeListener(name: name)
        let service = await MainActor.run { Self.makeService() }
        EnginePipeServer.start(listener: listener, service: service, candidateWindowPath: "")

        let connection = try NamedPipeClient.connect(name: name, timeoutMilliseconds: 5000)
        defer { connection.close() }
        var reader = MessageFraming.Reader()
        let plain = WireModifiers(shift: false, control: false, alt: false)
        let context = WireFieldContext(applicationId: "test.exe", isSecure: false)

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
        #expect(last?.id == 13)
        guard case .edit(true, let operations, _) = last?.body else {
            Issue.record("編集の応答にならない")
            return
        }
        #expect(operations == [.setComposition(segments: [WireTextSegment(text: "かな", style: .reading)])])

        let space = try Self.exchange(WireRequest(id: 20, body: .key(session: session, input: WireKeyInput(key: .space, modifiers: plain, isKeypad: false), context: context)),
                                      over: connection, reader: &reader)
        #expect(space.id == 20)
        let enter = try Self.exchange(WireRequest(id: 21, body: .key(session: session, input: WireKeyInput(key: .enter, modifiers: plain, isKeypad: false), context: context)),
                                      over: connection, reader: &reader)
        guard case .edit(_, let committed, _) = enter.body else {
            Issue.record("確定できない")
            return
        }
        #expect(committed.contains(.commit(text: "仮名")))
    }

    @Test("1 キーの往復は DLL が待つ時間(50ms)より十分に短い")
    func latency() async throws {
        let name = Self.uniqueName()
        let listener = try NamedPipeListener(name: name)
        let service = await MainActor.run { Self.makeService() }
        EnginePipeServer.start(listener: listener, service: service, candidateWindowPath: "")

        let connection = try NamedPipeClient.connect(name: name, timeoutMilliseconds: 5000)
        defer { connection.close() }
        var reader = MessageFraming.Reader()
        _ = try Self.exchange(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), over: connection, reader: &reader)
        guard case .sessionOpened(let session, _) = try Self.exchange(WireRequest(id: 2, body: .openSession), over: connection, reader: &reader).body else {
            Issue.record("セッションを作れない")
            return
        }
        let plain = WireModifiers(shift: false, control: false, alt: false)
        let clock = ContinuousClock()
        var durations: [Duration] = []
        for index in 0..<200 {
            let key: WireKey = index % 2 == 0 ? .character(text: "a") : .backspace
            let request = WireRequest(id: UInt32(10 + index), body: .key(session: session, input: WireKeyInput(key: key, modifiers: plain, isKeypad: false),
                                                                         context: WireFieldContext(isSecure: false)))
            let start = clock.now
            _ = try Self.exchange(request, over: connection, reader: &reader)
            durations.append(clock.now - start)
        }
        let p95 = durations.sorted()[durations.count * 95 / 100]
        #expect(p95 < .milliseconds(20), "p95: \(p95)")
    }

    @Test("上限を超える長さを送った接続は切る")
    func tooLarge() async throws {
        let name = Self.uniqueName()
        let listener = try NamedPipeListener(name: name)
        let service = await MainActor.run { Self.makeService() }
        EnginePipeServer.start(listener: listener, service: service, candidateWindowPath: "")

        let connection = try NamedPipeClient.connect(name: name, timeoutMilliseconds: 5000)
        defer { connection.close() }
        let length = UInt32(WireProtocol.maximumMessageBytes + 1)
        try connection.write([UInt8(length & 0xff), UInt8((length >> 8) & 0xff), UInt8((length >> 16) & 0xff), UInt8(length >> 24)])
        #expect(try connection.read().isEmpty)
    }
    @Test("手書きの窓で選んだ文字は，候補ウィンドウの実行ファイルからの接続だけが送れる")
    func handwritingFromCandidateWindow() async throws {
        let ownPath = try #require(NamedPipePeer.imagePath(processID: GetCurrentProcessId()))
        for (path, expected) in [(ownPath, WireResponseBody.done), ("C:\\other.exe", .error(code: .malformed))] {
            let name = Self.uniqueName()
            let listener = try NamedPipeListener(name: name)
            let service = await MainActor.run { Self.makeService() }
            EnginePipeServer.start(listener: listener, service: service, candidateWindowPath: path)
            let connection = try NamedPipeClient.connect(name: name, timeoutMilliseconds: 5000)
            defer { connection.close() }
            var reader = MessageFraming.Reader()
            _ = try Self.exchange(WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version)), over: connection, reader: &reader)
            let response = try Self.exchange(WireRequest(id: 2, body: .handwritingChosen(text: "鬱")), over: connection, reader: &reader)
            #expect(response.body == expected)
        }
    }

    @Test("候補ウィンドウが何も書かなくても，エンジンからの送信は止まらない")
    func candidateWindowLinkSends() throws {
        let ownPath = try #require(NamedPipePeer.imagePath(processID: GetCurrentProcessId()))
        let name = Self.uniqueName()
        let listener = try NamedPipeListener(name: name)
        let link = CandidateWindowLink()
        link.start(listener: listener, expectedImagePath: ownPath) { [] }
        let connection = try NamedPipeClient.connect(name: name, timeoutMilliseconds: 5000)
        defer { connection.close() }
        // 受け入れた接続に切り替わるまで待ってから送る
        Thread.sleep(forTimeInterval: 0.5)
        link.send(.hide)
        let received = DispatchSemaphore(value: 0)
        let box = ReceivedBytes()
        Thread {
            box.bytes = (try? connection.read()) ?? []
            received.signal()
        }.start()
        #expect(received.wait(timeout: .now() + 5) == .success)
        var reader = MessageFraming.Reader()
        reader.append(box.bytes)
        #expect(try reader.next(WireUiCommand.self) == .hide)
    }
}

private final class ReceivedBytes: @unchecked Sendable {
    var bytes: [UInt8] = []
}
#endif
