import HajimeDomain

/// 「nn」のあとの母音を，「ん+あ行」(hannei → 反映)と「ん+な行」(onna → 女)のどちらで読むかを決める．
///
/// 母音のまわりの数文字だけを両方の読みで変換にかけ，読みとしてもっともらしい方(変換エンジンの対数尤度が高い方)に合わせる．
/// 文全体ではなくまわりだけで比べるのは，1 キーごとに比べ直しても打鍵を待たせないため．
/// 文脈を見る変換(Zenzai)は使わず，候補を作らない軽い変換で比べる(KanaKanjiConverting.plausibility)．
///
/// 変換は短い読みでも 1 回 20ms ほどかかるので，比べるのは母音のあとの文字数が
/// DefaultSettings.nasalEvaluationPoints になったときだけにする(母音を打ったときから 3 文字あとまで)．
/// 1 文字あとで比べるのは，「hannei」の「い」のように，すぐあとの文字で読みが決まる短い語が多いため．
/// それ以外のキーでは前に決めた読みを使う．
///
/// 母音のあとの 3 文字より先で決まる読みもあるので，打ち終えたとき(打鍵が止まったときと，変換・確定の前)に，
/// 前後を広く見て選び直す(resolveSettled)
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

    /// 打ち終えた読みで選び直す(打鍵が止まったときと，変換・確定の前)．打鍵ごとには呼ばない．
    ///
    /// 打っているあいだは母音のあとの 3 文字までしか見ないので，その先で決まる読みを取り違える
    /// (「kousinnonegaisimasu」の「うしんおねがい」と「うしんのねがい」は後者が勝つが，「します」まで見れば「お願いします」)．
    /// 母音の前後を広く(DefaultSettings.nasalSettledContextLength)見て比べ直す．読みを変えたら true
    func resolveSettled(_ composition: inout Composition) -> Bool {
        let before = composition.conversionReading
        for position in composition.nasalAmbiguities.indices {
            let length = DefaultSettings.nasalSettledContextLength
            let vowel = score(composition, position: position, usesNaRow: false, contextLength: length)
            let naRow = score(composition, position: position, usesNaRow: true, contextLength: length)
            composition.setNasalReading(at: position, usesNaRow: naRow > vowel)
            composition.markNasalEvaluated(at: position, followingText: composition.nasalAmbiguities[position].followingText(in: composition.conversionReading))
        }
        return composition.conversionReading != before
    }

    /// 読みを切り替えたときの，母音のまわりの読みのもっともらしさ
    private func score(_ composition: Composition, position: Int, usesNaRow: Bool,
                       contextLength: Int = DefaultSettings.nasalContextLength) -> Double {
        var trial = composition
        trial.setNasalReading(at: position, usesNaRow: usesNaRow)
        let ambiguity = trial.nasalAmbiguities[position]
        let reading = Array(trial.conversionReading)
        let start = max(0, ambiguity.kanaIndex - contextLength)
        let end = min(reading.count, ambiguity.kanaIndex + ambiguity.currentForm.count + contextLength)
        return converter.plausibility(of: String(reading[start..<end]))
    }
}
