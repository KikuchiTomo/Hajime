import S90Domain

/// 画面に出す文言の置き場所．多言語にするときは Localizable.xcstrings に移す
enum UIStrings {
    enum Candidate {
        static let candidatesHint = "↑ 種類"
        static let variantsHint = "← → 選ぶ　↓ 候補"
        static func variantsPosition(_ index: Int, _ total: Int) -> String { "種類 \(index) / \(total)" }
    }

    enum Branch {
        static let hint = "↓ 候補　↑ 字種　← → 文節　Tab 迷う文節　⇧← → 区切り"
        static func position(_ first: Int, _ total: Int) -> String { "候補 \(first)〜 / \(total)" }
    }

    enum ModeIndicator {
        static func label(for mode: InputMode) -> String {
            switch mode {
            case .japanese: "あ"
            case .direct: "A"
            }
        }
    }

    enum Settings {
        static let windowTitle = "s90.tokyo IME の設定"
        static let ok = "OK"
        static let inputTab = "入力"
        static let conversionTab = "変換"
        static let dictionaryTab = "ユーザー辞書"
        static let appearanceTab = "見た目"
        static let inputStyleSection = "入力方式"
        static let characters = "入れる文字"
        static let punctuation = "句読点"
        static let brackets = "[ ] で入れる括弧"
        static let slash = "/ で入れる文字"
        static let spaceWidth = "空白(Shift+Space で逆)"
        static let numberWidth = "数字"
        static let keys = "キー"
        static let punctuationCommits = "句読点を打ったら確定する"
        static let numberKeySelection = "番号キーで候補を選ぶ"
        static let showsModeIndicator = "日本語と英数を切り替えたときにモードを出す"
        static let conversion = "変換"
        static let specialConversion = "特別な候補"
        static let dateConversion = "「きょう」「いま」などを日付と時刻にする"
        static let symbolConversion = "「やじるし」などの読みから記号を出す"
        static let emojiConversion = "読みから絵文字を出す"
        static let learning = "学習"
        static let resetLearning = "学習した内容を消す"
        static let reading = "読み(ひらがな)"
        static let word = "語"
        static let add = "登録"
        static let remove = "選んだ語を消す"
        static let importDictionary = "取り込む…"
        static let exportDictionary = "書き出す…"
        static let exportFileName = "s90-user-dictionary.txt"
        static let dictionaryNote = "取り込むファイルは「読み<タブ>語」の行が並んだテキストです．Google 日本語入力と ATOK が書き出すファイルを読めます．"
        static let appearance = "見た目"
        static let restoreDefaults = "設定を既定に戻す(ユーザー辞書は残す)"
        static let saveFailed = "設定を保存できませんでした"
        static let learningReset = "学習した内容を消しました"
        static let invalidEntry = "読みはひらがなで，語と合わせて長すぎないようにしてください"
        static let importFailed = "取り込めませんでした．大きすぎるか，テキストのファイルではありません"
        static let exportFailed = "書き出せませんでした"
        static func imported(_ count: Int) -> String { "\(count) 語を読みました" }
        static func fontSize(_ size: Int) -> String { "候補の文字の大きさ: \(size)" }

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
            case .readOnly: "学習した内容は使うが，新しく学習しない"
            case .disabled: "学習しない"
            }
        }
    }

    enum Menu {
        static let openSettings = "設定を開く…"
        static let inputStyle = "入力方式"

        static func label(for style: InputStyle) -> String {
            switch style {
            case .romaji: "ローマ字入力"
            case .kana: "かな入力(JIS かな配列)"
            case .english: "英語のまま入力(Tab で日本語)"
            }
        }
        static let liveConversion = "ライブ変換"
        static let variantRow = "候補の上に種類の行を出す"
        static let typoCorrection = "タイプミスの補正"
        static let yenKey = "¥ キーで入力する文字"
        static let theme = "外観"
        static let presentation = "候補の出し方"

        static func label(for presentation: CandidatePresentation) -> String {
            switch presentation {
            case .automatic: "分岐図(英単語の補正のときは一覧)"
            case .list: "一覧"
            }
        }

        static func label(for level: TypoCorrectionLevel) -> String {
            switch level {
            case .off: "切る"
            case .conservative: "控えめ(英単語だけ)"
            case .standard: "標準(綴りの誤りも直す)"
            }
        }

        static func label(for policy: YenKeyPolicy) -> String {
            switch policy {
            case .alwaysBackslash: "常に \\"
            case .alwaysYen: "常に ¥"
            case .backslashInProgramming: "エディタとターミナルだけ \\"
            }
        }

        static func label(for theme: ThemePreference) -> String {
            switch theme {
            case .automatic: "自動(ライトはプラチナ，ダークは夜のデスク)"
            case .platinum: "プラチナ"
            case .desk: "夜のデスク"
            case .native: "システム"
            }
        }
    }
}
