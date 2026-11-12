/// 候補の語の並びから，読みの一部の範囲に当たる文字を切り出す．
///
/// 文全体や前後の語を含めた変換の候補から，ある文節の読みの範囲がどの字になったかを取り出し，
/// その文節の候補を前後のつながりで並べるのに使う(SegmentContextRanker)
public enum CandidateSpan {
    /// candidate の読み(reading)のうち range に当たる文字．語の並びが読み全体を覆わなければ nil．
    /// 範囲の端が語の途中にあるときは，端より外の部分がその語の頭(または尻)にかなのまま付いていれば切る
    /// (辞書の「を書こう」の「を」，「加工し」の「し」)．かなのまま付いていなければ切れないので nil
    public static func text(of candidate: Candidate, in range: Range<Int>, reading: String) -> String? {
        let characters = Array(reading)
        guard range.lowerBound >= 0, range.upperBound <= characters.count, !range.isEmpty,
              candidate.words.reduce(0, { $0 + $1.readingCount }) == characters.count else { return nil }
        var result = ""
        var position = 0
        for word in candidate.words {
            let wordRange = position..<(position + word.readingCount)
            position = wordRange.upperBound
            guard wordRange.overlaps(range) else { continue }
            var text = Substring(word.text)
            if wordRange.lowerBound < range.lowerBound {
                let head = String(characters[wordRange.lowerBound..<range.lowerBound])
                guard text.hasPrefix(head) else { return nil }
                text = text.dropFirst(head.count)
            }
            if wordRange.upperBound > range.upperBound {
                let tail = String(characters[range.upperBound..<wordRange.upperBound])
                guard text.hasSuffix(tail) else { return nil }
                text = text.dropLast(tail.count)
            }
            result += text
        }
        return result.isEmpty ? nil : result
    }

    /// text が reading を変換した字として食い違わないか．text のかな(カタカナはひらがなにして比べる)は読みのその位置にそのまま
    /// 現れ，かなでない字(漢字・英字・数字など)の並びは読みの 1 文字以上に当たる，と見て合わせられれば true．
    /// 打ち間違いを直した候補(読みが違う「かく」の候補)を，文節の候補に混ぜないために使う
    public static func isConsistent(_ text: String, with reading: String) -> Bool {
        let readingCharacters = Array(KanaWidth.hiragana(from: reading))
        // かなの並び(文字列)と，かなでない字の並び(nil)を交互に並べる
        var pieces: [[Character]?] = []
        for character in KanaWidth.hiragana(from: text) {
            if isKana(character) {
                if case .some(.some(var run)) = pieces.last {
                    run.append(character)
                    pieces[pieces.count - 1] = run
                } else {
                    pieces.append([character])
                }
            } else if pieces.last.map({ $0 != nil }) ?? true {
                pieces.append(nil)
            }
        }
        // 読みの position から pieces[index...] を当てはめられるか
        var memo: [Int: Bool] = [:]
        func matches(_ index: Int, _ position: Int) -> Bool {
            let key = index * (readingCharacters.count + 1) + position
            if let known = memo[key] { return known }
            let result: Bool
            if index == pieces.count {
                result = position == readingCharacters.count
            } else if let run = pieces[index] {
                let end = position + run.count
                result = end <= readingCharacters.count && Array(readingCharacters[position..<end]) == run && matches(index + 1, end)
            } else {
                result = position < readingCharacters.count
                    && ((position + 1)...readingCharacters.count).contains { matches(index + 1, $0) }
            }
            memo[key] = result
            return result
        }
        return matches(0, 0)
    }

    /// 読みのとおりに書くかなか(長音「ー」を含む)．「ヶ」(が・か と読む)と踊り字「ゝ」「ゞ」は読みのとおりでないので含めない
    private static func isKana(_ character: Character) -> Bool {
        character == "ー" || (!"ゕゖゝゞ".contains(character) && character.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) })
    }
}
