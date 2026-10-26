import Foundation

/// メッセージの読み書きの失敗．入力の中身を含めない(docs/dev/SECURITY-MODEL.md)
public enum MessageFramingError: Error, Equatable {
    /// 上限(WireProtocol.maximumMessageBytes)より大きい．接続を切る
    case tooLarge(Int)
    /// protocol/schema.json の定義と合わない
    case malformed
}

/// メッセージの区切り方．4 バイトの長さ(リトルエンディアン)のあとに，UTF-8 の JSON を置く
/// (docs/dev/adr/0010-ipc-message-format.md)．Rust の側は apps/windows/crates/ipc/src/framing.rs
public enum MessageFraming {
    public static let lengthBytes = 4

    /// メッセージを，長さを前に付けたバイト列にする
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

    /// 長さを除いた本体を読む
    public static func decode<Message: Decodable>(_ type: Message.Type, from body: some Collection<UInt8>) throws(MessageFramingError) -> Message {
        guard body.count <= WireProtocol.maximumMessageBytes else { throw .tooLarge(body.count) }
        do {
            return try JSONDecoder().decode(type, from: Data(body))
        } catch {
            // DecodingError は値の一部を含むことがあるので，種類だけにする
            throw .malformed
        }
    }

    /// 受け取ったバイトをため，メッセージごとに切り出す．パイプは 1 回の読み込みでメッセージの途中までしか返さないことがあるため
    public struct Reader: Sendable {
        private var buffer: [UInt8] = []

        public init() {}

        public mutating func append(_ bytes: some Sequence<UInt8>) {
            buffer.append(contentsOf: bytes)
        }

        /// そろったメッセージの本体を 1 つ取り出す．まだそろっていなければ nil．
        /// 長さが上限を超えていたら，本体を待たずに断る
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

        /// そろったメッセージを 1 つ読む．まだそろっていなければ nil
        public mutating func next<Message: Decodable>(_ type: Message.Type) throws(MessageFramingError) -> Message? {
            guard let body = try nextBody() else { return nil }
            return try MessageFraming.decode(type, from: body)
        }
    }
}
