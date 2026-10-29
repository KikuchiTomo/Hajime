import HajimeDomain

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

    /// 候補を perPage 件ずつのページで前後に送り，ページの先頭を選ぶ(端では反対の端のページに戻る)
    mutating func movePage(by offset: Int, perPage: Int) {
        guard !candidates.isEmpty, perPage > 0 else { return }
        let index: Int = if case .candidate(let value) = focus { value } else { 0 }
        let pages = (candidates.count + perPage - 1) / perPage
        let page = ((index / perPage + offset) % pages + pages) % pages
        focus = .candidate(page * perPage)
    }
}
