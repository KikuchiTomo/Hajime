/// 促音の切れ端を漢字とつないだ崩れた候補(「はッ制」「じゅっ分」)を見分け，除くか下げる規則．
///
/// エンジンは辞書の語を自由につなぐので，動詞や副詞の活用の切れ端(這っ の「はっ」，「ざっ」「いッ」)が漢字の語とつながり，
/// 「はっ再の」「ざっ氏を」「いッ所に」のような候補を作る．Zenzai を使わない変換の候補を 2 番目から後ろに混ぜると(ADR 0016)，
/// これが上位に出る．
/// - 除く: ひらがなのすぐ後にカタカナの「ッ」が来る候補(はッ制・きッぷ・けッか)．正しい書き方に無い形
/// - 下げる: かなと促音で終わる語のすぐ後に，漢字で始まる語が続く候補(じゅっ分・ざっ氏・ハッ中)と，漢字のあとのカタカナの「ッ」に
///   漢字の語が続く候補(良ッ書)．同じ読みの数で，この形でない候補の下に移す．
///   1 つの語(辞書の「うっ血」「三ッ星」)と，強めの接頭の語(ぶっ飛ぶ・ひっ越し)は当たらない
/// - 第 1 候補は変えない．ライブ変換で見えている文字と同じにするため
public enum SokuonFragments {
    /// 強めの接頭の語(ぶっ飛ぶ・ひっ越し・おっ立てる・かっ飛ばす・つっ込む・とっ捕まえる・すっ飛ぶ・ふっ飛ぶ)．後ろに漢字の語が続いても崩れていない
    static let emphaticPrefixes: Set<String> = ["ぶっ", "ひっ", "おっ", "かっ", "つっ", "とっ", "すっ", "ふっ"]

    /// 候補の窓に出さない候補か(ひらがなのすぐ後にカタカナの「ッ」が来る)．エンジンの候補だけを見る
    public static func isBroken(_ candidate: Candidate) -> Bool {
        guard isEngineText(candidate) else { return false }
        return zip(candidate.text, candidate.text.dropFirst()).contains { isHiragana($0) && $1 == "ッ" }
    }

    /// 下げる候補か(かなと促音で終わる語のすぐ後に漢字で始まる語が続く)．エンジンの候補だけを見る．
    /// 語の区切りが分かるときは語の切れ目だけを，分からないとき(語をつないだ候補)はすべての字の間を見る．1 つの語(うっ血)は見ない
    public static func isFragmented(_ candidate: Candidate) -> Bool {
        guard isEngineText(candidate), candidate.words.count != 1 else { return false }
        let characters = Array(candidate.text)
        let boundaries: [Int]
        if candidate.words.count > 1, candidate.words.map(\.text).joined() == candidate.text {
            boundaries = Array(candidate.words.dropLast().reduce(into: [Int]()) { $0.append(($0.last ?? 0) + $1.text.count) })
        } else {
            boundaries = Array(characters.indices.dropFirst())
        }
        return boundaries.contains { isFragmentBoundary(characters, at: $0) }
    }

    /// characters[boundary] の前で，促音の切れ端が漢字とつながっているか
    private static func isFragmentBoundary(_ characters: [Character], at boundary: Int) -> Bool {
        guard boundary >= 1, boundary < characters.count, isKanji(characters[boundary]) else { return false }
        let tsu = characters[boundary - 1]
        guard isSmallTsu(tsu) else { return false }
        guard boundary >= 2 else { return true }
        let before = characters[boundary - 2]
        // 漢字のあとのカタカナの「ッ」(良ッ書)は崩れている．漢字のあとのひらがなの「っ」は動詞の活用(引っ＋越し)なので見ない
        if isKanji(before) { return tsu == "ッ" }
        guard isKana(before) else { return false }
        // 促音の前のかなの並び．漢字のすぐ後なら送りがな(開けっ＋放し)なので当たらない
        var start = boundary - 2
        while start > 0, isKana(characters[start - 1]) { start -= 1 }
        guard start == 0 || !isKanji(characters[start - 1]) else { return false }
        return !emphaticPrefixes.contains(String(characters[start..<boundary]))
    }

    /// 2 番目から後ろの除く候補を除き，下げる候補を，後ろにある同じ読みの数の下げない候補のうち最後のもののすぐ下へ移す．
    /// 下げる候補どうしの順と，ほかの候補の順は変えない
    public static func cleaned(_ candidates: [Candidate]) -> [Candidate] {
        guard let first = candidates.first else { return [] }
        let rest = candidates.dropFirst().filter { !isBroken($0) }
        let fragmented = rest.map(isFragmented)
        // 読みの数ごとの，下げない候補のうち最後のものの位置
        var lastClean: [Int: Int] = [:]
        for (index, candidate) in rest.enumerated() where !fragmented[index] { lastClean[candidate.readingCount] = index }
        var result = [first]
        var deferred: [Int: [Candidate]] = [:]
        for (index, candidate) in rest.enumerated() {
            if fragmented[index], let last = lastClean[candidate.readingCount], last > index {
                deferred[candidate.readingCount, default: []].append(candidate)
                continue
            }
            result.append(candidate)
            if !fragmented[index], lastClean[candidate.readingCount] == index {
                result += deferred.removeValue(forKey: candidate.readingCount) ?? []
            }
        }
        return result
    }

    /// エンジンが語をつないで作った候補か(記号・ユーザー辞書の語・字種の変換などは見ない)
    private static func isEngineText(_ candidate: Candidate) -> Bool {
        switch candidate.origin {
        case .engine, .combined, .sentencePart: true
        default: false
        }
    }

    private static func isSmallTsu(_ character: Character) -> Bool { character == "っ" || character == "ッ" }

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
