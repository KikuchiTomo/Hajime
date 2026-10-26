/// 文節格子．変換結果を文節ごとに分け，文節ごとに候補を持つ．
///
/// 文は 1 本の幹で，迷う文節で枝分かれする(分岐図．ADR 0007)．
/// 文節ごとに，下へ伸びる変換の候補(candidates)と，上へ伸びる字種(variants: そのまま・カタカナ・半角カタカナ)を持つ．
/// 上下のキーの向きと枝の向きを合わせるのは，押すキーと選ぶものの位置が対応しているほど速く誤りなく選べるため
/// (刺激と反応の適合性．docs/dev/research/candidate-presentation.md)．
public struct SegmentLattice: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        /// 文節の中で選んでいるもの
        public enum Choice: Sendable, Equatable {
            /// 変換の候補(下の枝)．0 は幹にある第 1 候補
            case candidate(Int)
            /// 字種(上の枝)．0 が幹にいちばん近い
            case variant(Int)
        }

        /// 読みの中での位置(文字数)
        public var readingStart: Int
        public var readingLength: Int
        public var candidates: [Candidate]
        public var variants: [Candidate]
        public var choice: Choice
        /// 第 1 候補が 2 番目より十分よいか．低ければ枝を見せる
        public var isConfident: Bool
        /// 利用者が選び直したか．選び直した文節は，あとで区切りを動かしても変えない(ADR 0007)
        public var isDecided: Bool
        /// 第 1 候補と 2 番目の点数の差．小さいほど変換を誤っている可能性が高い．候補が 1 つなら無限大
        public var confidenceGap: Double

        public init(readingStart: Int, readingLength: Int, candidates: [Candidate], variants: [Candidate] = [], choice: Choice = .candidate(0), isConfident: Bool,
                    isDecided: Bool = false, confidenceGap: Double = .infinity) {
            self.confidenceGap = confidenceGap
            self.readingStart = readingStart
            self.readingLength = readingLength
            self.candidates = candidates
            self.variants = variants
            self.choice = choice
            self.isConfident = isConfident
            self.isDecided = isDecided
        }

        public var selected: Candidate {
            switch choice {
            case .candidate(let index): candidates[index]
            case .variant(let index): variants[index]
            }
        }

        /// 上下の軸での位置．上の枝は負，幹は 0，下の枝は正
        var axisPosition: Int {
            switch choice {
            case .candidate(let index): index
            case .variant(let index): -(index + 1)
            }
        }

        mutating func setAxisPosition(_ position: Int) {
            choice = position >= 0 ? .candidate(position) : .variant(-position - 1)
        }
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

    /// 迷う文節(確信度の低い文節)へ注目を移す．端を越えたら反対の端から探す．迷う文節が無ければ動かない
    public mutating func moveToUncertain(forward: Bool) {
        let count = segments.count
        for step in 1...count {
            let index = ((focusedIndex + (forward ? step : -step)) % count + count) % count
            if !segments[index].isConfident {
                focusedIndex = index
                return
            }
        }
    }

    /// 入力位置にいちばん近い迷う文節．無ければ最後の文節．
    /// 打ち間違いの多くは打った直後に気づかれるので，入力位置の近くから確かめられるようにする(ADR 0007)
    public var initialFocus: Int { initialFocus(.automatic) }

    /// Space で変換したときに最初に選ぶ文節(設定)．
    /// 自動では，打ち間違いや誤変換の可能性がいちばん高い文節(第 1 候補と 2 番目の点数の差がいちばん小さい文節)を選ぶ．
    /// 選んだあとの移り方(Tab など)は設定によらない
    public func initialFocus(_ policy: InitialFocus) -> Int {
        switch policy {
        case .start: return 0
        case .end: return segments.count - 1
        case .automatic:
            return segments.indices.min { segments[$0].confidenceGap < segments[$1].confidenceGap } ?? 0
        }
    }

    /// 注目している文節を上下に送る．下は変換の候補，上は字種．
    /// 下の端では幹に戻り(Space を押し続けると候補を一周する)，上の端では止まる
    public mutating func moveSelection(by offset: Int) {
        var segment = segments[focusedIndex]
        guard !segment.candidates.isEmpty else { return }
        var next = segment.axisPosition + offset
        if next >= segment.candidates.count { next = 0 }
        next = max(next, -segment.variants.count)
        segment.setAxisPosition(next)
        segment.isDecided = segment.isDecided || offset != 0
        segments[focusedIndex] = segment
    }

    /// 注目している文節の変換の候補を番号で選ぶ．範囲の外なら false
    public mutating func select(number: Int) -> Bool {
        let index = number - 1
        guard segments[focusedIndex].candidates.indices.contains(index) else { return false }
        segments[focusedIndex].choice = .candidate(index)
        segments[focusedIndex].isDecided = true
        return true
    }

    /// 2 つの候補の点数の差から確信度を決める．点数は対数尤度で，大きいほどよい
    public static func isConfident(best: Candidate?, second: Candidate?) -> Bool {
        guard let best else { return false }
        guard let second else { return true }
        return best.score - second.score >= DefaultSettings.latticeConfidenceGap
    }
}

extension SegmentLattice.Segment: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "Segment(readingLength: \(readingLength), candidates: \(candidates.count))" }
    public var debugDescription: String { description }
}

extension SegmentLattice: CustomStringConvertible, CustomDebugStringConvertible {
    // 候補は入力内容なので，ログには文節の数だけを出す
    public var description: String { "SegmentLattice(segments: \(segments.count), focused: \(focusedIndex))" }
    public var debugDescription: String { description }
}

/// 候補の出し方
public enum CandidatePresentation: String, Sendable, Equatable, CaseIterable {
    /// 分岐図．英単語を補正しているときだけ一覧
    case automatic
    case list
}

extension CandidatePresentation: Codable {
    /// 古い版が保存した「文節格子(lattice)」など，今は無い値は分岐図として読む
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CandidatePresentation(rawValue: raw) ?? .automatic
    }
}
