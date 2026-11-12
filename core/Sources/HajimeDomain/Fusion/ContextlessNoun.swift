/// 左の文脈が無いときに，1 語の名詞の読みの第 1 候補を漢字にする規則．
///
/// Zenzai は左の文脈が無いと，短い読みをかなのまま写すほうを高く採点する(いえ → いえ，はし → はし，て → て)．
/// 入力欄の頭で名詞を 1 語だけ打つと，Zenzai を使わない変換では漢字が先なのに，かなが第 1 候補になる．
/// - 当てるのは，第 1 候補が読みのかなそのままで，Zenzai を使わない変換の第 1 候補が漢字を含む 1 つの一般名詞のときだけ
/// - その名詞を先頭に移し，かなの候補はすぐ後ろに置く．ほかの候補の順は変えない
/// - ありがとう・こんにちは・たぶん のような名詞でない語や，Zenzai を使わない変換でもかなが先の語は変えない．
///   Zenzai を使わない変換は学習を使うので，かなを選び続けた語も変えない
public enum ContextlessNoun {
    /// - Parameters:
    ///   - candidates: 読み全体の候補(Zenzai の候補．よさそうな順)
    ///   - reading: 読み(ひらがな)
    ///   - plain: Zenzai を使わない変換の第 1 候補．当てるときだけ求めるので，閉包で渡す
    public static func reordered(_ candidates: [Candidate], reading: String, plain: () -> Candidate?) -> [Candidate] {
        guard let first = candidates.first, first.text == reading, first.readingCount == reading.count,
              let noun = plain(), isNoun(noun, reading: reading) else { return candidates }
        var result = candidates
        if let index = result.firstIndex(where: { $0.text == noun.text && $0.readingCount == reading.count }) {
            result.insert(result.remove(at: index), at: 0)
        } else {
            result.insert(noun, at: 0)
        }
        return result
    }

    /// 読み全体を 1 語で置き換える，漢字を含む一般名詞か
    private static func isNoun(_ candidate: Candidate, reading: String) -> Bool {
        guard candidate.readingCount == reading.count, candidate.words.count == 1, let word = candidate.words.first,
              word.isCommonNoun, word.text == candidate.text else { return false }
        return candidate.text.unicodeScalars.contains { $0.properties.isIdeographic }
    }
}
