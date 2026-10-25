/// 組み立て中の読み．ローマ字をかなに直しながら，打ったキーの並びも覚えておく．
///
/// - `kana`: かなに直し終わった部分(記号や数字も含む)
/// - `pending`: まだかなにならないローマ字(「ky」など)
/// - `rawKeys`: 打ったキーをそのまま並べたもの．タイプミスの補正と英数の候補に使う．
///   途中を消すなどして，打ったキーと読みが対応しなくなったら nil にする
public struct Composition: Sendable, Equatable {
    public private(set) var kana: String = ""
    public private(set) var pending: String = ""
    public private(set) var rawKeys: String? = ""
    /// ローマ字として読めない並びがあり，英字のまま残したか(「py」+「t」など)．R-02 の判定に使う
    public private(set) var containsInvalidRomaji = false
    /// 直前の「nn」を「ん」にした．次が母音・y なら，2 つ目の n をその文字と組ませる
    private var nasalMayCarryN = false

    private let table: RomajiTable

    public init(table: RomajiTable = .standard) {
        self.table = table
    }

    public var isEmpty: Bool { kana.isEmpty && pending.isEmpty }

    /// 画面に出す読み．まだかなにならないローマ字もそのまま見せる
    public var displayReading: String { kana + pending }

    /// 変換エンジンに渡す読み．末尾の「n」は「ん」として扱う
    public var conversionReading: String { kana + Self.finalize(pending) }

    // MARK: - 入力

    /// ローマ字として組み立てる文字(英字の小文字・「-」・「'」)を足す
    public mutating func insertRomaji(_ character: Character) {
        rawKeys?.append(character)
        let lowered = Character(character.lowercased())
        if nasalMayCarryN, pending.isEmpty {
            nasalMayCarryN = false
            // 「onna」は「おんな」，「konnnitiha」は「こんにちは」．どちらも 2 つ目の n を次の文字と組ませる
            if lowered == "n" {
                // 3 つ目の n は，2 つ目の n と組んで次の音の頭になる
                pending = "n"
                return
            }
            if Self.vowelsAndY.contains(lowered) {
                pending = "n"
            }
        } else {
            nasalMayCarryN = false
        }
        if pending == "n" && lowered == "n" {
            kana.append("ん")
            pending = ""
            nasalMayCarryN = true
            return
        }
        pending.append(lowered)
        resolvePending()
    }

    /// ローマ字にせずそのまま足す文字(大文字の英字・数字・記号)．組み立て中のローマ字は先に確定させる
    public mutating func insertLiteral(_ text: String, rawKey: Character? = nil) {
        flushPending()
        nasalMayCarryN = false
        kana.append(text)
        if let rawKey {
            rawKeys?.append(rawKey)
        } else {
            rawKeys = nil
        }
    }

    public mutating func deleteBackward() {
        rawKeys = nil
        nasalMayCarryN = false
        if !pending.isEmpty {
            pending.removeLast()
        } else if !kana.isEmpty {
            kana.removeLast()
        }
        if isEmpty {
            containsInvalidRomaji = false
            rawKeys = ""
        }
    }

    /// 変換で先頭の readingCount 文字ぶんを確定したとき，残りの読みだけにする
    public mutating func dropReadingPrefix(_ readingCount: Int) {
        let finalizedPending = Self.finalize(pending)
        let whole = kana + finalizedPending
        guard readingCount < whole.count else {
            self = Composition(table: table)
            return
        }
        if readingCount <= kana.count {
            kana = String(kana.dropFirst(readingCount))
        } else {
            // 末尾の「ん」まで確定した場合は，ローマ字の残りも消える
            kana = ""
            pending = ""
        }
        rawKeys = nil
        containsInvalidRomaji = false
        nasalMayCarryN = false
    }

    // MARK: - ローマ字の解決

    private mutating func resolvePending() {
        while !pending.isEmpty {
            if let kanaText = table.entries[pending], !table.isPrefix(pending) {
                kana.append(kanaText)
                pending = ""
                return
            }
            if table.isPrefix(pending) || pending == "n" {
                return
            }
            let characters = Array(pending)
            let first = characters[0]
            // 子音の重ね打ちは促音．「matcha」の「tc」も促音として扱う
            if characters.count >= 2,
                (first == characters[1] && Self.consonants.contains(first)) || (first == "t" && characters[1] == "c") {
                kana.append("っ")
                pending.removeFirst()
                continue
            }
            if first == "n", characters.count >= 2, !Self.vowelsAndY.contains(characters[1]) {
                kana.append("ん")
                pending.removeFirst()
                continue
            }
            // どの綴りにもならないので，先頭の文字を英字のまま残す
            kana.append(first)
            containsInvalidRomaji = true
            pending.removeFirst()
        }
    }

    private mutating func flushPending() {
        kana.append(Self.finalize(pending))
        if !pending.isEmpty, Self.finalize(pending) == pending {
            containsInvalidRomaji = true
        }
        pending = ""
    }

    private static func finalize(_ pending: String) -> String {
        switch pending {
        case "n": "ん"
        default: pending
        }
    }

    private static let vowelsAndY: Set<Character> = ["a", "i", "u", "e", "o", "y"]
    private static let consonants: Set<Character> = Set("bcdfghjklmpqrstvwxyz")

    public static func == (lhs: Composition, rhs: Composition) -> Bool {
        lhs.kana == rhs.kana && lhs.pending == rhs.pending && lhs.rawKeys == rhs.rawKeys
            && lhs.containsInvalidRomaji == rhs.containsInvalidRomaji
    }
}

extension Composition: CustomStringConvertible, CustomDebugStringConvertible {
    // 読みは入力内容そのものなので，ログには長さだけを出す
    public var description: String { "Composition(length: \(displayReading.count))" }
    public var debugDescription: String { description }
}
