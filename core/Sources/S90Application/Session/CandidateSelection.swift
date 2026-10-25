import S90Domain

/// 候補を一覧から選んでいるときの状態．候補と添え書きと，今どこを選んでいるか．
struct CandidateSelection: Equatable {
    var candidates: [Candidate]
    var annotations: [String?]
    var focus: Focus

    enum Focus: Equatable {
        case candidate(Int)
        case variant(ScriptVariant)
    }
}

extension CandidateSelection {
    /// 候補を送る(端では反対の端に戻る)．種類の行にいるときは候補の先頭に戻る
    mutating func moveCandidate(by offset: Int) {
        guard case .candidate(let index) = focus, !candidates.isEmpty else {
            focus = .candidate(0)
            return
        }
        let count = candidates.count
        focus = .candidate(((index + offset) % count + count) % count)
    }
}
