import S90Domain

/// かな漢字変換のポート．入力欄ごとに 1 つ作る(変換の途中の状態を入力欄ごとに分けるため)．
///
/// 変換エンジン(AzooKeyKanaKanjiConverter)はスレッドセーフではないので，メインスレッドだけで呼ぶ．
/// Zenzai のような重い変換を入れるときは，ここを非同期にする ADR を書く．
@MainActor
public protocol KanaKanjiConverting: AnyObject {
    /// 読み全体の候補と，読みの先頭の一部だけの候補を，よさそうな順に返す
    func candidates(for reading: String) -> [Candidate]
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
