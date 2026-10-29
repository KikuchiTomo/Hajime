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
    /// 1 つの塊を処理するときの語の並び．塊ごとに作り直さない
    private var schedule = [UInt32](repeating: 0, count: 64)

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
        let bytes = Array(bytes)
        var offset = 0
        if !pending.isEmpty {
            let filling = min(Self.blockSize - pending.count, bytes.count)
            pending.append(contentsOf: bytes[0..<filling])
            offset = filling
            guard pending.count == Self.blockSize else { return }
            compress(pending)
            pending.removeAll(keepingCapacity: true)
        }
        // まとまった 64 バイトは写さずに処理する(70MB ほどのモデルを読むので)
        while bytes.count - offset >= Self.blockSize {
            compress(bytes[offset..<offset + Self.blockSize])
            offset += Self.blockSize
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
        var offset = 0
        while offset < tail.count {
            compress(tail[offset..<offset + Self.blockSize])
            offset += Self.blockSize
        }
        return state.flatMap { word in [UInt8(word >> 24), UInt8(truncatingIfNeeded: word >> 16), UInt8(truncatingIfNeeded: word >> 8), UInt8(truncatingIfNeeded: word)] }
    }

    /// 求めた値を 16 進の小文字で
    public mutating func finalizeHex() -> String {
        let digits = Array("0123456789abcdef")
        return String(finalize().flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0f)]] })
    }

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

    private mutating func compress(_ block: some Collection<UInt8>) {
        totalBytes &+= UInt64(Self.blockSize)
        // 持ち主を 1 つにして，書き換えのたびに写さないようにする
        var words = schedule
        schedule = []
        defer { schedule = words }
        var index = block.startIndex
        for word in 0..<16 {
            var value: UInt32 = 0
            for _ in 0..<4 {
                value = value << 8 | UInt32(block[index])
                index = block.index(after: index)
            }
            words[word] = value
        }
        for word in 16..<64 {
            let s0 = rotate(words[word - 15], 7) ^ rotate(words[word - 15], 18) ^ (words[word - 15] >> 3)
            let s1 = rotate(words[word - 2], 17) ^ rotate(words[word - 2], 19) ^ (words[word - 2] >> 10)
            words[word] = words[word - 16] &+ s0 &+ words[word - 7] &+ s1
        }
        var a = state[0], b = state[1], c = state[2], d = state[3], e = state[4], f = state[5], g = state[6], h = state[7]
        for round in 0..<64 {
            let s1 = rotate(e, 6) ^ rotate(e, 11) ^ rotate(e, 25)
            let choice = (e & f) ^ (~e & g)
            let temporary1 = h &+ s1 &+ choice &+ Self.constants[round] &+ words[round]
            let s0 = rotate(a, 2) ^ rotate(a, 13) ^ rotate(a, 22)
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
        state[0] &+= a
        state[1] &+= b
        state[2] &+= c
        state[3] &+= d
        state[4] &+= e
        state[5] &+= f
        state[6] &+= g
        state[7] &+= h
    }

    private func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        value >> count | value << (32 - count)
    }
}
