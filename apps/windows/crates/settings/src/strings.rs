#![forbid(unsafe_code)]

//! 画面に出す文言．macOS の設定の画面(apps/macos/Hajime/UI/UIStrings.swift)と同じ文言を，同じまとまりの名前で置く．
//! Windows で言い方が違うもの(キーの名前，Mac と PC など)だけを変える

/// UIStrings.Settings
pub mod settings {
    pub const WINDOW_TITLE: &str = "Hajime IME の設定";
    pub const IMPORT_DICTIONARY: &str = "インポート…";
    pub const EXPORT_DICTIONARY: &str = "エクスポート…";
    pub const EXPORT_FILE_NAME: &str = "hajime-user-dictionary.txt";
    pub const IMPORT_FAILED: &str =
        "インポートできませんでした。ファイルが大きすぎるか、テキストファイルではありません";
    pub const EXPORT_FAILED: &str = "エクスポートできませんでした";
    pub fn imported(count: u32) -> String {
        format!("{count} 件を追加しました")
    }
    pub const OK: &str = "OK";
    pub const CANCEL: &str = "キャンセル";
    pub const SAVE: &str = "保存";
    pub const INPUT_TAB: &str = "入力";
    pub const CONVERSION_TAB: &str = "変換";
    pub const DICTIONARY_TAB: &str = "ユーザー辞書";
    pub const APPEARANCE_TAB: &str = "外観";
    pub const USAGE_TAB: &str = "統計";
    pub const APPS_TAB: &str = "除外設定";
    pub const ROMAJI_TAB: &str = "ローマ字";
    pub const INPUT_GROUP: &str = "入力と変換";
    pub const DICTIONARY_GROUP: &str = "辞書と記号";
    pub const APPEARANCE_GROUP: &str = "見た目";
    pub const DATA_GROUP: &str = "データ";
    pub const ABOUT_GROUP: &str = "このアプリについて";
    pub const LOADING: &str = "読み込み中…";
    pub const INPUT_STYLE_SECTION: &str = "入力方式";
    pub const CHARACTERS: &str = "文字";
    pub const PUNCTUATION: &str = "句読点";
    pub const BRACKETS: &str = "[ ] キーで入力する括弧";
    pub const SLASH: &str = "/ キーで入力する文字";
    pub const SPACE_WIDTH: &str = "スペース幅";
    pub const NUMBER_WIDTH: &str = "数字幅";
    pub const NUMBER_SEPARATORS: &str = "数字のあとの句読点をピリオドとカンマに";
    pub const ALPHANUMERIC_HYPHEN: &str = "英数字のあとの長音をハイフンに";
    pub const KEYS: &str = "動作";
    pub const PUNCTUATION_COMMITS: &str = "句読点で確定";
    pub const QUESTION_EXCLAMATION_COMMITS: &str = "？と！で確定";
    pub const KEYPAD_CALCULATION: &str = "テンキーの Enter で計算";
    pub const CYCLES_LETTER_CASE: &str = "英数に変えるキーで大文字と小文字を切り替え";
    pub const NUMBER_KEY_SELECTION: &str = "番号キーで候補を選択";
    pub const SHOWS_MODE_INDICATOR: &str = "入力モードの切り替えを表示";
    pub const CONVERSION: &str = "変換";
    pub const SPECIAL_CONVERSION: &str = "特殊変換";
    pub const DATE_CONVERSION: &str = "日付と時刻に変換";
    pub const HOMOPHONE_NOTES: &str = "語の意味と使い分けを表示";
    pub const MEANING: &str = "語の意味";
    pub const MEANING_PLACEMENT: &str = "意味の位置";
    pub const MEANING_SENSE_LIMIT: &str = "意味の数";
    pub const SHOWS_PART_OF_SPEECH: &str = "品詞を表示";
    pub const SHOWS_USAGE_EXAMPLES: &str = "使い方の例を表示";
    pub const SHOWS_HOMOPHONES: &str = "同音語を表示";
    pub const MISUSE_NOTES: &str = "誤用の注釈を表示";
    pub const PROOFREADING: &str = "校正支援";
    pub const SYMBOL_CONVERSION: &str = "記号に変換";
    pub const EMOJI_SECTION: &str = "絵文字";
    pub const EMOJI_CONVERSION: &str = "文節を絵文字に変換";
    pub const EMOJI_WORD_CONVERSION: &str = "語を絵文字に変換";
    /// 項目名の横に出す，その設定で出る候補の見本(読みと候補)
    pub const EMOJI_CONVERSION_EXAMPLE: (&str, &str) = ("びーる", "🍺");
    pub const EMOJI_WORD_CONVERSION_EXAMPLE: (&str, &str) = ("ねこが", "🐈が");
    pub const EMOJI_CANDIDATE_POSITION: &str = "絵文字の位置";
    pub const EMOJI_CANDIDATE_COUNT: &str = "絵文字の数";
    pub const SHOWS_EMOJI_NAMES: &str = "絵文字の名前を表示";
    pub const LATEX_CONVERSION: &str = "LaTeX のコマンドに変換";
    pub const NUMBER_FORMS: &str = "数字の書き方";
    pub const NUMBER_FORM_CONVERSION: &str = "数字を丸数字などに変換";
    pub const NUMBER_FORM_CIRCLED: &str = "丸数字";
    pub const NUMBER_FORM_PARENTHESIZED: &str = "括弧付きとピリオド付きの数字";
    pub const NUMBER_FORM_KANJI: &str = "漢数字";
    pub const NUMBER_FORM_ROMAN: &str = "ローマ数字";
    pub const LEARNING: &str = "学習";
    pub const ZENZAI_MODEL: &str = "Zenzai のモデル";
    pub const ZENZAI_MODEL_NOTE: &str =
        "併用では、打っている間の表示を小さなモデルで速く求め、打鍵が止まったときと変換は大きなモデルで求め直します。小さなモデルが無いときは大きなモデルを使います。";
    pub const CANDIDATE_RERANKING: &str = "Zenzai による候補の並べ替え";
    pub const CANDIDATE_RERANKING_NOTE: &str =
        "変換の候補の 2 番目以降を、Zenzai で前後の文に合う順に並べ替えます。第 1 候補は変わりません。";
    pub const RESET_LEARNING: &str = "学習結果を消去";
    pub const SAVE_FAILED: &str = "設定を保存できませんでした";
    pub const RESTORE_DEFAULTS: &str = "すべての設定を既定に戻す";
    pub const LEARNING_RESET: &str = "学習結果を消去しました";
    pub const RECORDS_USAGE: &str = "入力の統計を記録";
    pub const USAGE_NOTE: &str = "入力した文字は記録しません。";
    pub const FIRST_CANDIDATE_RATE: &str = "第 1 候補のまま確定した割合";
    pub const COMMITS: &str = "確定した回数";
    pub const CONVERSIONS_OPENED: &str = "Space で変換した回数";
    pub const SEGMENTS_CHANGED: &str = "選び直した文節の数";
    pub const READING_CORRECTIONS: &str = "タイプミスを修正した回数 / 取り消した回数";
    pub const ENGLISH_CORRECTIONS: &str = "英単語を修正した回数 / 取り消した回数";
    pub const RESET_USAGE: &str = "統計を消去";
    /// UIStrings.Settings.fontSize から値を除いたもの
    pub const FONT_SIZE_NAME: &str = "候補の文字サイズ";
    pub const WORD_CLASS: &str = "品詞";
    pub const COMMENT: &str = "コメント";
    pub const COMMENT_PROMPT: &str = "コメント(省略可)";
    pub const ABBREVIATION_NOTE: &str =
        "短縮よみの単語は、読みだけを変換したときに出ます。文の中では出ません。";

    /// 絵文字の位置の値(macOS の UIStrings.Settings.emojiCandidatePositionValue)
    pub fn emoji_candidate_position(value: f64) -> String {
        format!("{value} 番目")
    }

    /// UIStrings.Settings.fontSize(スライダーの名前に今の値を付ける)
    pub fn font_size(size: f64) -> String {
        format!("{FONT_SIZE_NAME}: {}", size.round() as i64)
    }
    pub const ADD: &str = "追加";
    pub const ESCAPE_SWITCHES_TO_DIRECT: &str = "Esc で英数に切り替え";
    pub const ROMAJI_KEYS: &str = "入力";
    pub const READING: &str = "読み";
    pub const WORD: &str = "単語";
    pub const DICTIONARY_EMPTY: &str = "登録した単語はありません";
    pub const ROMAJI_KANA: &str = "出力";
    pub const ROMAJI_EMPTY: &str = "追加した組み合わせはありません";
    pub const REMOVE: &str = "削除";
}

/// UIStrings.Menu
pub mod menu {
    pub const LIVE_CONVERSION: &str = "ライブ変換";
}

/// UIStrings.Choice
pub mod choice {
    pub const INPUT_STYLE: &str = "入力方式";
    pub const KEYBOARD_LAYOUT: &str = "キー配列";
    pub const KEYBOARD_LAYOUT_NOTE: &str = "ローマ字入力と英字入力で使用します。";
    pub const ENGLISH_INPUT_LIVE_CONVERSION: &str = "英字入力のライブ変換";
    pub const ENGLISH_INPUT_LIVE_CONVERSION_NOTE: &str =
        "英語の辞書にない単語をローマ字として読み、日本語に変換して表示します。Esc で英字に戻せます。";
    pub const ENGLISH_AUTO_NOTE: &str =
        "英語で入力しながら、日本語にできる語句を自動で日本語に変換します。判別方法は「英語と日本語」で変更できます。";
    pub const VARIANT_ROW: &str = "候補の上に文字種の行を表示";
    pub const KEY_HINTS: &str = "キーの案内を表示";
    pub const TYPO_CORRECTION: &str = "タイプミスの修正";
    pub const YEN_KEY: &str = "¥ キーで入力する文字";
    pub const THEME: &str = "テーマ";
    pub const PRESENTATION: &str = "候補の表示";
    pub const INITIAL_FOCUS: &str = "最初に選択する文節";
    pub const SUGGESTION_DISPLAY: &str = "入力中の候補";
    pub const PREDICTION_DISPLAY: &str = "入力中の予測";
    pub const PREDICTION_PREFERS_HISTORY: &str = "入力履歴にある予測を優先";
    pub const PREDICTION_FROM_CORRECTION: &str = "打ち間違いを直した読みからも予測";
    pub const HIDDEN_PREDICTIONS: &str = "予測に表示しない語句";
    pub const HIDDEN_PREDICTION_PLACEHOLDER: &str = "語句";
    pub const HIDDEN_PREDICTIONS_EMPTY: &str = "予測に表示しない語句はありません";
}

/// UIStrings.Features
pub mod features {
    pub const KEYPAD_DIRECT: &str = "テンキーの数字を半角で確定";
    pub const OKURIGANA: &str = "送り仮名";
    pub const NOTATION: &str = "表記";
    pub const PREFERS_KATAKANA: &str = "カタカナ語を優先";
    pub const CALCULATION: &str = "計算";
    pub const POSTAL_CODE: &str = "郵便番号から住所に変換";
    pub const HANDWRITING: &str = "手書き入力";
    pub const MISREADINGS: &str = "読み違いの候補";
    pub const LANGUAGE_PAGE: &str = "英語と日本語";
    pub const ENGLISH_WORDS: &str = "常に英語にする単語";
    pub const JAPANESE_WORDS: &str = "常に日本語にする単語";
    pub const LANGUAGE_RULES: &str = "判別ルール";
    pub const TRY_LANGUAGE: &str = "試す";
    pub const LANGUAGE_JUDGING: &str = "判別方法";
    pub const USES_CONTEXT: &str = "前の単語で判別";
    pub const USES_CONTEXT_NOTE: &str =
        "make・shine のように英語にも日本語にも読める単語を、前が英語なら英語、日本語なら日本語にします。";
    pub const AVOIDS_OFFENSIVE: &str = "不適切な変換を避ける";
    pub const WORD_PLACEHOLDER: &str = "英字の単語";
    pub const LANGUAGE_RULE_WORD: &str = "単語";
    pub const LANGUAGE_RULE_CONTEXT: &str = "前";
    pub const LANGUAGE_RULE_RESULT: &str = "結果";
    pub const TRY_PLACEHOLDER: &str = "英字の文";
    pub const TRY_PRECEDING: &str = "前の文字列";
    pub const ENGLISH_WORDS_EMPTY: &str = "常に英語にする単語はありません";
    pub const JAPANESE_WORDS_EMPTY: &str = "常に日本語にする単語はありません";
    pub const CORRECTION_PAGE: &str = "補正";
    pub const CORRECTS_ENGLISH: &str = "英単語";
    pub const EXCEPTIONS: &str = "修正しない語句";
    pub const RULES: &str = "置き換え";
    pub const SYMBOLS_PAGE: &str = "記号";
    pub const SEQUENCES: &str = "連続入力によるサジェスト";
    pub const READINGS: &str = "読み仮名入力によるサジェスト";
    pub const SEARCH: &str = "検索";
    pub const INPUT: &str = "入力";
    pub const OUTPUT: &str = "記号";
    pub const READING_INPUT: &str = "読み";
    pub const READING_OUTPUT: &str = "空白で区切った記号";
    pub const SYMBOLS_EMPTY: &str = "ルールはありません";
    pub const CHANGED: &str = "変更あり";
    pub const ADDED: &str = "追加";
    pub const CORRECTION_KINDS: &str = "修正の対象";
    pub const CORRECTS_JAPANESE: &str = "日本語のタイプミス";
    pub const CORRECTS_REPEATED_KEYS: &str = "同じキーの重なり";
    pub const CORRECTION_KINDS_NOTE: &str =
        "使用できない項目は、変換の「タイプミスの修正」で有効にできます。";
    pub const EXCEPTION_PLACEHOLDER: &str = "英字か読み";
    pub const TYPED: &str = "入力した英字";
    pub const REPLACEMENT: &str = "置き換える語句";
    pub const RULES_EMPTY: &str = "置き換えはありません";
    pub const EXCEPTIONS_EMPTY: &str = "修正しない語句はありません";
    pub const RESTORE_DEFAULT: &str = "既定に戻す";
}

/// UIStrings.Extras
pub mod extras {
    pub const HAND_SHIFT: &str = "手の位置のずれを修正（試験的）";
    pub const HAND_SHIFT_NOTE: &str = "左右どちらか、または両方の手が 1 キー横にずれたまま打った文を修正します。設定したキー配列のキーの位置を使います。";
    pub const LOOSE_READINGS: &str = "うろ覚えのカタカナ語の候補";
    pub const LOOSE_READINGS_NOTE: &str = "「しゅみれーしょん」から「シミュレーション」のように、読みを少し違えて覚えている語を候補に出します。";
    pub const PHONETIC_SPELLING: &str = "発音どおりに綴った英単語の候補";
    pub const PHONETIC_SPELLING_NOTE: &str =
        "「ふぉと」から「photo」のように、音のとおりに綴った英単語の正しい綴りを候補に出します。";
    pub const ENGLISH_TERM_CANDIDATES: &str = "英語の語の辞書を使う";
    pub const ENGLISH_TERMS: &str = "英語の語の辞書に足した語";
    pub const ENGLISH_TERMS_SECTION: &str = "英語の語の辞書";
    pub const ENGLISH_TERM_CANDIDATES_NOTE: &str = "ローマ字で打った「api」を「API」に、「openai」を「OpenAI」にするように、書き方の決まった英語の語を候補に出します。「sora」のように読みが日本語の語（空）になるときは、日本語を先に出します。";
    pub const ENGLISH_TERM_PLACEHOLDER: &str = "書き方どおりの語（例: OpenAI）";
    pub const ENGLISH_TERMS_EMPTY: &str = "足した語はありません";
    pub const ENGLISH_TERMS_NOTE: &str = "同梱の辞書に無い語を、大文字と小文字を書き方どおりにして足します。足した語は同梱の語より先に出ます。";
    pub const DYNAMIC_DICTIONARY: &str = "単語に書いた日付や時刻などを入力時の値にする";
    pub const TEMPLATE_SYNTAX: &str = "書き方";
    pub const TEMPLATE_MEANING: &str = "入るもの";
    pub const TEMPLATE_NOW: &str = "今入れると";
    /// 単語に書ける書き方(TextTemplate)と，入るもの．「今入れると」の列は書き方を今の値に置き換えて出す
    pub const TEMPLATE_ROWS: &[(&str, &str)] = &[
        ("{date}", "今日の日付"),
        ("{time}", "今の時刻"),
        ("{datetime:YYYY/MM/DD hh:mm:ss}", "書式を決めた日時"),
        ("{datetime+1d:MM/DD}", "日をずらした日付（-7d なら 7 日前）"),
        (
            "{time+30m}",
            "ずらした時刻（m 分・h 時間・d 日・w 週・M 月・y 年）",
        ),
        (
            "{date+1w@mon:M/D(ddd)}",
            "来週の月曜（@mon〜@sun その週の曜日、@1〜@31 その月の日、@end 月末）",
        ),
        (
            "{date+3b:M/D(ddd)}",
            "3 営業日後（b は土日と祝日を除いて数える）",
        ),
        (
            "{date:GGEE年M月D日|kansuji}",
            "漢数字の和暦（1 年は「元年」）",
        ),
        ("{date:FFFF年度 NN JJ}", "年度・和風月名・干支"),
        ("{utc}", "協定世界時の日時"),
        ("{unixtime}", "UNIX 時間（秒）"),
        (
            "{holiday:平日}",
            "祝日の名前（祝日でなければ : のあとの文字）",
        ),
        ("{season}", "その月の時候の挨拶"),
        ("{greeting}", "時刻に合った挨拶"),
        (
            "{days:12/25}",
            "その日までの日数（2027-03-31 のように年も書ける）",
        ),
        ("{age:1990-04-01}", "その日に生まれた人の満年齢"),
        ("{uuid}", "UUID（入れるたびに変わる）"),
        ("{random:1-6}", "範囲の中の整数（入れるたびに変わる）"),
        (
            "{alnum:8}",
            "英数字 8 文字（{hex:8} なら 16 進数。入れるたびに変わる）",
        ),
        (
            "{pick:はい,いいえ}",
            "並べたうちのどれか 1 つ（入れるたびに変わる）",
        ),
        ("{date|fullwidth}", "| のあとの名前で変えた値"),
        ("{{ }}", "「{」と「}」の文字そのもの"),
    ];
    pub const COMMANDS_PAGE: &str = "コマンド";
    pub const COMMANDS_SECTION: &str = "コマンド";
    pub const LAUNCHER_COMMANDS: &str = "読みでコマンドを呼び出す";
    pub const COMMANDS_NOTE: &str = "読みを変換すると、候補の一覧に「コマンド」の札を付けた名前が並びます。選んで確定したときだけ動き、第 1 候補にはなりません。コマンドはこのコンピュータだけに保存し、同期や設定の読み込みでは変わりません。";
    pub const COMMAND_READING: &str = "読み";
    pub const COMMAND_TITLE: &str = "名前";
    pub const COMMAND_KIND: &str = "動作";
    pub const COMMAND_TARGET: &str = "行き先";
    pub const COMMANDS_EMPTY: &str = "コマンドはありません";
    pub const ADD_COMMAND: &str = "コマンドを追加…";
    pub const EDIT_COMMAND: &str = "編集…";
    pub const REMOVE_COMMAND: &str = "削除";
    pub const CHOOSE_APPLICATION: &str = "アプリを選択…";
    pub const CHOOSE_FILE: &str = "ファイルを選択…";
    pub const INVALID_COMMAND: &str = "読み・名前・行き先を確認してください";
    pub const TOO_MANY_COMMANDS: &str = "これ以上コマンドを追加できません";
    pub const SAVE: &str = "保存";
    pub const CANCEL: &str = "キャンセル";
    pub const TARGET_PLACEHOLDER_U_R_L: &str = "https://";
    pub const TARGET_PLACEHOLDER_SHORTCUT: &str = "ショートカットの名前";
    pub const MACROS_SECTION: &str = "変換マクロ";
    pub const CONVERSION_MACROS: &str = "連想変換のキーで変換マクロを表示";
    pub const MACROS_NOTE: &str = "変換中に連想変換のキーを押すと、選んでいる語を整えた形が「整形」に並びます。チェックを入れた形だけを出します。{text} が語、{reading} が読みです。日時・乱数・{reading|romaji} のような変換も使えます。";
    pub const MACRO_PATTERN: &str = "形";
    pub const MACROS_EMPTY: &str = "マクロはありません";
    pub const INVALID_MACRO: &str = "{text} か {reading} を含めてください";
    pub const MACRO_SKIPS_SAME_READING: &str = "かなの語には読みを添える形を出さない";
    pub const TRY_MACROS: &str = "変換マクロを試す";
    pub const TRY_MACRO_WORD: &str = "試す語";
    pub const TRY_MACRO_READING: &str = "読み";
    pub const MACRO_DRAFT_RESULT: &str = "入力中の形: ";
}

/// UIStrings.More
pub mod more {
    pub const ALPHABET_WIDTH: &str = "英字幅";
    pub const SHIFT_STARTS_ALPHABET: &str = "Shift で英字入力";
    pub const MODE_INDICATOR_DURATION: &str = "モードの表示時間";
    pub const CANDIDATES: &str = "候補";
    pub const EXCLUSIONS_EMPTY: &str = "アプリはありません";
    pub const TERMINAL_COMMANDS: &str = "ターミナルでコマンドを英字で入力";
    pub const RESTRAINS_LIVE_CONVERSION_IN_CODE: &str = "エディタとターミナルでライブ変換を控える";
    pub const BEHAVIOR: &str = "動作";
    pub const APPS: &str = "アプリ";
    pub const BRANCH_CANDIDATES: &str = "分岐図の候補数";
    pub const LIST_CANDIDATES: &str = "一覧の候補数";
    pub const GRID_COLUMNS: &str = "表の列数";
    pub const EXPANDS_GRID_ON_PAGING: &str = "候補を送り続けたら表に広げる";
    pub const GRID_COLUMNS_NOTE: &str =
        "変換中にキー設定の「候補を表に広げる」のキーを押すと、候補を「一覧の候補数」の行 × この列数の表に広げます。";
    pub const CONTEXTUAL_SEGMENT_CANDIDATES: &str = "前後の文脈で候補を並べ替え";
    pub const CONTEXTUAL_SEGMENT_CANDIDATES_NOTE: &str =
        "分岐図・文節ごとの一覧・入力中の候補で、前後の語句とのつながりがよい候補を上に表示します。";
    pub const LIST_SEGMENT_ALTERNATIVES: &str = "一覧に文節を入れ替えた候補を表示";
    pub const LIST_SEGMENT_ALTERNATIVES_NOTE: &str =
        "一覧で、文節を 1 か所だけほかの候補に替えた文を、迷う文節から順に表示します。";
    pub const LIVE_CONVERSION_DELAY: &str = "漢字にするまでの待ち時間";
    pub const LIVE_CONVERSION_SKIP_LENGTH: &str = "ライブ変換しない文字数";
    pub const ENGLISH_SKIP_LENGTH: &str = "英単語にしない文字数";
    pub const SUGGESTION_SKIP_COUNT: &str = "入力中の候補を表示しない件数";
    pub const TYPO: &str = "タイプミス";
    pub const CORRECTION_SENSITIVITY: &str = "修正の基準";
    pub const SHOWS_SUGGESTIONS: &str = "「もしかして」を表示";
    pub const CORRECTION_DELAY: &str = "見直すまでの待ち時間";
    pub const REVIEW_CORRECTION_TIMEOUT: &str = "見直しの時間の上限";
    pub const LATE_CORRECTION_TIMEOUT: &str = "変換後の補正の時間の上限";
    pub const REMEMBERS_REJECTED_CORRECTIONS: &str = "自動修正のキャンセルを学習";
    pub const THEME: &str = "テーマ";
    pub const CUSTOM_THEMES: &str = "カスタムテーマ";
    pub const DUPLICATE: &str = "今のテーマを複製";
    pub const DELETE_THEME: &str = "削除";
    pub const THEME_NAME: &str = "名前";
    pub const COLORS: &str = "色";
    pub const SURFACE: &str = "背景";
    pub const TEXT: &str = "文字";
    pub const TEXT_MUTED: &str = "補助の文字";
    pub const SELECTION: &str = "選択";
    pub const SELECTION_TEXT: &str = "選択中の文字";
    pub const CORRECTION: &str = "修正の印";
    pub const LINE: &str = "線";
    pub const SHAPE: &str = "形";
    pub const CORNER_RADIUS: &str = "角の丸さ";
    pub const BRANCH_STYLE: &str = "枝";
    pub const THEME_FONT: &str = "テーマに合わせる";
    pub const FONT_STYLE: &str = "スタイル";
    pub const DUPLICATE_THEME: &str = "複製";
    pub const NEW_THEME_NAME: &str = "新しいテーマ";
    pub const NO_CUSTOM_THEMES: &str = "カスタムテーマはありません";
    pub const PREVIEW: &str = "見本";
    pub const READABILITY: &str = "読みやすさ";
    pub const INVALID_THEME: &str = "名前を入力してください";

    pub fn copy_name(name: &str) -> String {
        format!("{name} のコピー")
    }

    pub fn themes_full(limit: usize) -> String {
        format!("カスタムテーマは {limit} 個までです")
    }

    pub fn confirm_delete_theme(name: &str) -> String {
        format!("「{name}」を削除しますか？")
    }

    /// 読みにくい組み合わせの知らせ(UIStrings.More.lowContrast と同じ文)
    pub fn low_contrast(name: &str, ground: &str, ratio: f64, minimum: f64) -> String {
        format!("{name}と{ground}の色が近く、読みにくくなっています。コントラスト比は {ratio:.1} で、{minimum:.1} 以上が目安です。")
    }
    pub const FONT: &str = "書体";
    pub const BACKUP: &str = "バックアップ";
    pub const ADD_APPS: &str = "アプリを追加…";
    pub const IMPORT_CSV: &str = "CSV をインポート…";
    pub const EXPORT_CSV: &str = "CSV をエクスポート…";
    pub const EXPORT_CSV_FILE_NAME: &str = "hajime-exclusions.csv";
    pub fn imported_rules(count: u32) -> String {
        format!("{count} 件を追加しました")
    }
    pub const CSV_FAILED: &str = "読み込めませんでした。CSV のファイルではないか、大きすぎます";
    pub const BACKUP_NOTE: &str = "すべての設定を JSON としてインポート・エクスポート可能です。";
    pub const EXPORT_SETTINGS: &str = "設定をエクスポート…";
    pub const IMPORT_SETTINGS: &str = "設定をインポート…";
    pub const EXPORT_SETTINGS_FILE_NAME: &str = "hajime-settings.json";
    pub const SETTINGS_IMPORTED: &str = "設定を読み込みました";
    pub const SETTINGS_IMPORT_FAILED: &str =
        "読み込めませんでした。Hajime IME の設定ファイルではないか、大きすぎます";
    pub const SETTINGS_EXPORT_FAILED: &str = "書き出せませんでした";
    pub const ABOUT: &str = "情報";
    pub const VERSION: &str = "バージョン";
    pub const CHECK_FOR_UPDATES: &str = "更新を確認";
    pub const ACKNOWLEDGEMENTS: &str = "謝辞";
    pub const ACKNOWLEDGEMENTS_NOTE: &str =
        "Hajime IME は上記のソフトウェア・モデル・データを利用しています。";
    pub const NOTICES_MISSING: &str = "謝辞のファイルが見つかりません";
    /// 謝辞の項目のライセンスの全文を開く(macOS の UIStrings.More.licenseText)
    pub const LICENSE_TEXT: &str = "ライセンス全文";

    pub fn seconds(value: f64) -> String {
        format!("{value:.1} 秒")
    }

    /// ライブ変換しない文字数・英単語にしない文字数の表示．0 はオフ
    pub fn skip_length(value: f64) -> String {
        if value == 0.0 {
            "オフ".to_string()
        } else {
            format!("{value} 文字以下")
        }
    }

    /// 入力中の候補を表示しない件数の表示．0 はオフ(macOS の UIStrings.More.skipCount)
    pub fn skip_count(value: f64) -> String {
        if value == 0.0 {
            "オフ".to_string()
        } else {
            format!("{value} 件以下")
        }
    }
}

/// UIStrings.Keys(キー設定のページの名前と，検索に使うコマンド・状態・ひな形の名前)
pub mod keys {
    /// 絞り込んで行が無くなったとき
    pub const NO_MATCHES: &str = "当てはまる行はありません";
    pub const SEARCH_PROMPT: &str = "コマンドやキーで検索";
    pub const TAB: &str = "キー設定";
    pub const PRESET_MENU: &str = "ひな形を読み込む";
    pub const STATE: &str = "状態";
    pub const KEY: &str = "キー";
    pub const COMMAND: &str = "コマンド";
    pub const LOAD: &str = "読み込む";
    pub const RESTORE: &str = "既定に戻す";
    pub const DUPLICATE: &str = "複製";
    pub const PRESS: &str = "キーを押してください";
    pub const RECORD: &str = "キーを記録";
    pub const LOAD_PRESET_TITLE: &str = "ひな形を読み込みますか？";
    pub const RESTORE_TITLE: &str = "既定の表に戻しますか？";
    pub const RESTORE_MESSAGE: &str = "追加した行と変更した行は削除されます。";
    pub const ALL_STATES: &str = "すべての状態";

    /// UIStrings.Keys.rowCount(出している行の数と，すべての行の数)
    pub fn row_count(shown: usize, total: usize) -> String {
        if shown == total {
            format!("{total} 行")
        } else {
            format!("{shown} / {total} 行")
        }
    }
    pub const PLAIN_CHARACTER: &str =
        "修飾キーの無い文字のキーです。この状態ではその文字を入力できなくなります";
    pub const MISSING_NOTE: &str = "キーが無いと、入力を確定したり取り消したりできなくなります。";

    pub fn load_preset_message(name: &str) -> String {
        format!("今の表を「{name}」の行で置き換えます。")
    }

    pub fn hidden(winners: &str) -> String {
        format!("同じキーの行があるため使われません: {winners}")
    }

    pub fn partly_hidden(states: &str, winners: &str) -> String {
        format!("{states}では次の行を使います: {winners}")
    }

    pub fn missing(state: &str, command: &str) -> String {
        format!("{state}に「{command}」のキーがありません")
    }

    /// 状態(KeymapState)の値と名前
    pub const STATES: &[(&str, &str)] = &[
        ("anywhere", "いつでも"),
        ("idle", "入力文字なし"),
        ("composing", "入力中"),
        ("converting", "変換中"),
        ("direct", "英数"),
    ];
    /// ひな形(KeymapPreset)の値と名前
    pub const PRESETS: &[(&str, &str)] = &[
        ("standard", "標準"),
        ("windows", "Windows 風"),
        ("mac", "Mac 風"),
        ("emacs", "Emacs 風"),
        ("vim", "Vim 風"),
        ("atok", "ATOK 風"),
    ];
    /// コマンド(KeymapCommand)の値と名前．並びは core の KeymapCommand と同じ
    pub const COMMANDS: &[(&str, &str)] = &[
        ("japaneseMode", "日本語入力に切り替え"),
        ("directMode", "英数入力に切り替え"),
        ("toggleMode", "日本語と英数の切り替え"),
        ("nextInputStyle", "入力方式の切り替え"),
        ("romajiStyle", "ローマ字入力"),
        ("kanaStyle", "かな入力"),
        ("englishStyle", "英字入力"),
        ("englishAutoStyle", "英字入力(自動)"),
        ("insertSpace", "空白を入力"),
        ("insertAlternateSpace", "逆の幅の空白を入力"),
        ("insertHalfwidthSpace", "半角空白を入力"),
        ("insertFullwidthSpace", "全角空白を入力"),
        ("convert", "変換"),
        ("convertWithoutLearning", "学習を使わずに変換"),
        ("deleteBackward", "左の文字を削除"),
        ("insertBoundary", "ここで区切る"),
        ("acceptSuggestion", "「もしかして」に修正・予測を確定"),
        ("toHiragana", "全文をひらがなに変換"),
        ("toKatakana", "全文を全角カタカナに変換"),
        ("toHalfwidthKatakana", "全文を半角カタカナに変換"),
        ("toFullwidthAlphanumeric", "全文を全角英数に変換"),
        ("toHalfwidthAlphanumeric", "全文を半角英数に変換"),
        ("switchKanaType", "かなの種類を切り替え"),
        ("segmentToHiragana", "文節をひらがなに変換"),
        ("segmentToKatakana", "文節を全角カタカナに変換"),
        ("segmentToHalfwidthKatakana", "文節を半角カタカナに変換"),
        ("nextCandidate", "次の候補"),
        ("previousCandidate", "前の候補"),
        ("nextCandidatePage", "次の候補のページ"),
        ("previousCandidatePage", "前の候補のページ"),
        ("firstCandidate", "先頭の候補"),
        ("lastCandidate", "末尾の候補"),
        ("nextSegment", "右の文節"),
        ("previousSegment", "左の文節"),
        ("firstSegment", "先頭の文節"),
        ("lastSegment", "末尾の文節"),
        ("nextUncertainSegment", "誤りやすい次の文節"),
        ("previousUncertainSegment", "誤りやすい前の文節"),
        ("extendSegment", "文節を長く"),
        ("shrinkSegment", "文節を短く"),
        ("extendSegmentToWord", "文節を単語ごとに長く"),
        ("shrinkSegmentToWord", "文節を単語ごとに短く"),
        ("splitSegment", "文節を区切る"),
        ("editSegment", "文節を打ち直す"),
        ("commit", "確定"),
        ("commitFirstSegment", "先頭の文節だけ確定"),
        ("cancel", "取り消し"),
        ("cancelAndDirectMode", "取り消して英数入力に"),
        ("backToReading", "全文を読みに戻す"),
        ("resumeEditing", "読みに戻して末尾から編集"),
        ("undoConversionEdit", "直前の変更を取り消し"),
        ("undoPrediction", "予測の確定を取り消し"),
        ("undoCommit", "確定を取り消し"),
        ("forgetCandidate", "候補を学習から削除"),
        ("forgetLastCommit", "最後の学習を取り消し"),
        ("hidePrediction", "予測に表示しない"),
        ("openSettings", "設定を開く"),
        ("toggleLiveConversion", "ライブ変換の切り替え"),
        ("handwriting", "手書き入力"),
        ("emojiPalette", "絵文字のパレット"),
        ("symbolPalette", "記号のパレット"),
        ("kaomojiPalette", "顔文字のパレット"),
        ("registerWord", "単語の登録"),
        ("openUserDictionary", "ユーザー辞書を開く"),
        ("openMenu", "入力メニューを開く"),
        ("reconvert", "再変換"),
        ("associate", "連想変換"),
        ("expandCandidates", "候補を表に広げる"),
    ];
    /// コマンドの説明(UIStrings.Keys.help(for:))．名前で分かるコマンドは並べない
    pub const COMMAND_HELP: &[(&str, &str)] = &[
        ("nextInputStyle", "ローマ字入力・かな入力・英字入力・英字入力(自動)を順に切り替えます"),
        ("englishAutoStyle", "英語で入力しながら、日本語にできる語句を自動で日本語に変換します"),
        ("insertSpace", "幅は「スペース幅」の設定に従います。入力中の文字は確定してから入力します"),
        ("insertAlternateSpace", "「スペース幅」の設定と逆の幅の空白を入力します"),
        ("convert", "英単語を修正した直後は、修正前に戻します"),
        ("convertWithoutLearning", "学習した順位を使わずに変換し、確定しても学習しません"),
        ("insertBoundary", "入力中に、現在の位置で文節を区切ります"),
        ("acceptSuggestion", "「もしかして」で示した読みに修正します。示していないときは入力中の予測を確定し、予測も表示していなければ入力中の候補から選択します"),
        ("switchKanaType", "ひらがな・全角カタカナ・半角カタカナを順に切り替えます"),
        ("nextCandidate", "入力中に押すと変換を始めます。入力中の候補を表示しているときは、その候補から選択します"),
        ("previousCandidate", "入力中に押すと変換を始めます。入力中の候補を表示しているときは、文字種から選択します。分岐図では上の枝の文字種へ進みます"),
        ("nextUncertainSegment", "誤変換の可能性が高い文節に移動します"),
        ("previousUncertainSegment", "誤変換の可能性が高い文節に移動します"),
        ("extendSegmentToWord", "文節の終わりを次・前の単語の切れ目まで動かします"),
        ("shrinkSegmentToWord", "文節の終わりを次・前の単語の切れ目まで動かします"),
        ("splitSegment", "単語の切れ目に番号を表示し、数字キーで区切ります"),
        ("editSegment", "選んでいる文節を消して読みを打ち直します。文節を移ると変換します"),
        ("commitFirstSegment", "先頭の文節を確定し、残りの変換を続けます"),
        ("cancel", "変換中は読みに戻し、修正した読みは入力したままに戻します。入力中は読みを削除します"),
        ("backToReading", "変換をやめて全文を読みに戻します。ライブ変換がオンでも、読みを変更するまで読みのまま表示します"),
        ("resumeEditing", "変換をやめて読みに戻り、末尾から入力を続けます"),
        ("undoConversionEdit", "直前に変更した候補や文節の区切りを元に戻します。続けて押すと全文を読みに戻します"),
        ("undoPrediction", "予測を確定した直後に押すと、確定した語句を削除して予測で補う前の読みに戻します。確定した語句の学習も取り消します。直後でなければ、キーはそのままアプリに渡します"),
        ("undoCommit", "確定した直後に押すと、確定した文字を削除して確定する前の変換に戻します。文節の区切りと選んだ候補も戻るので、そのまま選び直せます。確定した語句の学習も取り消します。直後でなければ、キーはそのままアプリに渡します"),
        ("segmentToHiragana", "変換中に、選択中の文節だけを変換します。ほかの文節はそのままです"),
        ("segmentToKatakana", "変換中に、選択中の文節だけを変換します。ほかの文節はそのままです"),
        ("segmentToHalfwidthKatakana", "変換中に、選択中の文節だけを変換します。ほかの文節はそのままです"),
        ("forgetCandidate", "選択中の候補を学習から削除します"),
        ("forgetLastCommit", "最後に確定した語句の学習を取り消します。入力した文字は削除しません"),
        ("hidePrediction", "入力中の予測の窓に表示している語句を「予測に表示しない語句」に追加し、次から予測に表示しません。設定の「予測に表示しない語句」から削除すると、また表示します"),
        ("handwriting", "「手書き入力」の設定がオンのときに使えます"),
        ("emojiPalette", "「絵文字と記号のパレット」の設定がオンのときに使えます。開いているときに押すと閉じます"),
        ("symbolPalette", "「絵文字と記号のパレット」の設定がオンのときに使えます。開いているときに押すと閉じます"),
        ("kaomojiPalette", "「絵文字と記号のパレット」の設定がオンのときに使えます。開いているときに押すと閉じます"),
        ("reconvert", "選択中の確定済みの文字を読みに戻して変換し直します。Esc で元の文字に戻します。確定した直後に押すと、確定を取り消して確定する前の変換に戻します"),
        ("associate", "選択中の文節を、似た意味や関連のある単語の一覧に切り替えます。入力中は変換してから切り替えます"),
        ("registerWord", "ユーザー辞書の画面を開き、入力中の語句か、選択中の文字を単語の欄に入れます"),
        ("openMenu", "入力メニューの項目を入力位置に表示します"),
        ("expandCandidates", "候補を何列かの表に広げ、一度に多くの候補を表示します。表では文節の移動のキーで列を移り、数字キーは選択中の列から選びます。もう一度押すか Esc で元に戻します"),
    ];
}

/// UIStrings.RuleList
pub mod rule_list {
    pub const UPDATE: &str = "更新";
    pub const ENABLED: &str = "有効";
    pub const FULL: &str = "これ以上は追加できません。";
    pub const ALREADY_REGISTERED: &str = "すでに登録されています。";
    pub const NO_MATCHES: &str = "一致する項目はありません";
}

/// UIStrings.Terms
pub mod terms {
    pub const ENABLED: &str = "専門用語の辞書を使う";
    pub const FIELDS: &str = "使う分野";
    pub const NOTE: &str = "医学・法律・情報技術などの専門用語のうち、通常の辞書に無い語を候補に足します。通常の辞書にある語は、ここで切っても出ます。語は JMdict と Wikidata から集めています。";

    /// 分野の id と名前(core の TermField と同じ並びと名前．tools/check/check_strings.py が確かめる)
    pub const FIELD_NAMES: &[(&str, &str)] = &[
        ("computing", "情報技術"),
        ("medicine", "医学"),
        ("biology", "生物学"),
        ("chemistry", "化学"),
        ("physics", "物理学"),
        ("mathematics", "数学"),
        ("earth", "地学・天文学"),
        ("engineering", "工学"),
        ("architecture", "建築"),
        ("law", "法律・政治"),
        ("economics", "経済・金融"),
        ("business", "ビジネス"),
        ("linguistics", "言語学"),
        ("philosophy", "哲学・思想"),
        ("religion", "宗教・神話"),
        ("music", "音楽"),
        ("design", "美術・デザイン"),
        ("food", "料理・食品"),
        ("sports", "スポーツ"),
        ("games", "囲碁・将棋・ゲーム"),
        ("military", "軍事"),
        ("agriculture", "農林水産"),
        ("performingArts", "芸能・映像"),
        ("history", "歴史・考古学"),
    ];
}

/// UIStrings.Dictionaries
pub mod dictionaries {
    pub const USER_WORDS: &str = "登録した単語";
    pub const IMPORTED: &str = "取り込んだ辞書";
    pub const TERMS: &str = "専門用語";
    pub const EMPTY: &str = "取り込んだ辞書はありません";
    pub const IMPORT_FILE: &str = "辞書をインポート…";
    pub const REIMPORT: &str = "再読み込み…";
    pub const NAME: &str = "名前";
    pub const FIELD: &str = "分野";
    pub const CONDITION: &str = "使う場面";
    pub const ALWAYS: &str = "常に";
    pub const APPS: &str = "選んだアプリ";
    pub const CONTEXT: &str = "文脈に合わせる";
    pub const MOVE_UP: &str = "優先度を上げる";
    pub const MOVE_DOWN: &str = "優先度を下げる";
    pub const IMPORT_FAILED: &str =
        "辞書を取り込めませんでした。大きすぎるか、対応していない形式です";
    pub const NOTE: &str =
        "タブ区切り・SKK・macOS のユーザー辞書の形式を読み込めます。上にある辞書ほど優先されます。";

    pub fn too_many(limit: usize) -> String {
        format!("取り込める辞書は {limit} 個までです")
    }

    pub fn imported(count: u32) -> String {
        format!("{count} 件を取り込みました")
    }

    /// 一覧の内容の列(分野・語の数・使う場面)．UIStrings.Dictionaries.summary と同じ形
    pub fn summary(field: &str, words: u64, condition: &str) -> String {
        let field = if field.is_empty() {
            String::new()
        } else {
            format!("{field}・")
        };
        format!("{field}{words} 件・{condition}")
    }

    /// 選んだアプリの使う場面(「選んだアプリ 2 個」)
    pub fn apps_condition(count: usize) -> String {
        format!("{APPS} {count} 個")
    }
}

/// UIStrings.Palette(絵文字と記号のパレット．R-26)
pub mod palette {
    pub const PAGE: &str = "絵文字と記号";
    pub const BEHAVIOR: &str = "パレット";
    pub const LOOK: &str = "パレットの見た目";
    pub const ENABLED: &str = "絵文字と記号のパレット";
    pub const CLOSES_AFTER_INSERT: &str = "入力したらパレットを閉じる";
    pub const RECORDS_HISTORY: &str = "パレットで使った文字を記録";
    pub const COLUMNS: &str = "パレットの列数";
    pub const ROWS: &str = "パレットの行数";
    pub const CELL_SIZE: &str = "パレットのマスの大きさ";
    pub const SHOWS_PREVIEW: &str = "パレットに文字の説明を表示";
    pub const SHOWS_UNICODE_NAME: &str = "説明に Unicode の名前を表示";
    pub const SHOWS_READINGS: &str = "説明に読みを表示";
    pub const SHOWS_SHORTCODES: &str = "説明にショートコードを表示";
    pub const SHOWS_CODE_POINTS: &str = "説明にコードポイントを表示";
    pub const FREQUENT_ROWS: &str = "よく使う文字の行数";
    pub const CLEAR_HISTORY: &str = "使った文字の記録を消去";
    pub const CLEAR_HISTORY_QUESTION: &str = "使った文字の記録を消去しますか？";
    pub const EMOJI_KEY: &str = "絵文字のパレットを開くキー";
    pub const SYMBOL_KEY: &str = "記号のパレットを開くキー";
    pub const KAOMOJI_KEY: &str = "顔文字のパレットを開くキー";
    pub const NO_KEY: &str = "なし";
    pub const CLEAR_HISTORY_NOTE: &str =
        "よく使う文字と、探した語ごとに選んだ文字の記録を消去します。ピン留めと肌の色はそのまま残します。";
    pub const THEME_NOTE: &str =
        "色と書体は「外観」のテーマに従います。開くキーは「キー設定」で変更できます。";

    /// UIStrings.Palette.cellSizeValue(スライダーの名前に今の値を付ける)
    pub fn cell_size_value(size: f64) -> String {
        format!("{CELL_SIZE}：{} pt", size.round() as i64)
    }
}

/// UIStrings.Association
pub mod association {
    pub const SECTION: &str = "連想変換";
    pub const ENABLED: &str = "連想変換";
    pub const LIMIT: &str = "連想の候補数";
    pub const HINT: &str = "連想の案内を表示";
    pub const DICTIONARIES: &str = "連想の辞書";
    pub const EMPTY: &str = "連想の辞書はありません";
    pub const IMPORT_FILE: &str = "連想の辞書をインポート…";
    pub const IMPORT_FAILED: &str =
        "連想の辞書を取り込めませんでした。大きすぎるか、対応していない形式です";
    pub const NOTE: &str = "1 行に同じ意味の単語をタブか「,」で区切って並べたファイルを読み込めます。タブで区切るときは、先頭の列に意味の説明を書きます。上にある辞書ほど先に出ます。";

    pub fn too_many(limit: usize) -> String {
        format!("取り込める連想の辞書は {limit} 個までです")
    }

    pub fn imported(count: u32) -> String {
        format!("{count} 件の意味を取り込みました")
    }

    pub fn summary(groups: u64) -> String {
        format!("{groups} 件の意味")
    }
}

/// UIStrings.Sync
pub mod sync {
    pub const PAGE: &str = "同期";
    pub const ENABLED: &str = "同期";
    pub const FOLDER: &str = "フォルダ";
    pub const NO_FOLDER: &str = "未選択";
    pub const CHOOSE_FOLDER: &str = "フォルダを選択…";
    pub const LAST_SYNCED: &str = "最後に同期した時刻";
    pub const SYNC_NOW: &str = "今すぐ同期";
    pub const SCOPES: &str = "同期する項目";
    pub const FAILED: &str = "同期できませんでした";
    pub const UNREADABLE: &str = "同期ファイルを読み込めないため、同期を停止しています";
    pub const ITEMS: &str = "項目ごとに選択";

    /// 項目(Settings の CodingKeys の名前)の表示名(UIStrings.Sync.label(forField:))
    pub const FIELD_LABELS: &[(&str, &str)] = &[
        ("inputStyle", "入力方式"),
        ("customRomaji", "ローマ字"),
        ("liveConversion", "ライブ変換"),
        ("englishInputLiveConversion", "英字入力のライブ変換"),
        ("wordLanguage", "英語と日本語"),
        ("yenKey", "¥ キーで入力する文字"),
        ("punctuation", "句読点"),
        ("brackets", "[ ] キーで入力する括弧"),
        ("slash", "/ キーで入力する文字"),
        ("spaceWidth", "スペース幅"),
        ("numberWidth", "数字幅"),
        ("alphabetWidth", "英字幅"),
        ("shiftStartsAlphabet", "Shift で英字入力"),
        ("numberSeparators", "数字のあとの句読点をピリオドとカンマに"),
        ("alphanumericHyphen", "英数字のあとの長音をハイフンに"),
        ("punctuationCommits", "句読点で確定"),
        ("keypadDirect", "テンキーの数字を半角で確定"),
        ("questionExclamationCommits", "？と！で確定"),
        ("keypadCalculation", "テンキーの Enter で計算"),
        (
            "cyclesLetterCase",
            "英数に変えるキーで大文字と小文字を切り替え",
        ),
        ("typoCorrection", "タイプミスの修正"),
        ("candidatePresentation", "候補の表示"),
        ("initialFocus", "最初に選択する文節"),
        ("suggestionDisplay", "入力中の候補"),
        ("predictionDisplay", "入力中の予測"),
        ("predictionPrefersHistory", "入力履歴にある予測を優先"),
        ("hiddenPredictions", "予測に表示しない語句"),
        (
            "predictionFromCorrection",
            "打ち間違いを直した読みからも予測",
        ),
        ("suggestionSkipCount", "入力中の候補を表示しない件数"),
        ("listCandidatesPerPage", "一覧の候補数"),
        ("branchCandidatesPerPage", "分岐図の候補数"),
        ("candidateGridColumns", "表の列数"),
        ("expandsGridOnPaging", "候補を送り続けたら表に広げる"),
        ("contextualSegmentCandidates", "前後の文脈で候補を並べ替え"),
        (
            "listSegmentAlternatives",
            "一覧に文節を入れ替えた候補を表示",
        ),
        ("liveConversionDelay", "漢字にするまでの待ち時間"),
        ("liveConversionSkipLength", "ライブ変換しない文字数"),
        ("englishSkipLength", "英単語にしない文字数"),
        ("correctionDelay", "見直すまでの待ち時間"),
        ("reviewCorrectionTimeout", "見直しの時間の上限"),
        ("lateCorrectionTimeout", "変換後の補正の時間の上限"),
        ("remembersRejectedCorrections", "自動修正のキャンセルを学習"),
        ("correctionSensitivity", "修正の基準"),
        ("showsSuggestions", "「もしかして」を表示"),
        ("correction", "補正"),
        ("okuriganaStyle", "送り仮名"),
        ("calculation", "計算"),
        ("postalCodeConversion", "郵便番号から住所に変換"),
        ("handwriting", "手書き入力"),
        ("homophoneNotes", "語の意味と使い分けを表示"),
        ("meaningPlacement", "意味の位置"),
        ("meaningSenseLimit", "意味の数"),
        ("showsPartOfSpeech", "品詞を表示"),
        ("showsUsageExamples", "使い方の例を表示"),
        ("showsHomophones", "同音語を表示"),
        ("misuseNotes", "誤用の注釈を表示"),
        ("proofreading", "校正支援"),
        ("misreadings", "読み違いの候補"),
        ("prefersKatakana", "カタカナ語を優先"),
        ("showsVariantRow", "候補の上に文字種の行を表示"),
        ("showsKeyHints", "キーの案内を表示"),
        ("numberKeySelection", "番号キーで候補を選択"),
        ("dateConversion", "日付と時刻に変換"),
        ("symbolConversion", "記号に変換"),
        ("emojiConversion", "文節を絵文字に変換"),
        ("emojiWordConversion", "語を絵文字に変換"),
        ("emojiCandidatePosition", "絵文字の位置"),
        ("emojiCandidateCount", "絵文字の数"),
        ("showsEmojiNames", "絵文字の名前を表示"),
        ("latexConversion", "LaTeX のコマンドに変換"),
        ("numberFormConversion", "数字を丸数字などに変換"),
        ("numberFormCircled", "丸数字"),
        ("numberFormParenthesized", "括弧付きとピリオド付きの数字"),
        ("numberFormKanji", "漢数字"),
        ("numberFormRoman", "ローマ数字"),
        ("learning", "学習"),
        ("zenzaiModel", "Zenzai のモデル"),
        ("candidateReranking", "Zenzai による候補の並べ替え"),
        ("theme", "テーマ"),
        ("candidateFontSize", "候補の文字サイズ"),
        ("showsModeIndicator", "入力モードの切り替えを表示"),
        ("modeIndicatorDuration", "モードの表示時間"),
        ("customThemes", "カスタムテーマ"),
        ("customThemeID", "使用するカスタムテーマ"),
        ("escapeSwitchesToDirect", "Esc で英数に切り替え"),
        ("terminalCommands", "ターミナルでコマンドを英字で入力"),
        ("profileRules", "除外設定"),
        (
            "restrainsLiveConversionInCode",
            "エディタとターミナルでライブ変換を控える",
        ),
        ("association", "連想変換"),
        ("associationLimit", "連想の候補数"),
        ("showsAssociationHint", "連想の案内を表示"),
        ("recordsUsage", "入力の統計を記録"),
        ("keyboardLayout", "キー配列"),
        ("keymap", "キー設定"),
        ("symbolRules", "記号"),
        ("userDictionary", "ユーザー辞書"),
        ("importedDictionaries", "取り込んだ辞書"),
        ("associationDictionaries", "連想の辞書"),
        ("termDictionary", "専門用語の辞書を使う"),
        ("termFields", "専門用語の辞書の分野"),
        (
            "macroSkipsSameReading",
            "かなの語には読みを添える形を出さない",
        ),
        ("englishTermCandidates", "英語の語の辞書を使う"),
        ("englishTerms", "英語の語の辞書に足した語"),
        ("palette", "絵文字と記号のパレット"),
        ("paletteClosesAfterInsert", "入力したらパレットを閉じる"),
        ("paletteRecordsHistory", "パレットで使った文字を記録"),
        ("paletteColumns", "パレットの列数"),
        ("paletteRows", "パレットの行数"),
        ("paletteCellSize", "パレットのマスの大きさ"),
        ("paletteShowsPreview", "パレットに文字の説明を表示"),
        ("paletteShowsUnicodeName", "説明に Unicode の名前を表示"),
        ("paletteShowsReadings", "説明に読みを表示"),
        ("paletteShowsShortcodes", "説明にショートコードを表示"),
        ("paletteShowsCodePoints", "説明にコードポイントを表示"),
        ("paletteFrequentRows", "よく使う文字の行数"),
    ];

    pub fn field_label(name: &str) -> &str {
        FIELD_LABELS
            .iter()
            .find(|(field, _)| *field == name)
            .map_or(name, |(_, label)| label)
    }
}

/// Windows の画面だけの文言
pub mod windows {
    /// パレットで使った文字の記録を消したときの知らせ(macOS は消す前に確かめる窓を出す)
    pub const PALETTE_HISTORY_CLEARED: &str = "使った文字の記録を消去しました";
    /// 製品の名前(情報のページの見出し．macOS は Bundle の名前を出す)
    pub const APP_NAME: &str = "Hajime IME";
    /// 数を 1 段ずつ変えるボタン(読み上げの名前．macOS の Stepper の矢印)
    pub const DECREASE: &str = "減らす";
    /// テーマの見本の札の文字(macOS の IndicatorLabels の日本語の札)
    pub const JAPANESE_MODE: &str = "あ";
    pub const INCREASE: &str = "増やす";
    /// 同梱の連想の辞書の内容の欄(件数は数えていないので出さない)
    pub const ASSOCIATION_BUNDLED: &str = "アプリに同梱";
    pub const ON: &str = "オン";
    pub const OFF: &str = "オフ";
    pub const OPEN_SETTINGS_FILE: &str = "設定ファイルを開く";
    /// macOS の UIStrings.Sync.note の Mac を PC に，iCloud Drive を OneDrive にしたもの
    pub const SYNC_NOTE: &str =
        "Dropbox や OneDrive のフォルダを選択すると、ほかの PC と同期できます。";
    /// 項目ごとの同期の表の列(macOS は項目ごとのスイッチ)
    pub const SYNC_FIELD: &str = "項目";
    pub const SYNC_SCOPE: &str = "範囲";
    pub const TOGGLE_SYNC_SCOPE: &str = "範囲の切り替え";
    /// 記号の一覧の状態の列(macOS は行ごとのオン・オフと印で出す)
    pub const SYMBOL_STATE: &str = "状態";
    pub const DISABLED: &str = "無効";
    /// カスタムテーマをすぐ作って下で編集する(macOS は編集の画面を開くので「…」が付く)
    pub const CREATE_THEME: &str = "カスタムテーマを作成";
    /// 選んだカスタムテーマを使う(macOS は行を押して使う)
    pub const USE_THEME: &str = "使用";
    pub const IN_USE: &str = "使用中";
    /// 取り込んだ辞書の一覧の内容の列(macOS は名前の下に小さく出す)
    pub const DICTIONARY_SUMMARY: &str = "内容";
    /// 取り込んだ辞書を使うアプリの欄(macOS はアプリを選んで足す)．実行ファイルの名前を「,」で区切る
    pub const DICTIONARY_APPS: &str = "アプリの実行ファイル名";
    /// コマンドの行き先のファイルやアプリを選ぶボタンと，選ぶ窓の種類の名前
    pub const CHOOSE_TARGET: &str = "行き先を選択…";
    pub const ALL_FILES: &str = "すべてのファイル";
    /// 試した語を一覧に足すボタン(macOS は結果の語を右クリックして選ぶ)
    pub const ADD_TO_ENGLISH: &str = "常に英語にする単語に追加";
    pub const ADD_TO_JAPANESE: &str = "常に日本語にする単語に追加";
    /// 試した語を足せないとき(1 語でない)
    pub const ADD_ONE_WORD: &str = "1 語だけを入力すると、一覧に追加できます";
    /// 選んだ記号の決まりを有効・無効にするボタン(macOS は行ごとのオン・オフ)
    pub const TOGGLE_ENABLED: &str = "有効・無効の切り替え";
    /// ファイルを選ぶ窓の種類の名前(macOS は種類を名前で出さない)
    pub const JSON_FILES: &str = "JSON ファイル";
    pub const TEXT_FILES: &str = "テキストファイル";
    pub const CSV_FILES: &str = "CSV ファイル";
    pub const APP_FILES: &str = "アプリ";

    /// バージョンの表示(ADR 0008．macOS と同じ「v0.1.0 (Windows)」の形．macOS は UIStrings.More.versionValue)
    pub fn version(version: &str) -> String {
        format!("v{version} (Windows)")
    }
    /// キーの欄の使い方(macOS は押して記録するだけなので無い．Windows は打って書くこともできる)
    pub const KEY_NOTE: &str =
        "キーの欄を押してから割り当てるキーを押すと記録します。「Ctrl+Shift+Space」のように入力することもできます。";
    /// 読めないキーの書き方
    pub const INVALID_KEY: &str = "キーの書き方が正しくありません";
    /// macOS の exclusionsNote の「アプリの固有ID」を，Windows で見分けに使う実行ファイルの名前にしたもの
    pub const EXCLUSIONS_NOTE: &str =
        "実行ファイルの名前を指定することで、アプリごとに入力方法を指定できます。昇順で適用されます。";
    /// 不正な実行ファイルの名前(macOS はアプリを選んで足すので無い)
    pub const INVALID_APP: &str = "実行ファイルの名前に使えない文字が含まれています";
    /// macOS の languageNote の右クリックで足す説明を，試す欄の下のボタンで足す説明にしたもの(Windows の結果は文字で出す)
    pub const LANGUAGE_NOTE: &str =
        "英字入力(自動)と、ローマ字入力で英語にも読める単語に使用します。試した単語は「試す」の下のボタンで一覧に追加できます。";
    /// 見分け方の決まりが無いとき(macOS は空の一覧を出すだけ)
    pub const LANGUAGE_RULES_EMPTY: &str = "判別ルールはありません";
    /// 変換エンジン(hajime-engine-host)に設定を頼めないとき
    pub const ENGINE_UNAVAILABLE: &str = "変換エンジンが動いていないため、設定を読み込めません";
    /// 変換エンジンにつながらないときの案内(設定の画面がエンジンを起動し，つながるまでつなぎ直す)
    pub const ENGINE_UNAVAILABLE_DETAIL: &str =
        "変換エンジンが動いていないため、設定を読み込めません。エンジンを起動して、つながるまで待っています。しばらくしても変わらないときは、サインインし直してください。";
}

/// UIStrings.Onboarding(初期設定．macOS と同じ文言)
pub mod wizard {
    pub const WINDOW_TITLE: &str = "Hajime IME へようこそ";
    pub const RECOMMENDED: &str = "推奨";
    pub const BACK: &str = "戻る";
    pub const NEXT: &str = "次へ";
    pub const SKIP: &str = "あとで設定する";
    pub const FINISH: &str = "はじめる";
    /// 設定の画面の「情報」のページからウィザードを開く
    pub const REDO: &str = "初期設定をやり直す";
    /// 情報のページの，ウィザードを開く行の名前
    pub const REDO_LABEL: &str = "初期設定";

    /// 何ページ目か
    pub fn step(index: usize, total: usize) -> String {
        format!("{index} / {total}")
    }

    /// 推奨の値の名前に添える(メニューの項目)
    pub fn recommended(label: &str) -> String {
        format!("{label} ({RECOMMENDED})")
    }

    pub const MODE_TITLE: &str = "英数とかなの切り替え";
    pub const MODE_DETAIL: &str = "日本語と英数を切り替えるキーを選びます。";
    pub const APP_MODES_TITLE: &str = "アプリごとの入力モード";
    pub const APP_MODES_DETAIL: &str = "アプリを切り替えたときに、IME をオンにするかオフにするかをアプリごとに決められます。除外設定でアプリを追加して選びます。";
    pub const DEMO_TERMINAL: &str = "ターミナル";
    pub const CORRECTION_TITLE: &str = "自動補正";
    pub const CORRECTION_DETAIL: &str = "打ち間違いを、文の流れから見つけて直します。直したところには点線が付き、Esc で打ったままに戻せます。";
    pub const CORRECTION_OFF: &str = "直さない";
    pub const THEME_TITLE: &str = "外観";
    pub const THEME_DETAIL: &str =
        "候補ウィンドウの見た目を選びます。あとから設定の画面で、色や書体を自由に変えられます。";
    pub const LIVE_TITLE: &str = "ライブ変換";
    pub const LIVE_DETAIL: &str =
        "打ちながら漢字に変換して見せます。Space を押さずに、そのまま Enter で確定できます。";
    pub const LIVE_ON: &str = "ライブ変換を使う";
    pub const LIVE_OFF: &str = "使わない";
    pub const LIVE_DELAY: &str = "漢字にするまでの時間";
    pub const PRESENTATION_TITLE: &str = "候補の出し方";
    pub const PRESENTATION_DETAIL: &str =
        "Space を押したときの候補の並べ方と、最初に選ぶ文節を選びます。";
    pub const INITIAL_FOCUS: &str = "最初に選ぶ文節";
    pub const CHARACTERS_TITLE: &str = "入力する文字";
    pub const CHARACTERS_DETAIL: &str = "句読点や括弧など、キーを押したときに入る文字を選びます。";
    pub const FEATURES_TITLE: &str = "便利な機能";
    pub const FEATURES_DETAIL: &str = "変換の候補に、関連する語や計算の結果などを出します。";
    pub const EXTRAS_TITLE: &str = "試験的な機能";
    pub const EXTRAS_DETAIL: &str = "既定ではオフの機能です。あとから設定の画面でも変えられます。";
    pub const MACROS: &str = "変換マクロ";
    pub const MACROS_DETAIL: &str =
        "連想変換と同じ Shift + Space で、選んでいる語を「」で囲む・ルビを付けるなどした形を出します。";
    pub const DYNAMIC_DICTIONARY: &str = "動的なユーザー辞書";
    pub const DYNAMIC_DICTIONARY_DETAIL: &str =
        "単語に {datetime:YYYY/MM/DD} などを書くと、入力したときの値にします。";
    pub const COMMANDS: &str = "コマンド";
    pub const COMMANDS_DETAIL: &str = "読みでアプリや Web ページを開きます。候補から選んだときだけ動きます。設定の「コマンド」で登録します。";
    pub const COMMANDS_EXAMPLE: &str = "Claude を開く";
    pub const SPOTLIGHT_HINT: &str = "項目にポインタを置くと、左に使い方を出します。";
    pub const ASSOCIATION: &str = "連想変換";
    pub const ASSOCIATION_DETAIL: &str = "Shift + Space で、似た意味の語を出します。";
    pub const CALCULATION: &str = "計算";
    pub const CALCULATION_DETAIL: &str = "「1+2*3=」と打つと、答えを候補に出します。";
    pub const POSTAL_CODE: &str = "郵便番号";
    pub const POSTAL_CODE_DETAIL: &str = "郵便番号から住所を出します。";
    pub const DATE: &str = "日付と時刻";
    pub const DATE_DETAIL: &str = "「きょう」「いま」「なう」から日付と時刻を出します。";
}

/// 初期設定の，macOS では関数(UIStrings.Onboarding の detail(for:) など)が返す文言と，Windows だけの文言
/// (Mac の英数キー・かなキーの代わりの無変換キー・変換キーと半角/全角キー，アプリの名前，読み込み・保存の案内)
pub mod windows_wizard {
    /// 英数とかなの切り替え(macOS の ModeSwitchStyle．分けるのが推奨)
    pub const MODE_SEPARATE: &str = "無変換キーと変換キーで分ける";
    pub const MODE_SEPARATE_DETAIL: &str =
        "無変換キーで英数、変換キーで日本語になります。半角/全角キーでも切り替えられます。";
    pub const MODE_SINGLE: &str = "半角/全角キーで切り替え";
    pub const MODE_SINGLE_DETAIL: &str =
        "半角/全角キーを押すたびに、日本語と英数が切り替わります。";

    /// アプリごとの入力モードの説明(macOS の UIStrings.Onboarding.appModeDetail(for:))
    pub const APP_MODE_OFF_DETAIL: &str =
        "そのアプリに切り替えるたびに英数にします。あとから日本語入力にも切り替えられます。";
    pub const APP_MODE_ON_DETAIL: &str = "そのアプリに切り替えるたびに日本語入力にします。";
    pub const APP_MODE_REMEMBERS_DETAIL: &str = "そのアプリで最後に使った入力モードに戻します。";

    /// 補正の強さの説明(macOS の UIStrings.Onboarding.detail(for: CorrectionSensitivity))
    pub const CORRECTION_CAUTIOUS_DETAIL: &str =
        "確かなときだけ直し、迷うときは「もしかして」で知らせます。";
    pub const CORRECTION_STANDARD_DETAIL: &str = "よくある打ち間違いを直します。";
    pub const CORRECTION_AGGRESSIVE_DETAIL: &str = "少しでも打ち間違いらしければ直します。";

    /// 候補の出し方の説明(macOS の UIStrings.Onboarding.detail(for: CandidatePresentation))
    pub const PRESENTATION_AUTOMATIC_DETAIL: &str =
        "文節ごとに候補が枝分かれします。文全体を見渡しながら、直したい文節だけを選び直せます。";
    pub const PRESENTATION_SEGMENT_LIST_DETAIL: &str = "選んでいる文節の候補を縦に並べます。";
    pub const PRESENTATION_LIST_DETAIL: &str = "文全体の候補を縦に並べます。";

    /// 実演でアプリを切り替えるときに出す名前(macOS は「メモ」)
    pub const DEMO_NOTES: &str = "メモ帳";
    /// 英数で打つ実演の文字(macOS は「Mac で」)
    pub const DEMO_DIRECT_TEXT: &str = "PC で";
    /// 補正とコマンドの実演の案内(core の Note と同じ文言)
    pub const NOTE_SUGGESTION: &str = "もしかして";
    pub const NOTE_CORRECTION: &str = "修正";
    pub const NOTE_FIX: &str = "修正";
    pub const NOTE_REVERT: &str = "戻す";
    pub const NOTE_RUN: &str = "実行";
    pub const KEY_TAB: &str = "Tab";
    pub const KEY_ESCAPE: &str = "Esc";
    pub const KEY_ENTER: &str = "Enter";
    /// コマンドの候補の頭の印(core の DefaultSettings.commandCandidateMark)
    pub const COMMAND_MARK: &str = "▶ ";
    /// 変換マクロの見出しの種類(core の DefaultSettings.macroGroupLabel)
    pub const MACRO_LABEL: &str = "整形";

    /// 最後のページの案内(macOS はメニューバーから設定を開く．Windows はタスクバーのアイコンから)
    pub const TASKBAR_NOTE: &str =
        "設定の画面は、タスクバーの入力モードのアイコンを右クリックしても開けます。";
    /// 実演の舞台の読み上げの名前
    pub const DEMO: &str = "実演";
    pub const LOADING: &str = "設定を読み込んでいます…";
    pub const SAVE_FAILED: &str =
        "設定を保存できませんでした。変換エンジンが動いているか確かめてください。";
}

/// 上限の数を差し込む誤りの文言．数は目録(protocol/settings-catalog.json．DefaultSettings の写し)から入れる．
/// macOS の UIStrings も同じ文に DefaultSettings の値を差し込む
/// 更新の確認(R-19)．Windows だけ(macOS は同梱の更新のアプリが自分の文言を持つ)
pub mod update {
    pub const TITLE: &str = "更新を確認";
    pub const CHECKING: &str = "確認中…";

    pub fn downloading(percent: Option<u8>) -> String {
        match percent {
            Some(percent) => format!("ダウンロード中… {percent}%"),
            None => "ダウンロード中…".to_string(),
        }
    }

    pub fn up_to_date(version: &str) -> String {
        format!("Hajime IME v{version} は最新のバージョンです。")
    }

    /// 新しいバージョンがあるときの問い．変更点があれば後ろに付ける
    pub fn available(latest: &str, current: &str, notes: &str) -> String {
        let question = format!(
            "Hajime IME v{latest} があります。今のバージョンは v{current} です。\n更新しますか？\n\nダウンロードしたあと、インストーラーが管理者の権限を求めます。"
        );
        if notes.is_empty() {
            question
        } else {
            format!("{question}\n\n変更点\n{notes}")
        }
    }

    pub const CHECK_FAILED: &str = "更新を確認できませんでした。";

    /// 新しいバージョンはあるが，配布物を確かめられない(SHA-256 が公開されていないなど)
    pub fn unverifiable(latest: &str) -> String {
        format!("Hajime IME v{latest} がありますが、自動では更新できません。")
    }
    pub const DOWNLOAD_FAILED: &str = "ダウンロードできませんでした。";
    pub const VERIFY_FAILED: &str = "ダウンロードしたファイルが公開されているものと一致しません。";
    pub const INSTALL_FAILED: &str = "インストーラーを起動できませんでした。";
    pub const OPEN_DOWNLOAD_PAGE: &str = "ダウンロードのページをブラウザで開きますか？";
}

pub mod limited {
    use crate::catalog::Limits;

    pub fn invalid_entry(limits: &Limits) -> String {
        format!(
            "読みはひらがなで {} 文字まで、単語は {} 文字までにしてください",
            limits.user_dictionary_reading_length, limits.user_dictionary_word_length
        )
    }

    pub fn invalid_romaji(limits: &Limits) -> String {
        format!(
            "入力は英小文字・「-」・「'」で {} 文字まで、出力は {} 文字までにしてください",
            limits.romaji_keys_length, limits.romaji_kana_length
        )
    }

    pub fn invalid_word(limits: &Limits) -> String {
        format!(
            "単語は {} 文字までの英字にしてください",
            limits.word_language_word_length
        )
    }

    pub fn invalid_rule(limits: &Limits) -> String {
        format!(
            "入力した英字は {}〜{} 文字の英字、置き換える語句は {} 文字までにしてください",
            limits.correction_rule_typed_minimum,
            limits.correction_rule_typed_maximum,
            limits.correction_rule_word_length
        )
    }

    pub fn invalid_exception(limits: &Limits) -> String {
        format!(
            "修正しない語句は {} 文字までにしてください",
            limits.exception_length
        )
    }

    pub fn invalid_symbol(limits: &Limits) -> String {
        format!(
            "連続入力は英字と数字以外の {}〜{} 文字にしてください",
            limits.symbol_sequence_minimum, limits.symbol_input_length
        )
    }

    pub fn invalid_hidden_prediction(limits: &Limits) -> String {
        format!(
            "予測に表示しない語句は {} 文字までにしてください",
            limits.hidden_prediction_length
        )
    }

    pub fn invalid_english_term(limits: &Limits) -> String {
        format!(
            "語は {}〜{} 文字の英字にしてください",
            limits.english_term_minimum, limits.english_term_maximum
        )
    }

    pub fn invalid_reading_symbol(limits: &Limits) -> String {
        format!(
            "読みは {} 文字まで、記号は {} 文字までにしてください",
            limits.symbol_input_length, limits.symbol_output_length
        )
    }
}

/// 知らせる文言．上限の数を入れるもの(Limited)は，出すときに目録の値で作る
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Text {
    Fixed(&'static str),
    Limited(LimitedText),
}

/// 上限の数を入れる誤りの文言の種類(limited の関数に当たる)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LimitedText {
    Entry,
    Romaji,
    Word,
    Rule,
    Exception,
    Symbol,
    ReadingSymbol,
    EnglishTerm,
    HiddenPrediction,
}

impl Text {
    pub fn resolve(self, limits: &crate::catalog::Limits) -> std::borrow::Cow<'static, str> {
        let make = match self {
            Text::Fixed(text) => return text.into(),
            Text::Limited(LimitedText::Entry) => limited::invalid_entry,
            Text::Limited(LimitedText::Romaji) => limited::invalid_romaji,
            Text::Limited(LimitedText::Word) => limited::invalid_word,
            Text::Limited(LimitedText::Rule) => limited::invalid_rule,
            Text::Limited(LimitedText::Exception) => limited::invalid_exception,
            Text::Limited(LimitedText::Symbol) => limited::invalid_symbol,
            Text::Limited(LimitedText::ReadingSymbol) => limited::invalid_reading_symbol,
            Text::Limited(LimitedText::EnglishTerm) => limited::invalid_english_term,
            Text::Limited(LimitedText::HiddenPrediction) => limited::invalid_hidden_prediction,
        };
        make(limits).into()
    }
}

#[cfg(test)]
mod limits {
    use super::limited;
    use crate::catalog::Catalog;

    /// 誤りの文言に，目録の上限の数がそのまま入るか(数を書き写さない)
    #[test]
    fn 誤りの文言に目録の上限の数を入れる() {
        let limits = Catalog::load().unwrap().limits;
        assert_eq!(
            limited::invalid_romaji(&limits),
            format!(
                "入力は英小文字・「-」・「'」で {} 文字まで、出力は {} 文字までにしてください",
                limits.romaji_keys_length, limits.romaji_kana_length
            )
        );
        assert!(limited::invalid_rule(&limits).starts_with(&format!(
            "入力した英字は {}〜{} 文字",
            limits.correction_rule_typed_minimum, limits.correction_rule_typed_maximum
        )));
        assert!(limited::invalid_entry(&limits).contains(&format!(
            "{} 文字まで、単語は {} 文字まで",
            limits.user_dictionary_reading_length, limits.user_dictionary_word_length
        )));
    }
}
