import Foundation
import S90Domain
@testable import S90Persistence
import Testing

/// 外から来るファイルのパーサに，でたらめなバイト列を与えても落ちないことを確かめる(docs/dev/SECURITY-MODEL.md)．
/// 毎回同じ並びになるよう，種を決めた乱数を使う
@Suite("パーサのファズテスト")
struct FuzzTests {
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return state
        }
    }

    private func samples(count: Int) -> [Data] {
        var generator = SeededGenerator(state: 0x5390)
        return (0..<count).map { _ in
            Data((0..<Int.random(in: 0...512, using: &generator)).map { _ in UInt8.random(in: 0...255, using: &generator) })
        }
    }

    @Test("ユーザー辞書のファイル")
    func userDictionary() {
        for data in samples(count: 500) {
            if let text = UserDictionaryFile.decode(data) {
                let entries = UserDictionaryFile.parse(text)
                #expect(entries.allSatisfy { $0.isValid })
            }
        }
    }

    @Test("設定のファイル")
    func settings() {
        for data in samples(count: 500) {
            _ = try? JSONDecoder().decode(Settings.self, from: data)
        }
    }

    @Test("BOM の無い UTF-16 らしいバイト列は読まない")
    func utf16WithoutBOM() {
        let data = "かいしゃ\t会社".data(using: .utf16LittleEndian)!
        #expect(UserDictionaryFile.decode(data) == nil)
        #expect(UserDictionaryFile.decode(Data([0xFF, 0xFE]) + data) == "かいしゃ\t会社")
    }
}
