#if canImport(CryptoKit)
import CryptoKit
import Foundation
#endif
import S90Domain
import Testing

@Suite("SHA-256(CryptoKit の無い OS で使う)")
struct SHA256DigestTests {
    @Test("FIPS 180-4 の見本の値になる")
    func knownVectors() {
        #expect(SHA256Digest.hex(of: Array("".utf8)) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(SHA256Digest.hex(of: Array("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(SHA256Digest.hex(of: Array("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8))
            == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        #expect(SHA256Digest.hex(of: [UInt8](repeating: 0x61, count: 1_000_000))
            == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test("少しずつ渡しても，一度に渡したときと同じ値になる")
    func incremental() {
        let bytes = (0..<1000).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ 7) }
        for size in [1, 3, 63, 64, 65, 200] {
            var digest = SHA256Digest()
            var offset = 0
            while offset < bytes.count {
                digest.update(bytes[offset..<min(offset + size, bytes.count)])
                offset += size
            }
            #expect(digest.finalizeHex() == SHA256Digest.hex(of: bytes), "区切り \(size)")
        }
    }

    #if canImport(CryptoKit)
    @Test("塊の境目の前後の長さで CryptoKit と同じ値になる")
    func matchesCryptoKit() {
        for length in [0, 1, 55, 56, 57, 63, 64, 65, 119, 120, 128, 1000, 4096 + 13] {
            let bytes = (0..<length).map { UInt8(truncatingIfNeeded: $0 &* 131 &+ length) }
            let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            #expect(SHA256Digest.hex(of: bytes) == expected, "長さ \(length)")
        }
    }

    @Test("乱数のデータでも CryptoKit と同じ値になる")
    func matchesCryptoKitOnRandomData() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<20 {
            let length = Int.random(in: 0...5000, using: &generator)
            let bytes = (0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
            let expected = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            #expect(SHA256Digest.hex(of: bytes) == expected, "長さ \(length)")
        }
    }
    #endif
}
