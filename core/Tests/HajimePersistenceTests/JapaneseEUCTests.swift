import Foundation
@testable import HajimeDomain
@testable import HajimePersistence
import Testing

@Suite("EUC-JP の辞書を読む(R-16)")
struct JapaneseEUCTests {
    /// 「でんあつ<タブ>電圧<タブ>名詞」「やまだ<タブ>山田<タブ>人名」を EUC-JP にしたもの(macOS の japaneseEUC で作った)
    private let dictionary: [UInt8] = [
        0xA4, 0xC7, 0xA4, 0xF3, 0xA4, 0xA2, 0xA4, 0xC4, 0x09, 0xC5, 0xC5, 0xB0, 0xB5, 0x09, 0xCC, 0xBE, 0xBB, 0xEC, 0x0A,
        0xA4, 0xE4, 0xA4, 0xDE, 0xA4, 0xC0, 0x09, 0xBB, 0xB3, 0xC5, 0xC4, 0x09, 0xBF, 0xCD, 0xCC, 0xBE, 0x0A,
    ]

    /// Shift_JIS を Foundation で読める OS か(Linux の Foundation は読めない．ADR 0012 の Linux の残り)
    static let readsShiftJIS = String(bytes: [0x82, 0xA0], encoding: .shiftJIS) != nil

    @Test("EUC-JP の辞書を macOS と Windows で読む", .enabled(if: readsShiftJIS))
    func readsDictionary() throws {
        #expect(JapaneseEUC.decode(Data(dictionary)) == "でんあつ\t電圧\t名詞\nやまだ\t山田\t人名\n")
        #expect(try DictionaryFileReader.parse(Data(dictionary)) == [
            DictionaryWord(reading: "でんあつ", word: "電圧", wordClass: .noun),
            DictionaryWord(reading: "やまだ", word: "山田", wordClass: .personName),
        ])
    }

    @Test("半角カナを読む")
    func halfwidthKana() {
        #expect(JapaneseEUC.decode(Data([0x8E, 0xC3, 0x8E, 0xDE, 0x8E, 0xDD, 0x8E, 0xB1, 0x8E, 0xC2])) == "ﾃﾞﾝｱﾂ")
    }

    @Test("Shift_JIS と割り当ての違う記号は，macOS で読んだときと同じ文字にする")
    func symbolsMatchMacOS() {
        let symbols: [UInt8] = [0xA1, 0xC1, 0xA1, 0xC2, 0xA1, 0xDD, 0xA1, 0xBD, 0xA1, 0xF1, 0xA1, 0xF2, 0xA2, 0xCC]
        #expect(JapaneseEUC.decode(Data(symbols)) == "\u{301C}\u{2016}\u{2212}\u{2014}\u{00A2}\u{00A3}\u{00AC}")
    }

    @Test("EUC-JP の並びとして正しくないものと補助漢字は読まない", arguments: [
        [0xA4] as [UInt8], [0xA4, 0x41], [0x8E, 0xA0], [0x8E], [0x8F, 0xB0, 0xA1], [0x80], [0xFF, 0xA1],
    ])
    func rejectsMalformed(bytes: [UInt8]) {
        #expect(JapaneseEUC.decode(Data(bytes)) == nil)
    }

    #if canImport(Darwin)
    /// 13 区(NEC の特殊文字)は，macOS の japaneseEUC が独自の文字(㈰ など)に割り当てるので比べない．
    /// こちらは Windows の EUC-JP(CP51932)と同じに ① などとして読む
    @Test("JIS X 0208 のすべての文字を，macOS の japaneseEUC と同じ文字として読む")
    func matchesFoundationOnMacOS() {
        var compared = 0
        for first in UInt8(0xA1)...0xFE where first != 0xAD {
            for second in UInt8(0xA1)...0xFE {
                let bytes = Data([first, second])
                guard let expected = String(data: bytes, encoding: .japaneseEUC) else { continue }
                #expect(JapaneseEUC.decode(bytes) == expected, "\(String(first, radix: 16))\(String(second, radix: 16))")
                compared += 1
            }
        }
        #expect(compared > 6_800)
        for kana in UInt8(0xA1)...0xDF {
            #expect(JapaneseEUC.decode(Data([0x8E, kana])) == String(data: Data([0x8E, kana]), encoding: .japaneseEUC))
        }
    }
    #endif
}
