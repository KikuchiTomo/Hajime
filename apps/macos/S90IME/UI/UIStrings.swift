import S90Domain

/// 画面に出す文言の置き場所．多言語にするときは Localizable.xcstrings に移す
enum UIStrings {
    enum Candidate {
        static let candidatesHints = [KeyHint(key: "↑", label: "文字種")]
        static let variantsHints = [KeyHint(key: "←→", label: "選ぶ"), KeyHint(key: "↓", label: "候補")]
        static func variantsPosition(_ index: Int, _ total: Int) -> String { "文字種 \(index) / \(total)" }
        static func position(_ index: Int, _ total: Int) -> String { "\(index) / \(total)" }
    }

    /// 取り込んだ辞書(R-16)
    enum Dictionaries {
        static let userWords = "登録した単語"
        static let imported = "取り込んだ辞書"
        static let empty = "取り込んだ辞書はありません"
        static let importFile = "辞書を取り込む…"
        static let reimport = "取り込み直す…"
        static let name = "名前"
        static let field = "分野"
        static let fieldPrompt = "電気・法律など"
        static let condition = "使う場面"
        static let always = "常に"
        static let apps = "選んだアプリ"
        static let context = "文脈に合わせる"
        static let addApp = "アプリを追加…"
        static let moveUp = "優先度を上げる"
        static let moveDown = "優先度を下げる"
        static let tooMany = "取り込める辞書は 32 個までです"
        static let importFailed = "辞書を取り込めませんでした。大きすぎるか、読めない形式です"
        static let note = "タブ区切り・SKK・macOS のユーザ辞書の形式を読み込めます。上にある辞書ほど優先されます。"
        static func imported(_ count: Int) -> String { "\(count) 語を取り込みました" }

        static func summary(_ dictionary: ImportedDictionary) -> String {
            let condition = switch dictionary.condition {
            case .always: always
            case .apps(let apps): "\(Dictionaries.apps) \(apps.count) 個"
            case .context: context
            }
            let field = dictionary.field.isEmpty ? "" : "\(dictionary.field)・"
            return "\(field)\(dictionary.wordCount) 語・\(condition)"
        }
    }

    enum Branch {
        /// 打ち間違いを直した文節に添える札
        static let corrected = "修正"
        /// 選んでいる候補の取り込んだ辞書
        static func dictionarySource(_ name: String) -> String { "辞書: \(name)" }
        /// 足元の案内．キーはキー設定の表で，変換中にそのコマンドに割り当てた最初のキーを出す(R-17)
        /// 文節の長さは，押したらどうなるか(shorter・longer)が分かればそれを見せる(「⇧← 入れ　⇧→ 入れると」)
        static func hints(for keymap: Keymap, shorter: String? = nil, longer: String? = nil) -> [KeyHint] {
            func first(_ command: KeymapCommand) -> String { keymap.strokes(for: command, in: .converting).first.map(Keys.name(of:)) ?? "" }
            let length: [KeyHint] = shorter == nil && longer == nil
                ? [KeyHint(key: Keys.pair(first(.shrinkSegment), first(.extendSegment)), label: "文節の長さ")]
                : [shorter.map { KeyHint(key: first(.shrinkSegment), label: $0) }, longer.map { KeyHint(key: first(.extendSegment), label: $0) }].compactMap { $0 }
            return ([
                KeyHint(key: first(.nextCandidate), label: "候補"),
                KeyHint(key: first(.previousCandidate), label: "文字種"),
                KeyHint(key: Keys.pair(first(.previousSegment), first(.nextSegment)), label: "文節"),
                KeyHint(key: first(.nextUncertainSegment), label: "次の文節"),
            ] + length + [
                KeyHint(key: Keys.pair(first(.shrinkSegmentToWord), first(.extendSegmentToWord)), label: "単語ごと"),
                KeyHint(key: first(.splitSegment), label: "区切る"),
            ]).filter { !$0.key.isEmpty }
        }
        /// 文節を区切っているときの足元の案内．数字で区切る位置を選び，Esc でやめる(InputSession.handleSplit)．
        /// count は区切れる位置の数
        static func splitHints(count: Int) -> [KeyHint] {
            [KeyHint(key: count > 1 ? "1–\(count)" : "1", label: "区切る"), KeyHint(key: "Esc", label: "やめる")]
        }
        /// 上の枝(文字種)の丸に入れる印
        static let variantBadge = "↑"
        static func position(first: Int, last: Int, total: Int) -> String {
            first == last ? "\(first) / \(total)" : "\(first)–\(last) / \(total)"
        }
    }

    /// キー設定(R-17)
    enum Keys {
        /// キーの名前(macOS のメニューと同じ記号)．core の KeyStroke.label と同じにする
        static func name(of stroke: KeyStroke) -> String { stroke.label }

        /// 「←」と「→」のように修飾キーだけが同じ 2 つのキーは「←→」とまとめる
        static func pair(_ first: String, _ second: String) -> String {
            let arrows: Set<Character> = ["←", "→"]
            if let a = first.last, let b = second.last, arrows.contains(a), arrows.contains(b), first.dropLast() == second.dropLast() {
                return String(first.dropLast()) + "←→"
            }
            return [first, second].filter { !$0.isEmpty }.joined(separator: " ")
        }

        static func label(for state: KeymapState) -> String {
            switch state {
            case .anywhere: "いつでも"
            case .idle: "入力文字なし"
            case .composing: "入力中"
            case .converting: "変換中"
            case .direct: "英数"
            }
        }

        static func label(for group: KeymapCommand.Group) -> String {
            switch group {
            case .mode: "入力モード"
            case .characters: "空白"
            case .composing: "入力"
            case .scripts: "文字種"
            case .candidates: "候補"
            case .segments: "文節"
            case .commit: "確定と取り消し"
            case .learning: "学習"
            case .tools: "そのほか"
            }
        }

        static func label(for command: KeymapCommand) -> String {
            switch command {
            case .japaneseMode: "日本語入力に切り替え"
            case .directMode: "英数入力に切り替え"
            case .toggleMode: "日本語と英数の切り替え"
            case .nextInputStyle: "入力方式の切り替え"
            case .romajiStyle: Choice.label(for: .romaji)
            case .kanaStyle: Choice.label(for: .kana)
            case .englishStyle: Choice.label(for: .english)
            case .englishAutoStyle: Choice.label(for: .englishAuto)
            case .cancelAndDirectMode: "取り消して英数入力に"
            case .insertSpace: "空白を入力"
            case .insertAlternateSpace: "逆の幅の空白を入力"
            case .insertHalfwidthSpace: "半角空白を入力"
            case .insertFullwidthSpace: "全角空白を入力"
            case .convert: "変換"
            case .convertWithoutLearning: "学習を使わずに変換"
            case .deleteBackward: "左の文字を削除"
            case .insertBoundary: "ここで区切る"
            case .acceptSuggestion: "「もしかして」に直す"
            case .toHiragana: "ひらがなに変換"
            case .toKatakana: "全角カタカナに変換"
            case .toHalfwidthKatakana: "半角カタカナに変換"
            case .toFullwidthAlphanumeric: "全角英数に変換"
            case .toHalfwidthAlphanumeric: "半角英数に変換"
            case .switchKanaType: "かなの種類を切り替え"
            case .nextCandidate: "次の候補"
            case .previousCandidate: "前の候補"
            case .nextCandidatePage: "次の候補のページ"
            case .previousCandidatePage: "前の候補のページ"
            case .firstCandidate: "先頭の候補"
            case .lastCandidate: "末尾の候補"
            case .nextSegment: "右の文節"
            case .previousSegment: "左の文節"
            case .firstSegment: "先頭の文節"
            case .lastSegment: "末尾の文節"
            case .nextUncertainSegment: "次の迷う文節"
            case .previousUncertainSegment: "前の迷う文節"
            case .extendSegment: "文節を長く"
            case .shrinkSegment: "文節を短く"
            case .extendSegmentToWord: "文節を単語ごとに長く"
            case .shrinkSegmentToWord: "文節を単語ごとに短く"
            case .splitSegment: "文節を区切る"
            case .commit: "確定"
            case .commitFirstSegment: "先頭の文節だけ確定"
            case .cancel: "取り消し"
            case .backToReading: "読みに戻す"
            case .forgetCandidate: "候補を学習から削除"
            case .forgetLastCommit: "最後の学習を取り消し"
            case .openSettings: "設定を開く"
            case .toggleLiveConversion: "ライブ変換の切り替え"
            case .handwriting: "手書き入力"
            }
        }

        /// コマンドの説明(選ぶときの補足)．名前で分かるものは nil
        static func help(for command: KeymapCommand) -> String? {
            switch command {
            case .nextInputStyle: "ローマ字入力・かな入力・英字入力・英字入力(自動)を順に切り替えます"
            case .insertSpace: "幅は「スペース幅」の設定に従います。組み立て中の文字は確定してから入れます"
            case .insertAlternateSpace: "「スペース幅」の設定と逆の幅の空白を入れます"
            case .convert: "英単語を直した直後は、直す前に戻します"
            case .convertWithoutLearning: "学習した順位を使わずに変換し、確定しても学習しません"
            case .insertBoundary: "打っている途中に、今の位置を文節の区切りにします"
            case .acceptSuggestion: "「もしかして」と示した読みに直します"
            case .switchKanaType: "ひらがな・全角カタカナ・半角カタカナを順に切り替えます"
            case .nextCandidate: "入力中に押すと変換を始めます"
            case .previousCandidate: "入力中に押すと変換を始めます。分岐図では上の枝の文字種へ進みます"
            case .nextUncertainSegment, .previousUncertainSegment: "確信の低い文節だけを渡り歩きます"
            case .extendSegmentToWord, .shrinkSegmentToWord: "文節の終わりを次・前の単語の切れ目まで動かします"
            case .splitSegment: "語の切れ目に番号を出し、数字で区切ります"
            case .commitFirstSegment: "先頭の文節を確定し、残りの変換を続けます"
            case .cancel: "変換中は読みに戻し、直した読みは打ったままに戻します。入力中は読みを消します"
            case .backToReading: "変換をやめて読みに戻ります"
            case .forgetCandidate: "選んでいる候補を学習から消します"
            case .forgetLastCommit: "最後に確定した語句の学習を取り消します。入力した文字は消しません"
            case .handwriting: "「手書き入力」の設定がオンのときに使えます"
            case .englishAutoStyle: "英語で打ちながら，日本語にできる語を自動で日本語にします"
            case .romajiStyle, .kanaStyle, .englishStyle: nil
            case .japaneseMode, .directMode, .toggleMode, .cancelAndDirectMode, .insertHalfwidthSpace, .insertFullwidthSpace, .deleteBackward,
                 .toHiragana, .toKatakana, .toHalfwidthKatakana, .toFullwidthAlphanumeric, .toHalfwidthAlphanumeric, .nextCandidatePage,
                 .previousCandidatePage, .firstCandidate, .lastCandidate, .nextSegment, .previousSegment, .firstSegment, .lastSegment,
                 .extendSegment, .shrinkSegment, .commit, .openSettings, .toggleLiveConversion: nil
            }
        }

        static func label(for preset: KeymapPreset) -> String {
            switch preset {
            case .standard: "標準"
            case .windows: "Windows 風"
            case .mac: "Mac 風"
            case .emacs: "Emacs 風"
            case .vim: "Vim 風"
            }
        }

        // キー設定のページ
        static let tab = "キー設定"
        static let state = "状態"
        static let key = "キー"
        static let command = "コマンド"
        static let allStates = "すべての状態"
        static let searchPrompt = "コマンドやキーで検索"
        static let searchByKey = "キーで検索"
        static let searchByKeyHelp = "押したキーの行だけを出します"
        static let presetMenu = "ひな形を読み込む"
        static let customPreset = "カスタム"
        static func currentPreset(_ name: String) -> String { "ひな形: \(name)" }
        static let loadPresetTitle = "ひな形を読み込みますか？"
        static func loadPresetMessage(_ name: String) -> String { "今の表を「\(name)」の行で置き換えます。" }
        static let load = "読み込む"
        static let cancel = "キャンセル"
        static let restore = "既定に戻す"
        static let restoreTitle = "既定の表に戻しますか？"
        static let restoreMessage = "足した行と変えた行は消えます。"
        static let newRow = "新しい行"
        static let add = "追加"
        static let remove = "削除"
        static let duplicate = "複製"
        static let press = "キーを押してください"
        static let record = "キーを記録"
        static let stopRecording = "記録をやめる"
        static let chooseKey = "キーを選ぶ"
        static let specialKeys = "特別なキー"
        static let functionKeys = "ファンクションキー"
        static let modifiers = "修飾キー"
        static let control = "⌃ Control"
        static let option = "⌥ Option"
        static let shift = "⇧ Shift"
        static let commandKey = "⌘ Command"
        static let clearKeyFilter = "キーでの絞り込みをやめる"
        static let noMatches = "当てはまる行はありません"
        static func rowCount(_ shown: Int, _ total: Int) -> String { shown == total ? "\(total) 行" : "\(shown) / \(total) 行" }
        static func hidden(by winners: String) -> String { "同じキーの行があるため使われません: \(winners)" }
        static func partlyHidden(states: String, by winners: String) -> String { "\(states)では次の行を使います: \(winners)" }
        static let plainCharacter = "修飾キーの無い文字のキーです。この状態ではその文字を打てなくなります"
        static func duplicateWarning(_ row: String) -> String { "同じキーの行があります: \(row)。追加した行を使います" }
        static func missing(state: String, command: String) -> String { "\(state)に「\(command)」のキーがありません" }
        static let missingNote = "キーが無いと、入力を確定したり取り消したりできなくなります。"

        /// 行を 1 行の文にする(警告の中で行を示す)
        static func describe(_ entry: KeymapEntry) -> String {
            "\(label(for: entry.state))・\(name(of: entry.stroke))・\(label(for: entry.command))"
        }

        /// 特別なキーとして選べるキー(押して記録しにくいもの)
        static let specialKeyChoices: [KeyStroke.Key] = [
            .escape, .enter, .tab, .space, .backspace, .delete, .up, .down, .left, .right, .home, .end, .pageUp, .pageDown,
            .eisu, .kana, .hankakuZenkaku, .henkan, .muhenkan,
        ]
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
            case .englishAuto: "英自動"
            }
        }
    }

    /// 決まりの一覧(RuleListEditor)
    enum RuleList {
        static let update = "更新"
        static let edit = "編集"
        static let enabled = "有効"
        static func overwrites(_ key: String) -> String { "「\(key)」はもうあります。追加すると上書きします。" }
        static let alreadyRegistered = "もう登録してあります。"
        static let full = "これ以上は追加できません。"
        static let noMatches = "一致する項目はありません"
    }

    enum Settings {
        static let windowTitle = "s90.tokyo IME の設定"
        static let ok = "OK"
        static let cancel = "キャンセル"
        static let save = "保存"
        static let inputTab = "入力"
        static let conversionTab = "変換"
        static let dictionaryTab = "ユーザー辞書"
        static let appearanceTab = "外観"
        static let usageTab = "統計"
        static let appsTab = "除外設定"
        static let romajiTab = "ローマ字"
        // 左の一覧の見出し
        static let inputGroup = "入力と変換"
        static let dictionaryGroup = "辞書と記号"
        static let appearanceGroup = "見た目"
        static let dataGroup = "データ"
        static let aboutGroup = "このアプリについて"
        static let loading = "読み込み中…"
        static let romajiKeys = "入力"
        static let romajiKana = "出力"
        static let romajiEmpty = "追加した組み合わせはありません"
        static let dictionaryEmpty = "登録した単語はありません"
        static let invalidRomaji = "入力は英小文字・「-」・「'」で 4 文字まで、出力は 6 文字までにしてください"
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
        static let homophoneNotes = "同音異義語の使い分けを表示"
        static let misuseNotes = "誤用の注釈を表示"
        static let proofreading = "校正支援"
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
        static let dictionaryNote = "読みと単語をタブで区切ったテキストファイルを読み込めます。"
        static let appearance = "外観"
        static let restoreDefaults = "初期設定に戻す"
        static let saveFailed = "設定を保存できませんでした"
        static func setAside(_ name: String) -> String { "設定ファイルを読み込めなかったため、初期設定で起動しました。元のファイルは同じ場所に \(name) として残してあります" }
        static let learningReset = "学習結果を消去しました"
        static let dictionaryFull = "ユーザー辞書に登録できるのは 10,000 語までです"
        static let invalidEntry = "読みはひらがなで入力し、読みと単語は長すぎないようにしてください"
        static let importFailed = "インポートできませんでした。ファイルが大きすぎるか、テキストファイルではありません"
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
            case .readOnly: "学習結果を使うが、新しく学習しない"
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
        static let englishInputLiveConversion = "英字入力のライブ変換"
        static let englishInputLiveConversionNote = "オンにすると、英語の辞書にない語をローマ字として日本語にして見せます。Esc で英字に戻せます。"
        static let englishAutoNote = "英語で打ちながら、日本語にできる語は自動で日本語にします。見分け方は「英語と日本語」で変えられます。"

        static func label(for style: InputStyle) -> String {
            switch style {
            case .romaji: "ローマ字入力"
            case .kana: "かな入力"
            case .english: "英字入力"
            case .englishAuto: "英字入力(自動)"
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
        static let keyHints = "キーの案内を表示"
        static let typoCorrection = "タイプミスの修正"
        static let yenKey = "¥ キーで入力する文字"
        static let theme = "テーマ"
        static let presentation = "候補の表示"
        static let initialFocus = "最初に選ぶ文節"
        static let suggestionDisplay = "入力中の候補"

        static func label(for display: SuggestionDisplay) -> String {
            switch display {
            case .off: "表示しない"
            case .whenLiveConversionOff: "ライブ変換がオフのとき"
            case .always: "常に表示"
            }
        }

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
    /// 足した機能の項目の名前(テンキー・記号・補正・送り仮名・計算・読み違い)
    enum Features {
        static let keypadDirect = "テンキーの数字を半角で確定"

        static let okurigana = "送り仮名"
        static let notation = "表記"
        static let prefersKatakana = "カタカナ語を優先"

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

        // 英語と日本語
        static let languagePage = "英語と日本語"
        static let languageJudging = "見分け方"
        static let usesContext = "前の語で見分ける"
        static let usesContextNote = "make・shine のように英語にも日本語にも読める語を、前が英語なら英語、日本語なら日本語にします。"
        static let avoidsOffensive = "不適切な変換を避ける"
        static let englishWords = "いつも英語にする語"
        static let japaneseWords = "いつも日本語にする語"
        static let wordPlaceholder = "英字で打つ語"
        static let languageRules = "見分け方の決まり"
        static let languageRuleWord = "語"
        static let languageRuleContext = "前"
        static let languageRuleResult = "結果"
        static let tryLanguage = "試す"
        static let tryPlaceholder = "英字で打つ文(空白で区切る)"
        static let tryPreceding = "前の文字列"
        static let invalidWord = "語は 32 文字までの英字にしてください"
        static let alreadyListed = "もう一覧にあります"
        static let englishWordsEmpty = "いつも英語にする語はありません"
        static let japaneseWordsEmpty = "いつも日本語にする語はありません"
        static let languageNote = "英字入力(自動)と、ローマ字入力で英語にも読める語に使います。試した結果を右クリックすると一覧に足せます。"

        static func label(for language: WordLanguage) -> String {
            switch language {
            case .english: "英語"
            case .japanese: "日本語"
            }
        }

        static func label(for context: WordLanguageContext) -> String {
            switch context {
            case .sentenceStart: "文の頭"
            case .afterEnglish: "英語"
            case .afterJapanese: "日本語"
            }
        }

        // 補正
        static let correctionPage = "補正"
        static let correctionKinds = "直すもの"
        static let correctsEnglish = "英単語"
        static let correctsJapanese = "日本語の打ち間違い"
        static let correctsRepeatedKeys = "同じキーの重なり"
        static let exceptions = "直さない語句"
        static let exceptionPlaceholder = "英字か読み"
        static let rules = "置き換え"
        static let typed = "打った英字"
        static let replacement = "置き換える語句"
        static let invalidRule = "打った英字は 2〜24 文字の英字、置き換える語句は 64 文字までにしてください"
        static let invalidException = "直さない語句は 64 文字までにしてください"
        static let rulesEmpty = "置き換えはありません"
        static let exceptionsEmpty = "直さない語句はありません"

        // 記号
        static let symbolsPage = "記号"
        static let sequences = "連続入力によるサジェスト"
        static let readings = "読み仮名入力によるサジェスト"
        static let input = "入力"
        static let output = "記号"
        static let readingInput = "読み"
        static let readingOutput = "空白で区切った記号"
        static let search = "検索"
        static let invalidSymbol = "連続入力は英字と数字以外の 2〜12 文字にしてください"
        static let invalidReadingSymbol = "読みは 12 文字まで、記号は 200 文字までにしてください"
        static let symbolsEmpty = "決まりはありません"
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
        static let exclusionsNote = "アプリの固有IDを指定することで、アプリごとに入力方法を指定できます。昇順で適用されます。"
        static let addApps = "アプリを追加…"
        static let exclusionsEmpty = "アプリはありません"
        static let importCSV = "CSV を読み込む…"
        static let exportCSV = "CSV に書き出す…"
        static let exportCSVFileName = "s90-exclusions.csv"
        static let terminalCommands = "ターミナルでコマンドを英字で入力"
        static let restrainsLiveConversionInCode = "エディタとターミナルでライブ変換を控える"
        static let behavior = "動作"
        static let apps = "アプリ"
        static func importedRules(_ count: Int) -> String { "\(count) 件を追加しました" }
        static let csvFailed = "読み込めませんでした。CSV のファイルではないか、大きすぎます"
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
        static let createTheme = "カスタムテーマを作成…"
        static let editTheme = "編集…"
        static let duplicateTheme = "複製"
        static let newThemeName = "新しいテーマ"
        static let noCustomThemes = "カスタムテーマはありません"
        static let preview = "見本"
        static let readability = "読みやすさ"
        static let invalidTheme = "名前を入れてください"
        static var themesFull: String { "カスタムテーマは \(DefaultSettings.maximumCustomThemes) 個までです" }
        static func confirmDeleteTheme(_ name: String) -> String { "「\(name)」を削除しますか？" }

        /// 読みにくい組み合わせの知らせ
        static func lowContrast(_ pair: CustomTheme.ContrastPair, ratio: Double) -> String {
            let name = switch pair {
            case .text: text
            case .textMuted: textMuted
            case .selectionText: selectionText
            case .correction: correction
            }
            let ground = pair == .selectionText ? selection : surface
            return String(format: "%@と%@の色が近く、読みにくくなっています。コントラスト比は %.1f で、%.1f 以上が目安です。", name, ground, ratio, pair.minimum)
        }

        static func label(for style: CustomTheme.BranchStyle) -> String {
            switch style {
            case .curved: "曲線"
            case .straight: "直線"
            }
        }

        // バックアップ
        static let backup = "バックアップ"
        static let backupNote = "すべての設定をJSONとしてインポート・エクスポート可能です。"
        static let exportSettings = "設定を書き出す…"
        static let importSettings = "設定を読み込む…"
        static let exportSettingsFileName = "s90-settings.json"
        static let settingsImported = "設定を読み込みました"
        static let settingsImportFailed = "読み込めませんでした。s90.tokyo IME の設定ファイルではないか、大きすぎます"
        static let settingsExportFailed = "書き出せませんでした"

        // 情報
        static let about = "情報"
        static let version = "バージョン"
        static let acknowledgements = "謝辞"
        static let acknowledgementsNote = "s90.tokyo IME は上記のソフトウェア・モデル・データを利用しています。"
        static let noticesMissing = "謝辞のファイルが見つかりません"
        static let licenseText = "ライセンス全文"
    }
}

extension UIStrings {
    /// 同期のページ
    enum Sync {
        static let page = "同期"
        static let enabled = "同期"
        static let folder = "フォルダ"
        static let noFolder = "未選択"
        static let chooseFolder = "フォルダを選ぶ…"
        static let lastSynced = "最後に同期した時刻"
        static let syncNow = "今すぐ同期"
        static let scopes = "同期する項目"
        static let note = "Dropbox や iCloud Drive のフォルダを選ぶと、ほかの Mac と同期できます。"
        static let failed = "同期できませんでした"
        static let unreadable = "同期のファイルを読めないため、同期を止めています"
        static let items = "項目ごとに選ぶ"

        /// 項目(Settings の CodingKeys の名前)の表示名
        static func label(forField name: String) -> String {
            fieldLabels[name] ?? name
        }

        private static let fieldLabels: [String: String] = [
            "inputStyle": "入力方式", "customRomaji": "ローマ字の追加", "liveConversion": "ライブ変換",
            "englishInputLiveConversion": "英字入力のライブ変換", "wordLanguage": "英語と日本語", "yenKey": "¥ キー",
            "punctuation": "句読点", "brackets": "括弧", "slash": "スラッシュ", "spaceWidth": "スペース幅", "numberWidth": "数字幅",
            "alphabetWidth": "英字幅", "shiftStartsAlphabet": "Shift で英字", "punctuationCommits": "句読点で確定",
            "keypadDirect": "テンキーの数字を半角で確定",
            "typoCorrection": "タイプミスの修正", "candidatePresentation": "候補の表示", "initialFocus": "最初に選ぶ文節",
            "suggestionDisplay": "入力中の候補", "listCandidatesPerPage": "一覧の候補数", "branchCandidatesPerPage": "分岐図の候補数",
            "liveConversionDelay": "漢字にするまでの時間", "correctionDelay": "修正するまでの時間", "correctionSensitivity": "修正の基準",
            "showsSuggestions": "もしかして", "okuriganaStyle": "送り仮名", "calculation": "計算", "postalCodeConversion": "郵便番号変換",
            "handwriting": "手書き入力", "homophoneNotes": "同音異義語の使い分け", "misuseNotes": "誤用の注釈", "proofreading": "校正支援", "misreadings": "読み違い", "prefersKatakana": "カタカナ語を優先",
            "showsVariantRow": "文字種の行", "showsKeyHints": "キーの案内", "numberKeySelection": "番号キーで選択",
            "dateConversion": "日付と時刻に変換", "symbolConversion": "記号に変換", "emojiConversion": "絵文字に変換", "learning": "学習",
            "theme": "テーマ", "candidateFontSize": "文字の大きさ", "showsModeIndicator": "入力モードの表示",
            "modeIndicatorDuration": "入力モードの表示時間", "customThemes": "カスタムテーマ", "customThemeID": "使うカスタムテーマ",
            "escapeSwitchesToDirect": "Esc で英数", "terminalCommands": "ターミナルのコマンド", "profileRules": "アプリごとの設定",
            "restrainsLiveConversionInCode": "エディタとターミナルのライブ変換",
        ]

        static func label(for scope: SyncScope) -> String {
            switch scope {
            case .synced: "同期する"
            case .local: "この Mac だけ"
            }
        }

        static func label(for group: SyncGroup) -> String {
            switch group {
            case .input: "入力"
            case .keyboard: "キー配列"
            case .keys: "キー設定"
            case .conversion: "変換"
            case .correction: "補正"
            case .symbols: "記号"
            case .dictionary: "ユーザー辞書"
            case .importedDictionaries: "取り込んだ辞書"
            case .appearance: "外観"
            case .exclusions: "除外設定"
            case .usage: "統計"
            }
        }
    }
}
