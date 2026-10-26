import Foundation
import S90Domain

/// かな漢字変換のポート．入力欄ごとに 1 つ作る(変換の途中の状態を入力欄ごとに分けるため)．
///
/// 変換エンジン(AzooKeyKanaKanjiConverter)はスレッドセーフではないので，メインスレッドだけで呼ぶ．
/// Zenzai のような重い変換を入れるときは，ここを非同期にする ADR を書く．
/// 打ち間違いの訂正を，入力を処理するスレッドとは別に求める(R-02)．
/// 訂正は 1 文に 1 秒ほどかかることがあるので，打鍵を止めないよう別の変換器で求め，結果をあとから渡す
public protocol TypoCorrecting: Sendable {
    /// キーの並びごとの訂正の候補(よさそうな順)
    func corrections(forKeys keys: [String], leftContext: String?) async -> [String: [ReadingCorrection]]
}

@MainActor
public protocol KanaKanjiConverting: AnyObject {
    /// 読み全体の候補と，読みの先頭の一部だけの候補を，よさそうな順に返す
    func candidates(for reading: String) -> [Candidate]
    /// 読みの先頭の文節の候補だけを，よさそうな順に返す(文節格子に使う)
    func clauseCandidates(for reading: String) -> [Candidate]
    /// 打っている読みに続く語の予測(入力中の候補)．読み全体を置き換える候補として返す
    func predictions(for reading: String) -> [Candidate]
    /// 読みとしてのもっともらしさ(大きいほどよい)．候補を作らずに点数だけを求める軽い変換で計る．
    /// 「nn」のあとの母音をどう読むかを比べるのに使う(NasalReadingResolver)
    func plausibility(of reading: String) -> Double
    /// 読み全体を Zenzai を使わずに変換したときの語の並び．文節の区切りを決めるのに使う(ClauseSplitter)．
    /// Zenzai が書き換えた候補は語の区切りを持たないことがあるので，区切りはこちらで決める
    func segmentationWords(for reading: String) -> [Candidate.Word]
    /// 打ったキーの打ち間違いを直した読みの候補を，よさそうな順に返す(「ようですね」→「よいですね」)．
    /// 文脈を見る変換(Zenzai)が無ければ空．重いので 1 キーごとには呼ばない
    func typoCorrections(forKeys keys: String) -> [ReadingCorrection]
    /// キーの並びをそのまま読んだときの，文脈を見る言語モデル(Zenzai)の点数．並びごとに返し，使えなければ nil
    func languageModelScores(forKeys keys: [String]) -> [Double?]
    /// 入力位置の前にある文字列(左の文脈)を伝える．文脈を使えるエンジン(Zenzai)が変換の手がかりにする
    func setLeftContext(_ text: String?)
    /// 候補を確定したことを伝える．学習に使う
    func didCommit(_ candidate: Candidate)
    /// 入力を最後まで確定した，または取り消した．学習を使わない変換(suspendLearningUntilEnd)もここで終える
    func endComposition()
    /// 候補を学習から消す(キー設定の表の「学習から消す」．R-17)
    func forget(_ candidate: Candidate)
    /// 最後に終えた入力で確定した語の学習を取り消す．取り消すものがあれば true
    func forgetLastCommit() -> Bool
    /// 今の入力を終えるまで，学習を使わずに変換し，確定しても学ばない(キー設定の表の「学習を使わずに変換」)
    func suspendLearningUntilEnd()
    /// 取り込んだ辞書から引いた語を渡す(R-16)．エンジンは読みの中の語として使う．同じものが続くときは何もしなくてよい
    func setAuxiliaryWords(_ words: [AuxiliaryWord])
    /// 入力先のアプリ(バンドル ID)を伝える．アプリの条件の辞書を選ぶのに使う
    func setApplication(_ identifier: String?)
    /// 候補がどの取り込んだ辞書の語か(分岐図に小さく出す)．取り込んだ辞書の語でなければ nil
    func sourceName(of text: String, reading: String) -> String?
}

extension KanaKanjiConverting {
    public func predictions(for reading: String) -> [Candidate] { [] }
    public func setAuxiliaryWords(_ words: [AuxiliaryWord]) {}
    public func setApplication(_ identifier: String?) {}
    public func sourceName(of text: String, reading: String) -> String? { nil }
}

/// エンジンに渡す，取り込んだ辞書の語．costOffset は語の点数に足す値(優先度)
public struct AuxiliaryWord: Sendable, Equatable, Hashable {
    public var word: DictionaryWord
    public var costOffset: Float

    public init(word: DictionaryWord, costOffset: Float) {
        self.word = word
        self.costOffset = costOffset
    }
}

/// 取り込んだ辞書を読みで引く(R-16)
@MainActor
public protocol DictionaryLookup: AnyObject {
    /// 読みがちょうど reading の語
    func words(reading: String, in dictionary: ImportedDictionary) -> [DictionaryWord]
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

/// 設定が変わったことを知らせるポート．エンジンや設定の画面を新しい設定に合わせるのに使う
@MainActor
public protocol SettingsObserving: AnyObject {
    func observe(_ handler: @escaping (Settings) -> Void)
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

/// 記録した回数を読むポート(設定の画面で見せる)
@MainActor
public protocol UsageReading: AnyObject {
    var counts: UsageCounts { get }
    func reset()
}

/// 郵便番号から住所を引くポート(R-13)．表は端末の中にあり，通信しない
@MainActor
public protocol PostalCodeLooking: AnyObject {
    /// 7 桁の郵便番号の住所．無ければ空
    func addresses(for code: String) -> [String]
}

/// 手書きの線から文字を探すポート(R-14)．端末の中だけで認識し，通信しない
public protocol HandwritingRecognizing: Sendable {
    /// 線(点の並び．左上が原点)を認識して，よさそうな順に文字列を返す
    func recognize(strokes: [[Point]], canvasSize: Size) async -> [String]
}

/// 同期のファイルの置き場所(R-15)．最初の実装は利用者が選んだフォルダ(FolderSyncBackend)．
/// Google Drive・Dropbox の API で読み書きする実装も，この形で足せるようにする(今は通信しない)
public protocol SyncBackend: Sendable {
    /// 同期のファイルの中身．まだ無ければ nil
    func read() throws -> Data?
    func write(_ data: Data) throws
}

/// この Mac の同期の設定(フォルダ・範囲・記録)の保存先
@MainActor
public protocol SyncStateStoring: AnyObject {
    var state: SyncState { get }
    func save(_ state: SyncState) throws
}

/// この Mac の同期の設定．同期のファイルには入れない
public struct SyncState: Sendable, Equatable, Codable {
    public var isEnabled = false
    /// 選んだフォルダ(セキュリティスコープ付きのブックマーク)．フォルダを選んでいなければ nil
    public var folderBookmark: Data?
    /// 画面に出すフォルダの名前
    public var folderName: String?
    /// まとまりごとの範囲．無いまとまりは既定の範囲(SyncGroup.defaultScope)
    public var scopes: [SyncGroup: SyncScope] = [:]
    /// まとまりを同期していても，この Mac だけで持つ項目(Settings の CodingKeys の名前)
    public var localFields: Set<String> = []
    public var ledger = SyncLedger()

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case isEnabled, folderBookmark, folderName, scopes, localFields, ledger
    }

    /// 項目を足しても前の版で書いたファイルを読めるよう，無い項目は既定のままにする(読めないとフォルダの選択まで失うため)
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        folderBookmark = try container.decodeIfPresent(Data.self, forKey: .folderBookmark)
        folderName = try container.decodeIfPresent(String.self, forKey: .folderName)
        scopes = try container.decodeIfPresent([SyncGroup: SyncScope].self, forKey: .scopes) ?? [:]
        localFields = try container.decodeIfPresent(Set<String>.self, forKey: .localFields) ?? []
        ledger = try container.decodeIfPresent(SyncLedger.self, forKey: .ledger) ?? SyncLedger()
    }

    public func scope(of group: SyncGroup) -> SyncScope { scopes[group] ?? group.defaultScope }
}
