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
        "windowsterminal.exe",
        "cmd.exe",
        "powershell.exe",
        "pwsh.exe",
        "conhost.exe",
        "wezterm-gui.exe",
        "alacritty.exe",
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
        "code.exe",
        "cursor.exe",
        "devenv.exe",
        "idea64.exe",
        "pycharm64.exe",
        "rider64.exe",
        "clion64.exe",
        "webstorm64.exe",
        "goland64.exe",
        "zed.exe",
        "sublime_text.exe",
    ].map { ProfileRule(applicationPrefix: $0, profile: .programming) }

    /// 候補一覧に一度に出す数．番号キーの 1〜9 に対応させる
    public static let candidatesPerPage = 9
    /// エンジンに求める候補の数
    public static let engineCandidateCount = 20
    /// 打っているあいだに出す候補(変換と予測)の数
    public static let suggestionCount = 5
    /// 文節の先頭の語を選び直した候補(LatticeBuilder.headWordAlternatives)の数
    public static let headWordAlternativeCount = 8
    /// 打っているあいだの候補を出し始める読みの長さ(1 文字では候補が多すぎて役に立たない)
    public static let minimumSuggestionReading = 2
    /// タイプミスの補正を試す最短の長さ．短い並びは英単語と偶然一致しやすい
    public static let minimumCorrectionLength = 4
    /// タイプミスの補正を試す最長の長さ．長い並びを英単語の辞書に問い合わせる手間を抑える
    public static let maximumCorrectionLength = 24
    /// ローマ字として読めてしまう英単語(「gitwotukau」の「git」)を見つける最短の長さ
    public static let minimumWordReadAsRomajiLength = 3
    /// ローマ字として読めてしまう英単語を探す最長の長さ．打鍵が止まるたびに英単語の辞書を引くので抑える
    public static let maximumWordReadAsRomajiLength = 12
    /// ローマ字として読めてしまう英単語を英単語とみなすときに，日本語として読んだときと比べる手間(対数尤度)．
    /// 英単語の後ろの日本語のもっともらしさからこれを引いたものが，全体を日本語として読んだときより大きければ英単語にする．
    /// 「gitwotukau」(ぎとぉつかう -52 に対し，を使う -16)は英単語にし，「kitte」(切手 -13 に対し，て -9)は日本語のままにする
    public static let wordReadAsRomajiCost = 15.0
    /// 英字入力(自動)で，英語の辞書にない語を日本語にする読みのもっともらしさ(1 文字あたりの対数尤度)の下限．
    /// 日本語の語は -2.7(きょう)〜 -7.1(きて)，ローマ字として読めても日本語でない並びは -8.8(て)〜 -14 だった
    public static let minimumJapanesePlausibilityPerCharacter = -7.5
    /// 英語か日本語かを決めておく語と決まりの数の上限と，語の長さの上限
    public static let maximumWordLanguageEntries = 2_000
    public static let maximumWordLanguageWordLength = 32
    /// 英語か日本語かを調べた結果を覚えておく語の数
    public static let maximumWordLanguageCache = 256
    /// 設定の画面の「試す」で見分ける語の数の上限
    public static let maximumWordLanguagePreviewWords = 20
    /// 綴りの補正で許す編集距離
    public static let maximumCorrectionDistance = 2
    /// 英単語の辞書に使う OS のスペルチェッカーの言語(macOS は NSSpellChecker，Windows は ISpellChecker)
    public static let englishSpellCheckLanguage = "en-US"
    /// OS のスペルチェッカーから受け取る綴りの候補の数の上限(Windows)．綴りの補正は近い候補から順に試す
    public static let maximumSpellingSuggestions = 8
    /// 文節格子で，第 1 候補と 2 番目の点数の差がこれより小さい文節は確信度が低いとみなし，候補の列を見せる．
    /// 点数は azooKey の対数尤度．値は試験的に決めたもので，利用の記録を見て調整する
    public static let latticeConfidenceGap: Double = 2.0
    /// 打ち間違いを直した読みの候補をいくつまで求めるか
    public static let typoCorrectionCandidateCount = 5
    /// 1 か所の打ち間違いを全部試す探し方(KeyEditSearch)で，言語モデルで採点する候補の数．多いほど拾えるが遅い
    public static let keyEditCandidateCount = 16
    /// かなの単位の訂正(KanaEditSearch)で，言語モデルにかける候補の数．変わったところの前後のもっともらしさで絞る
    public static let kanaEditCandidateCount = 12
    /// かなの単位の訂正の手間．置き換えは音の違い(KanaPhonetics．子音と母音)1 つごとに substitutionPerDifference．
    /// 音の違いが maximumPhoneticDistance より大きい字には置き換えない(候補の数を抑え，ありえない置き換えを試さない)
    public static let kanaEditCosts = (substitutionPerDifference: 0.5, maximumPhoneticDistance: 1.5, insertion: 1.0, deletion: 1.0, transposition: 1.0)
    /// 変換でかなのまま残った部分のうち，かなの単位の訂正を試す長さの下限(文字数)．1 字の助詞などは試さない
    public static let minimumUnconvertedSpanLength = 2
    /// 前に見直した部分のうち，探し直す文字の数(KeyEditSearch.searchStart)
    public static let keyEditOverlap = 4
    /// 訂正を裏で求めるときに覚えておく，読みの変換のもっともらしさの数．超えたら捨てる(メモリを増やし続けない)
    public static let maximumPlausibilityCacheEntries = 20_000
    /// 左の文脈を使わない点数も求める，訂正の候補の数(点数の高い順)．多いほど裏の処理が長くなる
    public static let contextFreeCandidateCount = 3
    /// KeyEditSearch の手間を，Zenzai の訂正の手間(隣のキーとの取り違え 1 回で 2)にそろえる倍率
    public static let keyEditCostScale = 2.0
    /// 直すかどうかを比べる点数(ReadingCorrection.rank)で，変換のもっともらしさの差に掛ける重みと，手間に掛ける重み．
    /// 評価の文(core/Evaluation/typo-correction.tsv)で，正しい文を誤って直さない範囲で直せる文が最も多くなる値を選んだ
    public static let correctionPlausibilityWeight = 0.25
    public static let correctionCostWeight = 3.0
    /// KeyEditSearch の打ち間違いの手間(隣のキー・母音どうし・同じキーは起きやすいので小さい)
    public static let keyEditCosts = (neighborSubstitution: 1.0, substitution: 2.0, easyOmission: 1.5, omission: 2.5,
                                      easyInsertion: 1.0, insertion: 2.0, transposition: 1.0, samePronunciation: 0.5,
                                      nasalSpelling: 0.5)
    /// 打ち間違いを探す幅．広いほど見つけやすいが遅い．4 で 1 文 0.2 秒以内(Zenzai small，Apple Silicon)
    public static let typoCorrectionBeamSize = 16
    public static let typoCorrectionTopK = 32
    /// 直した読みが打ったままの読みより，対数確率でいくつ以上よければ直すか．
    /// 「こんにちは」を「こんいちば」にするような誤った訂正(差 1.9)を避け，「ようですね」→「よいですね」(差 3.6)は直す
    public static let readingCorrectionMargin = 5.5
    /// 差がこれ以上で readingCorrectionMargin に届かないときは，直さずに「もしかして」として示し，Tab で直せるようにする
    public static let readingSuggestionMargin = 4.0
    /// 1 か所の直し(手間がこれ以下)は，Zenzai の点数の差(ReadingCorrection.score)だけでも直す・示す(前の決まり)
    public static let singleEditCost = 2.0
    /// 再変換できる文字の長さの上限(選んだ文字と読み)．長い文を選んだまま押しても重くならないよう抑える
    public static let maximumReconversionLength = 64
    /// Space で変換したあと，裏で求めている打ち間違いの訂正を待つ長さの上限(秒)．
    /// 変換はすぐに出し，訂正が届いたら(そのあいだにキーを押していなければ)直した変換に入れ替える
    public static let lateCorrectionTimeout = 5.0
    /// 利用者が変えられる lateCorrectionTimeout の範囲(秒)
    public static let lateCorrectionTimeoutRange = 1.0...30.0
    /// 打鍵が止まって見直すときに，裏で求める訂正を待つ上限(秒)．過ぎたらその入力は見直さない．
    /// 入力を待たせない裏の仕事なので，長い文(評価の文で最大 10 秒ほど)も求め終われるよう長めにする
    public static let reviewCorrectionTimeout = 15.0
    /// 利用者が変えられる reviewCorrectionTimeout の範囲(秒)
    public static let reviewCorrectionTimeoutRange = 5.0...60.0
    /// 変換できない読み(英字が残るなど)のもっともらしさの代わりに使う値．ふつうの読みより十分低い
    public static let unconvertiblePlausibility = -60.0
    /// 1 か所の直しを Zenzai の点数の差だけで直す境目(#52 より前の決まりと同じ)
    public static let readingCorrectionScoreMargin = 3.0
    /// 1 か所の直しを Zenzai の点数の差だけで「もしかして」と示す境目
    public static let readingSuggestionScoreMargin = 2.0
    /// 音の変わらない書き誤り(見ずらい → 見づらい)は，変換のもっともらしさの差がこれ以上なら「もしかして」と示す．
    /// かなの並びを見る言語モデルは書き分けの誤りを見分けにくく，辞書の語に切れるかどうかが決め手になるため
    public static let samePronunciationSuggestionGain = 6.0
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
    /// ライブ変換しない読みの長さの既定．読みがこの文字数以下なら，打鍵が止まってもかなのまま見せる(「の」「です」を漢字にしない)
    public static let liveConversionSkipLength = 2
    /// ライブ変換で，末尾の語の読みがこの文字数以下なら，打鍵が止まるまでかなのまま見せる(「らい」→「雷」を出さない)．
    /// 評価用の文で途中表示の誤りが 50 から 23 に減り，変換して見せた時点は 197 から 169 に減った
    public static let liveConversionHeldWordLength = 3
    /// 設定の画面のスライダーを動かしてから保存するまで待つ時間(秒)．1 段ごとに設定のファイルを書き直さないため
    public static let settingsSaveDelay = 0.4
    /// 打鍵が止まったとみなすまでの時間(秒)．止まったら変換した文を見せる
    public static let liveConversionSettleDelay = 0.4
    /// 初期設定で推奨する，ライブ変換で漢字にするまでの時間(秒)
    public static let onboardingLiveConversionDelay = 0.5
    /// 打ち間違いを見直すまでの打鍵の止まり(秒)．見直しは 1 文 0.1〜0.7 秒かかり，その間はキーを受け付けないので，
    /// 文を見せるときより長く止まったときだけ行う
    public static let liveCorrectionDelay = 0.8
    /// ローマ字入力で，前が英語でも日本語にする語の長さ(英字の数)の上限．「no」「to」のような短い語は助詞などのことが多く，
    /// 英語にすると上の枝でもかなに直しにくい．英語の語は変換の候補で出せる
    public static let maximumJapaneseFirstShortWordLength = 2
    /// EN 入力で日本語の候補を出し始める英字の数．短い英単語(an，to など)に候補を出さない
    public static let minimumEnglishInputSuggestionLength = 4
    /// 利用者が足すローマ字の綴りとかなの長さの上限と，足せる数
    public static let maximumRomajiKeysLength = 4
    public static let maximumRomajiKanaLength = 6
    public static let maximumRomajiRules = 500
    /// キー設定の表の行の上限(R-17)．ひな形はどれも 150 行ほど
    public static let maximumKeymapEntries = 500
    /// Windows の設定の画面がエンジンの応答を待つ時間(秒)．入力を止めない画面なので DLL より長く待つ
    public static let settingsAppResponseTimeout = 2.0
    /// 設定の画面がファイルの読み込み・書き出しを待つ時間(秒)．大きな辞書のファイルも読み終えられる長さにする
    public static let settingsAppFileTimeout = 60.0
    /// Windows の設定の画面がエンジンにつながらないとき，つなぎ直す間隔(秒)
    public static let settingsAppReconnectInterval = 3.0
    /// Windows のエンジンが，設定の画面などが書き換えた設定のファイルを読み直すために見る間隔(秒)
    public static let settingsFileWatchInterval = 2.0
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
    /// 入力中の表示(ライブ変換)で Zenzai を使ってよい 1 回の時間の目安(秒)．Zenzai の変換の時間の移動平均がこれを超える環境では，
    /// 打鍵が止まる前の表示に Zenzai を使わない(R-01 の 1 キー 50ms に，Zenzai 以外の処理と DLL との往復の分を残す)
    public static let zenzaiTypingBudget = 0.025
    /// Zenzai の変換の時間の移動平均で，新しく測った時間に掛ける重み
    public static let zenzaiCostSmoothing = 0.3
    /// Zenzai に渡す左の文脈の最大の長さ(文字数)
    public static let maximumLeftContextLength = 40
    /// 設定のファイルの大きさの上限(docs/dev/SECURITY-MODEL.md の「外から来るファイル」)．ユーザー辞書を上限いっぱい(10,000 語，読み 32 字，語 64 字)に登録しても，
    /// ふつうの文字なら 1 語 450 バイトほどで約 4.5MB に収まるので，余裕を見て倍にした．
    /// 結合文字を重ねた語のように 1 字が何バイトにもなる場合は超えうるが，書く前に大きさを確かめて断るので，ファイルは壊れない
    public static let maximumSettingsFileBytes = 9 * 1024 * 1024
    /// 同期のファイルの大きさの上限．設定とユーザー辞書と墓標が入る
    public static let maximumSyncFileBytes = 2 * maximumSettingsFileBytes
    /// 設定を変えてから同期のファイルに書くまで待つ時間(秒)．続けて変えたときに何度も書かないため
    public static let syncWriteDelay = 2.0
    /// 同期のファイルがほかの Mac で変わったかを確かめる間隔(秒)
    public static let syncPollInterval = 60.0
    /// 同期のフォルダの読み書きを待つ上限(秒)．クラウドのフォルダで手元に無いファイルを読むと時間がかかるため．過ぎたら次の同期でやり直す
    public static let syncFileTimeout = 15.0
    /// 設定の画面から頼まれたファイルの読み書き(大きな辞書の取り込みなど)を待つ上限(秒)
    public static let settingsFileTaskTimeout = 300.0
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
    /// カスタムテーマで文字と地に求めるコントラスト比(WCAG 2.2 AA)．下回れば設定の画面で知らせる
    public static let minimumTextContrast = 4.5
    /// カスタムテーマで印(修正の下線)と地に求めるコントラスト比
    public static let minimumMarkContrast = 3.0
    /// 1 ページに出す候補の数を選べる範囲(番号キー 1〜9 で選べる数まで)
    public static let candidatesPerPageRange = 3...9
    /// ライブ変換で漢字にするまでの待ち時間・打ち間違いを見直すまでの待ち時間・モードの表示の時間を選べる範囲(秒)
    public static let liveConversionDelayRange = 0.1...1.5
    /// ライブ変換しない読みの長さを選べる範囲(文字)．0 はすべてライブ変換する
    public static let liveConversionSkipLengthRange = 0...10
    public static let correctionDelayRange = 0.4...3.0
    public static let modeIndicatorDurationRange = 0.3...3.0
    /// 候補の文字の大きさ(pt)を選べる範囲
    public static let candidateFontSizeRange = 12.0...24.0
    /// 秒の項目(待ち時間・表示時間)を選ぶ刻み(秒)．macOS の SecondsSlider と Windows の設定の画面で使う
    public static let secondsStep = 0.1
    /// 打ち間違いを探す時間の上限(reviewCorrectionTimeout・lateCorrectionTimeout)を設定の画面で選ぶきざみ(秒)
    public static let correctionTimeoutStep = 1.0
    public static let maximumUserDictionaryReadingLength = 32
    public static let maximumUserDictionaryWordLength = 64
    /// 取り込むユーザー辞書のファイルの大きさの上限
    public static let maximumUserDictionaryFileBytes = 4 * 1024 * 1024
    /// 読み込む決まりの一覧(置き換え・ローマ字など)のファイルの大きさの上限
    public static let maximumRuleListFileBytes = 1024 * 1024
    /// 取り込む辞書のファイルの大きさの上限．大きな辞書(数十万語)を読めて，取り込みで手元のメモリを使い切らない大きさ
    public static let maximumImportedDictionaryBytes = 256 * 1024 * 1024
    /// 同期のフォルダと運ぶ索引のファイルの大きさの上限．索引は品詞を書き足すので，取り込むファイルより大きくなりうる
    public static let maximumSyncedDictionaryBytes = 2 * maximumImportedDictionaryBytes
    /// 索引を写すときとハッシュを求めるときに一度に読む大きさ
    public static let syncCopyChunkBytes = 1024 * 1024
    /// 取り込む辞書 1 つの語の数の上限
    public static let maximumImportedWords = 3_000_000
    /// 取り込める辞書の数の上限
    public static let maximumImportedDictionaries = 32
    /// 取り込む語の読みと語の長さの上限
    public static let maximumImportedReadingLength = 32
    public static let maximumImportedWordLength = 64
    /// 取り込んだ辞書の語の点数(大きいほど優先)．登録した語(userDictionaryWordCost)よりわずかに低くする
    public static let importedWordCost: Float = -6
    /// 一覧で 1 つ下の辞書ほど，語の点数をこれだけ下げる
    public static let importedDictionaryPriorityStep: Float = 0.5
    /// 文脈の条件の辞書を，最近その辞書の語を確定していないときに下げる点数
    public static let importedDictionaryContextPenalty: Float = 4
    /// 文脈の条件の辞書の優先度を上げる，最近確定したその辞書の語の数
    public static let importedDictionaryContextHits = 2
    /// 読み全体と一致する取り込んだ辞書の語を差し込む位置(上から何番目か)
    public static let importedWordCandidateOffset = 1
    /// 「最近」とみなす確定の回数
    public static let importedDictionaryContextWindow = 30
    /// ユーザー辞書の語の点数(対数尤度)．辞書の一般的な語より少し上に出る値(azooKey-Desktop と同じ)
    public static let userDictionaryWordCost: Float = -5

    /// 利用者が変えられる記号の決まりの数の上限
    public static let maximumSymbolRules = 2_000
    /// 置き換えの決まりと直さない語の数の上限
    public static let maximumCorrectionRules = 2_000
    /// 直さない語の長さの上限
    public static let maximumExceptionLength = 64
    /// 戻した補正から覚える語句の短さの下限(文字数)．これより短い文節は，読み全体を覚える
    public static let minimumRememberedPhraseLength = 2
    /// 置き換えの決まりの打った英字の長さと，置き換える語句の長さの上限
    public static let correctionRuleTypedLength = 2...24
    public static let maximumCorrectionRuleWordLength = 64
    /// 記号の決まりの入力(連続入力は下限も)と記号の長さの上限
    public static let symbolSequenceInputLength = 2...12
    public static let maximumSymbolOutputLength = 200
    /// カスタムテーマの id と書体の名前の長さの上限
    public static let maximumThemeIdentifierLength = 64
    public static let maximumThemeFontNameLength = 128

    // 連想変換(R-18)
    /// 連想の一覧に出す語の数(既定)と，選べる範囲
    public static let associationLimit = 60
    public static let associationLimitRange = 10...300
    /// 連想の候補数を変える刻み
    public static let associationLimitStep = 10
    /// 取り込める連想の辞書の数の上限(同梱の辞書を含む)
    public static let maximumAssociationDictionaries = 8
    /// アプリに同梱した連想の辞書(日本語 WordNet から作った data/thesaurus/wordnet-ja.tsv)．既定で一覧の先頭に置く
    public static let bundledAssociationDictionary = AssociationDictionary(
        id: "8C1F0E2A-5B7D-4E39-9A61-3D2C4B5E6F70", name: "日本語 WordNet", groupCount: 0, isBundled: true)
    /// 同梱の連想の辞書のファイルの名前(アプリの中・Windows のインストール先に置く)
    public static let bundledAssociationFileName = "wordnet-ja.tsv"
    /// 取り込む連想の辞書のファイルの大きさの上限．日本語 WordNet を丸ごと書き出しても 10MB ほどなので余裕を見た大きさ
    public static let maximumAssociationFileBytes = 64 * 1024 * 1024
    /// 連想の辞書 1 つのまとまり(意味)の数の上限
    public static let maximumAssociationGroups = 1_000_000
    /// 1 つのまとまりの語の数の上限．索引は語ごとにまとまりを書き写すので，語の数の 2 乗で大きくなるのを抑える
    public static let maximumAssociationGroupWords = 64
    /// 連想の語と意味の説明の長さの上限
    public static let maximumAssociationWordLength = 64
    public static let maximumAssociationLabelLength = 80

    /// 手書きの線を書き終えてから認識するまで待つ時間(秒)．続けて書く線を待つ
    public static let handwritingRecognitionDelay = 0.6
    /// 手書きの認識を待つ時間の上限(秒)．超えたら候補を出さずに次の線を待つ
    public static let handwritingRecognitionTimeout = 3.0
    /// Windows で候補の窓を出しているあいだ，DLL がマウスで押した候補を取りに来る(wake)間隔(秒)
    public static let candidateClickPollInterval = 0.1
    /// Windows で手書きの窓を開いているあいだ，DLL が選んだ文字を取りに来る(wake)間隔(秒)
    public static let handwritingPollInterval = 0.15
    /// Windows で打鍵が止まったあと，分岐図の候補を 1 文節ずつ前もって求めるために DLL に来てもらう(wake)間隔(秒)
    public static let latticeWarmingPollInterval = 0.01
    /// 入力中の表示を Zenzai なしで求めたとき，打鍵の合間に Zenzai の変換を求めるまでの間(秒)．Windows では DLL に来てもらう(wake)間隔
    public static let deferredConversionPollInterval = 0.005
    /// 手書きの窓から受け取る文字の長さの上限
    public static let maximumHandwritingTextLength = 16
}
