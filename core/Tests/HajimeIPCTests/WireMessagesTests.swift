import Foundation
import HajimeIPC
import Testing

@Suite("通信の型(ADR 0010)")
struct WireMessagesTests {
    private static func fixtures() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("protocol/fixtures/messages.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require(object as? [String: Any])
    }

    private static func roundTrip<Message: Codable>(_ type: Message.Type, group: String) throws -> Int {
        let messages = try #require(try fixtures()[group] as? [Any])
        for message in messages {
            let data = try JSONSerialization.data(withJSONObject: message)
            let decoded = try JSONDecoder().decode(type, from: data)
            let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded))
            #expect(NSDictionary(dictionary: try #require(encoded as? [String: Any])) == NSDictionary(dictionary: try #require(message as? [String: Any])),
                    "\(group) を読み戻すと形が変わる")
        }
        return messages.count
    }

    @Test("要求を読み戻せる")
    func requests() throws {
        #expect(try Self.roundTrip(WireRequest.self, group: "requests") > 0)
    }

    @Test("応答を読み戻せる")
    func responses() throws {
        #expect(try Self.roundTrip(WireResponse.self, group: "responses") > 0)
    }

    @Test("候補ウィンドウへの指示を読み戻せる")
    func uiCommands() throws {
        #expect(try Self.roundTrip(WireUiCommand.self, group: "uiCommands") > 0)
    }

    @Test("枠に入れたメッセージを，少しずつ届いても切り出せる")
    func framing() throws {
        let first = WireRequest(id: 1, body: .hello(protocolVersion: WireProtocol.version))
        let second = WireRequest(id: 2, body: .closeSession(session: 3))
        let bytes = try MessageFraming.encode(first) + MessageFraming.encode(second)
        var reader = MessageFraming.Reader()
        var received: [WireRequest] = []
        for byte in bytes {
            reader.append([byte])
            while let message = try reader.next(WireRequest.self) {
                received.append(message)
            }
        }
        #expect(received == [first, second])
    }

    @Test("上限を超える長さは本体を待たずに断る")
    func tooLarge() {
        var reader = MessageFraming.Reader()
        let length = UInt32(WireProtocol.maximumMessageBytes + 1)
        reader.append([UInt8(length & 0xff), UInt8((length >> 8) & 0xff), UInt8((length >> 16) & 0xff), UInt8(length >> 24)])
        #expect(throws: MessageFramingError.tooLarge(WireProtocol.maximumMessageBytes + 1)) {
            try reader.nextBody()
        }
    }

    @Test("定義に無い種類は断る")
    func unknownKind() {
        let body = Array(#"{"id":1,"body":{"type":"runCommand"}}"#.utf8)
        #expect(throws: MessageFramingError.malformed) {
            try MessageFraming.decode(WireRequest.self, from: body)
        }
    }

    @Test("ログに出すときは入力の中身を伏せる")
    func redaction() {
        let message = WireEditOperation.commit(text: "秘密の文")
        #expect(!String(describing: message).contains("秘密"))
        #expect(!String(reflecting: WireTextSegment(text: "秘密", style: .reading)).contains("秘密"))
    }
}
