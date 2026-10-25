import S90Domain

/// 画面に出す文言の置き場所．多言語にするときは Localizable.xcstrings に移す
enum UIStrings {
    enum Candidate {
        static let candidatesHint = "↑ 種類"
        static let variantsHint = "← → 選ぶ　↓ 候補"
        static func variantsPosition(_ index: Int, _ total: Int) -> String { "種類 \(index) / \(total)" }
    }

    enum Lattice {
        static let hint = "← → 文節　↑ ↓ 候補　⇧← → 区切り"
    }

    enum ModeIndicator {
        static func label(for mode: InputMode) -> String {
            switch mode {
            case .japanese: "あ"
            case .direct: "A"
            }
        }
    }

    enum Menu {
        static let liveConversion = "ライブ変換"
        static let variantRow = "候補の上に種類の行を出す"
        static let typoCorrection = "タイプミスの補正"
        static let yenKey = "¥ キーで入力する文字"
        static let theme = "外観"
        static let presentation = "候補の出し方"

        static func label(for presentation: CandidatePresentation) -> String {
            switch presentation {
            case .automatic: "自動(文節が 2 つ以上なら文節格子)"
            case .list: "一覧"
            case .lattice: "文節格子"
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
