/// キーボードの上で手の置き場所が横にずれたまま打った並びを，ずれを戻した並びに直す(R-20．試験的な機能)．
///
/// 「konnnitiha」を右手だけ 1 つ右にずらして打つと「lpmmmotojs」のようになる．打った文字の物理的な位置を配列から引き，
/// ずれた手の受け持つキーだけを 1 つ戻す．どちらの手が・どちらにずれたかは分からないので，ありうる組をすべて作り，
/// どれがもっともらしいかは訂正と同じく言語モデルの点数で決める(ReadingCorrector)
public enum HandShift {
    /// ずれた手
    public enum Hands: Sendable, Equatable, CaseIterable {
        case left
        case right
        case both
    }

    /// ずれのひと組．offset は手がずれた向き(+1 は右，−1 は左)
    public struct Shift: Sendable, Equatable {
        public var hands: Hands
        public var offset: Int

        public init(hands: Hands, offset: Int) {
            self.hands = hands
            self.offset = offset
        }
    }

    /// ずれを戻した並び
    public struct Variant: Sendable, Equatable {
        public var keys: String
        public var shift: Shift
    }

    /// 試すずれの組．両手・左手だけ・右手だけを，それぞれ左右に 1 つ
    public static let shifts: [Shift] = Hands.allCases.flatMap { hands in [Shift(hands: hands, offset: 1), Shift(hands: hands, offset: -1)] }

    /// keys を，ずれの組ごとに戻した並び．配列に無い文字を含むもの，元と同じになるもの，同じ並びになる組は除く
    public static func variants(of keys: String, layout: KeyboardGeometry) -> [Variant] {
        var seen: Set<String> = [keys]
        return shifts.compactMap { shift in
            // 戻した先が記号のキー(「;」「,」)になる組は，ローマ字として読めないので除く
            guard let restored = restore(keys, shift: shift, layout: layout), restored.allSatisfy({ ($0.isASCII && $0.isLetter) || $0 == "-" }),
                seen.insert(restored).inserted else { return nil }
            return Variant(keys: restored, shift: shift)
        }
    }

    /// ずれを戻す．打った文字の位置から，ずれた向きと逆に 1 つ戻したキーが，ずれた手の受け持ちならそのキーにする．
    /// ずれた手の受け持ちでないキー(左手だけずれたときの右手のキー)はそのまま残す
    static func restore(_ keys: String, shift: Shift, layout: KeyboardGeometry) -> String? {
        var result = ""
        for character in keys {
            guard let position = layout.position(of: character) else {
                // 長音の「-」は数字の段にあり，ずれても打ち直す人が多いのでそのまま残す
                guard character == "-" else { return nil }
                result.append(character)
                continue
            }
            let intended = KeyboardGeometry.Position(row: position.row, column: position.column - shift.offset)
            if shift.hands.includes(KeyboardGeometry.hand(of: intended)), let key = layout.character(at: intended) {
                result.append(key)
            } else if shift.hands == .both {
                // 両手がずれたのに戻した先にキーが無ければ(段の端)，打ち間違いの並びとして扱わない
                return nil
            } else {
                result.append(character)
            }
        }
        return result
    }
}

extension HandShift.Hands {
    func includes(_ hand: KeyboardGeometry.Hand) -> Bool {
        switch self {
        case .left: hand == .left
        case .right: hand == .right
        case .both: true
        }
    }
}

/// 英字の配列ごとの，文字の物理的な位置(段と列)．手のずれを戻すのに使う
public struct KeyboardGeometry: Sendable, Equatable {
    public struct Position: Sendable, Hashable {
        /// 0 が上の段(Q の段)
        public var row: Int
        /// 段の左端からの位置
        public var column: Int

        public init(row: Int, column: Int) {
            self.row = row
            self.column = column
        }
    }

    public enum Hand: Sendable, Equatable {
        case left
        case right
    }

    /// 上の段・中の段・下の段の文字(左から)．小文字だけ
    private let rows: [[Character]]

    public init(rows: [String]) {
        self.rows = rows.map(Array.init)
    }

    public static let qwerty = KeyboardGeometry(rows: ["qwertyuiop", "asdfghjkl;", "zxcvbnm,./"])
    public static let dvorak = KeyboardGeometry(rows: ["',.pyfgcrl", "aoeuidhtns", ";qjkxbmwvz"])
    public static let colemak = KeyboardGeometry(rows: ["qwfpgjluy;", "arstdhneio", "zxcvbkm,./"])

    /// 設定の配列の文字の位置．OS に任せる配列(system)と，JIS・US の配列は QWERTY として扱う
    public static func of(_ layout: KeyboardLayout) -> KeyboardGeometry {
        switch layout {
        case .system, .abc, .us: .qwerty
        case .dvorak, .dvorakQwertyCommand: .dvorak
        case .colemak: .colemak
        }
    }

    /// 左手が受け持つ列(どの段も左から 5 つ)．6 つ目からは右手
    static let leftHandColumns = 0..<5

    static func hand(of position: Position) -> Hand {
        leftHandColumns.contains(position.column) ? .left : .right
    }

    public func position(of character: Character) -> Position? {
        let lowered = Character(character.lowercased())
        for (row, keys) in rows.enumerated() {
            if let column = keys.firstIndex(of: lowered) { return Position(row: row, column: column) }
        }
        return nil
    }

    public func character(at position: Position) -> Character? {
        guard rows.indices.contains(position.row), rows[position.row].indices.contains(position.column) else { return nil }
        return rows[position.row][position.column]
    }
}
