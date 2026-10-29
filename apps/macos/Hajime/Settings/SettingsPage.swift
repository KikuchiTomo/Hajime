import HajimeDomain

extension SettingsView {
    /// 左の一覧の見出し．システム設定と同じく，近い項目をまとめて見出しを付ける
    enum Group: CaseIterable {
        case input, dictionary, appearance, data, about

        var title: String {
            switch self {
            case .input: UIStrings.Settings.inputGroup
            case .dictionary: UIStrings.Settings.dictionaryGroup
            case .appearance: UIStrings.Settings.appearanceGroup
            case .data: UIStrings.Settings.dataGroup
            case .about: UIStrings.Settings.aboutGroup
            }
        }

        var pages: [Page] { Page.allCases.filter { $0.group == self } }
    }

    /// 左の一覧の項目．システム設定と同じく，左で選んだ項目を右に出す(上のタブには収まらない)．並びは左の一覧の並び
    enum Page: CaseIterable, Hashable {
        case input, conversion, correction, language, romaji, keys, apps, dictionary, symbols, appearance, usage, sync, backup, about

        var group: Group {
            switch self {
            case .input, .conversion, .correction, .language, .romaji, .keys, .apps: .input
            case .dictionary, .symbols: .dictionary
            case .appearance: .appearance
            case .usage, .sync, .backup: .data
            case .about: .about
            }
        }

        var title: String {
            switch self {
            case .input: UIStrings.Settings.inputTab
            case .conversion: UIStrings.Settings.conversionTab
            case .correction: UIStrings.Features.correctionPage
            case .language: UIStrings.Features.languagePage
            case .symbols: UIStrings.Features.symbolsPage
            case .keys: UIStrings.Keys.tab
            case .dictionary: UIStrings.Settings.dictionaryTab
            case .romaji: UIStrings.Settings.romajiTab
            case .apps: UIStrings.Settings.appsTab
            case .appearance: UIStrings.Settings.appearanceTab
            case .usage: UIStrings.Settings.usageTab
            case .sync: UIStrings.Sync.page
            case .backup: UIStrings.More.backup
            case .about: UIStrings.More.about
            }
        }

        /// 見せていないあいだも作ったまま残すか(SettingsPageStack)．残したページは設定を変えるたびに描き直すので，
        /// 描き直しが重いページは残さない．キー設定の表は 1 回の描き直しに 200 ms ほどかかり，残すとほかのページで設定を
        /// 変えるたびに遅くなるため，開くたびに組み立てる(組み立てに 2 秒ほどかかる)
        var keepsWhenHidden: Bool { self != .keys }

        /// SF Symbols の名前．文字の形の記号(textformat.abc など)は言語によって「あいう」に変わり，ほかの絵と揃わないので使わない
        var symbol: String {
            switch self {
            case .input: "keyboard"
            case .conversion: "character.book.closed.ja"
            case .correction: "wand.and.stars"
            case .language: "character.bubble"
            case .symbols: "arrow.right.square"
            case .keys: "command"
            case .dictionary: "text.book.closed"
            case .romaji: "tablecells"
            case .apps: "nosign.app"
            case .appearance: "paintbrush"
            case .usage: "chart.line.uptrend.xyaxis"
            case .sync: "arrow.triangle.2.circlepath"
            case .backup: "externaldrive"
            case .about: "info.circle"
            }
        }

        /// 検索で見つけるための言葉．ページの名前に加え，そのページにある項目の名前
        var keywords: [String] {
            switch self {
            case .input: [UIStrings.Choice.inputStyle, UIStrings.Choice.keyboardLayout, UIStrings.Settings.punctuation, UIStrings.Features.keypadDirect]
            case .conversion: [UIStrings.Menu.liveConversion, UIStrings.Choice.presentation, UIStrings.Choice.initialFocus, UIStrings.Features.okurigana, UIStrings.Features.prefersKatakana,
                               UIStrings.Features.calculation, UIStrings.Features.postalCode, UIStrings.Features.handwriting,
                               UIStrings.Settings.dateConversion, UIStrings.Settings.emojiConversion, UIStrings.Association.enabled,
                               UIStrings.Association.limit, UIStrings.Association.dictionaries]
            case .correction: [UIStrings.Features.exceptions, UIStrings.Features.rules, UIStrings.Features.correctsEnglish, UIStrings.Features.misreadings]
            case .language: [UIStrings.Features.englishWords, UIStrings.Features.japaneseWords, UIStrings.Features.languageRules,
                             UIStrings.Features.tryLanguage, UIStrings.Choice.label(for: .englishAuto)]
            case .symbols: [UIStrings.Features.sequences, UIStrings.Features.readings]
            // コマンドと状態の名前でも見つける(「全角空白」「英数」「切り替え」で キー設定 を出す)
            case .keys: [UIStrings.Keys.presetMenu] + KeymapCommand.allCases.map(UIStrings.Keys.label(for:))
                + KeymapState.allCases.map(UIStrings.Keys.label(for:)) + KeymapPreset.allCases.map(UIStrings.Keys.label(for:))
            case .dictionary: [UIStrings.Settings.reading, UIStrings.Settings.word, UIStrings.Dictionaries.imported]
            case .appearance: [UIStrings.More.theme, UIStrings.More.customThemes, UIStrings.More.font]
            case .sync: [UIStrings.Sync.folder, UIStrings.Sync.scopes, UIStrings.Sync.label(for: .dictionary)]
            default: []
            }
        }
    }
}
