/// 読みから引く記号の辞書．読みを変換すると出す記号をまとめた．
/// 変換エンジンの辞書に無い記号だけを足すために使う(エンジンが同じ記号を出していれば重ねない)
public enum SymbolDictionary {
    /// 読みから引く記号．利用者が変えた決まり(SymbolRule の .reading)を既定に重ねる
    public static func symbols(for reading: String, rules: [SymbolRule] = []) -> [String] {
        if let rule = rules.last(where: { $0.kind == .reading && $0.input == reading }) {
            return rule.isEnabled ? rule.outputs : []
        }
        return table[reading] ?? []
    }

    /// 既定の決まり(読みと記号の並び)．設定の画面で一覧にする
    public static var defaultEntries: [(reading: String, symbols: [String])] {
        table.keys.sorted().map { ($0, table[$0] ?? []) }
    }

    static let table: [String: [String]] = {
        let entries: [(String, String)] = [
            // 矢印
            ("やじるし", "→ ← ↑ ↓ ⇒ ⇔ ↔ ↕ ↗ ↘ ↙ ↖ ⇐ ⇑ ⇓ ➡ ⬅"),
            ("みぎ", "→ ⇒ ➡"), ("ひだり", "← ⇐ ⬅"), ("うえ", "↑ ⇑"), ("した", "↓ ⇓"),
            ("みぎやじるし", "→"), ("ひだりやじるし", "←"), ("うえやじるし", "↑"), ("したやじるし", "↓"),
            ("ならば", "⇒"), ("どうち", "⇔"), ("さゆう", "↔"), ("じょうげ", "↕"),
            // 図形
            ("まる", "○ ● ◎ ◯ 〇"), ("くろまる", "●"), ("にじゅうまる", "◎"),
            ("しかく", "□ ■ ◻ ◼"), ("くろしかく", "■"),
            ("さんかく", "△ ▲ ▽ ▼ ▷ ▶ ◁ ◀"), ("くろさんかく", "▲"), ("ぎゃくさんかく", "▽ ▼"),
            ("ひし", "◇ ◆"), ("ひしがた", "◇ ◆"), ("ほし", "★ ☆ ✳ ✴"), ("くろぼし", "★"),
            ("はーと", "♡ ♥"), ("すぺーど", "♠ ♤"), ("だいや", "♢ ♦"), ("くらぶ", "♣ ♧"), ("とらんぷ", "♠ ♡ ♢ ♣"),
            ("ばつ", "× ✕ ✖"), ("ちぇっく", "✓ ✔"),
            // 約物
            ("こめ", "※"), ("こめじるし", "※"), ("から", "〜 ～"), ("なみ", "〜 ～"),
            ("おなじ", "々 〃 仝 ゝ ゞ ヽ ヾ"), ("どう", "〃 仝"), ("くりかえし", "々 ゝ ゞ ヽ ヾ 〻"), ("のま", "々"),
            ("てん", "・ 、 ， ．"), ("なかぐろ", "・"), ("まる", "。"), ("くてん", "。"), ("とうてん", "、"),
            ("さんてん", "… ‥"), ("てんてん", "… ‥"), ("りーだー", "… ‥"),
            ("かっこ", "「」 『』 （） 【】 〔〕 ［］ ｛｝ 〈〉 《》 ＜＞ ≪≫"), ("かぎかっこ", "「」 『』"),
            ("すみつきかっこ", "【】"), ("やまかっこ", "〈〉 《》"),
            ("ゆうびん", "〒 〶"), ("でんわ", "℡ ☎ ☏"), ("きごう", "※ 〒 ♪ ☆ ★ ○ ● ◎ □ ■ △ ▲"),
            ("おんぷ", "♪ ♫ ♬ ♩"), ("しゃーぷ", "♯"), ("ふらっと", "♭"),
            ("せくしょん", "§"), ("だんらく", "¶"), ("だがー", "† ‡"), ("こぴーらいと", "©"), ("とうろくしょうひょう", "®"),
            ("おす", "♂"), ("めす", "♀"), ("おとこ", "♂"), ("おんな", "♀"),
            ("たいよう", "☀"), ("くも", "☁"), ("あめ", "☂"), ("ゆき", "☃"), ("かみなり", "⚡"),
            ("ゆび", "☞ ☜ ☝ ☟"),
            // 単位
            ("ど", "° ℃ ℉"), ("せっし", "℃"), ("かし", "℉"), ("ふん", "′"), ("びょう", "″"),
            ("ぱーせんと", "％ ‰"), ("ぱーみる", "‰"), ("えん", "円 ¥ ￥"), ("どる", "$ ＄"), ("ゆーろ", "€"), ("ぽんど", "£ ￡"), ("せんと", "¢ ￠"),
            ("みり", "㎜ ㍉"), ("せんち", "㎝ ㌢"), ("めーとる", "m ㍍"), ("きろ", "㎞ ㎏ ㌔"), ("きろめーとる", "㎞"),
            ("きろぐらむ", "㎏"), ("ぐらむ", "g ㌘"), ("りっとる", "ℓ ㍑"), ("へいほうめーとる", "㎡"), ("りっぽうめーとる", "㎥"),
            ("へくたーる", "㌶"), ("とん", "㌧"), ("かろりー", "㌍"), ("わっと", "㍗"), ("ぼると", "V"), ("あんぺあ", "A"),
            ("おんす", "oz"), ("いんち", "″ in"),
            // 数学
            ("たす", "＋ +"), ("ぷらす", "＋ +"), ("ひく", "－ −"), ("まいなす", "－ −"), ("かける", "× ・"), ("わる", "÷ ／"),
            ("いこーる", "＝ ≒ ≠ ≡"), ("ちかい", "≒ ≈"), ("にあいこーる", "≒"), ("のっといこーる", "≠"), ("ふとうごう", "＜ ＞ ≦ ≧ ≠ ≪ ≫"),
            ("ぷらまい", "±"), ("ぷらすまいなす", "±"), ("むげん", "∞"), ("むげんだい", "∞"),
            ("るーと", "√"), ("こんごう", "≡"), ("ごうどう", "≡"), ("せきぶん", "∫ ∬ ∮"), ("でぃー", "∂"), ("ぜんぶ", "∀"), ("そんざい", "∃"),
            ("ゆえに", "∴"), ("なぜなら", "∵"), ("ひれい", "∝"), ("かく", "∠"), ("すいちょく", "⊥"), ("へいこう", "∥ ≒"),
            ("しゅうごう", "∈ ∋ ⊆ ⊇ ⊂ ⊃ ∪ ∩ ∅"), ("ふくまれる", "∈ ⊂ ⊆"), ("ふくむ", "∋ ⊃ ⊇"),
            ("くうしゅうごう", "∅"), ("かつ", "∧"), ("または", "∨"), ("ひてい", "¬"), ("なぶら", "∇"),
            ("しぐま", "Σ σ ∑"), ("ぱい", "π Π ∏"), ("あるふぁ", "α Α"), ("べーた", "β Β"), ("がんま", "γ Γ"), ("でるた", "δ Δ"),
            ("いぷしろん", "ε Ε"), ("ぜーた", "ζ Ζ"), ("いーた", "η Η"), ("しーた", "θ Θ"), ("いおた", "ι Ι"), ("かっぱ", "κ Κ"),
            ("らむだ", "λ Λ"), ("みゅー", "μ Μ"), ("にゅー", "ν Ν"), ("くさい", "ξ Ξ"), ("おみくろん", "ο Ο"), ("ろー", "ρ Ρ"),
            ("たう", "τ Τ"), ("うぷしろん", "υ Υ"), ("ふぁい", "φ Φ"), ("かい", "χ Χ"), ("ぷさい", "ψ Ψ"), ("おめが", "ω Ω"),
            ("おーむ", "Ω"), ("ぎりしゃもじ", "α β γ δ ε π σ ω"),
            // 丸数字・ローマ数字
            ("まるいち", "①"), ("まるに", "②"), ("まるさん", "③"), ("まるよん", "④"), ("まるご", "⑤"),
            ("まるろく", "⑥"), ("まるなな", "⑦"), ("まるはち", "⑧"), ("まるきゅう", "⑨"), ("まるじゅう", "⑩"),
            ("まるすうじ", "① ② ③ ④ ⑤ ⑥ ⑦ ⑧ ⑨ ⑩"), ("ろーますうじ", "Ⅰ Ⅱ Ⅲ Ⅳ Ⅴ Ⅵ Ⅶ Ⅷ Ⅸ Ⅹ"),
            // 年号・略号
            ("めいじ", "㍾"), ("たいしょう", "㍽"), ("しょうわ", "㍼"), ("へいせい", "㍻"), ("れいわ", "㋿"),
            ("かぶしきがいしゃ", "㈱ ㍿"), ("かぶ", "㈱"), ("ゆうげんがいしゃ", "㈲"), ("だいひょう", "㈹"), ("でんわばんごう", "℡"),
            ("なんばー", "№"), ("ばんごう", "№ ＃"), ("しゃーぷ", "＃"), ("いげた", "＃"), ("あっと", "＠"), ("あんど", "＆"),
            ("すたー", "＊ ★ ☆"), ("あすたりすく", "＊"), ("すらっしゅ", "／"), ("ばっくすらっしゅ", "＼"), ("えんまーく", "¥ ￥"),
            ("ちるだ", "〜 ～"), ("はいふん", "‐ －"), ("だっしゅ", "― —"), ("あんだーばー", "＿"), ("たてぼう", "｜"), ("くえすちょん", "？"),
            ("びっくり", "！ ‼ ⁉"), ("はてな", "？ ⁇ ⁈"), ("ころん", "："), ("せみころん", "；"),
        ]
        var table: [String: [String]] = [:]
        for (reading, symbols) in entries {
            table[reading, default: []] += symbols.split(separator: " ").map(String.init)
        }
        return table
    }()
}

/// 続けて打った記号を 1 つの記号にまとめる規則．「->」(ー＞)を「→」に，「<-」(＜ー)を「←」にする．
///
/// 決まりは打つキーの並び(「->」)で持ち，読みの中の形(「ー＞」)に直して照らし合わせる．
/// 短い決まりが先にまとまるので(「<-」→「←」)，長い決まりの照らし合わせる形は，短い決まりでまとめたあとの形にする
/// (「<->」は「←＞」で照らし合わせる)
public struct SymbolSequenceSet: Sendable, Equatable {
    /// 打つキーの並びと，まとめた記号．既定の決まり
    public static let defaultRules: [(input: String, symbol: String)] = [
        ("->", "→"), ("<-", "←"), ("=>", "⇒"), ("<=", "⇐"), ("<->", "↔"), ("<=>", "⇔"),
    ]

    public static let standard = SymbolSequenceSet(rules: [])

    /// 読みの中の形と記号．長いものを先に調べる
    private var forms: [(form: String, symbol: String)]

    /// 既定の決まりに，利用者が変えた決まり(SymbolRule の .sequence)を重ねる
    public init(rules: [SymbolRule]) {
        var effective: [(input: String, symbol: String)] = []
        for rule in Self.defaultRules where !rules.contains(where: { $0.kind == .sequence && $0.input == rule.input }) {
            effective.append(rule)
        }
        for rule in rules where rule.kind == .sequence && rule.isEnabled && !rule.input.isEmpty {
            effective.append((rule.input, rule.output))
        }
        effective.sort { $0.input.count < $1.input.count }
        var forms: [(form: String, symbol: String)] = []
        for rule in effective {
            // 短い決まりでまとめながら，読みの中の形を作る
            var text = ""
            for character in rule.input {
                text.append(Self.readingForm(of: character))
                if let match = forms.sorted(by: { $0.form.count > $1.form.count }).first(where: { text.hasSuffix($0.form) }) {
                    text.removeLast(match.form.count)
                    text.append(match.symbol)
                }
            }
            if text.count > 1 { forms.append((text, rule.symbol)) }
        }
        self.forms = forms.sorted { $0.form.count > $1.form.count }
    }

    /// 末尾の並びがまとめられるなら，まとめる並びの長さと記号を返す
    public func match(suffixOf text: String) -> (length: Int, symbol: String)? {
        forms.first { text.hasSuffix($0.form) }.map { ($0.form.count, $0.symbol) }
    }

    /// 打ったキーが読みの中でなる形．- は長音，記号は全角
    static func readingForm(of character: Character) -> String {
        switch character {
        case "-": "ー"
        case "~": "〜"
        default:
            if let scalar = character.unicodeScalars.first, character.isASCII, (0x21...0x7E).contains(scalar.value), !character.isLetter, !character.isNumber {
                String(Character(UnicodeScalar(scalar.value + 0xFEE0)!))
            } else {
                String(character)
            }
        }
    }

    public static func == (lhs: SymbolSequenceSet, rhs: SymbolSequenceSet) -> Bool {
        lhs.forms.map(\.form) == rhs.forms.map(\.form) && lhs.forms.map(\.symbol) == rhs.forms.map(\.symbol)
    }
}

/// 利用者が変えた記号の決まり．既定の決まりと同じ入力なら上書きし(無効にもできる)，無ければ足す．
/// 既定の決まりそのものは変えないので，バージョンが上がって既定が増えても利用者の変更は残る
public struct SymbolRule: Sendable, Equatable, Codable, Hashable {
    public enum Kind: String, Sendable, Equatable, Codable {
        /// 続けて打った記号(「->」→「→」)
        case sequence
        /// 読みから引く記号(「やじるし」→「→ ← ↑ ↓」)
        case reading
    }

    public var kind: Kind
    /// 打つキーの並び，または読み(ひらがな)
    public var input: String
    /// まとめた記号．読みの決まりでは空白で区切った記号の並び
    public var output: String
    public var isEnabled: Bool

    public init(kind: Kind, input: String, output: String, isEnabled: Bool = true) {
        self.kind = kind
        self.input = input
        self.output = output
        self.isEnabled = isEnabled
    }

    public var outputs: [String] { output.split(separator: " ").map(String.init) }

    /// 入力と出力が空でなく，長すぎない
    public var isValid: Bool {
        !input.isEmpty && input.count <= 12 && output.count <= 200 && (!output.isEmpty || !isEnabled)
            && (kind == .reading || (input.count >= 2 && input.allSatisfy { $0.isASCII && !$0.isLetter && !$0.isNumber && !$0.isWhitespace }))
    }
}
