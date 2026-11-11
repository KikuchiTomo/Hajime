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

    /// 打っているあいだの候補の窓．選び始めるまで番号を振らず，足元に選び始めるキーを出す
    static let suggestion: CandidatePanel = {
        var panel = CandidatePanel(
            variants: [], selectedVariant: nil,
            entries: ["あぴ", "アピ", "アピール", "アピールポイント"].map { .init(text: $0, annotation: nil) },
            selectedEntry: nil, focus: .candidate, position: 0, total: 4,
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
