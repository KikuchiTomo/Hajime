import HajimeDomain

/// 候補を一覧から選んでいるときの状態．候補と添え書きと，今どこを選んでいるか．
struct CandidateSelection: Equatable {
    var candidates: [Candidate]
    var annotations: [String?]
    var focus: Focus
    /// 候補の頭の，一覧に出さない字(打っているあいだに最後の文節だけを選ぶときの，前の文節)．一覧には残りだけを出す
    var shownPrefix = ""

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

/// 打っているあいだに最後の文節だけの候補を出すときの，その前の文節(見えているライブ変換の字と，読みの字数)
struct SuggestionPrefix: Equatable {
    var text: String
    var readingCount: Int

    /// 前の文節と文節の候補をつないだ，読み全体の候補．確定したら文節の候補を学ぶ
    func joined(with candidate: Candidate, readingCount whole: Int) -> Candidate {
        var joined = Candidate(text: text + candidate.text, readingCount: whole, origin: .combined)
        joined.learnedParts = candidate.isFromEngine ? [candidate] : candidate.learnedParts
        return joined
    }
}
