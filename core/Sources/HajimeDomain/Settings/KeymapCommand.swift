/// キー設定の表で，行が効く入力の状態．
///
/// 他の IME のキー設定の状態とは次のように対応する(docs/dev/adr/0009-keymap.md)．
/// - 英数: 直接入力(IME がオフ)
/// - 入力文字なし: 日本語のモードで何も組み立てていない
/// - 入力中: 読みを組み立てている．ライブ変換の表示と「もしかして」の案内もここ
/// - 変換中: 分岐図か候補の一覧で候補を選んでいる．文字種の行もここ
/// - いつでも: 英数・入力文字なし・入力中・変換中のうち，そのコマンドが効く状態すべて
public enum KeymapState: String, Sendable, Hashable, Codable, CaseIterable {
    case anywhere
    case idle
    case composing
    case converting
    case direct

    /// いつでも を除いた，入力の実際の状態
    public static let concrete: [KeymapState] = [.idle, .composing, .converting, .direct]
}

/// キーで行う操作．キー設定の表(Keymap)の 1 行のコマンド．
/// 値の名前は設定のファイルに書くので変えない
public enum KeymapCommand: String, Sendable, Hashable, Codable, CaseIterable {
    // 入力モード
    /// 日本語入力にする
    case japaneseMode
    /// 英数入力にする．組み立て中の文字は確定する
    case directMode
    /// 日本語入力と英数入力を入れ替える
    case toggleMode
    /// 入力方式を順に切り替える(ローマ字 → かな → 英字 → 英字(自動))．英数のときは日本語にしてから切り替える
    case nextInputStyle
    /// 入力方式を決めて切り替える．英数のときは日本語にしてから切り替える
    case romajiStyle
    case kanaStyle
    case englishStyle
    case englishAutoStyle

    // 文字の入力
    /// 空白を入れる．幅は設定(スペース幅)に従う
    case insertSpace
    /// 設定と逆の幅の空白を入れる
    case insertAlternateSpace
    case insertHalfwidthSpace
    case insertFullwidthSpace

    // 入力中
    /// 変換する．英単語を直した直後は，直す前に戻す(R-02，Q-01)
    case convert
    /// 学習を使わずに変換する．この変換で確定した語は学習しない
    case convertWithoutLearning
    /// 左の 1 文字を消す
    case deleteBackward
    /// 打っている途中に，今の位置を文節の区切りにする
    case insertBoundary
    /// 「もしかして」と示した読みに直す
    case acceptSuggestion
    /// 再変換．入力先で選んでいる確定済みの文字を読みに戻し，変換し直す．Esc で元の文字に戻す
    case reconvert

    // 字種
    case toHiragana
    case toKatakana
    case toHalfwidthKatakana
    case toFullwidthAlphanumeric
    case toHalfwidthAlphanumeric
    /// ひらがな → 全角カタカナ → 半角カタカナ → ひらがな と順に変える
    case switchKanaType

    // 候補
    /// 次の候補．入力中なら変換を始める(英単語を直した直後でも戻さない)
    case nextCandidate
    case previousCandidate
    case nextCandidatePage
    case previousCandidatePage
    case firstCandidate
    case lastCandidate
    /// 連想変換．選んでいる文節の語と似た意味・関わりのある語の一覧に切り替える(R-18)．
    /// 入力中なら変換してから切り替える．一覧を出しているときは元の変換に戻す
    case associate

    // 文節
    case nextSegment
    case previousSegment
    case firstSegment
    case lastSegment
    /// 確信の低い次の文節へ移る
    case nextUncertainSegment
    case previousUncertainSegment
    case extendSegment
    case shrinkSegment
    /// 文節の終わりを次の語の切れ目まで延ばす(1 文字ずつの extendSegment より少ない打鍵で長さを変える)
    case extendSegmentToWord
    /// 文節の終わりを前の語の切れ目まで縮める
    case shrinkSegmentToWord
    /// 注目している文節の区切れる位置に番号を出し，数字で区切る
    case splitSegment
    /// 注目している文節を消し，その場で読みを打ち直す．文節を移るキー・Space・Enter で打ち直した読みを変換する
    case editSegment

    // 確定と取り消し
    case commit
    /// 先頭の文節だけを確定し，残りの変換を続ける
    case commitFirstSegment
    /// 取り消す．変換中なら読みに戻し，直した読みは打ったままに戻す．入力中なら読みを捨てる
    case cancel
    /// 組み立て中の文字を捨てて英数入力にする
    case cancelAndDirectMode
    /// 変換をやめて読みに戻る
    case backToReading

    // 学習
    /// 選んでいる候補を学習から消す
    case forgetCandidate
    /// 最後に確定した語の学習を取り消す
    case forgetLastCommit

    // ツール
    /// 設定の画面を開く．入力メニューの操作を IME に取り次がないアプリ(cmux など)でも開けるようにする
    case openSettings
    case toggleLiveConversion
    /// 手書きで文字を探す窓を開く(設定の「手書き入力」がオンのときだけ．R-14)
    case handwriting

    /// 設定の画面でコマンドを並べるまとまり
    public enum Group: String, Sendable, CaseIterable {
        case mode
        case characters
        case composing
        case scripts
        case candidates
        case segments
        case commit
        case learning
        case tools
    }

    public var group: Group {
        switch self {
        case .japaneseMode, .directMode, .toggleMode, .nextInputStyle, .romajiStyle, .kanaStyle, .englishStyle, .englishAutoStyle,
             .cancelAndDirectMode: .mode
        case .insertSpace, .insertAlternateSpace, .insertHalfwidthSpace, .insertFullwidthSpace: .characters
        case .convert, .convertWithoutLearning, .deleteBackward, .insertBoundary, .acceptSuggestion, .reconvert: .composing
        case .toHiragana, .toKatakana, .toHalfwidthKatakana, .toFullwidthAlphanumeric, .toHalfwidthAlphanumeric, .switchKanaType: .scripts
        case .nextCandidate, .previousCandidate, .nextCandidatePage, .previousCandidatePage, .firstCandidate, .lastCandidate, .associate: .candidates
        case .nextSegment, .previousSegment, .firstSegment, .lastSegment, .nextUncertainSegment, .previousUncertainSegment,
             .extendSegment, .shrinkSegment, .extendSegmentToWord, .shrinkSegmentToWord, .splitSegment, .editSegment: .segments
        case .commit, .commitFirstSegment, .cancel, .backToReading: .commit
        case .forgetCandidate, .forgetLastCommit: .learning
        case .openSettings, .toggleLiveConversion, .handwriting: .tools
        }
    }

    /// このコマンドが効く状態(いつでも を含まない)
    public var states: Set<KeymapState> {
        switch self {
        // 設定を開く・ライブ変換・手書きは英数のときも効かせる．ターミナル(cmux など)では英数で打っていることが多く，
        // 入力メニューの操作も取り次がないので，キーが唯一の開き方になる
        case .japaneseMode, .directMode, .toggleMode, .nextInputStyle, .romajiStyle, .kanaStyle, .englishStyle, .englishAutoStyle,
             .openSettings, .toggleLiveConversion, .handwriting:
            [.direct, .idle, .composing, .converting]
        case .cancelAndDirectMode, .insertSpace, .insertAlternateSpace, .insertHalfwidthSpace, .insertFullwidthSpace: [.idle, .composing, .converting]
        case .convert, .convertWithoutLearning, .deleteBackward, .insertBoundary, .acceptSuggestion: [.composing]
        case .toHiragana, .toKatakana, .toHalfwidthKatakana, .toFullwidthAlphanumeric, .toHalfwidthAlphanumeric, .switchKanaType,
             .commit, .cancel, .nextCandidate, .previousCandidate, .associate: [.composing, .converting]
        case .nextCandidatePage, .previousCandidatePage, .firstCandidate, .lastCandidate,
             .nextSegment, .previousSegment, .firstSegment, .lastSegment, .nextUncertainSegment, .previousUncertainSegment,
             .extendSegment, .shrinkSegment, .extendSegmentToWord, .shrinkSegmentToWord, .splitSegment, .editSegment, .commitFirstSegment, .backToReading,
             .forgetCandidate: [.converting]
        case .forgetLastCommit, .reconvert: [.idle]
        }
    }

    /// state の行に置けるか．いつでも の行にはどのコマンドも置ける(効く状態でだけ効く)
    public func isAvailable(in state: KeymapState) -> Bool {
        state == .anywhere || states.contains(state)
    }

    /// 入力方式を決めて切り替えるコマンドなら，その入力方式
    public var inputStyle: InputStyle? {
        switch self {
        case .romajiStyle: .romaji
        case .kanaStyle: .kana
        case .englishStyle: .english
        case .englishAutoStyle: .englishAuto
        default: nil
        }
    }

    /// 入力モードを変えるコマンド．アプリごとの設定で IME を使わないアプリでは効かない
    public var changesMode: Bool { group == .mode && self != .cancelAndDirectMode }

    /// 設定を開く・ライブ変換・手書きのように，入力の状態を変えずに IME の機能を呼ぶコマンド．
    /// IME を使わないアプリでも効く(入力メニューの操作を取り次がないアプリでも設定を開けるように)
    public var isTool: Bool { group == .tools }
}
