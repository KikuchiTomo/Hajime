import S90Domain

/// 打ち間違いの見直しの結果を記録するための要約．補正が出ないときに，求めなかったのか・時間切れか・直さないと決めたのかを実機で見分ける．
/// 打った文字・読み・候補は含めず，結果の種類と数と時間だけを持つ(docs/dev/SECURITY-MODEL.md)
public enum CorrectionReport {
    /// 見直しの結果の文．直したか(補正の下線)・示したか(「もしかして」)・どちらでもないか，求めた並びと候補の数，かかった時間
    public static func outcome(_ label: String, corrections: [String: [ReadingCorrection]], actions: [ClientAction], milliseconds: Int) -> String {
        let corrected = actions.contains { if case .setMarkedText(let text) = $0 { text.segments.contains { $0.style == .correction } } else { false } }
        let suggested = actions.contains { if case .showNote(let note) = $0 { note.tone == .suggestion } else { false } }
        let result = corrected ? "直した" : suggested ? "示した" : "直さない"
        let candidates = corrections.values.reduce(0) { $0 + $1.count }
        return "\(label): \(result)．並び \(corrections.count) 件・候補 \(candidates) 件・\(milliseconds) ms"
    }

    public static func timedOut(_ label: String, seconds: Double) -> String {
        "\(label): 時間切れ(\(seconds) 秒)"
    }

    public static let unavailable = "見直し: 訂正を求める処理が無い(Zenzai を読み込めていない)"
}
