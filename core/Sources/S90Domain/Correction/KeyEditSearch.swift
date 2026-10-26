/// 打ったキーに 1 か所の打ち間違い(取り違え・打ち忘れ・余分な 1 打・隣どうしの入れ替え)があったとみなし，
/// ありうる打ち方を全部作って，読みが変換としてもっともらしくなるものを探す(R-02)．
///
/// 誤りの種類を決め打ちしない．キーの位置で説明できる誤り(「arigatpu」)も，かなの書き誤り(「mizurai」→「midurai」見づらい，
/// 「konnnitiwa」→「konnnitiha」，「ekieikimasu」→「ekiheikimasu」)も同じ仕組みで拾う．
/// どれが正しいかは，読み全体を変換したときのもっともらしさ(plausibility)から，打ち間違いの手間(cost)を引いた値で決める．
/// 書き誤りの読み(「みずらい」)は変換すると語に切れず，もっともらしさが大きく下がるので，読みの綴りを並べなくても見分けられる
public enum KeyEditSearch {
    public struct Edit: Sendable, Equatable {
        public var keys: String
        /// ひらがなの読み
        public var reading: String
        /// 打ち間違いとみなす手間(大きいほど起きにくい)
        public var cost: Double

        public init(keys: String, reading: String, cost: Double) {
            self.keys = keys
            self.reading = reading
            self.cost = cost
        }
    }

    /// 打ち間違いの手間．キーボードで隣のキー・母音どうし・同じキーの重なりは起きやすいので小さくする(値は DefaultSettings)
    public struct Costs: Sendable {
        public var neighborSubstitution = DefaultSettings.keyEditCosts.neighborSubstitution
        public var substitution = DefaultSettings.keyEditCosts.substitution
        public var easyOmission = DefaultSettings.keyEditCosts.easyOmission
        public var omission = DefaultSettings.keyEditCosts.omission
        public var easyInsertion = DefaultSettings.keyEditCosts.easyInsertion
        public var insertion = DefaultSettings.keyEditCosts.insertion
        public var transposition = DefaultSettings.keyEditCosts.transposition
        /// 読みの音が変わらない書き誤り(ず/づ・じ/ぢ・わ/は・え/へ・お/を・おう/おお)．聞いたとおりに書いた誤りなので起きやすい
        public var samePronunciation = DefaultSettings.keyEditCosts.samePronunciation
        /// 母音・や行・な行の前の「ん」を n 1 つで打った誤り(konichiha → konnichiha)．ローマ字の綴りの決まりの誤りなので起きやすい
        public var nasalSpelling = DefaultSettings.keyEditCosts.nasalSpelling
        public init() {}
    }

    static let alphabet: [Character] = Array("abcdefghijklmnopqrstuvwxyz-")
    static let vowels: Set<Character> = ["a", "i", "u", "e", "o"]

    /// keys から 1 か所を変えたキーの並びと読み．かなにならない綴りになるものと，元と同じ読みのものは除く．同じ読みは手間の小さい方を残す
    /// from より前の位置は変えない(前に見直した部分を探し直さないため)
    public static func edits(of keys: String, from: Int = 0, costs: Costs = Costs(), table: RomajiTable = .standard) -> [Edit] {
        let characters = Array(keys)
        let original = reading(of: keys, table: table)
        let originalSound = original.map(pronunciation(of:))
        var best: [String: Edit] = [:]
        func record(_ edited: String, cost: Double) {
            guard let reading = reading(of: edited, table: table), reading != original else { return }
            // 音が同じなら，キーの打ち間違いでなく書き分けの誤りとみなし，手間を小さくする
            let cost = pronunciation(of: reading) == originalSound ? min(cost, costs.samePronunciation) : cost
            if let existing = best[reading], existing.cost <= cost { return }
            best[reading] = Edit(keys: edited, reading: reading, cost: cost)
        }
        func add(_ edited: [Character], cost: Double) {
            // 「nn」のあとの母音は「ん+あ行」と「ん+な行」のどちらにも読める(hannei → 反映，konnichiha → こんにちは)．
            // 表は「ん+あ行」で読むので，「ん+な行」の読みも n を 1 つ足した並びとして試す(同じ手間)
            for variant in [edited] + nasalVariants(of: edited) {
                record(String(variant), cost: cost)
            }
        }
        for index in min(max(0, from), characters.count)...characters.count {
            let previous = index > 0 ? characters[index - 1] : nil
            let current = index < characters.count ? characters[index] : nil
            // 打ち忘れ: index の前に 1 文字を補う
            for character in alphabet {
                let easy = vowels.contains(character) || character == previous || character == current
                let nasal = isNasalSpelling(inserting: character, at: index, in: characters)
                add(Array(characters[..<index]) + [character] + Array(characters[index...]),
                    cost: nasal ? costs.nasalSpelling : easy ? costs.easyOmission : costs.omission)
            }
            guard let current else { continue }
            // 余分な 1 打: index の文字を除く
            let easyInsertion = current == previous || vowels.contains(current) || previous.map { KeyAdjacency.areNeighbors($0, current) } == true
            add(Array(characters[..<index]) + Array(characters[(index + 1)...]), cost: easyInsertion ? costs.easyInsertion : costs.insertion)
            // 取り違え: index の文字を別の文字にする
            for character in alphabet where character != current {
                let easy = KeyAdjacency.areNeighbors(character, current) || (vowels.contains(character) && vowels.contains(current))
                var replaced = characters
                replaced[index] = character
                add(replaced, cost: easy ? costs.neighborSubstitution : costs.substitution)
            }
            // 隣どうしの入れ替え
            if index + 1 < characters.count, characters[index] != characters[index + 1] {
                var swapped = characters
                swapped.swapAt(index, index + 1)
                add(swapped, cost: costs.transposition)
            }
        }
        return Array(best.values)
    }

    /// index に character を補うと，母音・や行・な行の前の 1 つの n が「nn」(ん)になるか
    static func isNasalSpelling(inserting character: Character, at index: Int, in keys: [Character]) -> Bool {
        guard character == "n", index > 0, index < keys.count, keys[index - 1] == "n" else { return false }
        let next = keys[index]
        return (vowels.contains(next) || next == "y" || next == "n") && (index < 2 || keys[index - 2] != "n")
    }

    /// 「nn」のあとに母音が続くところ(「nnn」でない)を 1 か所ずつ「nnn」にした並び．「ん+な行」で読ませるため
    static func nasalVariants(of keys: [Character]) -> [[Character]] {
        var variants: [[Character]] = []
        for index in keys.indices.dropLast(2) where keys[index] == "n" && keys[index + 1] == "n" && vowels.contains(keys[index + 2])
            && (index == 0 || keys[index - 1] != "n") {
            variants.append(Array(keys[...index]) + ["n"] + Array(keys[(index + 1)...]))
        }
        return variants
    }

    /// 1 か所の打ち間違いをすべて試して，訂正の候補にする．2 段で絞る:
    /// 1. 変わったところの前後の変換のもっともらしさ(localGain)から手間を引いた値で，上位 limit 件に絞る(速い)
    /// 2. 絞った候補と打ったままの並びを，文脈を見る言語モデル(languageModel)で採点する(遅いので件数を絞ってから)
    /// 点数は「言語モデルの点数 - 手間 × costScale」．Zenzai の訂正の候補(ReadingCorrection)と同じ尺度にし，混ぜて比べられるようにする．
    /// 打ったままの並びも候補に入れる(訂正するかどうかは ReadingCorrectionRule が打ったままとの差で決める)
    public static func corrections(
        of keys: String,
        from: Int = 0,
        limit: Int = DefaultSettings.keyEditCandidateCount,
        costScale: Double = DefaultSettings.keyEditCostScale,
        plausibility: (String) -> Double,
        languageModel: ([String]) -> [Double?]
    ) -> [ReadingCorrection] {
        // 打ったままの読みに，かなにならない英字が残ることがある(tkitou → tきとう)．そのときも訂正を探す
        let original = rawReading(of: keys)
        guard !original.isEmpty else { return [] }
        let ranked = edits(of: keys, from: from)
            .map { (edit: $0, local: localGain(of: $0.reading, over: original, plausibility: plausibility) - $0.cost) }
            .sorted { $0.local != $1.local ? $0.local > $1.local : $0.edit.keys < $1.edit.keys }
            .prefix(limit)
            .map(\.edit)
        let scores = languageModel([keys] + ranked.map(\.keys))
        // 打ったままの並びを言語モデルが読めない(かなにならない英字が残る「gakusri」)ときは，訂正の候補だけを返す
        let typed = (scores.first ?? nil).map { ReadingCorrection(keys: keys, reading: KanaWidth.katakana(from: original), score: $0, cost: 0) }
        let corrected = zip(ranked, scores.dropFirst()).compactMap { edit, score in
            score.map { ReadingCorrection(keys: edit.keys, reading: KanaWidth.katakana(from: edit.reading), score: $0 - edit.cost * costScale, cost: edit.cost * costScale) }
        }
        return (typed.map { [$0] } ?? []) + corrected
    }

    /// 候補ごとに，読みを変換したときのもっともらしさの打ったままの読みとの差(plausibilityGain)を入れる
    public static func withPlausibility(_ corrections: [ReadingCorrection], typedKeys keys: String, plausibility: (String) -> Double) -> [ReadingCorrection] {
        let original = rawReading(of: keys)
        guard !original.isEmpty else { return corrections }
        let base = finite(plausibility(original))
        return corrections.map { correction in
            var correction = correction
            correction.plausibilityGain = finite(plausibility(KanaWidth.hiragana(from: correction.reading))) - base
            return correction
        }
    }

    /// 前に見直したキーの並び(previous)と今の並びが先頭から同じ長さのうち，探し直さなくてよい長さ．
    /// 打ち間違いは変わったところの少し前にもありうる(打ち忘れ・入れ替え)ので，DefaultSettings.keyEditOverlap 文字は探し直す
    /// 前の並びに打ち足した並び(同じ入力の続き)のときだけ探し直さない．別の入力(前の文)と頭がたまたま同じでも，全部を探す
    public static func searchStart(keys: String, previous: String?) -> Int {
        guard let previous, keys.hasPrefix(previous) else { return 0 }
        let common = zip(keys, previous).prefix { $0 == $1 }.count
        return max(0, common - DefaultSettings.keyEditOverlap)
    }

    /// 2 つの訂正の候補の並びを 1 つにする．同じキーの並びは点数の高い方を残し，点数の高い順に並べる
    public static func merge(_ lists: [ReadingCorrection]...) -> [ReadingCorrection] {
        var best: [String: ReadingCorrection] = [:]
        for correction in lists.joined() where (best[correction.keys]?.score ?? -.infinity) < correction.score {
            best[correction.keys] = correction
        }
        return best.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.keys < $1.keys }
    }

    /// 読みの変わったところの前後だけを変換したときの，もっともらしさの差(局所の利得)．
    /// 読み全体を比べると，短い読みほどもっともらしくなる偏りが出るうえ遅いので，変わったところの前後 window 文字だけで比べる
    public static func localGain(of edited: String, over original: String, window: Int = 3, plausibility: (String) -> Double) -> Double {
        let a = Array(original), b = Array(edited)
        let prefix = zip(a, b).prefix { $0 == $1 }.count
        let suffix = zip(a.reversed(), b.reversed()).prefix { $0 == $1 }.count
        let common = min(suffix, min(a.count, b.count) - prefix)
        let start = max(0, prefix - window)
        func slice(_ text: [Character]) -> String { String(text[start..<min(text.count, text.count - common + window)]) }
        return finite(plausibility(slice(b))) - finite(plausibility(slice(a)))
    }

    /// 変換できない読み(英字が残るなど)のもっともらしさは −∞ なので，比べられるよう下限の値にする
    static func finite(_ value: Double) -> Double {
        value.isFinite ? value : DefaultSettings.unconvertiblePlausibility
    }

    /// キーの並びの読み(ひらがな)．かなにならない英字もそのまま残す(打ったままの読み)
    public static func rawReading(of keys: String, table: RomajiTable = .standard) -> String {
        var composition = Composition(table: table)
        for key in keys { composition.insertRomaji(key) }
        return composition.conversionReading
    }

    /// 読みの音．書き分けても音が同じかなをそろえる(ぢ→じ，づ→ず，を→お，は→わ，へ→え)．
    /// 長音は，お段のあとの「う」を「お」に，え段のあとの「い」を「え」にそろえる(とうり・とおり，えいが・ええが)
    static func pronunciation(of reading: String) -> String {
        let same: [Character: Character] = ["ぢ": "じ", "づ": "ず", "を": "お", "は": "わ", "へ": "え"]
        let oRow = Set("おこそとのほもよろごぞどぼぽょ"), eRow = Set("えけせてねへめれげぜでべぺ")
        var result: [Character] = []
        for character in reading {
            var sound = same[character] ?? character
            if let previous = result.last {
                if sound == "う", oRow.contains(previous) || previous == "お" { sound = "お" }
                if sound == "い", eRow.contains(previous) || previous == "え" { sound = "え" }
            }
            result.append(sound)
        }
        return String(result)
    }

    /// キーの並びの読み(ひらがな)．かなにならない文字が残れば nil
    public static func reading(of keys: String, table: RomajiTable = .standard) -> String? {
        var composition = Composition(table: table)
        for key in keys { composition.insertRomaji(key) }
        let reading = composition.conversionReading
        guard !reading.isEmpty, !reading.contains(where: { $0.isASCII && $0.isLetter }) else { return nil }
        return reading
    }
}

/// 打ち間違いの手間を決めるためのキーの並び(JIS・US の QWERTY で同じ)
enum KeyAdjacency {
    private static let rows: [String] = ["1234567890-", "qwertyuiop", "asdfghjkl", "zxcvbnm"]
    private static let positions: [Character: (row: Int, column: Double)] = {
        var result: [Character: (Int, Double)] = [:]
        // 段ごとのずれ(キーの幅の何分か)
        let offsets: [Double] = [0, 0.5, 0.75, 1.25]
        for (row, keys) in rows.enumerated() {
            for (column, key) in keys.enumerated() { result[key] = (row, Double(column) + offsets[row]) }
        }
        return result
    }()

    /// キーボードで隣り合うキーか(同じ段の両隣と，上下の段で近いもの)
    static func areNeighbors(_ a: Character, _ b: Character) -> Bool {
        guard a != b, let first = positions[a], let second = positions[b] else { return false }
        let rowDistance = abs(first.row - second.row)
        return rowDistance <= 1 && abs(first.column - second.column) <= (rowDistance == 0 ? 1.0 : 1.0)
    }
}
