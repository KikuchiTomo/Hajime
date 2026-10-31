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
        /// 候補をまだ求めていないか．Space ですぐ分岐図を出すため，見えている文字(幹)だけを持たせ，候補はあとから求める
        public var isPending: Bool

        public init(readingStart: Int, readingLength: Int, candidates: [Candidate], variants: [Candidate] = [], choice: Choice = .candidate(0), isConfident: Bool,
                    isDecided: Bool = false, confidenceGap: Double = .infinity, isPending: Bool = false) {
            self.confidenceGap = confidenceGap
            self.isPending = isPending
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

    /// 注目を隣の文節へ移す．端では止まる．wraps なら端を越えて反対の端へ移る(moveToUncertain と同じ)
    public mutating func moveFocus(by offset: Int, wraps: Bool = false) {
        guard !segments.isEmpty else { return }
        focusedIndex = wraps
            ? ((focusedIndex + offset) % segments.count + segments.count) % segments.count
            : min(max(focusedIndex + offset, 0), segments.count - 1)
    }

    /// 迷う文節(確信度の低い文節)へ注目を移す．端を越えたら反対の端から探す．
    /// ほかに迷う文節が無ければ，隣の文節へ移る(端では反対の端へ)．Tab を押しても動かないと，次の文節に移れなくなるため
    public mutating func moveToUncertain(forward: Bool) {
        let count = segments.count
        guard count > 1 else { return }
        for step in 1..<count {
            let index = ((focusedIndex + (forward ? step : -step)) % count + count) % count
            if !segments[index].isConfident {
                focusedIndex = index
                return
            }
        }
        focusedIndex = ((focusedIndex + (forward ? 1 : -1)) % count + count) % count
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
    /// entersVariants が false なら上の枝(字種)には移らない(設定で字種の行を出さないとき)
    public mutating func moveSelection(by offset: Int, entersVariants: Bool = true) {
        var segment = segments[focusedIndex]
        guard !segment.candidates.isEmpty else { return }
        var next = segment.axisPosition + offset
        if next >= segment.candidates.count { next = 0 }
        next = max(next, entersVariants ? -segment.variants.count : 0)
        segment.setAxisPosition(next)
        segment.isDecided = segment.isDecided || offset != 0
        segments[focusedIndex] = segment
    }

    /// 注目している文節の変換の候補を，perPage 件ずつのページで前後に送る．ページの先頭の候補を選ぶ．
    /// 端を越えたら反対の端のページに戻る．字種(上の枝)にいるときは候補の先頭のページから数える
    public mutating func moveToPage(by offset: Int, perPage: Int) {
        let count = segments[focusedIndex].candidates.count
        guard count > 0, perPage > 0 else { return }
        let current: Int = if case .candidate(let value) = segments[focusedIndex].choice { value } else { 0 }
        let pages = (count + perPage - 1) / perPage
        let page = ((current / perPage + offset) % pages + pages) % pages
        selectCandidate(at: page * perPage)
    }

    /// 注目している文節の変換の候補を位置で選ぶ．範囲の外なら端に収める
    public mutating func selectCandidate(at index: Int) {
        let count = segments[focusedIndex].candidates.count
        guard count > 0 else { return }
        segments[focusedIndex].choice = .candidate(min(max(index, 0), count - 1))
        segments[focusedIndex].isDecided = true
    }

    /// 注目している文節の変換の候補を番号で選ぶ．番号は今見えているページの中の順番(perPage 件ずつのページ)．範囲の外なら false
    public mutating func select(number: Int, perPage: Int = DefaultSettings.latticeCandidatesPerSegment) -> Bool {
        let current: Int = if case .candidate(let value) = segments[focusedIndex].choice { value } else { 0 }
        let index = current / perPage * perPage + number - 1
        guard segments[focusedIndex].candidates.indices.contains(index) else { return false }
        segments[focusedIndex].choice = .candidate(index)
        segments[focusedIndex].isDecided = true
        return true
    }

    /// 注目している文節の字種(上の枝)を位置で選ぶ．位置は幹に近いものから 0．範囲の外なら false
    public mutating func selectVariant(at index: Int) -> Bool {
        guard segments[focusedIndex].variants.indices.contains(index) else { return false }
        segments[focusedIndex].choice = .variant(index)
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
    /// 文節ごとの一覧．文節は分岐図と同じに分け，注目している文節の候補を縦に並べる．操作は分岐図と同じ
    case segmentList
    /// 文全体の候補の一覧
    case list

    /// Space で読みを文節に分けて変換するか(分岐図と文節ごとの一覧)
    public var segmentsReading: Bool { self != .list }
}

extension CandidatePresentation: Codable {
    /// 古いバージョンが保存した「文節格子(lattice)」など，今は無い値は分岐図として読む
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CandidatePresentation(rawValue: raw) ?? .automatic
    }
}
