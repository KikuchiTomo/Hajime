/// 促音の切れ端を漢字とつないだ崩れた候補(「はッ制」「シュッ派つ」「じゅっ分」)を見分け，2 番目から後ろで除く規則．
///
/// エンジンは辞書の語を自由につなぐので，動詞や副詞の活用の切れ端(這っ の「はっ」，「ざっ」「シュッ」「ハッ」)が漢字の語とつながり，
/// 「はっ再の」「シュッ派つ」「ハッ中」のような候補を作る．Zenzai を使わない変換の候補を 2 番目から後ろに混ぜると(ADR 0016)，
/// これが上位に出る．漢字の語の読みを途中でかなに崩した形で，正しい語には無いので除く．
/// - ひらがなのすぐ後のカタカナの「ッ」(はッ制・きッぷ)
/// - かなと促音で終わる語のすぐ後に漢字で始まる語が続く候補(じゅっ分・ざっ氏・はっ再・シュッ派つ・ハッ中)
/// - 漢字のあとのカタカナの「ッ」に漢字の語が続く候補(良ッ書)
/// - 当たらない: 1 つの語(辞書の「うっ血」「フッ素」「三ッ星」「トッ捕まる」)，強めの接頭の語(ぶっ飛ぶ・ブッ飛ばす・カッ飛ぶ・真ッ赤)，
///   数のあとの「ッ」(三ッ＋星)，動詞の活用の促音(引っ＋越し)，送りがなの促音(開けっ＋放し)，ユーザー辞書の語や記号
/// - 第 1 候補は変えない．ライブ変換で見えている文字と同じにするため
public enum SokuonFragments {
    /// 強めの接頭の語(ぶっ飛ぶ・ひっ越し・おっ立てる・かっ飛ばす・つっ込む・とっ捕まえる・すっ飛ぶ・ふっ飛ぶ)．
    /// 後ろに漢字の語が続いても崩れていない．カタカナで書くもの(ブッ殺す・カッ飛ぶ・トッ捕まる・フッ化)も同じ
    static let emphaticPrefixes: Set<String> = ["ぶっ", "ひっ", "おっ", "かっ", "つっ", "とっ", "すっ", "ふっ"]
    /// 「ッ」の前の漢字のうち，後ろに漢字の語が続いても崩れていないもの(真ッ赤・三ッ星・七ッ森・一ッ橋)
    static let kanjiBeforeSokuon: Set<Character> = Set("真一二三四五六七八九十")

    /// 候補の窓に出さない候補か．エンジンの候補だけを見る
    public static func isBroken(_ candidate: Candidate) -> Bool {
        guard isEngineText(candidate) else { return false }
        if zip(candidate.text, candidate.text.dropFirst()).contains(where: { isHiragana($0) && $1 == "ッ" }) { return true }
        return hasFragment(candidate)
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
        let boundaries: [Int]
        if candidate.origin == .combined, let head = candidate.learnedParts.first, candidate.text.hasPrefix(head.text) {
            boundaries = (wordBoundaries(of: head) ?? Array(1..<max(head.text.count, 1))) + [head.text.count]
        } else {
            boundaries = wordBoundaries(of: candidate) ?? Array(characters.indices.dropFirst())
        }
        return boundaries.contains { isFragment(characters, at: $0) }
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
