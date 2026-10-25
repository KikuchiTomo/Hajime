/// 文節格子．変換結果を文節ごとの列に分け，列ごとに候補を持つ．
///
/// 音声認識の訂正 UI(Parakeet，Speech Repair)を日本語の文節に当てはめたもの．
/// 確信度の低い文節だけ下に候補の列を見せ，誤りのある文節を一度に見つけられるようにする．
/// 根拠と採否は docs/dev/research/candidate-presentation.md の「文節格子」．
public struct SegmentLattice: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        /// 読みの中での位置(文字数)
        public var readingStart: Int
        public var readingLength: Int
        public var candidates: [Candidate]
        public var selectedIndex: Int
        /// 第 1 候補が 2 番目より十分よいか．低ければ候補の列を常に見せる
        public var isConfident: Bool

        public init(readingStart: Int, readingLength: Int, candidates: [Candidate], selectedIndex: Int = 0, isConfident: Bool) {
            self.readingStart = readingStart
            self.readingLength = readingLength
            self.candidates = candidates
            self.selectedIndex = selectedIndex
            self.isConfident = isConfident
        }

        public var selected: Candidate { candidates[selectedIndex] }
    }

    public var segments: [Segment]
    public var focusedIndex: Int

    public init(segments: [Segment], focusedIndex: Int = 0) {
        self.segments = segments
        self.focusedIndex = focusedIndex
    }

    public var focused: Segment { segments[focusedIndex] }
    public var text: String { segments.map(\.selected.text).joined() }

    public mutating func moveFocus(by offset: Int) {
        focusedIndex = min(max(focusedIndex + offset, 0), segments.count - 1)
    }

    /// 注目している文節の候補を送る(端では反対の端に戻る)
    public mutating func moveSelection(by offset: Int) {
        let count = segments[focusedIndex].candidates.count
        guard count > 0 else { return }
        let next = segments[focusedIndex].selectedIndex + offset
        segments[focusedIndex].selectedIndex = ((next % count) + count) % count
    }

    /// 注目している文節の候補を番号で選ぶ．範囲の外なら false
    public mutating func select(number: Int) -> Bool {
        let index = number - 1
        guard segments[focusedIndex].candidates.indices.contains(index) else { return false }
        segments[focusedIndex].selectedIndex = index
        return true
    }

    /// 2 つの候補の点数の差から確信度を決める．点数は対数尤度で，大きいほどよい
    public static func isConfident(best: Candidate?, second: Candidate?) -> Bool {
        guard let best else { return false }
        guard let second else { return true }
        return best.score - second.score >= DefaultSettings.latticeConfidenceGap
    }
}

/// 候補の出し方
public enum CandidatePresentation: String, Sendable, Equatable, Codable, CaseIterable {
    /// 文節が 2 つ以上なら文節格子，1 つなら一覧
    case automatic
    case list
    case lattice
}
