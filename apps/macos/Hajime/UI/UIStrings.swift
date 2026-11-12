import HajimeApplication
import HajimeDomain

/// 画面に出す文言の置き場所．多言語にするときは Localizable.xcstrings に移す
enum UIStrings {
    /// 打っているあいだの続く語句の予測の窓
    enum Prediction {
        /// VoiceOver で読み上げる文
        static func announcement(_ text: String) -> String { "予測 \(text)" }
    }

    enum Candidate {
        static func variantsPosition(_ index: Int, _ total: Int) -> String { "文字種 \(index) / \(total)" }
        static func position(_ index: Int, _ total: Int) -> String { "\(index) / \(total)" }
        /// 語の意味のカードに入らなかった同音語の数
        static func more(_ count: Int) -> String { "+\(count)" }
        /// 意味が 2 つ以上あるときの，意味の番号(語の意味のカードの角丸の四角に入れる)
        static func senseNumber(_ number: Int) -> String { "\(number)" }
        /// コマンドの候補を読み上げる文(「コマンド、Claude を開く」)
        static func commandAnnouncement(_ title: String) -> String { "\(CandidatePanel.commandAnnotation)、\(title)" }
        /// ユーザー辞書の語のコメントを，候補に続けて読み上げる文(「ピヨ株式会社、コメント、東京都千代田区…」)
        static func commentAnnouncement(_ text: String, comment: String) -> String { "\(text)、コメント、\(comment)" }
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
        static let note = "上の辞書ほど優先"
        /// 読み込めるファイルの例の行(同じ意味の単語を「,」で区切った 1 行)
        static let fileExample = "美しい,綺麗,麗しい"
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
    /// 手のずれ・うろ覚えの語・動的なユーザー辞書・コマンド・変換マクロ(R-02・R-16・R-18・R-22)
    enum Extras {
        static let handShift = "手の位置のずれを修正（試験的）"
        /// 項目名の横に出す，その設定で出る候補の見本(打った文字と候補)
        static let looseReadingsExample = DefaultSettings.looseReadingsExample
        static let phoneticSpellingExample = DefaultSettings.phoneticSpellingExample
        static let handShiftExample = DefaultSettings.handShiftExample
        static let englishTermCandidatesExample = DefaultSettings.englishTermCandidatesExample
        static let handShiftNote = "左右どちらか、または両方の手が 1 キー横にずれたまま打った文を修正します。設定したキー配列のキーの位置を使います。"
        static let looseReadings = "うろ覚えのカタカナ語の候補"
        static let looseReadingsNote = "「しゅみれーしょん」から「シミュレーション」のように、読みを少し違えて覚えている語を候補に出します。"
        static let phoneticSpelling = "発音どおりに綴った英単語の候補"
        static let phoneticSpellingNote = "「ふぉと」から「photo」のように、音のとおりに綴った英単語の正しい綴りを候補に出します。"
        static let englishTermCandidates = "英語の語の辞書を使う"
        static let englishTerms = "英語の語の辞書に足した語"
        static let englishTermsSection = "英語の語の辞書"
        static let englishTermPlaceholder = "書き方どおりの語"
        /// 英語の語の欄の入力の例
        static let englishTermPrompt = "例: OpenAI"
        static let englishTermsEmpty = "足した語はありません"
        static let invalidEnglishTerm = "語は \(DefaultSettings.englishTermLengthRange.lowerBound)〜\(DefaultSettings.englishTermLengthRange.upperBound) 文字の英字にしてください"
        static let dynamicDictionary = "単語に書いた日付や時刻などを入力時の値にする"
        static let commandsPage = "コマンド"
        static let commandsSection = "コマンド"
        static let launcherCommands = "読みでコマンドを呼び出す"
        /// コマンドを同期しないことを示す 1 行
        static let commandsStoredLocally = "この Mac だけに保存"
        static let commandReading = "読み"
        static let commandTitle = "名前"
        static let commandKind = "動作"
        static let commandTarget = "行き先"
        static let commandsEmpty = "コマンドはありません"
        static let addCommand = "コマンドを追加…"
        static let editCommand = "編集…"
        static let removeCommand = "削除"
        static let chooseApplication = "アプリを選択…"
        static let chooseFile = "ファイルを選択…"
        static let invalidCommand = "読み・名前・行き先を確認してください"
        static let tooManyCommands = "これ以上コマンドを追加できません"
        static let save = "保存"
        static let cancel = "キャンセル"
        static let targetPlaceholderURL = "https://"
        static let targetPlaceholderShortcut = "ショートカットの名前"
        static let macrosSection = "変換マクロ"
        static let conversionMacros = "連想変換のキーで変換マクロを表示"
        static let macroPattern = "形"
        static let macrosEmpty = "マクロはありません"
        static let invalidMacro = "{text} か {reading} を含めてください"
        static let macroSkipsSameReading = "かなの語には読みを添える形を出さない"
        static let tryMacros = "変換マクロを試す"
        static let tryMacroWord = "試す語"
        static let tryMacroReading = "読み"

        static func label(for kind: LauncherCommand.Kind) -> String {
            switch kind {
            case .openApplication: "アプリを開く"
            case .openURL: "Web ページを開く"
            case .openFile: "ファイルを開く"
            case .runShortcut: "ショートカットを実行"
            }
        }
    }

    /// 単語と変換マクロに書ける書き方のチップ(R-21・R-22．TemplateReference)．見出しは短い言葉だけにし，意味はチップにポインターを載せたときに出す．
    /// まとまりとチップは Windows の strings.rs の templates と同じ(tools/check/check_strings.py が確かめる)
    enum Templates {
        /// 単語に書ける書き方(ユーザー辞書)
        static let word = TemplateReference(groups)
        /// 変換マクロに書ける書き方．単語に書けるものに，選んでいる語と読みを足す
        static let macro = TemplateReference([textGroup] + groups)
        /// 欄の右の「{ }」のボタン(チップを開け閉めする)の読み上げとツールチップ
        static let button = "書き方"
        static let buttonHelp = "日付・時刻・乱数などの書き方"

        private static let textGroup = TemplateReference.Group(title: "語", kind: .syntax, items: [
            .init("{text}", "選んでいる語"),
            .init("{reading}", "読み"),
            .init("{reading|katakana}", "読みのカタカナ"),
            .init("{reading|romaji}", "読みのローマ字"),
        ])

        private static let groups: [TemplateReference.Group] = [
            .init(title: "日時", kind: .syntax, items: [
                .init("{date}", "今日の日付"),
                .init("{time}", "今の時刻"),
                .init("{datetime}", "今の日時"),
                .init("{date:M月D日(ddd)}", "書式を決めた日付"),
                .init("{time:A K時m分}", "書式を決めた時刻"),
                .init("{utc}", "協定世界時の日時"),
                .init("{unixtime}", "UNIX 時間（秒）"),
            ]),
            .init(title: "ずらす", kind: .syntax, items: [
                .init("{date+1d}", "明日"),
                .init("{date-1d}", "昨日"),
                .init("{date+1w}", "1 週間後"),
                .init("{date+1M}", "1 か月後"),
                .init("{date+1y}", "1 年後"),
                .init("{time+30m}", "30 分後"),
                .init("{time+2h}", "2 時間後"),
                .init("{date+3b}", "3 営業日後（土日と祝日を除く）"),
                .init("{date@fri}", "今週の金曜日"),
                .init("{date+1w@mon}", "来週の月曜日"),
                .init("{date@1}", "今月 1 日"),
                .init("{date@end}", "今月末"),
                .init("{date+1M@1}", "来月 1 日"),
            ]),
            .init(title: "暦", kind: .syntax, items: [
                .init("{date:GGE年M月D日}", "和暦"),
                .init("{date:GGEE年}", "1 年を「元年」と書く和暦"),
                .init("{date:GGEE年M月D日|kansuji}", "漢数字の和暦"),
                .init("{date:FFFF年度}", "年度（4 月始まり）"),
                .init("{date:NN}", "和風月名"),
                .init("{date:JJ}", "干支"),
                .init("{holiday}", "祝日の名前（祝日でなければ空）"),
                .init("{holiday:平日}", "祝日の名前（祝日でなければ「平日」）"),
            ]),
            .init(title: "数", kind: .syntax, items: [
                .init("{days:12/25}", "12 月 25 日までの日数"),
                .init("{days:2027-03-31}", "2027 年 3 月 31 日までの日数"),
                .init("{age:1990-04-01}", "1990 年 4 月 1 日生まれの満年齢"),
                .init("{date:DDD}", "年の何日目か"),
                .init("{date:WW}", "週番号（ISO 8601）"),
                .init("{date:Q}", "四半期"),
            ]),
            .init(title: "挨拶", kind: .syntax, items: [
                .init("{season}", "その月の時候の挨拶"),
                .init("{greeting}", "時刻に合った挨拶"),
            ]),
            .init(title: "乱数", kind: .syntax, items: [
                .init("{uuid}", "UUID", codeValue: true),
                .init("{uuid|lower}", "小文字の UUID", codeValue: true),
                .init("{random:1-6}", "1〜6 の整数"),
                .init("{alnum:8}", "英数字 8 文字", codeValue: true),
                .init("{hex:8}", "16 進数 8 桁", codeValue: true),
                .init("{pick:はい,いいえ}", "並べたうちのどれか"),
            ]),
            .init(title: "括弧", kind: .syntax, items: [
                .init("{{", "「{」の文字"),
                .init("}}", "「}」の文字"),
            ]),
            .init(title: "変換", kind: .filter, items: [
                .init("|upper", "大文字", sample: "{date:MMM|upper}"),
                .init("|lower", "小文字", sample: "{date:EEE|lower}"),
                .init("|capitalize", "先頭だけ大文字", sample: "{date:EEE|lower|capitalize}"),
                .init("|katakana", "カタカナ", sample: "{greeting|katakana}"),
                .init("|hiragana", "ひらがな", sample: "{greeting|katakana|hiragana}"),
                .init("|halfwidth", "半角カタカナ", sample: "{greeting|halfwidth}"),
                .init("|fullwidth", "全角英数", sample: "{date|fullwidth}"),
                .init("|ascii", "半角英数", sample: "{date|fullwidth|ascii}"),
                .init("|romaji", "ローマ字", sample: "{greeting|romaji}"),
                .init("|snake", "小文字を _ でつなぐ", sample: "{date:MMMM EEEE|snake}", codeValue: true),
                .init("|camel", "2 語目から先頭を大文字にしてつなぐ", sample: "{date:MMMM EEEE|camel}", codeValue: true),
                .init("|pascal", "語の先頭を大文字にしてつなぐ", sample: "{date:MMMM EEEE|pascal}", codeValue: true),
                .init("|kebab", "小文字を - でつなぐ", sample: "{date:MMMM EEEE|kebab}", codeValue: true),
                .init("|url", "URL に入れる形", sample: "{date:NN|url}", codeValue: true),
                .init("|length", "文字数", sample: "{greeting|length}"),
                .init("|kansuji", "漢数字", sample: "{date:YYYY|kansuji}"),
                .init("|kanjidigits", "1 字ずつの漢数字", sample: "{date:YYYY|kanjidigits}"),
                .init("|daiji", "大字", sample: "{date:YYYY|daiji}"),
                .init("|comma", "3 桁区切り", sample: "{unixtime|comma}"),
                .init("|circled", "丸数字", sample: "{date:D|circled}"),
                .init("|html", "HTML に入れる形", sample: "{pick:<b>|html}", codeValue: true),
                .init("|base64", "Base64", sample: "{date|base64}", codeValue: true),
                .init("|upper|fullwidth", "左から順にかける", sample: "{date:MMM|upper|fullwidth}"),
            ]),
            .init(title: "書式", kind: .formatSymbol, items: [
                .init("YYYY", "年", sample: "{date:YYYY}"),
                .init("YY", "年（下 2 桁）", sample: "{date:YY}"),
                .init("MM", "月（2 桁）", sample: "{date:MM}"),
                .init("M", "月", sample: "{date:M}"),
                .init("MMMM", "英語の月", sample: "{date:MMMM}"),
                .init("MMM", "英語の月（略）", sample: "{date:MMM}"),
                .init("DD", "日（2 桁）", sample: "{date:DD}"),
                .init("D", "日", sample: "{date:D}"),
                .init("DDDD", "年の何日目か（3 桁）", sample: "{date:DDDD}"),
                .init("DDD", "年の何日目か", sample: "{date:DDD}"),
                .init("dddd", "曜日", sample: "{date:dddd}"),
                .init("ddd", "曜日（略）", sample: "{date:ddd}"),
                .init("EEEE", "英語の曜日", sample: "{date:EEEE}"),
                .init("EEE", "英語の曜日（略）", sample: "{date:EEE}"),
                .init("hh", "時（24 時間制、2 桁）", sample: "{time:hh}"),
                .init("h", "時（24 時間制）", sample: "{time:h}"),
                .init("KK", "時（12 時間制、2 桁）", sample: "{time:KK}"),
                .init("K", "時（12 時間制）", sample: "{time:K}"),
                .init("A", "午前・午後", sample: "{time:A}"),
                .init("AA", "AM・PM", sample: "{time:AA}"),
                .init("mm", "分（2 桁）", sample: "{time:mm}"),
                .init("m", "分", sample: "{time:m}"),
                .init("ss", "秒（2 桁）", sample: "{time:ss}"),
                .init("s", "秒", sample: "{time:s}"),
                .init("GG", "元号", sample: "{date:GG}"),
                .init("E", "元号の年", sample: "{date:E}"),
                .init("EE", "元号の年（1 年は「元」）", sample: "{date:EE}"),
                .init("FFFF", "年度（4 月始まり）", sample: "{date:FFFF}"),
                .init("FF", "年度（下 2 桁）", sample: "{date:FF}"),
                .init("NN", "和風月名", sample: "{date:NN}"),
                .init("JJ", "干支", sample: "{date:JJ}"),
                .init("WW", "週番号（2 桁）", sample: "{date:WW}"),
                .init("W", "週番号", sample: "{date:W}"),
                .init("Q", "四半期", sample: "{date:Q}"),
                .init("ZZ", "時間帯", sample: "{time:ZZ}"),
                .init("'Q'", "' で囲んだ文字はそのまま入る", sample: "{date:'Q'Q}"),
            ]),
        ]
    }

    /// 専門用語の辞書(R-29)．分野の名前は core の TermField.name(分岐図と同じ名前)
    enum Terms {
        static let enabled = "専門用語の辞書を使う"
        static let fields = "使う分野"
        static let note = "通常の辞書にもある語は、分野をオフにしても出ます"
    }

    /// 辞書のファイルを取り込む前に中身を見せるシート(ImportPreview)
    enum ImportPreview {
        static let line = "行"
        static let all = "すべて"
        static let defaulted = "名詞にする"
        static let unreadable = "読めない"
        static let meaning = "意味"
        static let words = "語"
        static func filter(_ name: String, _ count: Int) -> String { "\(name) \(count.formatted())" }
        /// 品詞の列が無い・知らない品詞の行に添えるツールチップ
        static let defaultedHelp = "品詞が無いため名詞として登録します"
        static let unreadableHelp = "読めないため取り込みません"
        /// 表の行の読み上げ(行の番号・列の値・意味を「、」でつなぐ)
        static func row(line: Int, values: [String]) -> String {
            (["\(line.formatted()) 行目"] + values).joined(separator: "、")
        }
        static func format(_ format: HajimeDomain.ImportPreview.Format) -> String {
            switch format {
            case .tabSeparated: "タブ区切り"
            case .commaSeparated: "「,」区切り"
            case .skk: "SKK"
            case .propertyList: "macOS のユーザ辞書"
            }
        }
        static func importButton(_ count: Int, _ kind: HajimeDomain.ImportPreview.Kind) -> String {
            kind == .association ? "\(count.formatted()) 件を取り込む" : "\(count.formatted()) 語を取り込む"
        }
    }

    enum Dictionaries {
        static let userWords = "登録した単語"
        static let imported = "取り込んだ辞書"
        static let terms = "専門用語"
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
        static let showDetails = "詳細を表示"
        static let hideDetails = "詳細を隠す"
        static let tooMany = "取り込める辞書は \(DefaultSettings.maximumImportedDictionaries) 個までです"
        static let importFailed = "辞書を取り込めませんでした。大きすぎるか、対応していない形式です"
        static let note = "上の辞書ほど優先"
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
        /// 打ち間違いを直した文節に添えるタグ
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
            return [first, second].filter { !$0.isEmpty }.joined(separator: IndicatorLabels.keySeparator)
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
            case .acceptSuggestion: "「もしかして」に修正・予測を確定"
            case .reconvert: "再変換"
            case .toHiragana: "全文をひらがなに変換"
            case .toKatakana: "全文を全角カタカナに変換"
            case .toHalfwidthKatakana: "全文を半角カタカナに変換"
            case .toFullwidthAlphanumeric: "全文を全角英数に変換"
            case .toHalfwidthAlphanumeric: "全文を半角英数に変換"
            case .switchKanaType: "かなの種類を切り替え"
            case .segmentToHiragana: "文節をひらがなに変換"
            case .segmentToKatakana: "文節を全角カタカナに変換"
            case .segmentToHalfwidthKatakana: "文節を半角カタカナに変換"
            case .nextCandidate: "次の候補"
            case .previousCandidate: "前の候補"
            case .nextCandidatePage: "次の候補のページ"
            case .previousCandidatePage: "前の候補のページ"
            case .firstCandidate: "先頭の候補"
            case .lastCandidate: "末尾の候補"
            case .associate: "連想変換"
            case .expandCandidates: "候補を表に広げる"
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
            case .backToReading: "全文を読みに戻す"
            case .resumeEditing: "読みに戻して末尾から編集"
            case .undoConversionEdit: "直前の変更を取り消し"
            case .undoPrediction: "予測の確定を取り消し"
            case .undoCommit: "確定を取り消し"
            case .forgetCandidate: "候補を学習から削除"
            case .forgetLastCommit: "最後の学習を取り消し"
            case .hidePrediction: "予測に表示しない"
            case .openSettings: "設定を開く"
            case .toggleLiveConversion: "ライブ変換の切り替え"
            case .handwriting: "手書き入力"
            case .emojiPalette: "絵文字のパレット"
            case .symbolPalette: "記号のパレット"
            case .kaomojiPalette: "顔文字のパレット"
            case .registerWord: "単語の登録"
            case .openUserDictionary: "ユーザー辞書を開く"
            case .openMenu: "入力メニューを開く"
            }
        }

        /// コマンドの説明(選ぶときの補足)．名前で分かるものは nil
        static func help(for command: KeymapCommand) -> String? {
            switch command {
            case .nextInputStyle: "ローマ字 → かな → 英字 → 英字(自動)"
            case .insertSpace: "「スペース幅」の幅の空白を入力します"
            case .insertAlternateSpace: "「スペース幅」と逆の幅の空白を入力します"
            case .convert: "英単語を修正した直後は、修正前に戻します"
            case .convertWithoutLearning: "学習を使わずに変換し、学習もしません"
            case .insertBoundary: "今の位置で文節を区切ります"
            case .acceptSuggestion: "「もしかして」の読みに修正します"
            case .reconvert: "確定した文字を変換し直します"
            case .switchKanaType: "ひらがな → 全角カタカナ → 半角カタカナ"
            case .nextCandidate: "入力中は変換を始めます"
            case .previousCandidate: "入力中は変換を始め、文字種を選択します"
            case .nextUncertainSegment, .previousUncertainSegment: "誤変換の多い文節に移動します"
            case .extendSegmentToWord, .shrinkSegmentToWord: "文節の終わりを単語の切れ目まで動かします"
            case .splitSegment: "切れ目の番号を数字キーで選んで区切ります"
            case .editSegment: "選択中の文節の読みを打ち直します"
            case .commitFirstSegment: "先頭の文節だけを確定します"
            case .cancel: "変換中は読みに戻し、入力中は読みを削除します"
            case .backToReading: "全文を読みに戻します"
            case .resumeEditing: "読みに戻り、末尾から入力を続けます"
            case .undoConversionEdit: "直前の候補と区切りの変更を戻します"
            case .undoPrediction: "確定した予測を取り消し、補う前の読みに戻します"
            case .undoCommit: "確定を取り消し、確定前の変換に戻します"
            case .segmentToHiragana, .segmentToKatakana, .segmentToHalfwidthKatakana: "選択中の文節だけを変換します"
            case .forgetCandidate: "選択中の候補を学習から削除します"
            case .forgetLastCommit: "最後に確定した語句の学習を取り消します"
            case .hidePrediction: "表示中の予測を「予測に表示しない語句」に追加します"
            case .handwriting: "「手書き入力」がオンのときに使えます"
            case .emojiPalette, .symbolPalette, .kaomojiPalette: "「絵文字と記号のパレット」がオンのときに使えます"
            case .associate: "選択中の文節を似た意味の単語の一覧にします"
            case .registerWord: "選択中の文字でユーザー辞書の登録を開きます"
            case .openMenu: "入力メニューを入力位置に表示します"
            case .expandCandidates: "候補を表に広げます"
            case .englishAutoStyle: "kyou no meeting → 今日の meeting"
            case .romajiStyle, .kanaStyle, .englishStyle: nil
            case .japaneseMode, .directMode, .toggleMode, .cancelAndDirectMode, .insertHalfwidthSpace, .insertFullwidthSpace, .deleteBackward,
                 .toHiragana, .toKatakana, .toHalfwidthKatakana, .toFullwidthAlphanumeric, .toHalfwidthAlphanumeric, .nextCandidatePage,
                 .previousCandidatePage, .firstCandidate, .lastCandidate, .nextSegment, .previousSegment, .firstSegment, .lastSegment,
                 .extendSegment, .shrinkSegment, .commit, .openSettings, .toggleLiveConversion, .openUserDictionary: nil
            }
        }

        static func label(for preset: KeymapPreset) -> String {
            switch preset {
            case .standard: "標準"
            case .windows: "Windows 風"
            case .mac: "Mac 風"
            case .emacs: "Emacs 風"
            case .vim: "Vim 風"
            case .atok: "ATOK 風"
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
        static let plainCharacter = "この状態ではこの文字を入力できなくなります"
        static func duplicateWarning(_ row: String) -> String { "同じキーの行より優先します: \(row)" }
        static func missing(state: String, command: String) -> String { "\(state)に「\(command)」のキーがありません" }
        static let addStandardKeys = "既定のキーを追加"

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
        /// 一覧の行を入れたときの結果の列(変換マクロ)
        static let result = "結果"
        /// 列の見出しを押したときの読み上げの案内
        static let sortHint = "並べ替え"
        static func overwrites(_ key: String) -> String { "「\(key)」はすでにあります。追加すると上書きします。" }
        static let alreadyRegistered = "すでに登録されています。"
        static let changesKind = "すでに登録されています。追加すると品詞とコメントを書き換えます。"
        static let full = "これ以上は追加できません。"
        static let noMatches = "一致する項目はありません"
    }

    enum Settings {
        static let windowTitle = "Hajime IME の設定"
        static let appName = "Hajime IME"
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
            case .imeOff: "IME をオフ"
            case .imeOn: "IME をオン"
            case .remembersMode: "IME のオンオフを記憶"
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
        static let numberSeparators = "数字のあとの句読点をピリオドとカンマに"
        static let alphanumericHyphen = "英数字のあとの長音をハイフンに"
        static let keys = "動作"
        static let punctuationCommits = "句読点で確定"
        static let questionExclamationCommits = "？と！で確定"
        static let keypadCalculation = "テンキーの Enter で計算"
        static let cyclesLetterCase = "英数に変えるキーで大文字と小文字を切り替え"
        static let numberKeySelection = "番号キーで候補を選択"
        static let showsModeIndicator = "入力モードの切り替えを表示"
        static let conversion = "変換"
        static let specialConversion = "特殊変換"
        static let dateConversion = "日付と時刻に変換"
        static let homophoneNotes = "語の意味と使い分けを表示"
        static let meaning = "語の意味"
        static let meaningPlacement = "意味の位置"
        static let meaningSenseLimit = "意味の数"
        static let showsPartOfSpeech = "品詞を表示"
        static let showsUsageExamples = "使い方の例を表示"
        static let showsHomophones = "同音語を表示"
        static let misuseNotes = "誤用の注釈を表示"
        static let proofreading = "校正支援"
        static let symbolConversion = "記号に変換"
        static let emojiSection = "絵文字"
        static let emojiConversion = "文節を絵文字に変換"
        static let emojiWordConversion = "語を絵文字に変換"
        /// 項目名の横に出す，その設定で出る候補の見本(読みと候補)
        static let emojiConversionExample = DefaultSettings.emojiConversionExample
        static let emojiWordConversionExample = DefaultSettings.emojiWordConversionExample
        static let emojiCandidatePosition = "絵文字の位置"
        static let emojiCandidateCount = "絵文字の数"
        static let showsEmojiNames = "絵文字の名前を表示"
        /// 絵文字の位置の値(「4 番目」)
        static func emojiCandidatePositionValue(_ position: Int) -> String { "\(position) 番目" }
        static let latexConversion = "LaTeX のコマンドに変換"
        static let numberForms = "数字の書き方"
        static let numberFormConversion = "数字を丸数字などに変換"
        static let numberFormCircled = "丸数字"
        static let numberFormParenthesized = "括弧付きとピリオド付きの数字"
        static let numberFormKanji = "漢数字"
        static let numberFormRoman = "ローマ数字"
        static let learning = "学習"
        static let zenzaiModel = "Zenzai のモデル"
        /// 併用を選んだときに出す，入力中と変換で使うモデル
        static let zenzaiCombinedNote = "入力中: 速さを優先 / 変換: 精度を優先"
        static let candidateReranking = "2 番目以降の候補を Zenzai で並べ替え"
        static let resetLearning = "学習結果を消去"
        static let reading = "読み"
        static let word = "単語"
        static let add = "追加"
        static let remove = "削除"
        static let importDictionary = "インポート…"
        static let exportDictionary = "エクスポート…"
        static let exportFileName = "hajime-user-dictionary.txt"
        static let comment = "コメント"
        static let commentPrompt = "コメント(省略可)"
        static let wordClass = "品詞"
        static let personNameGroup = "人名"
        static let otherWordClasses = "その他"
        static let abbreviationNote = "読みだけを変換したときに出ます"

        static func label(for wordClass: WordClass) -> String {
            switch wordClass {
            case .noun: "名詞"
            case .personName: "人名(姓と名)"
            case .surname: "人名(姓のみ)"
            case .givenName: "人名(名のみ)"
            case .place: "地名"
            case .symbol: "顔文字・記号"
            case .abbreviation: "短縮よみ"
            case .properNoun: "固有名詞"
            case .organization: "組織名"
            case .suruNoun: "サ変名詞(〜する)"
            case .adjectivalNoun: "形容動詞(〜な)"
            case .adverb: "副詞"
            case .interjection: "感動詞"
            }
        }
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

        static func label(for placement: MeaningPlacement) -> String {
            switch placement {
            case .side: "吹き出し"
            case .below: "候補の下"
            }
        }

        static func label(for style: PunctuationStyle) -> String { style.comma + style.period }
        static func label(for style: BracketStyle) -> String { style.open + style.close }
        static func label(for style: SlashStyle) -> String { style.text }

        static func label(for width: CharacterWidth) -> String {
            switch width {
            case .halfwidth: "半角"
            case .fullwidth: "全角"
            }
        }

        static func label(for choice: ZenzaiModelChoice) -> String {
            switch choice {
            case .accurate: "精度を優先"
            case .fast: "速さを優先"
            case .combined: "併用"
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
        static let windowTitle = "Hajime IME へようこそ"
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
        static func label(for style: ModeSwitchStyle) -> String {
            switch style {
            case .separate: "英数キーとかなキーで分ける"
            case .single: "1 つのキーで切り替え"
            }
        }

        // アプリごとの入力モード
        static let appModesTitle = "アプリごとの入力モード"
        static let appModesDetail = "除外設定でアプリを追加して選びます。"
        /// 実演でアプリを切り替えるときに出す名前
        static let demoNotes = "メモ"
        static let demoTerminal = "ターミナル"
        /// 実演で押すキーの名前(キーキャップに出す)
        static let demoKeyKana = "かな"
        static let demoKeyEisu = "英数"

        // b. 自動補正
        static let correctionTitle = "自動補正"
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
        static let themeDetail = "色や書体は、あとから設定の画面で変えられます。"

        // d. ライブ変換
        static let liveTitle = "ライブ変換"
        static let liveOn = "ライブ変換を使う"
        static let liveOff = "使わない"
        static let liveDelay = "漢字にするまでの時間"

        // e. 候補の出し方
        static let presentationTitle = "候補の出し方"
        static func detail(for presentation: CandidatePresentation) -> String {
            switch presentation {
            case .automatic: "文節ごとに候補を枝分かれさせます。"
            case .segmentList: "選んでいる文節の候補を縦に並べます。"
            case .list: "文全体の候補を縦に並べます。"
            }
        }
        static let initialFocus = "最初に選ぶ文節"

        // f. 入力する文字
        static let charactersTitle = "入力する文字"

        // g. 機能の紹介
        static let featuresTitle = "便利な機能"
        static let extrasTitle = "試験的な機能"
        static let extrasDetail = "既定ではオフの機能です。"
        static let macros = "変換マクロ"
        static let macrosDetail = "連想変換と同じ Shift + Space で、選んでいる語を「」で囲む・ルビを付けるなどした形を出します。"
        static let dynamicDictionary = "動的なユーザー辞書"
        static let dynamicDictionaryDetail = "単語に {datetime:YYYY/MM/DD} などを書くと、入力したときの値にします。"
        static let commands = "コマンド"
        static let commandsDetail = "読みでアプリや Web ページを開きます。候補から選んだときだけ動きます。設定の「コマンド」で登録します。"
        static let commandsExample = "Claude を開く"
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
        static let palette = "絵文字と記号"
        static let checkForUpdates = "更新を確認"
        static let registerWord = "単語の登録…"
        static let userDictionary = "ユーザー辞書…"
    }

    /// 設定の画面の選択肢の名前
    enum Choice {
        static let inputStyle = "入力方式"
        static let keyboardLayout = "キー配列"
        static let englishInputLiveConversion = "英字入力のライブ変換"
        /// 項目名の横に出す，その設定で出る候補の見本(打った文字と候補)
        static let englishInputLiveConversionExample = DefaultSettings.englishInputLiveConversionExample
        static let englishAutoExample = DefaultSettings.englishAutoExample

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
        static let predictionDisplay = "入力中の予測"
        static let predictionPrefersHistory = "入力履歴にある予測を優先"
        static let predictionFromCorrection = "打ち間違いを直した読みからも予測"
        static let hiddenPredictions = "予測に表示しない語句"
        static let hiddenPredictionPlaceholder = "語句"
        static let hiddenPredictionsEmpty = "予測に表示しない語句はありません"
        static let invalidHiddenPrediction = "予測に表示しない語句は \(DefaultSettings.maximumHiddenPredictionLength) 文字までにしてください"

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
    /// 絵文字と記号のパレット(R-26)の設定の項目
    enum Palette {
        static let enabled = "絵文字と記号のパレット"
        static let closesAfterInsert = "入力したらパレットを閉じる"
        static let recordsHistory = "パレットで使った文字を記録"
        static let columns = "パレットの列数"
        static let rows = "パレットの行数"
        static let cellSize = "パレットのマスの大きさ"
        static let showsPreview = "パレットに文字の説明を表示"
        static let showsUnicodeName = "説明に Unicode の名前を表示"
        static let showsReadings = "説明に読みを表示"
        static let showsShortcodes = "説明にショートコードを表示"
        static let showsCodePoints = "説明にコードポイントを表示"
        /// 説明の欄の項目名．englishNameLabel は UCD の名前の無い並び(国旗など)で代わりに出す英語の名前
        static let unicodeNameLabel = "Unicode"
        static let englishNameLabel = "英語"
        static let readingsLabel = "読み"
        static let shortcodesLabel = "ショートコード"
        static let codePointsLabel = "コードポイント"
        static let frequentRows = "よく使う文字の行数"
        static let page = "絵文字と記号"
        static let behavior = "パレット"
        static let look = "パレットの見た目"
        static let emojiKey = "絵文字のパレットを開くキー"
        static let symbolKey = "記号のパレットを開くキー"
        static let kaomojiKey = "顔文字のパレットを開くキー"
        static let noKey = "なし"
        static let clearHistory = "使った文字の記録を消去"
        static let clearHistoryQuestion = "使った文字の記録を消去しますか？"
        static let clearHistoryNote = "ピン留めと肌の色は残ります"
        static let openKeys = "キー設定を開く"
        static func cellSizeValue(_ size: Int) -> String { "\(cellSize)：\(size) pt" }
    }

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
        static let usesContextExample = DefaultSettings.usesContextExample
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
        static let gridColumns = "表の列数"
        static let expandsGridOnPaging = "候補を送り続けたら表に広げる"
        /// 表に広げたときの大きさ(一覧の候補数の行 × 列数)
        static func gridSize(rows: Int, columns: Int) -> String { "\(rows) 行 × \(columns) 列" }
        static let contextualSegmentCandidates = "前後の文脈で候補を並べ替え"
        static let listSegmentAlternatives = "一覧に文節を入れ替えた候補を表示"
        static let listSegmentAlternativesExample = DefaultSettings.listSegmentAlternativesExample
        static let liveConversionDelay = "漢字にするまでの待ち時間"
        static let liveConversionSkipLength = "ライブ変換しない文字数"
        static let englishSkipLength = "英単語にしない文字数"
        static func skipLength(_ value: Int) -> String { value == 0 ? "オフ" : "\(value) 文字以下" }
        static let suggestionSkipCount = "入力中の候補を表示しない件数"
        static func skipCount(_ value: Int) -> String { value == 0 ? "オフ" : "\(value) 件以下" }
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
        /// 一覧の並びの意味を示す 1 行
        static let exclusionsOrder = "上の行ほど優先"
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
        static let fontStyle = "スタイル"
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
            return String(format: "%@と%@ %.1f : 1(目安 %.1f : 1 以上)", name, ground, ratio, pair.minimum)
        }

        static func label(for style: CustomTheme.BranchStyle) -> String {
            switch style {
            case .curved: "曲線"
            case .straight: "直線"
            }
        }

        // バックアップ
        static let backup = "バックアップ"
        static let exportSettings = "設定をエクスポート…"
        static let importSettings = "設定をインポート…"
        static let exportSettingsFileName = "hajime-settings.json"
        static let settingsImported = "設定を読み込みました"
        static let settingsExported = "設定を書き出しました"
        static let settingsImportFailed = "読み込めませんでした。Hajime IME の設定ファイルではないか、大きすぎます"
        static let settingsExportFailed = "書き出せませんでした"

        // 情報
        static let about = "情報"
        static let version = "バージョン"
        /// バージョンの表示(ADR 0008．Windows と同じ「v0.1.0 (macOS)」の形)
        static func versionValue(_ version: String) -> String { "v\(version) (macOS)" }
        static let checkForUpdates = "更新を確認"
        static let acknowledgements = "謝辞"
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
            "alphabetWidth": More.alphabetWidth, "shiftStartsAlphabet": More.shiftStartsAlphabet,
            "numberSeparators": UIStrings.Settings.numberSeparators, "alphanumericHyphen": UIStrings.Settings.alphanumericHyphen,
            "punctuationCommits": UIStrings.Settings.punctuationCommits,
            "keypadDirect": Features.keypadDirect, "questionExclamationCommits": UIStrings.Settings.questionExclamationCommits,
            "keypadCalculation": UIStrings.Settings.keypadCalculation, "cyclesLetterCase": UIStrings.Settings.cyclesLetterCase,
            "typoCorrection": Choice.typoCorrection, "candidatePresentation": Choice.presentation, "initialFocus": Choice.initialFocus,
            "suggestionDisplay": Choice.suggestionDisplay, "predictionDisplay": Choice.predictionDisplay, "predictionPrefersHistory": Choice.predictionPrefersHistory,
            "predictionFromCorrection": Choice.predictionFromCorrection, "hiddenPredictions": Choice.hiddenPredictions, "suggestionSkipCount": More.suggestionSkipCount,
            "listCandidatesPerPage": More.listCandidates, "branchCandidatesPerPage": More.branchCandidates, "candidateGridColumns": More.gridColumns, "expandsGridOnPaging": More.expandsGridOnPaging,
            "contextualSegmentCandidates": More.contextualSegmentCandidates, "listSegmentAlternatives": More.listSegmentAlternatives,
            "liveConversionDelay": More.liveConversionDelay, "liveConversionSkipLength": More.liveConversionSkipLength, "englishSkipLength": More.englishSkipLength, "correctionDelay": More.correctionDelay, "reviewCorrectionTimeout": More.reviewCorrectionTimeout,
            "lateCorrectionTimeout": More.lateCorrectionTimeout, "remembersRejectedCorrections": More.remembersRejectedCorrections, "correctionSensitivity": More.correctionSensitivity,
            "showsSuggestions": More.showsSuggestions, "correction": Features.correctionPage, "okuriganaStyle": Features.okurigana,
            "calculation": Features.calculation, "postalCodeConversion": Features.postalCode,
            "handwriting": Features.handwriting, "homophoneNotes": UIStrings.Settings.homophoneNotes, "misuseNotes": UIStrings.Settings.misuseNotes,
            "meaningPlacement": UIStrings.Settings.meaningPlacement, "meaningSenseLimit": UIStrings.Settings.meaningSenseLimit,
            "showsPartOfSpeech": UIStrings.Settings.showsPartOfSpeech, "showsUsageExamples": UIStrings.Settings.showsUsageExamples,
            "showsHomophones": UIStrings.Settings.showsHomophones,
            "proofreading": UIStrings.Settings.proofreading, "misreadings": Features.misreadings, "prefersKatakana": Features.prefersKatakana,
            "showsVariantRow": Choice.variantRow, "showsKeyHints": Choice.keyHints, "numberKeySelection": UIStrings.Settings.numberKeySelection,
            "dateConversion": UIStrings.Settings.dateConversion, "symbolConversion": UIStrings.Settings.symbolConversion,
            "emojiConversion": UIStrings.Settings.emojiConversion, "emojiWordConversion": UIStrings.Settings.emojiWordConversion,
            "emojiCandidatePosition": UIStrings.Settings.emojiCandidatePosition,
            "emojiCandidateCount": UIStrings.Settings.emojiCandidateCount, "showsEmojiNames": UIStrings.Settings.showsEmojiNames,
            "latexConversion": UIStrings.Settings.latexConversion,
            "numberFormConversion": UIStrings.Settings.numberFormConversion, "numberFormCircled": UIStrings.Settings.numberFormCircled,
            "numberFormParenthesized": UIStrings.Settings.numberFormParenthesized, "numberFormKanji": UIStrings.Settings.numberFormKanji,
            "numberFormRoman": UIStrings.Settings.numberFormRoman, "learning": UIStrings.Settings.learning, "zenzaiModel": UIStrings.Settings.zenzaiModel,
            "candidateReranking": UIStrings.Settings.candidateReranking,
            "theme": More.theme, "candidateFontSize": UIStrings.Settings.fontSizeName, "showsModeIndicator": UIStrings.Settings.showsModeIndicator,
            "modeIndicatorDuration": More.modeIndicatorDuration, "customThemes": More.customThemes, "customThemeID": "使用するカスタムテーマ",
            "escapeSwitchesToDirect": UIStrings.Settings.escapeSwitchesToDirect, "terminalCommands": More.terminalCommands,
            "profileRules": UIStrings.Settings.appsTab, "restrainsLiveConversionInCode": More.restrainsLiveConversionInCode,
            "association": Association.enabled, "associationLimit": Association.limit, "showsAssociationHint": Association.hint,
            "recordsUsage": UIStrings.Settings.recordsUsage, "keyboardLayout": Choice.keyboardLayout, "keymap": Keys.tab,
            "symbolRules": Features.symbolsPage, "userDictionary": UIStrings.Settings.dictionaryTab,
            "importedDictionaries": Dictionaries.imported, "associationDictionaries": Association.dictionaries,
            "termDictionary": Terms.enabled, "termFields": "専門用語の辞書の分野",
            "handShiftCorrection": Extras.handShift, "looseReadings": Extras.looseReadings, "phoneticSpelling": Extras.phoneticSpelling,
            "dynamicDictionary": Extras.dynamicDictionary, "conversionMacros": Extras.conversionMacros, "macros": Extras.macrosSection,
            "macroSkipsSameReading": Extras.macroSkipsSameReading,
            "launcherCommands": Extras.launcherCommands, "commands": Extras.commandsPage,
            "englishTermCandidates": Extras.englishTermCandidates, "englishTerms": Extras.englishTerms,
            "palette": Palette.enabled, "paletteClosesAfterInsert": Palette.closesAfterInsert, "paletteRecordsHistory": Palette.recordsHistory,
            "paletteColumns": Palette.columns, "paletteRows": Palette.rows, "paletteCellSize": Palette.cellSize,
            "paletteShowsPreview": Palette.showsPreview, "paletteFrequentRows": Palette.frequentRows,
            "paletteShowsUnicodeName": Palette.showsUnicodeName, "paletteShowsReadings": Palette.showsReadings,
            "paletteShowsShortcodes": Palette.showsShortcodes, "paletteShowsCodePoints": Palette.showsCodePoints,
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
            case .commands: "コマンド"
            }
        }
    }
}

extension KeyHint {
    /// 共通の案内の表(IndicatorLabels)から，キー設定の表で変換中にそのコマンドに割り当てた最初のキーを入れて作る．キーの無い案内は出さない
    static func make(_ table: [IndicatorLabels.Hint], keymap: Keymap) -> [KeyHint] {
        table.map { hint in
            let strokes = hint.strokes(in: keymap)
            let first = strokes.first.map(UIStrings.Keys.name(of:)) ?? ""
            return KeyHint(key: hint.second == nil ? first : UIStrings.Keys.pair(first, strokes.second.map(UIStrings.Keys.name(of:)) ?? ""), label: hint.label)
        }
        .filter { !$0.key.isEmpty }
    }
}
