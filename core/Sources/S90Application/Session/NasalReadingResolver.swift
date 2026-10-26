import S90Domain

/// 「nn」のあとの母音を，「ん+あ行」(hannei → 反映)と「ん+な行」(onna → 女)のどちらで読むかを決める．
///
/// 母音のまわりの数文字だけを両方の読みで変換にかけ，読みとしてもっともらしい方(変換エンジンの対数尤度が高い方)に合わせる．
/// 文全体ではなくまわりだけで比べるのは，1 キーごとに比べ直しても打鍵を待たせないため．
/// 文脈を見る変換(Zenzai)は使わず，候補を作らない軽い変換で比べる(KanaKanjiConverting.plausibility)．
///
/// 変換は短い読みでも 1 回 20ms ほどかかるので，比べるのは母音のあとの文字数が
/// DefaultSettings.nasalEvaluationPoints になったときだけにする(母音を打ったときから 3 文字あとまで)．
/// 1 文字あとで比べるのは，「hannei」の「い」のように，すぐあとの文字で読みが決まる短い語が多いため．
/// それ以外のキーでは前に決めた読みを使うので，表示と確定する文字は食い違わない
@MainActor
struct NasalReadingResolver {
    let converter: any KanaKanjiConverting

    func resolve(_ composition: inout Composition) {
        let count = composition.nasalAmbiguities.count
        guard count > 0 else { return }
        for position in max(0, count - DefaultSettings.maximumNasalAmbiguities)..<count {
            let ambiguity = composition.nasalAmbiguities[position]
            let following = ambiguity.followingCount(in: composition.conversionReading)
            let followingText = ambiguity.followingText(in: composition.conversionReading)
            // 数が同じでも，打ちかけのローマ字がかなになって文字が変わったら比べ直す(「ふんにk」→「ふんにき」)
            guard DefaultSettings.nasalEvaluationPoints.contains(following),
                ambiguity.evaluatedFollowingText != followingText else { continue }
            let vowel = score(composition, position: position, usesNaRow: false)
            let naRow = score(composition, position: position, usesNaRow: true)
            composition.setNasalReading(at: position, usesNaRow: naRow > vowel)
            composition.markNasalEvaluated(at: position, followingText: followingText)
        }
    }

    /// 読みを切り替えたときの，母音のまわりの読みのもっともらしさ
    private func score(_ composition: Composition, position: Int, usesNaRow: Bool) -> Double {
        var trial = composition
        trial.setNasalReading(at: position, usesNaRow: usesNaRow)
        let ambiguity = trial.nasalAmbiguities[position]
        let reading = Array(trial.conversionReading)
        let start = max(0, ambiguity.kanaIndex - DefaultSettings.nasalContextLength)
        let end = min(reading.count, ambiguity.kanaIndex + ambiguity.currentForm.count + DefaultSettings.nasalContextLength)
        return converter.plausibility(of: String(reading[start..<end]))
    }
}
