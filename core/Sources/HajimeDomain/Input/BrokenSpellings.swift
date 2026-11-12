/// 字の並びが崩れた候補(「はッ制」「シュッ派つ」「じゅっ分」「出発スる」「自ャ」)を見分け，2 番目から後ろで除く規則．
///
/// エンジンは辞書の語を自由につなぐので，活用の切れ端(這っ の「はっ」，「ざっ」「シュッ」)や 1 文字のカタカナの語(ス・ノ・コ・ヲ)，
/// 小さいかな(ャ・ァ)が，漢字やひらがなの語とつながった候補を作る．Zenzai を使わない変換の候補を 2 番目から後ろに混ぜると(ADR 0016)，
/// これが上位に出る．正しい書き方に無い形なので除く．
/// - 促音の切れ端: かなと促音で終わる語のすぐ後に漢字で始まる語が続く(じゅっ分・はっ再・シュッ派つ・ハッ中)，漢字のあとのカタカナの「ッ」
///   (良ッ書・良ッた)
/// - 拍の途中の字種の切り替え: ひらがなのすぐ後の小さいカタカナ(はッ制・ねェ)，カタカナのすぐ後の小さいひらがな(シゃ)，
///   カタカナの「ッ」のすぐ後の「と」以外のひらがな(ザッしを・アッさり．サッと・ハッとする は残す)
/// - 小さいかなの位置: 漢字・数字・英字のすぐ後の小さいかな(自ャ・打ァ・非ゃっぽ)
/// - 1 文字のカタカナ: 前後にカタカナの無い 1 文字のカタカナが，ひらがなか漢字と並ぶ(出発スる・コの・雑誌ヲ・コども)．
///   ひらがなか漢字のすぐ後のカタカナの「ン」(えンピつ)も同じ．
///   ヵ・ヶ，数のあとの カ・ケ(3カ月)，漢字に挟まれた ノ・ケ・ツ(湯ノ沢・霞ケ関・一ツ橋)，音の名前(ハ長調)は残す
/// - 当たらない: 1 つの語(辞書の「うっ血」「フッ素」「三ッ星」「トッ捕まる」)，強めの接頭の語(ぶっ飛ぶ・ブッ飛ばす・カッ飛ぶ・真ッ赤)，
///   数のあとの「ッ」(三ッ＋星)，動詞の活用の促音(引っ＋越し)，送りがなの促音(開けっ＋放し)，ユーザー辞書の語や記号
/// - 第 1 候補は変えない．ライブ変換で見えている文字と同じにするため
public enum BrokenSpellings {
    /// 強めの接頭の語(ぶっ飛ぶ・ひっ越し・おっ立てる・かっ飛ばす・つっ込む・とっ捕まえる・すっ飛ぶ・ふっ飛ぶ)．
    /// 後ろに漢字の語が続いても崩れていない．カタカナで書くもの(ブッ殺す・カッ飛ぶ・トッ捕まる・フッ化)も同じ
    static let emphaticPrefixes: Set<String> = ["ぶっ", "ひっ", "おっ", "かっ", "つっ", "とっ", "すっ", "ふっ"]
    /// 「ッ」の前の漢字のうち，後ろに漢字の語が続いても崩れていないもの(真ッ赤・三ッ星・七ッ森・一ッ橋)
    static let kanjiBeforeSokuon: Set<Character> = Set("真一二三四五六七八九十")

    /// 1 文字のカタカナのうち，数のすぐ後なら助数詞の一部のもの(3カ月・三ケ所)
    static let counterKatakana: Set<Character> = ["カ", "ケ"]
    /// 1 文字のカタカナのうち，漢字に挟まれていれば地名の一部のもの(湯ノ沢・霞ケ関・一ツ橋)
    static let placeKatakana: Set<Character> = ["ノ", "ケ", "ツ"]
    /// 音の名前(ハ長調・イ短調)の頭の字
    static let noteNames: Set<Character> = ["イ", "ロ", "ハ", "ニ", "ホ", "ヘ", "ト"]
    static let smallKana: Set<Character> = Set("ぁぃぅぇぉゃゅょゎァィゥェォャュョヮ")

    /// 候補の窓に出さない候補か．エンジンの候補だけを見る
    public static func isBroken(_ candidate: Candidate) -> Bool {
        guard isEngineText(candidate) else { return false }
        return hasScriptBreak(Array(candidate.text)) || hasFragment(candidate)
    }

    /// 拍の途中の字種の切り替え・小さいかなの位置・1 文字のカタカナ
    static func hasScriptBreak(_ characters: [Character]) -> Bool {
        for (index, character) in characters.enumerated() {
            let before = index > 0 ? characters[index - 1] : nil
            let after = index + 1 < characters.count ? characters[index + 1] : nil
            if smallKana.contains(character) || character == "ッ" {
                // 頭の小さいかなは，読みが小さいかなで始まる(かな入力で「ぁ」を打った)ときもあるので見ない
                guard let before else { continue }
                // ひらがなのすぐ後の小さいカタカナ(はッ・ねェ)，カタカナのすぐ後の小さいひらがな(シゃ)
                if isHiragana(before) && isKatakana(character) { return true }
                if isKatakana(before) && isHiragana(character) { return true }
                // 漢字・数字・英字のすぐ後の小さいかな(自ャ・打ァ)．漢字のあとの「ッ」は，漢字が続くとき(三ッ星・良ッ書)を促音の切れ端で見る
                if isKanji(before) || before.isASCII || before.isNumber {
                    if character != "ッ" { return true }
                    if !kanjiBeforeSokuon.contains(before), let after, !isKanji(after) { return true }
                }
                // カタカナの「ッ」のすぐ後の「と」以外のひらがな(ザッしを・アッさり)
                if character == "ッ", isKatakana(before), let after, isHiragana(after), after != "と" { return true }
                continue
            }
            guard isKatakana(character), character != "ー", !"ヵヶ".contains(character) else { continue }
            // カタカナの「ン」から始まる並び(えンピつ)．語は「ン」から始まらない
            if character == "ン", let before, isHiragana(before) || isKanji(before) { return true }
            if let before, isKatakana(before) || before == "ー" { continue }
            if let after, isKatakana(after) || after == "ー" || smallKana.contains(after) { continue }
            let neighbors = [before, after].compactMap { $0 }
            guard neighbors.contains(where: { isHiragana($0) || isKanji($0) }) else { continue }
            if counterKatakana.contains(character), let before, before.isNumber || "〇一二三四五六七八九十百千万何数".contains(before) { continue }
            if placeKatakana.contains(character), let before, let after, isKanji(before), isKanji(after) { continue }
            if noteNames.contains(character), let after, "長短".contains(after) { continue }
            return true
        }
        return false
    }

    /// 2 番目から後ろの崩れた候補を除く．ほかの候補の順は変えない
    public static func cleaned(_ candidates: [Candidate]) -> [Candidate] {
        guard let first = candidates.first else { return [] }
        return [first] + candidates.dropFirst().filter { !isBroken($0) }
    }

    /// 候補の中の切れ端．語の区切りが分かるときは語の切れ目だけを，先頭の語を選び直した候補はその語の中の切れ目と後ろを，
    /// 分からないとき(文全体の候補から切り出した文節)はすべての字の間を見る．1 つの語(うっ血)は見ない
    private static func hasFragment(_ candidate: Candidate) -> Bool {
        let characters = Array(candidate.text)
        let words: [Int]?
        if candidate.origin == .combined, let head = candidate.learnedParts.first, candidate.text.hasPrefix(head.text) {
            words = wordBoundaries(of: head).map { $0 + [head.text.count] }
        } else {
            words = wordBoundaries(of: candidate)
        }
        let boundaries = words ?? Array(characters.indices.dropFirst())
        if boundaries.contains(where: { isFragment(characters, at: $0) }) { return true }
        // 「っ子」のように促音で始まる語に，1 文字のかなの語をつないだもの(い＋っ子・や＋っ子)．ちび＋っ子・売れ＋っ子 は残す．
        // 語の区切りが分かるときだけ見る(フッ素 のような 1 つの語を切らないため)
        guard let words else { return false }
        return zip([0] + words, words).contains { start, boundary in
            boundary + 1 < characters.count && boundary - start == 1 && isSmallTsu(characters[boundary]) && isKanji(characters[boundary + 1])
                && isKana(characters[start]) && (start == 0 || !isKanji(characters[start - 1]))
        }
    }


    /// 語の切れ目の位置(字の数)．1 つの語なら空，語の区切りが分からなければ nil
    private static func wordBoundaries(of candidate: Candidate) -> [Int]? {
        guard !candidate.words.isEmpty, candidate.words.map(\.text).joined() == candidate.text else { return nil }
        return candidate.words.dropLast().reduce(into: [Int]()) { $0.append(($0.last ?? 0) + $1.text.count) }
    }

    /// characters[boundary] の前で，促音の切れ端が漢字とつながっているか
    private static func isFragment(_ characters: [Character], at boundary: Int) -> Bool {
        guard boundary >= 2, boundary < characters.count, isKanji(characters[boundary]) else { return false }
        let tsu = characters[boundary - 1]
        guard isSmallTsu(tsu) else { return false }
        let before = characters[boundary - 2]
        if isKanji(before) {
            // 漢字のあとのひらがなの「っ」は動詞の活用(引っ＋越し)．カタカナの「ッ」は真ッ赤・三ッ星のほかは崩れている(良ッ書)
            return tsu == "ッ" && !kanjiBeforeSokuon.contains(before)
        }
        guard isKana(before) else { return false }
        // 促音の前のかなの並び．漢字のすぐ後なら送りがな(開けっ＋放し)なので当たらない
        var start = boundary - 2
        while start > 0, isKana(characters[start - 1]) { start -= 1 }
        guard start == 0 || !isKanji(characters[start - 1]) else { return false }
        let prefix = String(characters[start..<boundary])
        return !emphaticPrefixes.contains(prefix) && !emphaticPrefixes.contains(hiragana(prefix))
    }

    /// エンジンが語をつないで作った候補か(記号・ユーザー辞書の語・字種の変換などは見ない)
    private static func isEngineText(_ candidate: Candidate) -> Bool {
        switch candidate.origin {
        case .engine, .combined, .sentencePart: true
        default: false
        }
    }

    private static func isSmallTsu(_ character: Character) -> Bool { character == "っ" || character == "ッ" }

    /// カタカナをひらがなにした文字列(強めの接頭の語をカタカナで書いたもの「ブッ」を「ぶっ」として引くため)
    private static func hiragana(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { (0x30A1...0x30F6).contains($0.value) ? Unicode.Scalar($0.value - 0x60) ?? $0 : $0 }))
    }

    private static func isKatakana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x30A1...0x30FA).contains($0.value) || $0.value == 0x30FC }
    }

    private static func isHiragana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) }
    }

    private static func isKana(_ character: Character) -> Bool {
        character == "ー" || character.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || (0x30A1...0x30FA).contains($0.value) }
    }

    private static func isKanji(_ character: Character) -> Bool {
        character == "々" || character.unicodeScalars.allSatisfy {
            (0x4E00...0x9FFF).contains($0.value) || (0x3400...0x4DBF).contains($0.value) || (0xF900...0xFAFF).contains($0.value)
                || (0x20000...0x2FA1F).contains($0.value)
        }
    }
}
