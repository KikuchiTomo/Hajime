/// 設定の既定値と，コードの中で使う上限などの値の置き場所(docs/dev/GUIDELINES.md)．
public enum DefaultSettings {
    public static let settings = Settings(
        liveConversion: true,
        yenKey: .alwaysBackslash,
        typoCorrection: .standard,
        showsVariantRow: true,
        theme: .automatic,
        candidateFontSize: 15,
        candidatePresentation: .automatic,
        profileRules: terminalRules + programmingRules
    )

    // R-06，R-07: 既定でプロファイルを割り当てるアプリ
    static let terminalRules: [ProfileRule] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp",
        "io.alacritty",
        "org.alacritty",
        "com.github.wez.wezterm",
    ].map { ProfileRule(applicationPrefix: $0, profile: .terminal) }

    static let programmingRules: [ProfileRule] = [
        "com.microsoft.VSCode",
        "com.todesktop.230313mzl4w4u92", // Cursor
        "com.jetbrains.",
        "com.google.android.studio",
        "dev.zed.Zed",
        "com.apple.dt.Xcode",
        "com.sublimetext.",
        "org.vim.MacVim",
        "com.panic.Nova",
    ].map { ProfileRule(applicationPrefix: $0, profile: .programming) }

    /// 候補一覧に一度に出す数．番号キーの 1〜9 に対応させる
    public static let candidatesPerPage = 9
    /// エンジンに求める候補の数
    public static let engineCandidateCount = 20
    /// タイプミスの補正を試す最短の長さ．短い並びは英単語と偶然一致しやすい
    public static let minimumCorrectionLength = 4
    /// タイプミスの補正を試す最長の長さ．長い並びを英単語の辞書に問い合わせる手間を抑える
    public static let maximumCorrectionLength = 24
    /// 綴りの補正で許す編集距離
    public static let maximumCorrectionDistance = 2
    /// 文節格子で，第 1 候補と 2 番目の点数の差がこれより小さい文節は確信度が低いとみなし，候補の列を見せる．
    /// 点数は azooKey の対数尤度．値は試験的に決めたもので，利用の記録を見て調整する
    public static let latticeConfidenceGap: Double = 2.0
    /// 打ち間違いを直した読みの候補をいくつまで求めるか
    public static let typoCorrectionCandidateCount = 5
    /// 打ち間違いを探す幅．広いほど見つけやすいが遅い．4 で 1 文 0.2 秒以内(Zenzai small，Apple Silicon)
    public static let typoCorrectionBeamSize = 4
    public static let typoCorrectionTopK = 8
    /// 直した読みが打ったままの読みより，対数確率でいくつ以上よければ直すか．
    /// 「こんにちは」を「こんいちば」にするような誤った訂正(差 1.9)を避け，「ようですね」→「よいですね」(差 3.6)は直す
    public static let readingCorrectionMargin = 3.0
    /// ライブ変換で，読みがこの文字数に満たないあいだは，打鍵が止まるまでかなのまま見せる
    public static let liveConversionMinimumLength = 3
    /// ライブ変換で，末尾の語の読みがこの文字数以下なら，打鍵が止まるまでかなのまま見せる(「らい」→「雷」を出さない)．
    /// 評価用の文で途中表示の誤りが 50 から 23 に減り，変換して見せた時点は 197 から 169 に減った
    public static let liveConversionHeldWordLength = 3
    /// 打鍵が止まったとみなすまでの時間(秒)．止まったら変換した文を見せる
    public static let liveConversionSettleDelay = 0.4
    /// 読みから引いた記号を，候補の上から何番目に差し込むか
    public static let symbolCandidateOffset = 3
    /// 文節格子の列ごとに見せる候補の数
    public static let latticeCandidatesPerSegment = 5
    /// 「nn」のあとの母音の読みを選び直す数．1 キーごとに変換にかけるので小さく保つ
    public static let maximumNasalAmbiguities = 2
    /// 「nn」のあとの母音の読みを比べるときに見る，前後の文字数
    public static let nasalContextLength = 3
    /// 「nn」のあとの母音の読みを比べ直す時点(母音のあとの文字数)．比べるたびに変換を 2 回するので少なく保つ
    public static let nasalEvaluationPoints: Set<Int> = [0, 1, 2, 3]
    /// Zenzai が 1 回の変換で推論する回数の上限．小さいほど速く，大きいほど精度がよい(azooKey の既定は 10)
    public static let zenzaiInferenceLimit = 10
    /// Zenzai に渡す左の文脈の最大の長さ(文字数)
    public static let maximumLeftContextLength = 40
    /// 設定ファイルの大きさの上限(docs/dev/SECURITY-MODEL.md の「外から来るファイル」)
    public static let maximumSettingsFileBytes = 256 * 1024
}
