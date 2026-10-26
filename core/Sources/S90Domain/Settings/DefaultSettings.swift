/// 設定の既定値と，コードの中で使う上限などの値の置き場所(docs/dev/GUIDELINES.md)．
public enum DefaultSettings {
    /// 既定の設定．項目ごとの既定値は Settings に書いてある
    public static let settings = Settings()

    // R-06，R-07: 既定でプロファイルを割り当てるアプリ
    public static let terminalRules: [ProfileRule] = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "dev.warp.Warp",
        "io.alacritty",
        "org.alacritty",
        "com.github.wez.wezterm",
    ].map { ProfileRule(applicationPrefix: $0, profile: .terminal) }

    public static let programmingRules: [ProfileRule] = [
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
    public static let typoCorrectionBeamSize = 16
    public static let typoCorrectionTopK = 32
    /// 直した読みが打ったままの読みより，対数確率でいくつ以上よければ直すか．
    /// 「こんにちは」を「こんいちば」にするような誤った訂正(差 1.9)を避け，「ようですね」→「よいですね」(差 3.6)は直す
    public static let readingCorrectionMargin = 3.0
    /// 差がこれ以上で readingCorrectionMargin に届かないときは，直さずに「もしかして」として示し，Tab で直せるようにする
    public static let readingSuggestionMargin = 2.0
    /// 同じキーを続けて 2 回打ってしまった誤り(「koonnichiha」)を直す手間．近くのキーを余分に打った誤りの手間(3.0)より小さくする
    public static let repeatedKeyCost = 2.0
    /// 同じキーを続けて打った箇所のうち，1 回にして試す箇所の数の上限．1 か所ごとに Zenzai に問い合わせるので抑える
    public static let maximumRepeatedKeyVariants = 2
    /// ライブ変換で，打鍵が止まったときに打ち間違いを探す最短のキーの数．短い読みは見間違えやすく，直す意味も薄い
    public static let minimumKeysForLiveCorrection = 6
    /// 打ち間違いを探す最長のキーの数．長いと探すのに時間がかかり，打鍵が止まったときに待たせる
    public static let maximumKeysForCorrection = 60
    /// 別のところで求めた訂正の候補を覚えておく数の上限(キーの並びの数)
    public static let maximumProvidedCorrections = 64
    /// ライブ変換で，読みがこの文字数に満たないあいだは，打鍵が止まるまでかなのまま見せる
    public static let liveConversionMinimumLength = 3
    /// ライブ変換で，末尾の語の読みがこの文字数以下なら，打鍵が止まるまでかなのまま見せる(「らい」→「雷」を出さない)．
    /// 評価用の文で途中表示の誤りが 50 から 23 に減り，変換して見せた時点は 197 から 169 に減った
    public static let liveConversionHeldWordLength = 3
    /// 設定の画面のスライダーを動かしてから保存するまで待つ時間(秒)．1 段ごとに設定のファイルを書き直さないため
    public static let settingsSaveDelay = 0.4
    /// 打鍵が止まったとみなすまでの時間(秒)．止まったら変換した文を見せる
    public static let liveConversionSettleDelay = 0.4
    /// 打ち間違いを見直すまでの打鍵の止まり(秒)．見直しは 1 文 0.1〜0.7 秒かかり，その間はキーを受け付けないので，
    /// 文を見せるときより長く止まったときだけ行う
    public static let liveCorrectionDelay = 0.8
    /// EN 入力で日本語の候補を出し始める英字の数．短い英単語(an，to など)に候補を出さない
    public static let minimumEnglishInputSuggestionLength = 4
    /// 利用者が足すローマ字の綴りとかなの長さの上限と，足せる数
    public static let maximumRomajiKeysLength = 4
    public static let maximumRomajiKanaLength = 6
    public static let maximumRomajiRules = 500
    /// 使い方の記録を，何回ごとにファイルへ書くか
    public static let usageSaveInterval = 20
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
    /// 設定のファイルの大きさの上限(docs/dev/SECURITY-MODEL.md の「外から来るファイル」)．ユーザー辞書を上限いっぱい(10,000 語，読み 32 字，語 64 字)に登録しても，
    /// ふつうの文字なら 1 語 450 バイトほどで約 4.5MB に収まるので，余裕を見て倍にした．
    /// 結合文字を重ねた語のように 1 字が何バイトにもなる場合は超えうるが，書く前に大きさを確かめて断るので，ファイルは壊れない
    public static let maximumSettingsFileBytes = 9 * 1024 * 1024
    /// 使い方の記録のファイルの大きさの上限．回数だけなので小さい
    public static let maximumUsageFileBytes = 16 * 1024
    /// ユーザー辞書に登録できる語の数と，読み・語の長さの上限．設定ファイルが大きくなりすぎないようにする
    public static let maximumUserDictionaryEntries = 10_000
    /// アプリの扱いの規則の上限(CSV で取り込むとき)
    public static let maximumProfileRules = 1_000
    public static let maximumProfileRuleFileBytes = 256 * 1024
    public static let maximumApplicationIdentifierLength = 255
    /// 保存できるカスタムテーマの数と名前の長さの上限
    public static let maximumCustomThemes = 50
    public static let maximumThemeNameLength = 40
    public static let customThemeCornerRadius = 12.0
    public static let customThemeCornerRadiusRange = 0.0...24.0
    /// 1 ページに出す候補の数を選べる範囲(番号キー 1〜9 で選べる数まで)
    public static let candidatesPerPageRange = 3...9
    /// ライブ変換で漢字にするまでの待ち時間・打ち間違いを見直すまでの待ち時間・モードの表示の時間を選べる範囲(秒)
    public static let liveConversionDelayRange = 0.1...1.5
    public static let correctionDelayRange = 0.4...3.0
    public static let modeIndicatorDurationRange = 0.3...3.0
    /// 候補の文字の大きさ(pt)を選べる範囲
    public static let candidateFontSizeRange = 12.0...24.0
    public static let maximumUserDictionaryReadingLength = 32
    public static let maximumUserDictionaryWordLength = 64
    /// 取り込むユーザー辞書のファイルの大きさの上限
    public static let maximumUserDictionaryFileBytes = 4 * 1024 * 1024
    /// ユーザー辞書の語の点数(対数尤度)．辞書の一般的な語より少し上に出る値(azooKey-Desktop と同じ)
    public static let userDictionaryWordCost: Float = -5

    /// 利用者が変えられる記号の決まりの数の上限
    public static let maximumSymbolRules = 2_000
    /// 置き換えの決まりと直さない語の数の上限
    public static let maximumCorrectionRules = 2_000
}
