import HajimeDomain

/// 変換中の候補の選択(表記)と文節の区切りの変更を，取り消せるように覚える(KeymapCommand.undoConversionEdit)．
///
/// 変える前の状態を段にして積み，取り消すと最後の段に戻す．段の数は depth まで(古い段から捨てる)．
/// 続けて同じ種類の変更をしたとき(Space の連打，同じ字種のキーの連打，文節の長さを続けて変える)は 1 段にまとめ，
/// 取り消すとその続きを始める前に戻す．文節を移るなど変更でないキーを挟むと，まとまりは切れる
struct ConversionHistory<Snapshot> {
    /// 続けて行うと 1 段にまとめる変更
    struct Run: Equatable {
        enum Kind: Equatable {
            /// 候補を送る(次・前の候補，ページ，先頭・末尾の候補)
            case candidate
            /// 文節の長さを変える
            case resize
            /// 字種を変える．同じコマンドの連打だけをまとめる
            case script(KeymapCommand)
        }

        var kind: Kind
        /// 変えた文節の位置．ほかの文節の変更とはまとめない
        var segment: Int

        /// コマンドの変更のまとまり．まとめないコマンドなら nil
        init?(_ command: KeymapCommand?, segment: Int) {
            switch command {
            case .nextCandidate, .previousCandidate, .nextCandidatePage, .previousCandidatePage, .firstCandidate, .lastCandidate:
                kind = .candidate
            case .extendSegment, .shrinkSegment, .extendSegmentToWord, .shrinkSegmentToWord:
                kind = .resize
            case let command? where command.group == .scripts:
                kind = .script(command)
            default:
                return nil
            }
            self.segment = segment
        }
    }

    private(set) var steps: [Snapshot] = []
    private var lastRun: Run?
    private let depth: Int

    init(depth: Int) {
        self.depth = max(depth, 0)
    }

    /// 変更を覚える．before は変える前の状態．run が直前の変更と同じまとまりなら段を増やさない
    mutating func record(before: Snapshot, run: Run?) {
        defer { lastRun = run }
        if let run, run == lastRun { return }
        steps.append(before)
        if steps.count > depth { steps.removeFirst(steps.count - depth) }
    }

    /// 最後の段を捨てる(続けた変更で元に戻り，取り消しても何も変わらない段)．続けて押した変更のまとまりも切る
    mutating func discardLatest() {
        _ = steps.popLast()
        lastRun = nil
    }

    /// 変更でないキーを押した．続けて押した変更のまとまりを切る
    mutating func breakRun() {
        lastRun = nil
    }

    /// 最後の段を取り出す．無ければ nil
    mutating func undo() -> Snapshot? {
        lastRun = nil
        return steps.popLast()
    }

    mutating func clear() {
        steps = []
        lastRun = nil
    }
}

extension ConversionHistory: CustomStringConvertible, CustomDebugStringConvertible {
    // 段は候補(入力内容)を持つので，ログには段の数だけを出す
    var description: String { "ConversionHistory(steps: \(steps.count))" }
    var debugDescription: String { description }
}
