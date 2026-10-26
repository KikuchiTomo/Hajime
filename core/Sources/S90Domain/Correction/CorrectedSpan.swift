/// 打ち間違いを直した部分が，変換した文のどこに当たるか(R-02)．
///
/// 文全体に補正の印を付けると，どこを直したのかが分からない．そこで，直す前と後の読みを比べて変わった部分を求め，
/// 変換した文を語(または文節)に分けたうち，その部分にかかるものだけに印を付ける．
/// 読みの位置と文の位置の対応は，変換の候補が持つ語ごとの読みの長さ(Candidate.Word.readingCount)から取る
public enum CorrectedSpan {
    /// 文を分けたひとつ
    public struct Piece: Sendable, Equatable {
        public var text: String
        /// 直した部分にかかるか
        public var isCorrected: Bool

        public init(_ text: String, isCorrected: Bool) {
            self.text = text
            self.isCorrected = isCorrected
        }
    }

    /// 文を読みの順に分けるときのひとつ(語か文節)
    public struct Unit: Sendable, Equatable {
        public var text: String
        public var readingCount: Int

        public init(text: String, readingCount: Int) {
            self.text = text
            self.readingCount = readingCount
        }
    }

    /// 直した読み(corrected)のうち，別の読み(other．打ったままの読みなど)と違う部分．読みの先頭からの文字数の範囲．
    /// 前と後ろから同じ文字をたどり，残った部分を変わった部分とする．文字を消しただけの直し(こおんにちは → こんにちは)は，
    /// 消した位置の次の 1 文字にする(範囲を空にしない)．読みが同じなら nil
    public static func changedRange(from other: String, to corrected: String) -> Range<Int>? {
        guard other != corrected, !corrected.isEmpty else { return nil }
        let before = Array(other), after = Array(corrected)
        let prefix = zip(before, after).prefix { $0 == $1 }.count
        let suffix = zip(before.reversed(), after.reversed()).prefix { $0 == $1 }.count
        let common = min(suffix, min(before.count, after.count) - prefix)
        // 末尾の文字を消しただけなら，消した位置の前の 1 文字にする
        let start = min(prefix, after.count - 1)
        let end = max(after.count - common, start + 1)
        return start..<end
    }

    /// 文(text)を units に分け，changed にかかる単位とそうでない単位に分ける．隣り合う同じ種類はまとめる．
    /// 単位の読みの長さの合計が readingCount と合わない，または単位の文字をつなげて text にならないときは nil(対応が取れない)
    public static func pieces(of text: String, units: [Unit], readingCount: Int, changed: Range<Int>) -> [Piece]? {
        guard !units.isEmpty, units.reduce(0, { $0 + $1.readingCount }) == readingCount,
            units.map(\.text).joined() == text else { return nil }
        var result: [Piece] = []
        var position = 0
        for unit in units {
            let range = position..<(position + unit.readingCount)
            position = range.upperBound
            let isCorrected = range.overlaps(changed) || (unit.readingCount == 0 && changed.contains(range.lowerBound))
            append(Piece(unit.text, isCorrected: isCorrected), to: &result)
        }
        return result
    }

    /// 候補(読みの先頭から candidate.readingCount 文字を変換したもの)を，changed にかかる部分とそうでない部分に分ける．
    /// 候補が読みのかなそのものなら 1 文字ずつ対応させ，そうでなければ候補の語の並び(Candidate.words)で対応させる．
    /// 辞書の語は助詞と次の語をつないでいることがある(「は良い」)ので，語の中の文節の切れ目でも分ける(ClauseSplitter.pieces)．
    /// 対応が取れなければ，候補が changed にかかるかどうかで全体を 1 つにする
    public static func pieces(of candidate: Candidate, reading: String, changed: Range<Int>) -> [Piece] {
        let slice = String(reading.prefix(candidate.readingCount))
        let units = candidate.text == slice
            ? slice.map { Unit(text: String($0), readingCount: 1) }
            : ClauseSplitter.pieces(of: candidate.words).map { Unit(text: $0.text, readingCount: $0.readingCount) }
        if let pieces = pieces(of: candidate.text, units: units, readingCount: candidate.readingCount, changed: changed) {
            return pieces
        }
        let overlaps = (0..<candidate.readingCount).overlaps(changed)
        return candidate.text.isEmpty ? [] : [Piece(candidate.text, isCorrected: overlaps)]
    }

    /// pieces を，実際に見せる文字(shown)に合わせる．ライブ変換は打っている途中の末尾の語をかなのまま見せるので，
    /// 文と見せる文字は末尾が違うことがある．先頭から一致する部分の分け方は残し，違う部分から後ろは 1 つにまとめる
    public static func aligning(_ pieces: [Piece], to shown: String) -> [Piece] {
        let text = pieces.map(\.text).joined()
        guard text != shown else { return pieces }
        let same = zip(text, shown).prefix { $0 == $1 }.count
        var result: [Piece] = []
        var position = 0
        var restCorrected = false
        for piece in pieces {
            let end = position + piece.text.count
            if end <= same {
                append(piece, to: &result)
            } else {
                restCorrected = restCorrected || piece.isCorrected
                if position < same { append(Piece(String(piece.text.prefix(same - position)), isCorrected: piece.isCorrected), to: &result) }
            }
            position = end
        }
        append(Piece(String(shown.dropFirst(same)), isCorrected: restCorrected), to: &result)
        return result
    }

    /// 文の中の直した部分(文字の位置の範囲)．直した部分が 1 か所にまとまらないとき(間に直していない語がある)は，最初から最後までにする
    public static func textRange(of pieces: [Piece]) -> Range<Int>? {
        var position = 0
        var first: Int?
        var last: Int?
        for piece in pieces {
            if piece.isCorrected {
                first = first ?? position
                last = position + piece.text.count
            }
            position += piece.text.count
        }
        guard let first, let last, first < last else { return nil }
        return first..<last
    }

    private static func append(_ piece: Piece, to pieces: inout [Piece]) {
        guard !piece.text.isEmpty else { return }
        if let last = pieces.last, last.isCorrected == piece.isCorrected {
            pieces[pieces.count - 1].text += piece.text
        } else {
            pieces.append(piece)
        }
    }
}
