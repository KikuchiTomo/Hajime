/// 郵便番号の読み．「100-0001」「1000001」「１００ー０００１」を 7 桁の数字(「1000001」)にする(R-13)
public enum PostalCode {
    public struct Query: Sendable, Equatable {
        /// 7 桁の数字
        public var code: String
        /// 3 桁と 4 桁の間に区切りがあったか．あれば郵便番号を打ったのが明らかなので，住所を先頭に出す
        public var hasSeparator: Bool
    }

    /// 郵便番号として読めなければ nil．区切りは「-」「ー」「－」「‐」「−」のどれか 1 つだけを 3 桁目のあとに許す
    public static func query(for reading: String) -> Query? {
        var digits = ""
        var separatorIndex: Int?
        for character in reading {
            if let digit = digit(character) {
                digits.append(digit)
            } else if separators.contains(character), separatorIndex == nil, digits.count == 3 {
                separatorIndex = digits.count
            } else {
                return nil
            }
        }
        guard digits.count == 7 else { return nil }
        return Query(code: digits, hasSeparator: separatorIndex != nil)
    }

    private static let separators: Set<Character> = ["-", "ー", "－", "‐", "−"]

    private static func digit(_ character: Character) -> Character? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        switch scalar.value {
        case 0x30...0x39: return character
        case 0xFF10...0xFF19: return Character(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!)
        default: return nil
        }
    }
}
