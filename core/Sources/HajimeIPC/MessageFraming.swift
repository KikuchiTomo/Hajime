import Foundation

public enum MessageFramingError: Error, Equatable {
    case tooLarge(Int)
    case malformed
}

public enum MessageFraming {
    public static let lengthBytes = 4

    public static func encode(_ message: some Encodable) throws(MessageFramingError) -> [UInt8] {
        let body: Data
        do {
            body = try JSONEncoder().encode(message)
        } catch {
            throw .malformed
        }
        guard body.count <= WireProtocol.maximumMessageBytes else { throw .tooLarge(body.count) }
        let length = UInt32(body.count)
        var frame: [UInt8] = []
        frame.reserveCapacity(lengthBytes + body.count)
        for shift in stride(from: 0, to: 32, by: 8) {
            frame.append(UInt8(truncatingIfNeeded: length >> UInt32(shift)))
        }
        frame.append(contentsOf: body)
        return frame
    }

    public static func decode<Message: Decodable>(_ type: Message.Type, from body: some Collection<UInt8>) throws(MessageFramingError) -> Message {
        guard body.count <= WireProtocol.maximumMessageBytes else { throw .tooLarge(body.count) }
        do {
            return try JSONDecoder().decode(type, from: Data(body))
        } catch {
            throw .malformed
        }
    }

    public struct Reader: Sendable {
        private var buffer: [UInt8] = []

        public init() {}

        public mutating func append(_ bytes: some Sequence<UInt8>) {
            buffer.append(contentsOf: bytes)
        }

        public mutating func nextBody() throws(MessageFramingError) -> [UInt8]? {
            guard buffer.count >= MessageFraming.lengthBytes else { return nil }
            var length = 0
            for index in 0..<MessageFraming.lengthBytes {
                length |= Int(buffer[index]) << (8 * index)
            }
            guard length <= WireProtocol.maximumMessageBytes else { throw .tooLarge(length) }
            guard buffer.count >= MessageFraming.lengthBytes + length else { return nil }
            let body = Array(buffer[MessageFraming.lengthBytes..<(MessageFraming.lengthBytes + length)])
            buffer.removeFirst(MessageFraming.lengthBytes + length)
            return body
        }

        public mutating func next<Message: Decodable>(_ type: Message.Type) throws(MessageFramingError) -> Message? {
            guard let body = try nextBody() else { return nil }
            return try MessageFraming.decode(type, from: body)
        }
    }
}
