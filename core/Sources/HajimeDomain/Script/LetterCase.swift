/// 英数(全角英数・半角英数)に変えた読みの，英字の大文字と小文字(R-03)．
/// 英数に変えるキーを続けて押すと，入力どおり → 大文字 → 小文字 → 先頭だけ大文字 の順に変える
public enum LetterCase: Sendable, Equatable, CaseIterable {
    /// 打ったとおり
    case asTyped
    case uppercase
    case lowercase
    /// 先頭の 1 文字だけ大文字にし，残りを小文字にする
    case capitalized

    public func apply(to text: String) -> String {
        switch self {
        case .asTyped: text
        case .uppercase: text.uppercased()
        case .lowercase: text.lowercased()
        case .capitalized: text.prefix(1).uppercased() + text.dropFirst().lowercased()
        }
    }

    /// 次に見せる大文字と小文字．text に当てて見た目が前の段と同じになる段(打ったとおりが小文字のときの 小文字)は飛ばす．
    /// 英字が無く，どの段でも見た目が変わらなければ asTyped のまま
    public func next(for text: String) -> LetterCase {
        var seen = Set<String>()
        let distinct = Self.allCases.filter { seen.insert($0.apply(to: text)).inserted }
        let shown = apply(to: text)
        guard let index = distinct.firstIndex(where: { $0.apply(to: text) == shown }) else { return .asTyped }
        return distinct[(index + 1) % distinct.count]
    }
}
