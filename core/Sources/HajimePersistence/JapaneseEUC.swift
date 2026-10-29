import Foundation

/// EUC-JP のバイト列を文字列にする．Windows の Foundation は EUC-JP を読めない(String.Encoding.japaneseEUC が使えない)ので，
/// Shift_JIS のバイト列に計算で並べ替えてから Shift_JIS として読む．
///
/// - 2 バイトの文字(JIS X 0208 の区点)は，区点が同じ Shift_JIS の 2 バイトに置き換える．表を持たずに計算で済む
/// - 半角カナ(0x8E に続く 1 バイト)は Shift_JIS の 1 バイトにする
/// - JIS X 0212 の補助漢字(0x8F に続く 2 バイト)は Shift_JIS に無いので読まない(macOS の japaneseEUC も読まない)
///
/// Shift_JIS(Windows の CP932)と EUC-JP(macOS)とで割り当てが違う記号(〜 ‖ − — ¢ £ ¬)は，
/// Shift_JIS に写さずに，macOS で読んだときと同じ文字を直接置く
enum JapaneseEUC {
    static func decode(_ data: Data) -> String? {
        var text = ""
        var pending: [UInt8] = []
        pending.reserveCapacity(min(data.count, 1 << 20))
        // ためた Shift_JIS のバイト列を読んで text に足す
        func flush() -> Bool {
            guard !pending.isEmpty else { return true }
            guard let piece = String(bytes: pending, encoding: .shiftJIS) else { return false }
            text += piece
            pending.removeAll(keepingCapacity: true)
            return true
        }
        let isValid = data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> Bool in
            var index = 0
            while index < buffer.count {
                let byte = buffer[index]
                switch byte {
                case 0x00...0x7F:
                    pending.append(byte)
                    index += 1
                case 0x8E:
                    guard index + 1 < buffer.count, (0xA1...0xDF).contains(buffer[index + 1]) else { return false }
                    pending.append(buffer[index + 1])
                    index += 2
                case 0xA1...0xFE:
                    guard index + 1 < buffer.count, (0xA1...0xFE).contains(buffer[index + 1]) else { return false }
                    let second = buffer[index + 1]
                    if let symbol = macOSSymbols[UInt16(byte) << 8 | UInt16(second)] {
                        guard flush() else { return false }
                        text.unicodeScalars.append(symbol)
                    } else {
                        let (first, trail) = shiftJIS(row: Int(byte) - 0x80, cell: Int(second) - 0x80)
                        pending.append(first)
                        pending.append(trail)
                    }
                    index += 2
                default:
                    return false
                }
            }
            return true
        }
        guard isValid, flush() else { return nil }
        return text
    }

    /// JIS の 2 バイト(それぞれ 0x21〜0x7E)を Shift_JIS の 2 バイトにする
    private static func shiftJIS(row: Int, cell: Int) -> (UInt8, UInt8) {
        let first = (row + 1) / 2 + (row <= 0x5E ? 0x70 : 0xB0)
        let second = row % 2 == 1 ? cell + (cell >= 0x60 ? 0x20 : 0x1F) : cell + 0x7E
        return (UInt8(first), UInt8(second))
    }

    /// CP932 では別の文字に割り当てる EUC-JP の記号と，macOS の japaneseEUC で読んだときの文字
    private static let macOSSymbols: [UInt16: Unicode.Scalar] = [
        0xA1BD: "\u{2014}",
        0xA1C1: "\u{301C}",
        0xA1C2: "\u{2016}",
        0xA1DD: "\u{2212}",
        0xA1F1: "\u{00A2}",
        0xA1F2: "\u{00A3}",
        0xA2CC: "\u{00AC}",
    ]
}
