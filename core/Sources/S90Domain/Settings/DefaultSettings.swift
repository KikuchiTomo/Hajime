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
    /// 文節格子の列ごとに見せる候補の数
    public static let latticeCandidatesPerSegment = 5
    /// Zenzai が 1 回の変換で推論する回数の上限．小さいほど速く，大きいほど精度がよい(azooKey の既定は 10)
    public static let zenzaiInferenceLimit = 10
    /// Zenzai に渡す左の文脈の最大の長さ(文字数)
    public static let maximumLeftContextLength = 40
    /// 設定ファイルの大きさの上限(docs/dev/SECURITY-MODEL.md の「外から来るファイル」)
    public static let maximumSettingsFileBytes = 256 * 1024
}
