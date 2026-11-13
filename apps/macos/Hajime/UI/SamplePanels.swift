import HajimeApplication

import HajimeDomain

/// 見本の分岐図と候補の一覧．設定の画面の外観のプレビューと，見本の画像(SnapshotRenderer)で使う
enum SamplePanels {
    static let list = CandidatePanel(
        variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
        selectedVariant: nil,
        entries: ["変換", "返還", "偏官", "へんかん", "ヘンカン"].map { .init(text: $0, annotation: nil) },
        selectedEntry: 1, focus: .candidate, position: 2, total: 12, note: nil
    )

    /// 候補を表に広げた一覧(キー設定の表の「候補を表に広げる」)．9 行 × 4 列で，2 列目の候補を選んでいる．番号は選んでいる列にだけ振る
    static let grid: CandidatePanel = {
        let words = ["高", "校", "考", "効", "行", "公", "工", "功", "好", "光", "口", "向", "項", "幸", "構", "港", "稿", "鋼",
                     "講", "購", "候", "交", "甲", "江", "孝", "抗", "拘", "肯", "荒", "香", "航", "康", "黄", "侯", "坑", "后"]
        var panel = CandidatePanel(
            variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
            selectedVariant: nil,
            entries: words.map { .init(text: $0, annotation: nil) },
            selectedEntry: 11, focus: .candidate, position: 12, total: 58, note: nil
        )
        panel.columnLength = DefaultSettings.candidatesPerPage
        return panel
    }()

    /// 打っているあいだの候補の窓．読みの変換の候補だけを並べ(続く語句の予測は別の窓)，選び始めるまで番号を振らず，
    /// 足元に選び始めるキーを出す．予測の窓を出していないときは Tab でも選び始める
    static let suggestion: CandidatePanel = {
        var panel = CandidatePanel(
            variants: [], selectedVariant: nil,
            entries: ["なんだ", "何だ", "なんだ？"].map { .init(text: $0, annotation: nil) },
            selectedEntry: nil, focus: .candidate, position: 0, total: 3,
            note: Note(tone: .info, title: "", key: ["↓", "Tab"].joined(separator: IndicatorLabels.keySeparator), keyAction: "選択")
        )
        panel.showsNumbers = false
        return panel
    }()

    /// コマンドの候補(R-22)を含む一覧．selected は選んでいる行．コマンドを選んでいれば，確定のキーで動くことを足元に出す
    static func commands(selected: Int) -> CandidatePanel {
        let entries: [CandidatePanel.Entry] = [
            .init(text: "クロード", annotation: nil),
            .init(text: "Claude を開く", annotation: CandidatePanel.commandAnnotation, command: .openApplication),
            .init(text: "Claude のサイト", annotation: CandidatePanel.commandAnnotation, command: .openURL),
            .init(text: "黒戸", annotation: nil),
        ]
        let note = entries[selected].command == nil ? nil : Note(tone: .info, title: "", key: "Enter", keyAction: "実行")
        return CandidatePanel(variants: [], selectedVariant: nil, entries: entries, selectedEntry: selected, focus: .candidate,
                              position: selected + 1, total: entries.count, note: note)
    }

    /// ユーザー辞書の語のコメント(R-21)をタグに出した一覧．タグを押すと候補の代わりにコメントを入れる．長いコメントはタグでは先頭だけを出す
    static let comment = CandidatePanel(
        variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
        selectedVariant: nil,
        entries: [
            .init(text: "会社", annotation: nil),
            .init(text: "ピヨ株式会社", annotation: "東京都千代田区千代田1-1 ピヨピヨビル…", hasComment: true),
            .init(text: "かいしゃ", annotation: nil),
            .init(text: "カイシャ", annotation: nil),
        ],
        selectedEntry: 1, focus: .candidate, position: 2, total: 4, note: nil
    )

    /// ユーザー辞書の語のコメントを下の枝に添えた分岐図．コメントの無い第 1 候補を選んでいる(選んでいない枝のタグの見え方)
    static let commentLattice: LatticePanel = {
        var column = LatticePanel.Column(text: "会社", alternatives: ["会社", "ピヨ株式会社", "かいしゃ"], selectedAlternative: 0,
                                         isFocused: true, isUncertain: false)
        column.alternativeNotes = [nil, "千代田区千代田1-1", nil]
        column.alternativeComments = [false, true, false]
        return LatticePanel(columns: [column, .init(text: "に行く", isFocused: false, isUncertain: false)], position: 1, total: 3)
    }()

    /// 同音異義語の使い分け(R-08)．意味が 2 つあるもの
    static let homophone = HomophoneNote(
        word: "撮る", partOfSpeech: .verb,
        senses: [.init(meaning: "写真や動画を写す", example: "記念写真を撮った"), .init(meaning: "映画やテレビ番組などを撮影する", example: "ドラマを撮る")],
        others: ["取る", "採る", "執る", "捕る"])

    /// 同音異義語の無い語の意味(R-08)．同音語の行を出さない．意味が長く，カードの幅で折り返す
    static let meaning = HomophoneNote(
        word: "動く", partOfSpeech: .verb,
        senses: [.init(meaning: "位置や姿勢が変わる。止まっていたものが移る", example: "車がゆっくり動く"),
                 .init(meaning: "機械などが作動する", example: "時計が動き始める"),
                 .init(meaning: "気持ちが変わる。心が揺れる", example: "心が動く")],
        others: [])

    /// 読みで引いた絵文字(設定の「語を絵文字に変換」)．「ねこがかわいい」を変換し，「ねこが」の文節の 4・5 番目に語を絵文字にした候補を出す．
    /// 絵文字の名前(CLDR)を候補の横に薄く添える．候補は hajime-playground --panels で求めたもの
    static let emojiCandidates = ["猫が", "ネコが", "ネコ画", "🐈が", "😺が", "ねこ画", "猫画", "根子が", "音子が"]
    static let emojiNames: [String: String] = ["🐈が": "ネコ", "😺が": "にっこり笑う猫"]

    /// 設定の画面の絵文字の見本．位置・数・名前の設定を変えると，その場で並びが変わる．
    /// 「文節を絵文字に変換」がオンなら「ねこ」の文節全体の絵文字を，オフなら「ねこが」の語を絵文字にした候補を並べる．どちらもオフなら nil．
    /// 位置と数がわかる範囲(絵文字の後ろのふだんの候補 1 つまで．1 ページに収まる分)だけを出す
    static func emojiPlacement(_ settings: HajimeDomain.Settings) -> CandidatePanel? {
        guard let placement = settings.emojiPlacement else { return nil }
        let tail = settings.emojiConversion ? "" : emojiPlacementParticle
        let emoji = emojiPlacementEmoji.prefix(placement.count).map { (text: $0.emoji + tail, name: $0.name) }
        let names = Dictionary(uniqueKeysWithValues: emoji.map { ($0.text, $0.name) })
        let texts = placement.placed(emojiPlacementWords.map { $0 + tail } + emoji.map(\.text)) { names[$0] != nil }
        return CandidatePanel(
            variants: [], selectedVariant: nil,
            entries: texts.prefix(min(settings.listCandidatesPerPage, placement.index + placement.count + 1)).map { .init(text: $0, annotation: nil, detail: settings.showsEmojiNames ? names[$0] : nil) },
            selectedEntry: 0, focus: .candidate, position: 1, total: texts.count, note: nil
        )
    }

    /// 見本の「ねこ」のふだんの候補(位置の上限 9 番目より前を埋める数)と，「ねこが」にするときの助詞
    private static let emojiPlacementWords = ["猫", "ネコ", "ねこ", "根子", "音子", "値子", "寝子", "子子", "弥固"]
    private static let emojiPlacementParticle = "が"
    /// 見本の「ねこ」の絵文字と名前(数の上限 5 つ．名前は CLDR)
    private static let emojiPlacementEmoji: [(emoji: String, name: String)] = [
        ("🐈", "ネコ"), ("😺", "にっこり笑う猫"), ("😸", "にやっと笑う猫"), ("😹", "嬉し泣きする猫"), ("😻", "目がハートの猫"),
    ]

    /// 文節ごとの一覧で絵文字を選んだところ
    static let emojiList = CandidatePanel(
        variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) }, selectedVariant: nil,
        entries: emojiCandidates.map { .init(text: $0, annotation: nil, detail: emojiNames[$0]) },
        selectedEntry: 3, focus: .candidate, position: 4, total: 11, note: nil
    )

    /// 打っているあいだの候補の窓．絵文字は変換したときの候補にだけ出すので，ここには出さない(候補は --panels で求めたもの)
    static let emojiSuggestion: CandidatePanel = {
        var panel = CandidatePanel(
            variants: [], selectedVariant: nil,
            entries: ["猫が可愛い", "猫がかわいい", "ねこが可愛い", "ネコが可愛い", "ねこがかわいい"].map { .init(text: $0, annotation: nil) },
            selectedEntry: nil, focus: .candidate, position: 0, total: 5,
            note: Note(tone: .info, title: "", key: ["↓", "Tab"].joined(separator: IndicatorLabels.keySeparator), keyAction: "選択")
        )
        panel.showsNumbers = false
        return panel
    }()

    /// 分岐図で語を絵文字にした候補を選んだところ
    static let emojiLattice: LatticePanel = {
        let alternatives = Array(emojiCandidates.prefix(5))
        var column = LatticePanel.Column(text: "🐈が", alternatives: alternatives, selectedAlternative: 3,
                                         variants: ["ねこが", "ネコガ", "ﾈｺｶﾞ"], isFocused: true, isUncertain: false)
        column.alternativeDetails = alternatives.map { emojiNames[$0] }
        return LatticePanel(columns: [column, .init(text: "かわいい", isFocused: false, isUncertain: false)], position: 1, total: 11)
    }()

    static let lattice = LatticePanel(columns: [
        .init(text: "私の", isFocused: false, isUncertain: false),
        .init(text: "名前は", isFocused: false, isUncertain: false, isDecided: true),
        .init(text: "中野です", alternatives: ["中のです", "中野です", "仲のです", "那珂のです"], selectedAlternative: 1,
              variants: ["なかのです", "ナカノデス", "ﾅｶﾉﾃﾞｽ"], isFocused: true, isUncertain: true, shorter: "中野で", longer: nil),
    ], position: 1, total: 8)
}

/// 見本のパレット(R-26)．設定の画面の外観のプレビューと，見本の画像(SnapshotRenderer)で使う
enum SamplePalettes {
    private static let emojiRows: [[String]] = [
        ["👍", "🙇", "😂", "🎉", "🙏", "✨", "👀", "🔥", "💯"],
        ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂"],
        ["🙃", "🫠", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘"],
        ["😗", "☺️", "😚", "😙", "🥲", "😋", "😛", "😜", "🤪"],
        ["😝", "🤑", "🤗", "🤭", "🫢", "🫣", "🤫", "🤔", "🫡"],
        ["🤐", "🤨", "😐", "😑", "😶", "🫥", "😏", "😒", "🙄"],
    ]
    private static let symbolRows: [[String]] = [
        ["※", "→", "★", "〒", "①", "℃"],
        ["→", "←", "↑", "↓", "↔", "↕", "↗", "↘", "↙"],
        ["↖", "⇒", "⇐", "⇑", "⇓", "⇔", "⇕", "⟶", "⟵"],
        ["⟷", "⟹", "⟸", "⟺", "↦", "↤", "↩", "↪", "↺"],
        ["↻", "⤴", "⤵", "↰", "↱", "↲", "↳", "↴", "↵"],
        ["⇄", "⇅", "⇆", "⇇", "⇈", "⇉", "⇊", "⇋", "⇌"],
    ]

    private static let hints: [PalettePanel.Hint] = [
        .init(key: "Enter", action: PaletteStrings.insert), .init(key: "Tab", action: PaletteStrings.category),
        .init(key: "⌃Tab", action: PaletteStrings.switchKind), .init(key: "⇧Enter", action: PaletteStrings.insertAndContinue),
        .init(key: "⌥Enter", action: PaletteStrings.skinTone), .init(key: "⌃D", action: PaletteStrings.pin), .init(key: "Esc", action: PaletteStrings.close),
    ]

    private static func modes(_ kind: PaletteItem.Kind) -> [PalettePanel.Mode] {
        PaletteItem.Kind.allCases.map { .init(kind: $0, title: PaletteStrings.title(of: $0), isSelected: $0 == kind) }
    }

    private static func rows(_ texts: [[String]], titles: [String], starts: Set<Int>) -> [PalettePanel.Row] {
        texts.enumerated().map { index, row in
            PalettePanel.Row(index: index, cells: row.map { .init(text: $0, name: $0) }, startsSection: starts.contains(index), sectionTitle: titles[index])
        }
    }

    private static let frequentSample = ["👍", "🙇", "😂", "🎉", "🙏", "✨", "👀", "🔥", "💯", "❤️", "🙌", "😊", "🥺", "😭", "👏", "🤔", "😅", "🍣",
                                         "☕️", "🎂", "🌸", "🐱", "🚀", "💡", "📌", "✅", "⚠️", "🆗"]
    private static let smileySample = ["😀", "😃", "😄", "😁", "😆", "😅", "🤣", "😂", "🙂", "🙃", "🫠", "😉", "😊", "😇", "🥰", "😍", "🤩", "😘",
                                       "😗", "☺️", "😚", "😙", "🥲", "😋", "😛", "😜", "🤪", "😝", "🤑", "🤗", "🤭", "🫢", "🫣", "🤫", "🤔", "🫡",
                                       "🤐", "🤨", "😐", "😑", "😶", "🫥", "😏", "😒", "🙄", "😬", "😮‍💨", "🤥", "🫨", "😌", "😔", "😪", "🤤", "😴",
                                       "😷", "🤒", "🤕", "🤢", "🤮", "🤧", "🥵", "🥶", "🥴", "😵", "🤯", "🤠", "🥳", "🥸", "😎", "🤓", "🧐", "😕",
                                       "🫤", "😟", "🙁", "😮", "😯", "😲", "😳", "🥺", "🥹", "😦", "😧", "😨", "😰", "😥", "😢", "😭", "😱", "😖",
                                       "😣", "😞", "😓", "😩", "😫", "🥱", "😤", "😡", "😠", "🤬", "😈", "👿", "💀", "☠️", "💩", "🤡", "👹", "👺"]

    /// 説明の欄の見本にする文字．値は同梱の表(data/palette/palette.tsv)の行のとおり
    private static let smile = PaletteItem(kind: .emoji, category: .smileys, text: "😄", japaneseName: "笑顔", nameReading: "えがお",
                                           englishName: "grinning face with smiling eyes", readings: ["すまいる", "はっぴー", "わーい", "えがお", "かお"],
                                           shortcodes: ["smile"])
    private static let bowing = PaletteItem(kind: .emoji, category: .people, text: "🙇", japaneseName: "おじぎする人", nameReading: "おじぎするひと",
                                            englishName: "person bowing",
                                            readings: ["おじぎ", "ごめんなさい", "じぇすちゃー", "おじぎするひと", "おねがい", "しゃざい", "どげざ", "ゆるして"],
                                            shortcodes: ["bow"], skinTones: ["🙇🏻", "🙇🏼", "🙇🏽", "🙇🏾", "🙇🏿"])
    private static let japanFlag = PaletteItem(kind: .emoji, category: .flags, text: "🇯🇵", japaneseName: "旗: 日本", nameReading: "にっぽん",
                                               englishName: "flag: Japan",
                                               readings: ["こっき", "しゅくじつ", "にっぽん", "にほん", "はた", "ひのまる", "ふらぐ", "ふらっぐ"],
                                               shortcodes: ["jp", "flag-jp"])
    private static let shobon = PaletteItem(kind: .kaomoji, category: .sorrow, text: "(´・ω・｀)", japaneseName: "しょぼーん", nameReading: "しょぼーん",
                                            readings: ["しょぼーん", "しょんぼり", "がっかり"])
    private static let doubleArrow = PaletteItem(kind: .symbol, category: .arrows, text: "⇒", japaneseName: "右向き二重矢印", nameReading: "みぎむきにじゅうやじるし",
                                                 englishName: "rightwards double arrow", readings: ["みぎむきにじゅうやじるし", "やじるし"], nameSource: .cldr)

    private static let nextTrack = PaletteItem(kind: .emoji, category: .symbols, text: "⏭️", japaneseName: "次の曲ボタン", nameReading: "つぎのきょくぼたん",
                                               englishName: "next track button", readings: ["ぼたん", "つぎのきょくぼたん", "つぎのしーん", "つぎのとらっく", "やじるし"],
                                               shortcodes: ["black_right_pointing_double_triangle_with_vertical_bar"])
    /// 種類ごとにマス目に回す行の数(既定のマスの大きさで，説明の項目はすべて出す)
    private static func extraRows(_ kind: PaletteItem.Kind) -> Int {
        let fields = PalettePanel.PreviewFields()
        return PaletteWindowLayout.extraRows(previewHeight: PalettePreviewDrawing.height(for: fields, kind: kind),
                                             windowPreviewHeight: PalettePreviewDrawing.height(for: fields, kind: .emoji),
                                             cellSize: DefaultSettings.paletteCellSize)
    }

    /// 説明に出す項目を減らした見本(読みとコードポイントを出さない)
    static let reducedFields = PalettePanel.PreviewFields(unicodeName: true, readings: false, shortcodes: true, codePoints: false)

    private static func preview(_ item: PaletteItem, fields: PalettePanel.PreviewFields = .init(), isPinned: Bool = false) -> PalettePanel.Preview {
        PalettePanel.Preview(item: item, text: item.text, fields: fields, isPinned: isPinned)
    }

    /// 設定の画面の見本．設定の列数・行数・よく使う文字の行数・説明と説明に出す項目のとおりに並べる
    static func preview(columns: Int, rows visibleRows: Int, frequentRows: Int, showsPreview: Bool, previewFields: PalettePanel.PreviewFields) -> PalettePanel {
        let columns = max(columns, 1)
        let frequent = Array(frequentSample.prefix(frequentRows * columns))
        var rows: [PalettePanel.Row] = []
        func append(_ texts: [String], title: String) {
            for start in stride(from: 0, to: texts.count, by: columns) {
                let cells = texts[start..<min(start + columns, texts.count)].map { PalettePanel.Cell(text: $0, name: $0) }
                rows.append(PalettePanel.Row(index: rows.count, cells: cells, startsSection: start == 0, sectionTitle: title))
            }
        }
        append(frequent, title: PaletteStrings.frequent)
        let smileyStart = rows.count
        append(smileySample, title: PaletteCategory.smileys.title)
        let tabs: [PalettePanel.Tab] = (frequent.isEmpty ? [] : [.init(section: .frequent, title: PaletteStrings.frequent, symbol: PaletteStrings.frequentSymbol, isSelected: false)])
            + PaletteCategory.allCases.filter { $0.kind == .emoji }.map { .init(section: .category($0), title: $0.title, symbol: $0.symbol, isSelected: $0 == .smileys) }
        let selected = smileyStart < rows.count ? PalettePanel.Position(row: smileyStart, column: min(2, rows[smileyStart].cells.count - 1)) : nil
        return PalettePanel(
            modes: modes(.emoji), query: "", placeholder: PaletteStrings.emojiPlaceholder, tabs: tabs, heading: rows.first?.sectionTitle ?? "",
            rows: Array(rows.prefix(visibleRows)), rowCount: rows.count, firstRow: 0, columns: columns, visibleRows: visibleRows, selection: selected,
            preview: showsPreview ? preview(smile, fields: previewFields) : nil, showsPreview: showsPreview, previewFields: previewFields,
            skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
    }

    /// 絵文字のパレットを開いたところ．よく使う文字の行の下に表のまとまりが続く
    static let emoji: PalettePanel = {
        let titles = [PaletteStrings.frequent] + Array(repeating: PaletteCategory.smileys.title, count: 5)
        let tabs: [PalettePanel.Tab] = [.init(section: .frequent, title: PaletteStrings.frequent, symbol: PaletteStrings.frequentSymbol, isSelected: false)]
            + PaletteCategory.allCases.filter { $0.kind == .emoji }.map { .init(section: .category($0), title: $0.title, symbol: $0.symbol, isSelected: $0 == .smileys) }
        return PalettePanel(
            modes: modes(.emoji), query: "", placeholder: PaletteStrings.emojiPlaceholder, tabs: tabs, heading: PaletteStrings.frequent,
            rows: rows(emojiRows, titles: titles, starts: [0, 1]), rowCount: 210, firstRow: 0, columns: 9, visibleRows: 6,
            selection: .init(row: 1, column: 2),
            preview: preview(smile),
            showsPreview: true, skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
    }()

    /// 絵文字のパレットをホイールでスクロールし，選んでいる文字の行(1 行目)が見えなくなったところ(3 行目から見えている)
    static let scrolledUp: PalettePanel = {
        var panel = emoji
        panel.rows = rows(emojiRows, titles: Array(repeating: PaletteCategory.smileys.title, count: emojiRows.count), starts: []).map {
            PalettePanel.Row(index: $0.index + 3, cells: $0.cells, startsSection: false, sectionTitle: $0.sectionTitle)
        }
        panel.heading = PaletteCategory.smileys.title
        panel.firstRow = 3
        return panel
    }()

    /// 選んでいる文字の行(8 行目)が見えている行(0〜5 行目)より下にあるところ(上へスクロールした)
    static let scrolledDown: PalettePanel = {
        var panel = emoji
        panel.selection = .init(row: 8, column: 4)
        return panel
    }()

    /// 「ojigi」と打って探したところ．肌の色の帯を開いている
    static let search: PalettePanel = {
        let options = SkinTone.allCases.map { bowing.text(skinTone: $0) }
        return PalettePanel(
            modes: modes(.emoji), query: "おじぎ", placeholder: PaletteStrings.emojiPlaceholder, tabs: [],
            heading: PaletteStrings.results + "　" + PaletteStrings.resultCount(3),
            rows: rows([["🙇", "🙇‍♂️", "🙇‍♀️"]], titles: [PaletteStrings.results], starts: [0]), rowCount: 1, firstRow: 0, columns: 9, visibleRows: 6,
            selection: .init(row: 0, column: 0),
            preview: preview(bowing, isPinned: true),
            showsPreview: true, skinTone: .none, skinTonePicker: .init(options: options, selected: 2), message: nil, hints: hints)
    }()

    /// 「nihon」と打って探し，国旗を選んだところ．並び(国旗)には UCD の名前が無いので，CLDR の英語の名前を出す
    static let flag: PalettePanel = {
        PalettePanel(
            modes: modes(.emoji), query: "にほん", placeholder: PaletteStrings.emojiPlaceholder, tabs: [],
            heading: PaletteStrings.results + "　" + PaletteStrings.resultCount(4),
            rows: rows([["🗾", "🏯", "🎌", "🇯🇵"]], titles: [PaletteStrings.results], starts: [0]), rowCount: 1, firstRow: 0, columns: 9, visibleRows: 6,
            selection: .init(row: 0, column: 3), preview: preview(japanFlag), showsPreview: true, skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
    }()

    /// 「tsugi」と打って探し，Unicode の名前とショートコードの長い ⏭️ を選んだところ．名前は 2 行で「…」にし，長いタグは字を縮めて折り返す
    static let longName: PalettePanel = {
        PalettePanel(
            modes: modes(.emoji), query: "つぎ", placeholder: PaletteStrings.emojiPlaceholder, tabs: [],
            heading: PaletteStrings.results + "　" + PaletteStrings.resultCount(3),
            rows: rows([["⏭️", "⏩", "▶️"]], titles: [PaletteStrings.results], starts: [0]), rowCount: 1, firstRow: 0, columns: 9, visibleRows: 6,
            selection: .init(row: 0, column: 0), preview: preview(nextTrack), showsPreview: true, skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
    }()

    /// 説明に出す項目を設定で減らしたところ(Unicode の名前とショートコードだけ)．欄は出す項目の分だけの高さになる
    static let reduced: PalettePanel = {
        var panel = emoji
        panel.previewFields = reducedFields
        panel.preview = preview(smile, fields: reducedFields)
        return panel
    }()

    /// 顔文字のパレット．よく使う行の下に笑顔のまとまりが広いマスで続く
    static let kaomoji: PalettePanel = {
        let texts = [["(^o^)", "m(_ _)m", "(´・ω・｀)"], ["＼(^o^)／", "(^o^)", "(^^)"], ["(*^^*)", "^_^", ":D"], ["・ω・", "(*´ω｀*)", "(^O^)"],
                     ["(^_^)", "(・∀・)", "(*^_^*)"], ["ヾ(｡>﹏<｡)ﾉﾞ✧*。", "(((((((((((っ･ω･)っ ﾌﾞｰﾝ", "(*´∀｀*)"],
                     ["(*´ω`*)", "(o^―^o)", "ヽ(*´∀｀)ノ"], ["(・ω・)", "(｀・ω・´)", "(*ﾟ▽ﾟ*)"]]
        // 説明の欄が低い分(見出しと読みだけ)をマス目の行に回す(core の PaletteSession と同じ決め方)
        let visibleRows = 6 + extraRows(.kaomoji)
        let titles = [PaletteStrings.frequent] + Array(repeating: PaletteCategory.joy.title, count: texts.count - 1)
        let tabs: [PalettePanel.Tab] = [.init(section: .frequent, title: PaletteStrings.frequent, symbol: PaletteStrings.frequentSymbol, isSelected: false)]
            + PaletteCategory.allCases.filter { $0.kind == .kaomoji }.map { .init(section: .category($0), title: $0.title, symbol: $0.symbol, isSelected: $0 == .joy) }
        return PalettePanel(
            modes: modes(.kaomoji), query: "", placeholder: PaletteStrings.kaomojiPlaceholder, tabs: tabs, heading: PaletteStrings.frequent,
            rows: rows(Array(texts.prefix(visibleRows)), titles: titles, starts: [0, 1]), rowCount: 48, firstRow: 0, columns: 9,
            visibleRows: visibleRows, cellsPerRow: 3,
            selection: .init(row: 0, column: 2),
            preview: preview(shobon),
            showsPreview: true, skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
    }()

    /// 記号のパレット．ピン留めの行の下に矢印のまとまり
    static let symbol: PalettePanel = {
        let titles = [PaletteStrings.pinned] + Array(repeating: PaletteCategory.arrows.title, count: 5)
        let tabs: [PalettePanel.Tab] = [.init(section: .pinned, title: PaletteStrings.pinned, symbol: PaletteStrings.pinnedSymbol, isSelected: false)]
            + PaletteCategory.allCases.filter { $0.kind == .symbol }.map { .init(section: .category($0), title: $0.title, symbol: $0.symbol, isSelected: $0 == .arrows) }
        return PalettePanel(
            modes: modes(.symbol), query: "", placeholder: PaletteStrings.symbolPlaceholder, tabs: tabs, heading: PaletteCategory.arrows.title,
            rows: rows(symbolRows, titles: titles, starts: [0, 1]), rowCount: 160, firstRow: 0, columns: 9, visibleRows: 6,
            selection: .init(row: 2, column: 1),
            preview: preview(doubleArrow),
            showsPreview: true, skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
    }()

    /// 動きの途中のコマの見本(SnapshotRenderer)．前の内容・動きを添えた次の内容・描く時刻(主な動きの長さの半分の秒)
    static var motionSteps: [(from: PalettePanel, to: PalettePanel, time: Double)] {
        typealias Duration = DesignTokens.Motion.Palette
        // 選択の枠が右下へ滑り，タブの印も次のまとまりへ滑る
        var moved = emoji
        moved.selection = .init(row: 3, column: 6)
        moved.tabs = moved.tabs.enumerated().map { index, tab in .init(section: tab.section, title: tab.title, symbol: tab.symbol, isSelected: index == 2) }
        moved.motion = .init(selectionFrom: emoji.selection, tabFrom: .category(.smileys))
        // 絵文字から記号へ切り替えて，種類の印を滑らせ，中身を左へ送る
        var switched = symbol
        switched.motion = .init(modeFrom: .emoji, content: .next)
        // 肌の色の帯が浮かび上がる
        var picking = search
        let before = { var panel = search; panel.skinTonePicker = nil; return panel }()
        picking.motion = .init(opensPicker: true)
        return [(emoji, moved, Duration.indicator / 1000 / 2), (emoji, switched, Duration.content / 1000 / 2), (before, picking, Duration.pop / 1000 / 3)]
    }

    /// 選択の枠が滑っている途中でホイールでスクロールしたところの見本(SnapshotRenderer)．滑り始めの内容・滑らせる内容・スクロールした内容と描く時刻
    static var scrollWhileSliding: (from: PalettePanel, sliding: PalettePanel, scrolled: PalettePanel, time: Double) {
        var sliding = emoji
        sliding.selection = .init(row: 4, column: 6)
        sliding.motion = .init(selectionFrom: emoji.selection)
        var scrolled = scrolledUp
        scrolled.selection = sliding.selection
        return (emoji, sliding, scrolled, DesignTokens.Motion.Palette.selection / 1000 / 2)
    }
}
