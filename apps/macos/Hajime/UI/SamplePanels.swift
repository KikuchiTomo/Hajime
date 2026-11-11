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

    /// 設定の画面の見本．設定の列数・行数・よく使う文字の行数・説明のとおりに並べる
    static func preview(columns: Int, rows visibleRows: Int, frequentRows: Int, showsPreview: Bool) -> PalettePanel {
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
            preview: showsPreview ? emoji.preview : nil, showsPreview: showsPreview, skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
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
            preview: .init(text: "😄", japaneseName: "目も笑っている笑顔", englishName: "grinning face with smiling eyes", shortcodes: [":smile:"],
                           readings: ["めもわらっているえがお", "えがお", "すまいる"], codePoints: "U+1F604", isPinned: false),
            showsPreview: true, skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
    }()

    /// 「ojigi」と打って探したところ．肌の色の帯を開いている
    static let search: PalettePanel = {
        let options = SkinTone.allCases.map { PaletteItem(kind: .emoji, category: .people, text: "🙇", skinTones: ["🙇🏻", "🙇🏼", "🙇🏽", "🙇🏾", "🙇🏿"]).text(skinTone: $0) }
        return PalettePanel(
            modes: modes(.emoji), query: "おじぎ", placeholder: PaletteStrings.emojiPlaceholder, tabs: [],
            heading: PaletteStrings.results + "　" + PaletteStrings.resultCount(3),
            rows: rows([["🙇", "🙇‍♂️", "🙇‍♀️"]], titles: [PaletteStrings.results], starts: [0]), rowCount: 1, firstRow: 0, columns: 9, visibleRows: 6,
            selection: .init(row: 0, column: 0),
            preview: .init(text: "🙇", japaneseName: "おじぎする人", englishName: "person bowing", shortcodes: [":bow:"],
                           readings: ["おじぎするひと", "おじぎ", "ごめんなさい", "どげざ"], codePoints: "U+1F647", isPinned: true),
            showsPreview: true, skinTone: .none, skinTonePicker: .init(options: options, selected: 2), message: nil, hints: hints)
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
            preview: .init(text: "⇒", japaneseName: "右向き二重矢印", englishName: "rightwards double arrow", shortcodes: [],
                           readings: ["みぎむきにじゅうやじるし", "ならば", "やじるし"], codePoints: "U+21D2", isPinned: false),
            showsPreview: true, skinTone: .none, skinTonePicker: nil, message: nil, hints: hints)
    }()
}
