import HajimeApplication
import HajimeDomain

/// 画面に出す文言の置き場所．多言語にするときは Localizable.xcstrings に移す
enum UIStrings {
    enum Candidate {
        static let candidatesHints = [KeyHint(key: "↑", label: "文字種")]
        static let variantsHints = [KeyHint(key: "←→", label: "選択"), KeyHint(key: "↓", label: "候補")]
        static func variantsPosition(_ index: Int, _ total: Int) -> String { "文字種 \(index) / \(total)" }
        static func position(_ index: Int, _ total: Int) -> String { "\(index) / \(total)" }
    }

    /// 連想変換(R-18)
    enum Association {
        static let section = "連想変換"
        static let enabled = "連想変換"
        static let limit = "連想の候補数"
        static let hint = "連想の案内を表示"
        static let dictionaries = "連想の辞書"
        static let empty = "連想の辞書はありません"
        static let importFile = "連想の辞書をインポート…"
        static let tooMany = "取り込める連想の辞書は \(DefaultSettings.maximumAssociationDictionaries) 個までです"
        static let importFailed = "連想の辞書を取り込めませんでした。大きすぎるか、対応していない形式です"
        static let note = "1 行に同じ意味の単語をタブか「,」で区切って並べたファイルを読み込めます。タブで区切るときは、先頭の列に意味の説明を書きます。上にある辞書ほど先に出ます。"
        static func imported(_ count: Int) -> String { "\(count) 件の意味を取り込みました" }
        static func summary(_ dictionary: AssociationDictionary) -> String { "\(dictionary.groupCount) 件の意味" }
        /// 連想の一覧の見出しの前に置く言葉
        static let headingPrefix = "連想"
        static func groupPosition(_ index: Int, _ total: Int) -> String { "\(index) / \(total)" }
        /// 連想の一覧の足元の案内．キーはキー設定の表で，変換中にそのコマンドに割り当てた最初のキー(R-17)
        static func hints(for keymap: Keymap) -> [KeyHint] {
            KeyHint.make(IndicatorLabels.associationHints, keymap: keymap)
        }
    }

    /// 取り込んだ辞書(R-16)
    enum Dictionaries {
        static let userWords = "登録した単語"
        static let imported = "取り込んだ辞書"
        static let empty = "取り込んだ辞書はありません"
        static let importFile = "辞書をインポート…"
        static let reimport = "再読み込み…"
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
        static let tooMany = "取り込める辞書は \(DefaultSettings.maximumImportedDictionaries) 個までです"
        static let importFailed = "辞書を取り込めませんでした。大きすぎるか、対応していない形式です"
        static let note = "タブ区切り・SKK・macOS のユーザー辞書の形式を読み込めます。上にある辞書ほど優先されます。"
        static func imported(_ count: Int) -> String { "\(count) 件を取り込みました" }

        static func summary(_ dictionary: ImportedDictionary) -> String {
            let condition = switch dictionary.condition {
            case .always: always
            case .apps(let apps): "\(Dictionaries.apps) \(apps.count) 個"
            case .context: context
            }
            let field = dictionary.field.isEmpty ? "" : "\(dictionary.field)・"
            return "\(field)\(dictionary.wordCount) 件・\(condition)"
        }
    }

    enum Branch {
        /// 打ち間違いを直した文節に添える札
        static let corrected = "修正"
        /// 選んでいる候補の取り込んだ辞書
        static func dictionarySource(_ name: String) -> String { "辞書: \(name)" }
        /// 足元の案内．キーはキー設定の表で，変換中にそのコマンドに割り当てた最初のキーを出す(R-17)
        /// 文節の長さを変えるキーは「区切り調整」とまとめて出す
        static func hints(for keymap: Keymap) -> [KeyHint] {
            KeyHint.make(IndicatorLabels.branchHints, keymap: keymap)
        }
        /// 文節を区切っているときの足元の案内．数字で区切る位置を選び，Esc でやめる(InputSession.handleSplit)．
        /// count は区切れる位置の数
        static func splitHints(count: Int) -> [KeyHint] {
            IndicatorLabels.splitHints(count: count).map { KeyHint(key: $0.key, label: $0.label) }
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
            case .acceptSuggestion: "「もしかして」に修正"
            case .reconvert: "再変換"
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
            case .associate: "連想変換"
            case .nextSegment: "右の文節"
            case .previousSegment: "左の文節"
            case .firstSegment: "先頭の文節"
            case .lastSegment: "末尾の文節"
            case .nextUncertainSegment: "誤りやすい次の文節"
            case .previousUncertainSegment: "誤りやすい前の文節"
            case .extendSegment: "文節を長く"
            case .shrinkSegment: "文節を短く"
            case .extendSegmentToWord: "文節を単語ごとに長く"
            case .shrinkSegmentToWord: "文節を単語ごとに短く"
            case .splitSegment: "文節を区切る"
            case .editSegment: "文節を打ち直す"
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
            case .insertSpace: "幅は「スペース幅」の設定に従います。入力中の文字は確定してから入力します"
            case .insertAlternateSpace: "「スペース幅」の設定と逆の幅の空白を入力します"
            case .convert: "英単語を修正した直後は、修正前に戻します"
            case .convertWithoutLearning: "学習した順位を使わずに変換し、確定しても学習しません"
            case .insertBoundary: "入力中に、現在の位置で文節を区切ります"
            case .acceptSuggestion: "「もしかして」で示した読みに修正します"
            case .reconvert: "選択中の確定済みの文字を読みに戻して変換し直します。Esc で元の文字に戻します"
            case .switchKanaType: "ひらがな・全角カタカナ・半角カタカナを順に切り替えます"
            case .nextCandidate: "入力中に押すと変換を始めます"
            case .previousCandidate: "入力中に押すと変換を始めます。分岐図では上の枝の文字種へ進みます"
            case .nextUncertainSegment, .previousUncertainSegment: "誤変換の可能性が高い文節に移動します"
            case .extendSegmentToWord, .shrinkSegmentToWord: "文節の終わりを次・前の単語の切れ目まで動かします"
            case .splitSegment: "単語の切れ目に番号を表示し、数字キーで区切ります"
            case .editSegment: "選んでいる文節を消して読みを打ち直します。文節を移ると変換します"
            case .commitFirstSegment: "先頭の文節を確定し、残りの変換を続けます"
            case .cancel: "変換中は読みに戻し、修正した読みは入力したままに戻します。入力中は読みを削除します"
            case .backToReading: "変換をやめて読みに戻ります"
            case .forgetCandidate: "選択中の候補を学習から削除します"
            case .forgetLastCommit: "最後に確定した語句の学習を取り消します。入力した文字は削除しません"
            case .handwriting: "「手書き入力」の設定がオンのときに使えます"
            case .associate: "選択中の文節を、似た意味や関連のある単語の一覧に切り替えます。入力中は変換してから切り替えます"
            case .englishAutoStyle: "英語で入力しながら、日本語にできる語句を自動で日本語に変換します"
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
        static let searchByKeyHelp = "押したキーの行だけを表示します"
        static let presetMenu = "ひな形を読み込む"
        static let customPreset = "カスタム"
        static func currentPreset(_ name: String) -> String { "ひな形: \(name)" }
        static let loadPresetTitle = "ひな形を読み込みますか？"
        static func loadPresetMessage(_ name: String) -> String { "今の表を「\(name)」の行で置き換えます。" }
        static let load = "読み込む"
        static let cancel = "キャンセル"
        static let restore = "既定に戻す"
        static let restoreTitle = "既定の表に戻しますか？"
        static let restoreMessage = "追加した行と変更した行は削除されます。"
        static let newRow = "新しい行"
        static let add = "追加"
        static let remove = "削除"
        static let duplicate = "複製"
        static let press = "キーを押してください"
        static let record = "キーを記録"
        static let stopRecording = "記録を停止"
        static let chooseKey = "キーを選択"
        static let specialKeys = "特別なキー"
        static let functionKeys = "ファンクションキー"
        static let modifiers = "修飾キー"
        static let control = "⌃ Control"
        static let option = "⌥ Option"
        static let shift = "⇧ Shift"
        static let commandKey = "⌘ Command"
        static let clearKeyFilter = "絞り込みを解除"
        static let noMatches = "当てはまる行はありません"
        static func rowCount(_ shown: Int, _ total: Int) -> String { shown == total ? "\(total) 行" : "\(shown) / \(total) 行" }
        static func hidden(by winners: String) -> String { "同じキーの行があるため使われません: \(winners)" }
        static func partlyHidden(states: String, by winners: String) -> String { "\(states)では次の行を使います: \(winners)" }
        static let plainCharacter = "修飾キーの無い文字のキーです。この状態ではその文字を入力できなくなります"
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
        static func label(for mode: InputMode) -> String { IndicatorLabels.label(for: mode) }
        static func label(for style: InputStyle) -> String { IndicatorLabels.label(for: style) }
    }

    /// 決まりの一覧(RuleListEditor)
    enum RuleList {
        static let update = "更新"
        static let edit = "編集"
        static let enabled = "有効"
        /// 列の見出しを押したときの読み上げの案内
        static let sortHint = "並べ替え"
        static func overwrites(_ key: String) -> String { "「\(key)」はすでにあります。追加すると上書きします。" }
        static let alreadyRegistered = "すでに登録されています。"
        static let full = "これ以上は追加できません。"
        static let noMatches = "一致する項目はありません"
    }

    enum Settings {
        static let windowTitle = "はじめの設定"
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
        static let invalidRomaji = "入力は英小文字・「-」・「'」で \(DefaultSettings.maximumRomajiKeysLength) 文字まで、出力は \(DefaultSettings.maximumRomajiKanaLength) 文字までにしてください"
        static let escapeSwitchesToDirect = "Esc で英数に切り替え"
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
        static let exportFileName = "hajime-user-dictionary.txt"
        static let dictionaryNote = "読みと単語をタブで区切ったテキストファイルを読み込めます。"
        static let appearance = "外観"
        static let restoreDefaults = "すべての設定を既定に戻す"
        static let saveFailed = "設定を保存できませんでした"
        static func setAside(_ name: String) -> String { "設定ファイルを読み込めなかったため、既定の設定で起動しました。元のファイルは同じ場所に \(name) として保存しました" }
        static let learningReset = "学習結果を消去しました"
        static let dictionaryFull = "ユーザー辞書に登録できるのは \(DefaultSettings.maximumUserDictionaryEntries.formatted()) 件までです"
        static let invalidEntry = "読みはひらがなで \(DefaultSettings.maximumUserDictionaryReadingLength) 文字まで、単語は \(DefaultSettings.maximumUserDictionaryWordLength) 文字までにしてください"
        static let importFailed = "インポートできませんでした。ファイルが大きすぎるか、テキストファイルではありません"
        static let exportFailed = "エクスポートできませんでした"
        static func imported(_ count: Int) -> String { "\(count) 件を追加しました" }
        static let fontSizeName = "候補の文字サイズ"
        static func fontSize(_ size: Int) -> String { "\(fontSizeName): \(size)" }

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
            case .readOnly: "学習結果のみ使用"
            case .disabled: "学習しない"
            }
        }
    }

    /// 初期設定(初めて使うときに 1 回だけ開く案内)
    enum Onboarding {
        static let windowTitle = "はじめへようこそ"
        static let recommended = "推奨"
        static let back = "戻る"
        static let next = "次へ"
        static let skip = "あとで設定する"
        static let finish = "はじめる"
        static func step(_ index: Int, of count: Int) -> String { "\(index) / \(count)" }
        static let redo = "初期設定をやり直す"
        static let redoLabel = "初期設定"

        // a. 英数とかなの切り替え
        static let modeTitle = "英数とかなの切り替え"
        static let modeDetail = "日本語と英数を切り替えるキーを選びます。"
        static func label(for style: ModeSwitchStyle) -> String {
            switch style {
            case .separate: "英数キーとかなキーで分ける"
            case .single: "1 つのキーで切り替え"
            }
        }
        static func detail(for style: ModeSwitchStyle) -> String {
            switch style {
            case .separate: "英数キーで英数、かなキーで日本語になります。"
            case .single: "英数キーとかなキーのどちらでも、押すたびに切り替わります。"
            }
        }

        // b. 自動補正
        static let correctionTitle = "自動補正"
        static let correctionDetail = "打ち間違いを、文の流れから見つけて直します。直したところには点線が付き、Esc で打ったままに戻せます。"
        static let correctionOff = "直さない"
        static func detail(for sensitivity: CorrectionSensitivity) -> String {
            switch sensitivity {
            case .cautious: "確かなときだけ直し、迷うときは「もしかして」で知らせます。"
            case .standard: "よくある打ち間違いを直します。"
            case .aggressive: "少しでも打ち間違いらしければ直します。"
            }
        }

        // c. 外観
        static let themeTitle = "外観"
        static let themeDetail = "候補ウィンドウの見た目を選びます。あとから設定の画面で、色や書体を自由に変えられます。"

        // d. ライブ変換
        static let liveTitle = "ライブ変換"
        static let liveDetail = "打ちながら漢字に変換して見せます。Space を押さずに、そのまま Enter で確定できます。"
        static let liveOn = "ライブ変換を使う"
        static let liveOff = "使わない"
        static let liveDelay = "漢字にするまでの時間"

        // e. 候補の出し方
        static let presentationTitle = "候補の出し方"
        static let presentationDetail = "Space を押したときの候補の並べ方と、最初に選ぶ文節を選びます。"
        static func detail(for presentation: CandidatePresentation) -> String {
            switch presentation {
            case .automatic: "文節ごとに候補が枝分かれします。文全体を見渡しながら、直したい文節だけを選び直せます。"
            case .segmentList: "選んでいる文節の候補を縦に並べます。"
            case .list: "文全体の候補を縦に並べます。"
            }
        }
        static let initialFocus = "最初に選ぶ文節"

        // f. 入力する文字
        static let charactersTitle = "入力する文字"
        static let charactersDetail = "句読点や括弧など、キーを押したときに入る文字を選びます。"

        // g. 機能の紹介
        static let featuresTitle = "便利な機能"
        static let featuresDetail = "変換の候補に、関連する語や計算の結果などを出します。"
        static let association = "連想変換"
        static let associationDetail = "Shift + Space で、似た意味の語を出します。"
        static let calculation = "計算"
        static let calculationDetail = "「1+2*3=」と打つと、答えを候補に出します。"
        static let postalCode = "郵便番号"
        static let postalCodeDetail = "郵便番号から住所を出します。"
        static let date = "日付と時刻"
        static let dateDetail = "「きょう」「いま」「なう」から日付と時刻を出します。"
    }

    enum Menu {
        static let openSettings = "設定を開く…"
        static let liveConversion = "ライブ変換"
        static let handwriting = "手書き入力"
    }

    /// 設定の画面の選択肢の名前
    enum Choice {
        static let inputStyle = "入力方式"
        static let keyboardLayout = "キー配列"
        static let keyboardLayoutNote = "ローマ字入力と英字入力で使用します。"
        static let englishInputLiveConversion = "英字入力のライブ変換"
        static let englishInputLiveConversionNote = "英語の辞書にない単語をローマ字として読み、日本語に変換して表示します。Esc で英字に戻せます。"
        static let englishAutoNote = "英語で入力しながら、日本語にできる語句を自動で日本語に変換します。判別方法は「英語と日本語」で変更できます。"

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
        static let initialFocus = "最初に選択する文節"
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
            case .segmentList: "一覧"
            case .list: "文全体の一覧"
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
        static let languageJudging = "判別方法"
        static let usesContext = "前の単語で判別"
        static let usesContextNote = "make・shine のように英語にも日本語にも読める単語を、前が英語なら英語、日本語なら日本語にします。"
        static let avoidsOffensive = "不適切な変換を避ける"
        static let englishWords = "常に英語にする単語"
        static let japaneseWords = "常に日本語にする単語"
        static let wordPlaceholder = "英字の単語"
        static let languageRules = "判別ルール"
        static let languageRuleWord = "単語"
        static let languageRuleContext = "前"
        static let languageRuleResult = "結果"
        static let tryLanguage = "試す"
        static let tryPlaceholder = "英字の文"
        static let tryPreceding = "前の文字列"
        static let invalidWord = "単語は \(DefaultSettings.maximumWordLanguageWordLength) 文字までの英字にしてください"
        static let alreadyListed = "すでに一覧にあります"
        static let englishWordsEmpty = "常に英語にする単語はありません"
        static let japaneseWordsEmpty = "常に日本語にする単語はありません"
        static let languageNote = "英字入力(自動)と、ローマ字入力で英語にも読める単語に使用します。試した結果を右クリックすると一覧に追加できます。"

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
        static let correctionKinds = "修正の対象"
        static let correctsEnglish = "英単語"
        static let correctsJapanese = "日本語のタイプミス"
        static let correctsRepeatedKeys = "同じキーの重なり"
        static let exceptions = "修正しない語句"
        static let exceptionPlaceholder = "英字か読み"
        static let rules = "置き換え"
        static let typed = "入力した英字"
        static let replacement = "置き換える語句"
        static let invalidRule = "入力した英字は \(DefaultSettings.correctionRuleTypedLength.lowerBound)〜\(DefaultSettings.correctionRuleTypedLength.upperBound) 文字の英字、置き換える語句は \(DefaultSettings.maximumCorrectionRuleWordLength) 文字までにしてください"
        static let invalidException = "修正しない語句は \(DefaultSettings.maximumExceptionLength) 文字までにしてください"
        static let rulesEmpty = "置き換えはありません"
        static let exceptionsEmpty = "修正しない語句はありません"

        // 記号
        static let symbolsPage = "記号"
        static let sequences = "連続入力によるサジェスト"
        static let readings = "読み仮名入力によるサジェスト"
        static let input = "入力"
        static let output = "記号"
        static let readingInput = "読み"
        static let readingOutput = "空白で区切った記号"
        static let search = "検索"
        static let invalidSymbol = "連続入力は英字と数字以外の \(DefaultSettings.symbolSequenceInputLength.lowerBound)〜\(DefaultSettings.symbolSequenceInputLength.upperBound) 文字にしてください"
        static let invalidReadingSymbol = "読みは \(DefaultSettings.symbolSequenceInputLength.upperBound) 文字まで、記号は \(DefaultSettings.maximumSymbolOutputLength) 文字までにしてください"
        static let symbolsEmpty = "ルールはありません"
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
        static let liveConversionSkipLength = "ライブ変換しない文字数"
        static let englishSkipLength = "英単語にしない文字数"
        static func skipLength(_ value: Int) -> String { value == 0 ? "オフ" : "\(value) 文字以下" }
        static let typo = "タイプミス"
        static let correctionSensitivity = "修正の基準"
        static let showsSuggestions = "「もしかして」を表示"
        static let correctionDelay = "見直すまでの待ち時間"
        static let reviewCorrectionTimeout = "見直しの時間の上限"
        static let lateCorrectionTimeout = "変換後の補正の時間の上限"
        static let remembersRejectedCorrections = "自動修正のキャンセルを学習"

        static func label(for sensitivity: CorrectionSensitivity) -> String {
            switch sensitivity {
            case .cautious: "慎重"
            case .standard: "標準"
            case .aggressive: "積極的"
            }
        }

        // 除外設定
        static let exclusionsNote = "アプリの固有 ID を指定することで、アプリごとに入力方法を指定できます。昇順で適用されます。"
        static let addApps = "アプリを追加…"
        static let exclusionsEmpty = "アプリはありません"
        static let importCSV = "CSV をインポート…"
        static let exportCSV = "CSV をエクスポート…"
        static let exportCSVFileName = "hajime-exclusions.csv"
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
        static let invalidTheme = "名前を入力してください"
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
        static let backupNote = "すべての設定を JSON としてインポート・エクスポート可能です。"
        static let exportSettings = "設定をエクスポート…"
        static let importSettings = "設定をインポート…"
        static let exportSettingsFileName = "hajime-settings.json"
        static let settingsImported = "設定を読み込みました"
        static let settingsImportFailed = "読み込めませんでした。はじめの設定ファイルではないか、大きすぎます"
        static let settingsExportFailed = "書き出せませんでした"

        // 情報
        static let about = "情報"
        static let version = "バージョン"
        /// バージョンの表示(ADR 0008．Windows と同じ「v0.1.0 (macOS)」の形)
        static func versionValue(_ version: String) -> String { "v\(version) (macOS)" }
        static let acknowledgements = "謝辞"
        static let acknowledgementsNote = "はじめは上記のソフトウェア・モデル・データを利用しています。"
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
        static let chooseFolder = "フォルダを選択…"
        static let lastSynced = "最後に同期した時刻"
        static let syncNow = "今すぐ同期"
        static let scopes = "同期する項目"
        static let note = "Dropbox や iCloud Drive のフォルダを選択すると、ほかの Mac と同期できます。"
        static let failed = "同期できませんでした"
        static let unreadable = "同期ファイルを読み込めないため、同期を停止しています"
        static let items = "項目ごとに選択"

        /// 項目(Settings の CodingKeys の名前)の表示名
        static func label(forField name: String) -> String {
            fieldLabels[name] ?? name
        }

        /// 設定の画面の項目と同じ名前にする
        private static let fieldLabels: [String: String] = [
            "inputStyle": Choice.inputStyle, "customRomaji": Settings.romajiTab, "liveConversion": Menu.liveConversion,
            "englishInputLiveConversion": Choice.englishInputLiveConversion, "wordLanguage": Features.languagePage, "yenKey": Choice.yenKey,
            "punctuation": UIStrings.Settings.punctuation, "brackets": UIStrings.Settings.brackets, "slash": UIStrings.Settings.slash,
            "spaceWidth": UIStrings.Settings.spaceWidth, "numberWidth": UIStrings.Settings.numberWidth,
            "alphabetWidth": More.alphabetWidth, "shiftStartsAlphabet": More.shiftStartsAlphabet, "punctuationCommits": UIStrings.Settings.punctuationCommits,
            "keypadDirect": Features.keypadDirect,
            "typoCorrection": Choice.typoCorrection, "candidatePresentation": Choice.presentation, "initialFocus": Choice.initialFocus,
            "suggestionDisplay": Choice.suggestionDisplay, "listCandidatesPerPage": More.listCandidates, "branchCandidatesPerPage": More.branchCandidates,
            "liveConversionDelay": More.liveConversionDelay, "liveConversionSkipLength": More.liveConversionSkipLength, "englishSkipLength": More.englishSkipLength, "correctionDelay": More.correctionDelay, "reviewCorrectionTimeout": More.reviewCorrectionTimeout,
            "lateCorrectionTimeout": More.lateCorrectionTimeout, "remembersRejectedCorrections": More.remembersRejectedCorrections, "correctionSensitivity": More.correctionSensitivity,
            "showsSuggestions": More.showsSuggestions, "correction": Features.correctionPage, "okuriganaStyle": Features.okurigana,
            "calculation": Features.calculation, "postalCodeConversion": Features.postalCode,
            "handwriting": Features.handwriting, "homophoneNotes": UIStrings.Settings.homophoneNotes, "misuseNotes": UIStrings.Settings.misuseNotes,
            "proofreading": UIStrings.Settings.proofreading, "misreadings": Features.misreadings, "prefersKatakana": Features.prefersKatakana,
            "showsVariantRow": Choice.variantRow, "showsKeyHints": Choice.keyHints, "numberKeySelection": UIStrings.Settings.numberKeySelection,
            "dateConversion": UIStrings.Settings.dateConversion, "symbolConversion": UIStrings.Settings.symbolConversion,
            "emojiConversion": UIStrings.Settings.emojiConversion, "learning": UIStrings.Settings.learning,
            "theme": More.theme, "candidateFontSize": UIStrings.Settings.fontSizeName, "showsModeIndicator": UIStrings.Settings.showsModeIndicator,
            "modeIndicatorDuration": More.modeIndicatorDuration, "customThemes": More.customThemes, "customThemeID": "使用するカスタムテーマ",
            "escapeSwitchesToDirect": UIStrings.Settings.escapeSwitchesToDirect, "terminalCommands": More.terminalCommands,
            "profileRules": UIStrings.Settings.appsTab, "restrainsLiveConversionInCode": More.restrainsLiveConversionInCode,
            "association": Association.enabled, "associationLimit": Association.limit, "showsAssociationHint": Association.hint,
            "recordsUsage": UIStrings.Settings.recordsUsage, "keyboardLayout": Choice.keyboardLayout, "keymap": Keys.tab,
            "symbolRules": Features.symbolsPage, "userDictionary": UIStrings.Settings.dictionaryTab,
            "importedDictionaries": Dictionaries.imported, "associationDictionaries": Association.dictionaries,
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
            case .associationDictionaries: "連想の辞書"
            case .appearance: "外観"
            case .exclusions: "除外設定"
            case .usage: "統計"
            }
        }
    }
}

extension KeyHint {
    /// 共通の案内の表(IndicatorLabels)から，キー設定の表で変換中にそのコマンドに割り当てた最初のキーを入れて作る．キーの無い案内は出さない
    static func make(_ table: [IndicatorLabels.Hint], keymap: Keymap) -> [KeyHint] {
        func first(_ command: KeymapCommand) -> String { keymap.strokes(for: command, in: .converting).first.map(UIStrings.Keys.name(of:)) ?? "" }
        return table.map { hint in
            KeyHint(key: hint.second.map { UIStrings.Keys.pair(first(hint.first), first($0)) } ?? first(hint.first), label: hint.label)
        }
        .filter { !$0.key.isEmpty }
    }
}
