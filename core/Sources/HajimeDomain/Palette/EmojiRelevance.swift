/// かな漢字変換の候補に足す絵文字を引くときの，文節の語(R-26)．
/// text は文節の第 1 候補の表記(「空」「帰る」「猫」．第 1 候補がひらがなのままなら最初の漢字かカタカナの候補)，isNoun はそれが名詞 1 語か．
/// hiraganaText は第 1 候補がひらがなのままのときの表記(「みかん」)で，名前がそのひらがなの絵文字(🍊 みかん)にだけ合わせる
public struct EmojiWord: Sendable, Equatable {
    public var text: String
    public var isNoun: Bool
    public var hiraganaText: String?

    public init(text: String, isNoun: Bool, hiraganaText: String? = nil) {
        self.text = text
        self.isNoun = isNoun
        self.hiraganaText = hiraganaText
    }
}

/// 読みで引いた絵文字が，文節の語と合うか(R-26)．
///
/// 絵文字の表の読みとキーワードには，名前と関係の薄い連想の語(翼の「空」，空き瓶の「空(から)」を「そら」と読んだもの)や，
/// 同じ読みの別の語(髪 と 紙，カエル と 帰る)が入っている．読みが合うだけでは関係の薄い絵文字が出るので，
/// 文節の第 1 候補の語が絵文字の名前(CLDR の日本語の名前)の語と合うものだけを出す．
/// 名前に出てこない語で期待される絵文字(コーヒー → ☕ 温かい飲み物)は，同じ意味の語の一覧(EmojiSynonyms)で出す
public enum EmojiRelevance {
    /// item の名前の語と word が合うか．読みは呼び出し側で引いてある(名前の読みか読みが文節の読みと同じ)
    /// 1. 語が名前そのもの(「笑顔」→ 😄 笑顔，「すし」→ 🍣 すし)
    /// 2. 語が名前の語の境にある(「猫」→ 😺 にっこり笑う猫，「ハート」→ ❤️ 赤いハート)．境は字の種類の変わり目と記号．
    ///    かなの語は名前のかなの語とひらがなにして比べる(「くま」→ 🐻 クマの顔)
    /// 3. 語がキーワードにあり，名前の中にもある(「花」→ 💐 花束)
    ///
    /// 2 と 3 で漢字の語を名前の中に見つけたときは，名前の読みに文節の読みがあるときだけにする．字が同じでも読みの違う語
    /// (「空(そら)」と 空マーク の「空(くう)」，「車(くるま)」と 自動車 の「車(しゃ)」)は別の語なので出さない．
    /// 囲み文字の記号(🈁〜🉑・㊗️・㊙️)は字 1 つで別の意味(空室・月極)を表すので，名前そのもののときだけにする(空室 → 🈳 は一覧で出す)
    /// 4. 名詞の語がキーワードにあり，名前のかなの語の読みと文節の読みが同じ(「猫」→ 🐈 ネコ，「犬」→ 🐕 イヌ)．
    ///    キーワードにあることを求めるので，同じ読みの別の語(「雲」→ 🕷️ クモ)は出さない
    /// 5. カタカナの語が名前のカタカナの語の頭か終わりにあり，読みがその絵文字の読みにある(「ビール」→ 🍺 ビールジョッキ，「ケーキ」→ 🎂 バースデーケーキ)
    public static func matches(_ item: PaletteItem, reading: String, word: EmojiWord) -> Bool {
        let name = item.japaneseName
        let text = word.text
        guard !name.isEmpty, !text.isEmpty else { return false }
        if let kana = word.hiraganaText, kana == name { return true }
        if text == name || hiragana(text) == hiragana(name) { return true }
        if isEnclosedIdeograph(item.text) { return false }
        // 漢字の語は，名前の読みに文節の読みがあるときだけ(名前の読みが無ければ確かめない)
        let readsAlike = !containsKanji(text) || item.nameReading.isEmpty || hiragana(item.nameReading).contains(reading)
        if readsAlike, occursAtWordBoundary(text, in: name) { return true }
        // かなの語は，名前のかなの語とひらがなにして比べる(「くま」→ 🐻 クマの顔)
        if text.allSatisfy({ [.hiragana, .katakana].contains(Script.of($0)) }), kanaWords(of: name).contains(where: { hiragana($0) == hiragana(text) }) {
            return true
        }
        if readsAlike, item.keywords.contains(text), name.contains(text) { return true }
        if word.isNoun, item.keywords.contains(text), kanaWords(of: name).contains(where: { hiragana($0) == reading }) { return true }
        if text.allSatisfy({ Script.of($0) == .katakana }), item.readings.contains(reading),
           kanaWords(of: name).contains(where: { $0.hasPrefix(text) || $0.hasSuffix(text) }) { return true }
        return false
    }

    /// 囲み文字の漢字・カタカナの記号(🈁 ココ・🈳 空・🉑 可・㊗️ 祝・㊙️ 秘)か
    static func isEnclosedIdeograph(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        return (0x1F200...0x1F2FF).contains(scalar.value) || scalar.value == 0x3297 || scalar.value == 0x3299
    }

    /// 字の種類(語の境を見つけるため)
    enum Script: Equatable {
        case hiragana, katakana, kanji, other

        static func of(_ character: Character) -> Script {
            guard let scalar = character.unicodeScalars.first else { return .other }
            switch scalar.value {
            case 0x3041...0x309F: return .hiragana
            case 0x30A0...0x30FF, 0x31F0...0x31FF: return .katakana
            case 0x4E00...0x9FFF, 0x3400...0x4DBF, 0x3005, 0x3006: return .kanji
            default: return .other
            }
        }
    }

    /// text が name の中に，前後が語の境(名前の端・記号・字の種類の変わり目)になる位置で現れるか
    static func occursAtWordBoundary(_ text: String, in name: String) -> Bool {
        let characters = Array(name)
        let pattern = Array(text)
        guard !pattern.isEmpty, pattern.count <= characters.count else { return false }
        for start in 0...(characters.count - pattern.count) where Array(characters[start..<(start + pattern.count)]) == pattern {
            let end = start + pattern.count
            let opens = start == 0 || isBoundary(between: characters[start - 1], and: characters[start])
            let closes = end == characters.count || isBoundary(between: characters[end - 1], and: characters[end])
            if opens && closes { return true }
        }
        return false
    }

    private static func isBoundary(between left: Character, and right: Character) -> Bool {
        let (a, b) = (Script.of(left), Script.of(right))
        return a == .other || b == .other || a != b
    }

    /// 名前の中のかなの語(カタカナの続きとひらがなの続き)
    static func kanaWords(of name: String) -> [String] {
        var words: [String] = []
        var current = ""
        var script: Script?
        for character in name {
            let kind = Script.of(character)
            if kind == script, kind == .hiragana || kind == .katakana {
                current.append(character)
                continue
            }
            if !current.isEmpty { words.append(current) }
            current = kind == .hiragana || kind == .katakana ? String(character) : ""
            script = kind
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    /// すべてひらがなの文字か(長音を含む)
    public static func isHiragana(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { Script.of($0) == .hiragana || $0 == "ー" }
    }

    /// 漢字を含むか(語の意味が字で決まっているか)
    public static func containsKanji(_ text: String) -> Bool {
        text.contains { Script.of($0) == .kanji }
    }

    /// カタカナをひらがなにした文字(長音はそのまま)
    static func hiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { scalar in
            (0x30A1...0x30F6).contains(scalar.value) ? Unicode.Scalar(scalar.value - 0x60) ?? scalar : scalar
        }))
    }
}
