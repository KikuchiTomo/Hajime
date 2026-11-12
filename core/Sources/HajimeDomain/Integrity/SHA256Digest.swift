/// SHA-256(FIPS 180-4)を少しずつ求める．
///
/// CryptoKit の無い OS(Windows)で，Zenzai のモデルや取り込んだ辞書の索引の中身を確かめるために使う．
/// 依存を足さないために自前で持つ．CryptoKit のある OS では CryptoKit を使い，テストで両者の値が同じことを確かめる
public struct SHA256Digest: Sendable {
    private var state: [UInt32] = [
        0x6a09_e667, 0xbb67_ae85, 0x3c6e_f372, 0xa54f_f53a, 0x510e_527f, 0x9b05_688c, 0x1f83_d9ab, 0x5be0_cd19,
    ]
    /// 64 バイトに満たず，まだ処理していない末尾
    private var pending: [UInt8] = []
    private var totalBytes: UInt64 = 0

    public init() {
        pending.reserveCapacity(Self.blockSize)
    }

    /// 1 回で求める
    public static func hex(of bytes: some Sequence<UInt8>) -> String {
        var digest = SHA256Digest()
        digest.update(bytes)
        return digest.finalizeHex()
    }

    public mutating func update(_ bytes: some Sequence<UInt8>) {
        // 続いたメモリにあるもの(Data，Array)は写さずに読む．起動のたびに同梱の辞書と Zenzai のモデル(合わせて 280MB ほど)を確かめるので
        let done: Void? = bytes.withContiguousStorageIfAvailable { absorb(UnsafeRawBufferPointer($0)) }
        if done == nil {
            Array(bytes).withUnsafeBytes { absorb($0) }
        }
    }

    private mutating func absorb(_ bytes: UnsafeRawBufferPointer) {
        var offset = 0
        if !pending.isEmpty {
            let filling = min(Self.blockSize - pending.count, bytes.count)
            pending.append(contentsOf: bytes[0..<filling])
            offset = filling
            guard pending.count == Self.blockSize else { return }
            let block = pending
            block.withUnsafeBytes { compress($0) }
            pending.removeAll(keepingCapacity: true)
        }
        let whole = (bytes.count - offset) / Self.blockSize * Self.blockSize
        if whole > 0 {
            compress(UnsafeRawBufferPointer(rebasing: bytes[offset..<offset + whole]))
            offset += whole
        }
        pending.append(contentsOf: bytes[offset...])
    }

    /// 求めた値(32 バイト)．このあと update しない
    public mutating func finalize() -> [UInt8] {
        let bitLength = (totalBytes + UInt64(pending.count)) &* 8
        var tail = pending
        tail.append(0x80)
        while tail.count % Self.blockSize != Self.blockSize - 8 { tail.append(0) }
        for shift in stride(from: 56, through: 0, by: -8) { tail.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift))) }
        pending.removeAll()
        tail.withUnsafeBytes { compress($0) }
        return state.flatMap { word in [UInt8(word >> 24), UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word)] }
    }

    /// 求めた値を 16 進の小文字で
    public mutating func finalizeHex() -> String {
        Self.lowercaseHex(finalize())
    }

    /// ハッシュの値のバイト列を 16 進の小文字にする．CryptoKit で求めた値にも使う．
    /// 同梱の辞書はファイルが数千あり起動のたびに確かめるので，String(format:) を 1 バイトずつ呼ぶより速い表引きで作る
    public static func lowercaseHex(_ bytes: some Sequence<UInt8>) -> String {
        var text: [UInt8] = []
        text.reserveCapacity(64)
        for byte in bytes {
            text.append(hexDigits[Int(byte >> 4)])
            text.append(hexDigits[Int(byte & 0x0f)])
        }
        return String(decoding: text, as: UTF8.self)
    }

    private static let hexDigits = Array("0123456789abcdef".utf8)

    private static let blockSize = 64

    private static let constants: [UInt32] = [
        0x428a_2f98, 0x7137_4491, 0xb5c0_fbcf, 0xe9b5_dba5, 0x3956_c25b, 0x59f1_11f1, 0x923f_82a4, 0xab1c_5ed5,
        0xd807_aa98, 0x1283_5b01, 0x2431_85be, 0x550c_7dc3, 0x72be_5d74, 0x80de_b1fe, 0x9bdc_06a7, 0xc19b_f174,
        0xe49b_69c1, 0xefbe_4786, 0x0fc1_9dc6, 0x240c_a1cc, 0x2de9_2c6f, 0x4a74_84aa, 0x5cb0_a9dc, 0x76f9_88da,
        0x983e_5152, 0xa831_c66d, 0xb003_27c8, 0xbf59_7fc7, 0xc6e0_0bf3, 0xd5a7_9147, 0x06ca_6351, 0x1429_2967,
        0x27b7_0a85, 0x2e1b_2138, 0x4d2c_6dfc, 0x5338_0d13, 0x650a_7354, 0x766a_0abb, 0x81c2_c92e, 0x9272_2c85,
        0xa2bf_e8a1, 0xa81a_664b, 0xc24b_8b70, 0xc76c_51a3, 0xd192_e819, 0xd699_0624, 0xf40e_3585, 0x106a_a070,
        0x19a4_c116, 0x1e37_6c08, 0x2748_774c, 0x34b0_bcb5, 0x391c_0cb3, 0x4ed8_aa4a, 0x5b9c_ca4f, 0x682e_6ff3,
        0x748f_82ee, 0x78a5_636f, 0x84c8_7814, 0x8cc7_0208, 0x90be_fffa, 0xa450_6ceb, 0xbef9_a3f7, 0xc671_78f2,
    ]

    /// 64 バイトの倍数の長さの塊をまとめて処理する．語の並びは塊ごとに作り直さず，一時的な領域に置く
    private mutating func compress(_ blocks: UnsafeRawBufferPointer) {
        guard !blocks.isEmpty else { return }
        totalBytes &+= UInt64(blocks.count)
        var h0 = state[0], h1 = state[1], h2 = state[2], h3 = state[3], h4 = state[4], h5 = state[5], h6 = state[6], h7 = state[7]
        Self.constants.withUnsafeBufferPointer { constants in
            withUnsafeTemporaryAllocation(of: UInt32.self, capacity: 64) { words in
                var offset = 0
                while offset < blocks.count {
                    for word in 0..<16 {
                        words[word] = UInt32(bigEndian: blocks.loadUnaligned(fromByteOffset: offset + word * 4, as: UInt32.self))
                    }
                    for word in 16..<64 {
                        let s0 = Self.rotate(words[word - 15], 7) ^ Self.rotate(words[word - 15], 18) ^ (words[word - 15] >> 3)
                        let s1 = Self.rotate(words[word - 2], 17) ^ Self.rotate(words[word - 2], 19) ^ (words[word - 2] >> 10)
                        words[word] = words[word - 16] &+ s0 &+ words[word - 7] &+ s1
                    }
                    var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7
                    for round in 0..<64 {
                        let s1 = Self.rotate(e, 6) ^ Self.rotate(e, 11) ^ Self.rotate(e, 25)
                        let choice = (e & f) ^ (~e & g)
                        let temporary1 = h &+ s1 &+ choice &+ constants[round] &+ words[round]
                        let s0 = Self.rotate(a, 2) ^ Self.rotate(a, 13) ^ Self.rotate(a, 22)
                        let majority = (a & b) ^ (a & c) ^ (b & c)
                        let temporary2 = s0 &+ majority
                        h = g
                        g = f
                        f = e
                        e = d &+ temporary1
                        d = c
                        c = b
                        b = a
                        a = temporary1 &+ temporary2
                    }
                    h0 &+= a
                    h1 &+= b
                    h2 &+= c
                    h3 &+= d
                    h4 &+= e
                    h5 &+= f
                    h6 &+= g
                    h7 &+= h
                    offset += Self.blockSize
                }
            }
        }
        state = [h0, h1, h2, h3, h4, h5, h6, h7]
    }

    @inline(__always)
    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        value >> count | value << (32 - count)
    }
}
