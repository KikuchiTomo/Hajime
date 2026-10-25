import S90Domain

/// かな漢字変換のポート．入力欄ごとに 1 つ作る(変換の途中の状態を入力欄ごとに分けるため)．
///
/// 変換エンジン(AzooKeyKanaKanjiConverter)はスレッドセーフではないので，メインスレッドだけで呼ぶ．
/// Zenzai のような重い変換を入れるときは，ここを非同期にする ADR を書く．
@MainActor
public protocol KanaKanjiConverting: AnyObject {
    /// 読み全体の候補と，読みの先頭の一部だけの候補を，よさそうな順に返す
    func candidates(for reading: String) -> [Candidate]
    /// 読みの先頭の文節の候補だけを，よさそうな順に返す(文節格子に使う)
    func clauseCandidates(for reading: String) -> [Candidate]
    /// 読みとしてのもっともらしさ(大きいほどよい)．候補を作らずに点数だけを求める軽い変換で計る．
    /// 「nn」のあとの母音をどう読むかを比べるのに使う(NasalReadingResolver)
    func plausibility(of reading: String) -> Double
    /// 打ったキーの打ち間違いを直した読みの候補を，よさそうな順に返す(「ようですね」→「よいですね」)．
    /// 文脈を見る変換(Zenzai)が無ければ空．重いので 1 キーごとには呼ばない
    func typoCorrections(forKeys keys: String) -> [ReadingCorrection]
    /// 入力位置の前にある文字列(左の文脈)を伝える．文脈を使えるエンジン(Zenzai)が変換の手がかりにする
    func setLeftContext(_ text: String?)
    /// 候補を確定したことを伝える．学習に使う
    func didCommit(_ candidate: Candidate)
    /// 入力を最後まで確定した，または取り消した
    func endComposition()
}

/// 英単語の辞書のポート(R-02)．中身は端末の中だけで調べる
@MainActor
public protocol EnglishLexicon: AnyObject {
    func isWord(_ text: String) -> Bool
    /// 綴りを誤った単語に近い単語を，よさそうな順に返す
    func suggestions(for text: String) -> [String]
}

@MainActor
public protocol SettingsReading: AnyObject {
    var current: Settings { get }
}

@MainActor
public protocol SettingsStoring: SettingsReading {
    func update(_ change: (inout Settings) -> Void) throws
}

/// 今の日時と，今日からずらした日を返すポート．日付の候補(DateExpressions)に使う
@MainActor
public protocol CalendarReading: AnyObject {
    func now() -> CalendarDate
    func day(offsetFromToday offset: Int) -> CalendarDate
}

/// 使い方の記録を受け取るポート．回数だけを数え，入力した文字列は渡さない
@MainActor
public protocol UsageRecording: AnyObject {
    func record(_ event: UsageEvent)
}
