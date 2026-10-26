import S90Domain

/// 画面に出す文言の置き場所．多言語にするときは Localizable.xcstrings に移す
enum UIStrings {
    enum Candidate {
        static let candidatesHints = [KeyHint(key: "↑", label: "文字種")]
        static let variantsHints = [KeyHint(key: "←→", label: "選ぶ"), KeyHint(key: "↓", label: "候補")]
        static func variantsPosition(_ index: Int, _ total: Int) -> String { "文字種 \(index) / \(total)" }
        static func position(_ index: Int, _ total: Int) -> String { "\(index) / \(total)" }
    }

    enum Branch {
        /// 足元の案内．キーは設定の割り当て(KeyBindings)の最初のキーを出す
        /// 文節の長さは，押したらどうなるか(shorter・longer)が分かればそれを見せる(「⇧← 入れ　⇧→ 入れると」)
        static func hints(for keys: KeyBindings, shorter: String? = nil, longer: String? = nil) -> [KeyHint] {
            func first(_ command: ConversionCommand) -> String { keys.strokes(for: command).first.map(Keys.name(of:)) ?? "" }
            let length: [KeyHint] = shorter == nil && longer == nil
                ? [KeyHint(key: Keys.pair(first(.shrinkSegment), first(.extendSegment)), label: "文節の長さ")]
                : [shorter.map { KeyHint(key: first(.shrinkSegment), label: $0) }, longer.map { KeyHint(key: first(.extendSegment), label: $0) }].compactMap { $0 }
            return ([
                KeyHint(key: first(.nextCandidate), label: "候補"),
                KeyHint(key: first(.previousCandidate), label: "文字種"),
                KeyHint(key: Keys.pair(first(.previousSegment), first(.nextSegment)), label: "文節"),
                KeyHint(key: first(.nextUncertainSegment), label: "次の文節"),
            ] + length).filter { !$0.key.isEmpty }
        }
        /// 上の枝(文字種)の丸に入れる印
        static let variantBadge = "↑"
        static func position(first: Int, last: Int, total: Int) -> String {
            first == last ? "\(first) / \(total)" : "\(first)–\(last) / \(total)"
        }
    }

    /// キーの名前(macOS のメニューと同じ記号)
    enum Keys {
        static func name(of stroke: KeyStroke) -> String {
            var name = ""
            if stroke.control { name += "⌃" }
            if stroke.option { name += "⌥" }
            if stroke.shift { name += "⇧" }
            switch stroke.key {
            case .space: name += "Space"
            case .tab: name += "Tab"
            case .up: name += "↑"
            case .down: name += "↓"
            case .left: name += "←"
            case .right: name += "→"
            case .character(let text): name += text.uppercased()
            }
            return name
        }

        /// 「←」と「→」のように修飾キーだけが同じ 2 つのキーは「←→」とまとめる
        static func pair(_ first: String, _ second: String) -> String {
            let arrows: Set<Character> = ["←", "→"]
            if let a = first.last, let b = second.last, arrows.contains(a), arrows.contains(b), first.dropLast() == second.dropLast() {
                return String(first.dropLast()) + "←→"
            }
            return [first, second].filter { !$0.isEmpty }.joined(separator: " ")
        }

        static func label(for command: ConversionCommand) -> String {
            switch command {
            case .openSettings: "設定を開く"
            case .toggleLiveConversion: "ライブ変換の切り替え"
            case .handwriting: "手書き入力"
            case .nextCandidate: "次の候補"
            case .previousCandidate: "前の候補"
            case .nextSegment: "右の文節"
            case .previousSegment: "左の文節"
            case .nextUncertainSegment: "次の文節"
            case .previousUncertainSegment: "前の文節"
            case .extendSegment: "文節を長く"
            case .shrinkSegment: "文節を短く"
            }
        }

        static let tab = "キー操作"
        static let note = "Enter・Escape・Backspace・数字キーは変更できません。"
        static let generalSection = "いつでも"
        static let conversionSection = "変換中"
        static let add = "追加"
        static let press = "キーを押してください"
        static let restore = "初期設定に戻す"
    }

    enum ModeIndicator {
        static func label(for mode: InputMode) -> String {
            switch mode {
            case .japanese: "あ"
            case .direct: "A"
            }
        }

        static func label(for style: InputStyle) -> String {
            switch style {
            case .romaji: "ローマ字"
            case .kana: "かな"
            case .english: "英"
            }
        }
    }

    enum Settings {
        static let windowTitle = "s90.tokyo IME の設定"
        static let ok = "OK"
        static let inputTab = "入力"
        static let conversionTab = "変換"
        static let dictionaryTab = "ユーザー辞書"
        static let appearanceTab = "外観"
        static let usageTab = "統計"
        static let appsTab = "除外設定"
        static let romajiTab = "ローマ字"
        static let romajiKeys = "入力"
        static let romajiKana = "出力"
        static let romajiNote = "ローマ字の変換表に組み合わせを追加します。"
        static let invalidRomaji = "入力は英小文字・「-」・「'」で 4 文字まで，出力は 6 文字までにしてください"
        static let escapeSwitchesToDirect = "Escape で英数に切り替え"
        static let bundlePrefix = "バンドル ID"
        static let profile = "モード"

        static func label(for profile: AppProfile) -> String {
            switch profile {
            case .standard: "標準"
            case .programming: "記号を半角"
            case .terminal: "コマンドを英字"
            case .direct: "IME を使わない"
            }
        }
        static let recordsUsage = "入力の統計を記録"
        static let usageNote = "入力した文字は記録しません。"
        static let firstCandidateRate = "第 1 候補のまま確定した割合"
        static let commits = "確定した回数"
        static let conversionsOpened = "Space で変換した回数"
        static let segmentsChanged = "選び直した文節の数"
        static let readingCorrections = "タイプミスを修正した回数 / 取り消した回数"
        static let englishCorrections = "英単語を修正した回数 / 取り消した回数"
        static let resetUsage = "統計を消去"
        static let inputStyleSection = "入力方式"
        static let characters = "文字"
        static let punctuation = "句読点"
        static let brackets = "[ ] キーで入力する括弧"
        static let slash = "/ キーで入力する文字"
        static let spaceWidth = "スペース幅"
        static let numberWidth = "数字幅"
        static let keys = "動作"
        static let punctuationCommits = "句読点で確定"
        static let numberKeySelection = "番号キーで候補を選択"
        static let showsModeIndicator = "入力モードの切り替えを表示"
        static let conversion = "変換"
        static let specialConversion = "特殊変換"
        static let dateConversion = "日付と時刻に変換"
        static let symbolConversion = "記号に変換"
        static let emojiConversion = "絵文字に変換"
        static let learning = "学習"
        static let resetLearning = "学習結果を消去"
        static let reading = "読み"
        static let word = "単語"
        static let add = "追加"
        static let remove = "削除"
        static let importDictionary = "インポート…"
        static let exportDictionary = "エクスポート…"
        static let exportFileName = "s90-user-dictionary.txt"
        static let dictionaryNote = "「読み<タブ>単語」形式のテキストファイルを読み込めます。"
        static let appearance = "外観"
        static let restoreDefaults = "初期設定に戻す"
        static let saveFailed = "設定を保存できませんでした"
        static func setAside(_ name: String) -> String { "設定ファイルを読み込めなかったため，初期設定で起動しました．元のファイルは同じ場所に \(name) として残してあります" }
        static let learningReset = "学習結果を消去しました"
        static let dictionaryFull = "ユーザー辞書に登録できるのは 10,000 語までです"
        static let invalidEntry = "読みはひらがなで入力し，読みと単語は長すぎないようにしてください"
        static let importFailed = "インポートできませんでした．ファイルが大きすぎるか，テキストファイルではありません"
        static let exportFailed = "エクスポートできませんでした"
        static func imported(_ count: Int) -> String { "\(count) 語を追加しました" }
        static func fontSize(_ size: Int) -> String { "候補の文字サイズ: \(size)" }

        static func label(for style: PunctuationStyle) -> String { style.comma + style.period }
        static func label(for style: BracketStyle) -> String { style.open + style.close }
        static func label(for style: SlashStyle) -> String { style.text }

        static func label(for width: CharacterWidth) -> String {
            switch width {
            case .halfwidth: "半角"
            case .fullwidth: "全角"
            }
        }

        static func label(for mode: LearningMode) -> String {
            switch mode {
            case .enabled: "学習する"
            case .readOnly: "学習結果を使うが，新しく学習しない"
            case .disabled: "学習しない"
            }
        }
    }

    enum Menu {
        static let openSettings = "設定を開く…"
        static let liveConversion = "ライブ変換"
    }

    /// 設定の画面の選択肢の名前
    enum Choice {
        static let inputStyle = "入力方式"
        static let keyboardLayout = "キー配列"
        static let keyboardLayoutNote = "ローマ字入力と英字入力で使用します。"

        static func label(for style: InputStyle) -> String {
            switch style {
            case .romaji: "ローマ字入力"
            case .kana: "かな入力"
            case .english: "英字入力"
            }
        }

        static func label(for layout: KeyboardLayout) -> String {
            switch layout {
            case .system: "システムの設定に従う"
            case .abc: "ABC"
            case .us: "US"
            case .dvorak: "Dvorak"
            case .dvorakQwertyCommand: "Dvorak - QWERTY ⌘"
            case .colemak: "Colemak"
            }
        }

        static let variantRow = "候補の上に文字種の行を表示"
        static let typoCorrection = "タイプミスの修正"
        static let yenKey = "¥ キーで入力する文字"
        static let theme = "テーマ"
        static let presentation = "候補の表示"
        static let initialFocus = "最初に選ぶ文節"

        static func label(for focus: InitialFocus) -> String {
            switch focus {
            case .start: "先頭"
            case .end: "末尾"
            case .automatic: "自動"
            }
        }

        static func label(for presentation: CandidatePresentation) -> String {
            switch presentation {
            case .automatic: "分岐図"
            case .list: "一覧"
            }
        }

        static func label(for level: TypoCorrectionLevel) -> String {
            switch level {
            case .off: "オフ"
            case .conservative: "英単語のみ"
            case .standard: "英単語と日本語"
            }
        }

        static func label(for policy: YenKeyPolicy) -> String {
            switch policy {
            case .alwaysBackslash: "常に \\"
            case .alwaysYen: "常に ¥"
            case .backslashInProgramming: "エディタとターミナルだけ \\"
            }
        }

        /// 選べる外観．native は標準と同じ見た目なので並べない(古い設定のファイルにあっても標準として読む)
        static let themes: [ThemePreference] = [.automatic, .washi, .nordic, .neon, .terminal, .contrast, .platinum, .desk]

        static func label(for theme: ThemePreference) -> String {
            switch theme {
            case .automatic, .native: "標準"
            case .platinum: "プラチナ"
            case .desk: "夜のデスク"
            case .washi: "和紙"
            case .neon: "ネオン"
            case .terminal: "端末"
            case .nordic: "北欧"
            case .contrast: "高コントラスト"
            }
        }
    }

    /// 設定の画面で足したページと項目
    /// 足した機能の項目の名前(テンキー・切り替えのキー・記号・補正・送り仮名・計算・読み違い・キーのひな形)
    enum Features {
        static let keypadDirect = "テンキーの数字を半角で確定"
        static let modeKeysSection = "切り替えのキー"
        static let eisuKey = "英数キー"
        static let kanaKey = "かなキー"
        static let hankakuZenkakuKey = "半角/全角キー"
        static let henkanKey = "変換キー"
        static let muhenkanKey = "無変換キー"

        static func label(for action: ModeKeyAction) -> String {
            switch action {
            case .toggle: "切り替え"
            case .japanese: "日本語"
            case .direct: "英数"
            case .none: "使わない"
            }
        }

        static let okurigana = "送り仮名"

        static func label(for style: OkuriganaStyle) -> String {
            switch style {
            case .standard: "本則"
            case .allowed: "許容"
            case .engine: "変換の順のまま"
            }
        }

        static let calculation = "計算"
        static let postalCode = "郵便番号から住所に変換"
        static let handwriting = "手書き入力"
        static let handwritingTitle = "手書き入力"
        static let handwritingClear = "消去"
        static let handwritingPrompt = "ここに文字を書いてください"
        static let misreadings = "読み違いの候補"
        static let preset = "ひな形"
        static let customPreset = "カスタム"

        static func label(for preset: KeyPreset) -> String {
            switch preset {
            case .standard: "標準"
            case .windows: "Windows 風"
            case .emacs: "Emacs 風"
            }
        }

        // 補正
        static let correctionPage = "補正"
        static let correctionKinds = "直すもの"
        static let correctsEnglish = "英単語"
        static let correctsJapanese = "日本語の打ち間違い"
        static let correctsRepeatedKeys = "同じキーの重なり"
        static let exceptions = "直さない語"
        static let exceptionPlaceholder = "英字か読み"
        static let rules = "置き換え"
        static let typed = "打った英字"
        static let replacement = "置き換える語"
        static let invalidRule = "打った英字は 2〜24 文字の英字，置き換える語は 64 文字までにしてください"

        // 記号
        static let symbolsPage = "記号"
        static let sequences = "続けて打つ記号"
        static let readings = "読みから出す記号"
        static let input = "入力"
        static let output = "記号"
        static let readingInput = "読み"
        static let readingOutput = "空白で区切った記号"
        static let search = "検索"
        static let invalidSymbol = "続けて打つ記号は英字と数字以外の 2〜12 文字にしてください"
        static let restoreDefault = "既定に戻す"
        static let changed = "変更あり"
        static let added = "追加"
    }

    enum More {
        // 入力
        static let alphabetWidth = "英字幅"
        static let shiftStartsAlphabet = "Shift で英字入力"
        static let modeIndicatorDuration = "モードの表示時間"
        static func seconds(_ value: Double) -> String { String(format: "%.1f 秒", value) }

        // 変換
        static let candidates = "候補"
        static let branchCandidates = "分岐図の候補数"
        static let listCandidates = "一覧の候補数"
        static let liveConversionDelay = "漢字にするまでの待ち時間"
        static let typo = "タイプミス"
        static let correctionSensitivity = "修正の基準"
        static let showsSuggestions = "「もしかして」を表示"
        static let correctionDelay = "見直すまでの待ち時間"

        static func label(for sensitivity: CorrectionSensitivity) -> String {
            switch sensitivity {
            case .cautious: "慎重"
            case .standard: "標準"
            case .aggressive: "積極的"
            }
        }

        // 除外設定
        static let exclusionsNote = "アプリごとに入力の扱いを変えます。上にあるものが優先されます。"
        static let addApps = "アプリを追加…"
        static let importCSV = "CSV を読み込む…"
        static let exportCSV = "CSV に書き出す…"
        static let exportCSVFileName = "s90-exclusions.csv"
        static let terminalCommands = "ターミナルでコマンドを英字で入力"
        static let behavior = "動作"
        static let apps = "アプリ"
        static func importedRules(_ count: Int) -> String { "\(count) 件を追加しました" }
        static let csvFailed = "読み込めませんでした。CSV のファイルではないか，大きすぎます"
        static let noBundleID = "バンドル ID の無いアプリは追加できません"

        // 外観
        static let theme = "テーマ"
        static let customThemes = "カスタムテーマ"
        static let duplicate = "今のテーマを複製"
        static let deleteTheme = "削除"
        static let themeName = "名前"
        static let colors = "色"
        static let surface = "背景"
        static let text = "文字"
        static let textMuted = "補助の文字"
        static let selection = "選択"
        static let selectionText = "選択中の文字"
        static let correction = "修正の印"
        static let line = "線"
        static let shape = "形"
        static let cornerRadius = "角の丸さ"
        static let branchStyle = "枝"
        static let font = "書体"
        static let themeFont = "テーマに合わせる"
        static func copyName(_ name: String) -> String { "\(name) のコピー" }

        static func label(for style: CustomTheme.BranchStyle) -> String {
            switch style {
            case .curved: "曲線"
            case .straight: "直線"
            }
        }

        // バックアップ
        static let backup = "バックアップ"
        static let backupNote = "ユーザー辞書・テーマ・キー操作を含むすべての設定を JSON で保存します。"
        static let exportSettings = "設定を書き出す…"
        static let importSettings = "設定を読み込む…"
        static let exportSettingsFileName = "s90-settings.json"
        static let settingsImported = "設定を読み込みました"
        static let settingsImportFailed = "読み込めませんでした。s90.tokyo IME の設定ファイルではないか，大きすぎます"
        static let settingsExportFailed = "書き出せませんでした"

        // 情報
        static let about = "情報"
        static let version = "バージョン"
        static let acknowledgements = "謝辞"
        static let acknowledgementsNote = "s90.tokyo IME は次のオープンソースソフトウェアとモデルを利用しています。"
        static let noticesMissing = "利用表記のファイルが見つかりません"
    }
}
