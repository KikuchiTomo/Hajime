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
    /// 読みの区切り．ローマ字が残っていない時点ごとに，打ったキーの数とかなの文字数を記録する．
    /// 文の途中に打った英単語(「このばーじょんの」+「python」)を見つけるために使う(R-02)
    public private(set) var boundaries: [Boundary] = [Boundary(rawCount: 0, kanaCount: 0)]
    /// 確定させた英単語の終わり(かなの文字数)．ここより前は英単語を探さない．
    /// 確定させた英単語そのものを「読めない並び」と数えて，後ろの日本語まで補正しないため
    private var frozenKanaEnd = 0
    /// 「nn」のあとの母音の位置．語によって「ん+あ行」(hannei → はんえい)か「ん+な行」(onna → おんな)かが
    /// 変わるので，どちらの読みにも切り替えられるようにしておく．どちらにするかは変換の点数で決める(NasalReadingResolver)
    public private(set) var nasalAmbiguities: [NasalAmbiguity] = []
    /// 直前に「nn」を「ん」にした位置．次にかなになった文字が母音なら，そこを nasalAmbiguities に加える
    private var nasalWatchIndex: Int?

    /// 「nn」のあとの母音 1 つぶん．kanaIndex は読みの中の位置
    public struct NasalAmbiguity: Sendable, Equatable {
        public var kanaIndex: Int
        /// 「ん+あ行」の形(「え」)と「ん+な行」の形(「ね」)
        public var vowelForm: String
        public var naRowForm: String
        public var usesNaRow: Bool
        /// 前に読みを比べたとき，母音のあとに何文字あったか．比べ直すかどうかを決めるのに使う
        public var evaluatedFollowingCount: Int?

        public var currentForm: String { usesNaRow ? naRowForm : vowelForm }
        /// 読みの中で，この母音のあとに続く文字数
        public func followingCount(in reading: String) -> Int {
            reading.count - kanaIndex - currentForm.count
        }
    }

    /// あ行・や行の文字と，前に「n」を足したときの文字
    private static let naRowForms: [(vowel: String, naRow: String)] = [
        ("あ", "な"), ("い", "に"), ("う", "ぬ"), ("え", "ね"), ("お", "の"),
        ("や", "にゃ"), ("ゆ", "にゅ"), ("よ", "にょ"),
    ]

    public struct Boundary: Sendable, Equatable {
        public var rawCount: Int
        public var kanaCount: Int
    }

    /// 区切りから末尾までの部分．keys はその部分で打ったキー，rawStart と kanaStart はその部分の始まりの位置
    public struct Tail: Sendable, Equatable {
        public var keys: String
        public var rawStart: Int
        public var kanaStart: Int
        /// その部分にローマ字として読めない並びがあるか
        public var containsInvalidRomaji: Bool
        /// その部分がローマ字として読めない文字(「python」の「p」)で始まるか
        public var startsWithUnconvertible: Bool
        /// その部分が，英単語を探してよい範囲の先頭(読みの先頭か，確定させた英単語の直後)から始まるか
        public var startsFreeRegion: Bool
    }

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
        // 「nn」は必ず「ん」にする．次の文字と組ませない．
        // 「hunniki」は「ふんいき」，「konnnitiha」は「こんにちは」になり，「おんな」は「onnna」と打つ．
        // 多くの日本語入力と同じ決まりで，打つ人の指の癖に合わせるため
        if pending == "n" && lowered == "n" {
            kana.append("ん")
            pending = ""
            nasalWatchIndex = kana.count
            recordBoundary()
            return
        }
        let watch = nasalWatchIndex
        nasalWatchIndex = nil
        pending.append(lowered)
        resolvePending()
        if let watch { noteNasalAmbiguity(at: watch) }
        mergeSymbolSequence()
        if pending.isEmpty { recordBoundary() }
    }

    /// 続けて打った記号を 1 つにまとめる(「ー＞」→「→」)．規則は SymbolSequence
    private mutating func mergeSymbolSequence() {
        guard pending.isEmpty, let match = SymbolSequence.match(suffixOf: kana) else { return }
        kana.removeLast(match.length)
        kana.append(match.symbol)
        // まとめた記号の途中を指す記録は使えないので外す
        boundaries = boundaries.filter { $0.kanaCount <= kana.count }
        nasalAmbiguities = nasalAmbiguities.filter { $0.kanaIndex + $0.currentForm.count <= kana.count }
        frozenKanaEnd = min(frozenKanaEnd, kana.count)
    }

    /// 「nn」の直後にかなになった文字が母音(や行を含む)なら，両方の読みを持てるように記録する
    private mutating func noteNasalAmbiguity(at index: Int) {
        let characters = Array(kana)
        guard characters.count > index else {
            // 「nny」の「y」のように，まだかなになっていない．次のキーまで見張る
            if !pending.isEmpty { nasalWatchIndex = index }
            return
        }
        let following = String(characters[index...])
        guard let form = Self.naRowForms.first(where: { following.hasPrefix($0.vowel) }) else { return }
        nasalAmbiguities.append(NasalAmbiguity(kanaIndex: index, vowelForm: form.vowel, naRowForm: form.naRow, usesNaRow: false, evaluatedFollowingCount: nil))
    }

    /// 読みを比べたことを記録する
    public mutating func markNasalEvaluated(at position: Int, followingCount: Int) {
        guard nasalAmbiguities.indices.contains(position) else { return }
        nasalAmbiguities[position].evaluatedFollowingCount = followingCount
    }

    /// 「nn」のあとの母音を「ん+あ行」と「ん+な行」のどちらで読むかを切り替える
    public mutating func setNasalReading(at position: Int, usesNaRow: Bool) {
        guard nasalAmbiguities.indices.contains(position), nasalAmbiguities[position].usesNaRow != usesNaRow else { return }
        let ambiguity = nasalAmbiguities[position]
        let old = ambiguity.currentForm
        nasalAmbiguities[position].usesNaRow = usesNaRow
        let new = nasalAmbiguities[position].currentForm
        var characters = Array(kana)
        characters.replaceSubrange(ambiguity.kanaIndex..<(ambiguity.kanaIndex + old.count), with: Array(new))
        kana = String(characters)
        // 文字数が変わる(「や」→「にゃ」)ときは，後ろの位置をずらす
        let delta = new.count - old.count
        guard delta != 0 else { return }
        for i in nasalAmbiguities.indices where nasalAmbiguities[i].kanaIndex > ambiguity.kanaIndex {
            nasalAmbiguities[i].kanaIndex += delta
        }
        for i in boundaries.indices where boundaries[i].kanaCount > ambiguity.kanaIndex {
            boundaries[i].kanaCount += delta
        }
        if frozenKanaEnd > ambiguity.kanaIndex { frozenKanaEnd += delta }
    }

    /// 区切りから末尾までの部分を，長いもの(前の区切り)から順に返す．打ったキーと読みの対応が外れていたら空
    public func tails() -> [Tail] {
        guard let rawKeys else { return [] }
        let keys = Array(rawKeys)
        // まだかなになっていないローマ字(pending の「b」など)は読めない並びに数えない．
        // 数えると「konob」のような打ちかけの日本語まで英単語として補正してしまう
        let resolved = Array(kana)
        return boundaries.compactMap { boundary in
            guard boundary.rawCount < keys.count, boundary.kanaCount >= frozenKanaEnd,
                boundary.kanaCount <= resolved.count else { return nil }
            let tailKana = resolved[boundary.kanaCount...]
            return Tail(
                keys: String(keys[boundary.rawCount...]),
                rawStart: boundary.rawCount,
                kanaStart: boundary.kanaCount,
                containsInvalidRomaji: tailKana.contains { $0.isASCII && $0.isLetter },
                startsWithUnconvertible: tailKana.first.map { $0.isASCII && $0.isLetter } ?? false,
                startsFreeRegion: boundary.kanaCount == frozenKanaEnd
            )
        }
    }

    /// 補正した英単語を読みの中に確定させる．英単語のあとに打ったキー(after)は，日本語として打ち直す．
    /// 「python」+「ha」なら，読みは「(前の読み) + python + は」になる
    /// - Parameters:
    ///   - rawStart: 英単語を打ち始めたキーの位置
    ///   - kanaStart: 英単語が読みの中で始まる位置
    ///   - keys: 英単語として打ったキー
    ///   - word: 確定させる英単語
    ///   - after: 英単語のあとに打ったキー(ローマ字だけ)
    public mutating func freeze(rawStart: Int, kanaStart: Int, keys: String, as word: String, replaying after: String) {
        let prefixKeys = String((rawKeys ?? "").prefix(rawStart))
        boundaries = boundaries.filter { $0.rawCount <= rawStart && $0.kanaCount <= kanaStart }
        kana = String(kana.prefix(kanaStart)) + word
        pending = ""
        rawKeys = prefixKeys + keys
        nasalAmbiguities = nasalAmbiguities.filter { $0.kanaIndex < kanaStart }
        nasalWatchIndex = nil
        frozenKanaEnd = kana.count
        recordBoundary()
        for key in after {
            insertRomaji(key)
        }
    }

    private mutating func recordBoundary() {
        guard let rawKeys else { return }
        let boundary = Boundary(rawCount: rawKeys.count, kanaCount: kana.count)
        if boundaries.last != boundary { boundaries.append(boundary) }
    }

    /// ローマ字にせずそのまま足す文字(大文字の英字・数字・記号)．組み立て中のローマ字は先に確定させる
    public mutating func insertLiteral(_ text: String, rawKey: Character? = nil) {
        flushPending()
        nasalWatchIndex = nil
        kana.append(text)
        mergeSymbolSequence()
        if let rawKey {
            rawKeys?.append(rawKey)
            recordBoundary()
        } else {
            rawKeys = nil
        }
    }

    /// かな入力のかなを足す(R-05)．濁点・半濁点は前のかなと合わせる．打ったキーはローマ字ではないので覚えない
    public mutating func insertKana(_ text: String) {
        flushPending()
        nasalWatchIndex = nil
        rawKeys = nil
        if text.count == 1, let mark = text.first, let last = kana.last, let combined = KanaLayout.combine(last, with: mark) {
            kana.removeLast()
            kana.append(combined)
            return
        }
        kana.append(text)
    }

    public mutating func deleteBackward() {
        rawKeys = nil
        nasalWatchIndex = nil
        if !pending.isEmpty {
            pending.removeLast()
        } else if !kana.isEmpty {
            kana.removeLast()
        }
        // 消した文字にかかっていた「nn」の読みの記録は外す．残った分は，あとの文字が変わったので比べ直す
        nasalAmbiguities = nasalAmbiguities.filter { $0.kanaIndex + $0.currentForm.count <= kana.count }
        for i in nasalAmbiguities.indices { nasalAmbiguities[i].evaluatedFollowingCount = nil }
        if isEmpty {
            containsInvalidRomaji = false
            rawKeys = ""
            boundaries = [Boundary(rawCount: 0, kanaCount: 0)]
            frozenKanaEnd = 0
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
            nasalAmbiguities = nasalAmbiguities.compactMap { ambiguity in
                guard ambiguity.kanaIndex >= readingCount else { return nil }
                var shifted = ambiguity
                shifted.kanaIndex -= readingCount
                return shifted
            }
        } else {
            // 末尾の「ん」まで確定した場合は，ローマ字の残りも消える
            kana = ""
            pending = ""
            nasalAmbiguities = []
        }
        rawKeys = nil
        containsInvalidRomaji = false
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
            && lhs.containsInvalidRomaji == rhs.containsInvalidRomaji && lhs.boundaries == rhs.boundaries
            && lhs.nasalAmbiguities == rhs.nasalAmbiguities
    }
}

extension Composition: CustomStringConvertible, CustomDebugStringConvertible {
    // 読みは入力内容そのものなので，ログには長さだけを出す
    public var description: String { "Composition(length: \(displayReading.count))" }
    public var debugDescription: String { description }
}

extension Composition.Tail: CustomStringConvertible, CustomDebugStringConvertible {
    // 打ったキーは入力内容なので，ログには長さと位置だけを出す
    public var description: String { "Tail(keysLength: \(keys.count), rawStart: \(rawStart), kanaStart: \(kanaStart))" }
    public var debugDescription: String { description }
}

extension Composition.NasalAmbiguity: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "NasalAmbiguity(kanaIndex: \(kanaIndex), usesNaRow: \(usesNaRow))" }
    public var debugDescription: String { description }
}
