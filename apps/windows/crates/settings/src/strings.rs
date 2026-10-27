#![forbid(unsafe_code)]

//! 画面に出す文言．macOS の設定の画面(apps/macos/S90IME/UI/UIStrings.swift)と同じ文言を，同じまとまりの名前で置く．
//! Windows で言い方が違うもの(キーの名前，Mac と PC など)だけを変える

/// UIStrings.Settings
pub mod settings {
    pub const WINDOW_TITLE: &str = "s90.tokyo IME の設定";
    pub const IMPORT_DICTIONARY: &str = "インポート…";
    pub const EXPORT_DICTIONARY: &str = "エクスポート…";
    pub const EXPORT_FILE_NAME: &str = "s90-user-dictionary.txt";
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
    pub const KEYS: &str = "動作";
    pub const PUNCTUATION_COMMITS: &str = "句読点で確定";
    pub const NUMBER_KEY_SELECTION: &str = "番号キーで候補を選択";
    pub const SHOWS_MODE_INDICATOR: &str = "入力モードの切り替えを表示";
    pub const CONVERSION: &str = "変換";
    pub const SPECIAL_CONVERSION: &str = "特殊変換";
    pub const DATE_CONVERSION: &str = "日付と時刻に変換";
    pub const HOMOPHONE_NOTES: &str = "同音異義語の使い分けを表示";
    pub const MISUSE_NOTES: &str = "誤用の注釈を表示";
    pub const PROOFREADING: &str = "校正支援";
    pub const SYMBOL_CONVERSION: &str = "記号に変換";
    pub const EMOJI_CONVERSION: &str = "絵文字に変換";
    pub const LEARNING: &str = "学習";
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
    /// UIStrings.Settings.fontSize から値を除いたもの(値は部品に出す)
    pub const FONT_SIZE_NAME: &str = "候補の文字サイズ";
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
    pub const EXCEPTION_PLACEHOLDER: &str = "英字か読み";
    pub const TYPED: &str = "入力した英字";
    pub const REPLACEMENT: &str = "置き換える語句";
    pub const RULES_EMPTY: &str = "置き換えはありません";
    pub const EXCEPTIONS_EMPTY: &str = "修正しない語句はありません";
    pub const RESTORE_DEFAULT: &str = "既定に戻す";
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
    pub const LIVE_CONVERSION_DELAY: &str = "漢字にするまでの待ち時間";
    pub const TYPO: &str = "タイプミス";
    pub const CORRECTION_SENSITIVITY: &str = "修正の基準";
    pub const SHOWS_SUGGESTIONS: &str = "「もしかして」を表示";
    pub const CORRECTION_DELAY: &str = "見直すまでの待ち時間";
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
    pub const EXPORT_CSV_FILE_NAME: &str = "s90-exclusions.csv";
    pub fn imported_rules(count: u32) -> String {
        format!("{count} 件を追加しました")
    }
    pub const CSV_FAILED: &str = "読み込めませんでした。CSV のファイルではないか、大きすぎます";
    pub const BACKUP_NOTE: &str = "すべての設定を JSON としてインポート・エクスポート可能です。";
    pub const EXPORT_SETTINGS: &str = "設定をエクスポート…";
    pub const IMPORT_SETTINGS: &str = "設定をインポート…";
    pub const EXPORT_SETTINGS_FILE_NAME: &str = "s90-settings.json";
    pub const SETTINGS_IMPORTED: &str = "設定を読み込みました";
    pub const SETTINGS_IMPORT_FAILED: &str =
        "読み込めませんでした。s90.tokyo IME の設定ファイルではないか、大きすぎます";
    pub const SETTINGS_EXPORT_FAILED: &str = "書き出せませんでした";
    pub const ABOUT: &str = "情報";
    pub const VERSION: &str = "バージョン";
    pub const ACKNOWLEDGEMENTS: &str = "謝辞";
    pub const ACKNOWLEDGEMENTS_NOTE: &str =
        "s90.tokyo IME は上記のソフトウェア・モデル・データを利用しています。";
    pub const NOTICES_MISSING: &str = "謝辞のファイルが見つかりません";

    pub fn seconds(value: f64) -> String {
        format!("{value:.1} 秒")
    }
}

/// UIStrings.Keys(キー設定のページの名前と，検索に使うコマンド・状態・ひな形の名前)
pub mod keys {
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
        ("acceptSuggestion", "「もしかして」に修正"),
        ("toHiragana", "ひらがなに変換"),
        ("toKatakana", "全角カタカナに変換"),
        ("toHalfwidthKatakana", "半角カタカナに変換"),
        ("toFullwidthAlphanumeric", "全角英数に変換"),
        ("toHalfwidthAlphanumeric", "半角英数に変換"),
        ("switchKanaType", "かなの種類を切り替え"),
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
        ("commit", "確定"),
        ("commitFirstSegment", "先頭の文節だけ確定"),
        ("cancel", "取り消し"),
        ("cancelAndDirectMode", "取り消して英数入力に"),
        ("backToReading", "読みに戻す"),
        ("forgetCandidate", "候補を学習から削除"),
        ("forgetLastCommit", "最後の学習を取り消し"),
        ("openSettings", "設定を開く"),
        ("toggleLiveConversion", "ライブ変換の切り替え"),
        ("handwriting", "手書き入力"),
        ("reconvert", "再変換"),
        ("associate", "連想変換"),
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
        ("acceptSuggestion", "「もしかして」で示した読みに修正します"),
        ("switchKanaType", "ひらがな・全角カタカナ・半角カタカナを順に切り替えます"),
        ("nextCandidate", "入力中に押すと変換を始めます"),
        ("previousCandidate", "入力中に押すと変換を始めます。分岐図では上の枝の文字種へ進みます"),
        ("nextUncertainSegment", "誤変換の可能性が高い文節に移動します"),
        ("previousUncertainSegment", "誤変換の可能性が高い文節に移動します"),
        ("extendSegmentToWord", "文節の終わりを次・前の単語の切れ目まで動かします"),
        ("shrinkSegmentToWord", "文節の終わりを次・前の単語の切れ目まで動かします"),
        ("splitSegment", "単語の切れ目に番号を表示し、数字キーで区切ります"),
        ("commitFirstSegment", "先頭の文節を確定し、残りの変換を続けます"),
        ("cancel", "変換中は読みに戻し、修正した読みは入力したままに戻します。入力中は読みを削除します"),
        ("backToReading", "変換をやめて読みに戻ります"),
        ("forgetCandidate", "選択中の候補を学習から削除します"),
        ("forgetLastCommit", "最後に確定した語句の学習を取り消します。入力した文字は削除しません"),
        ("handwriting", "「手書き入力」の設定がオンのときに使えます"),
        ("reconvert", "選択中の確定済みの文字を読みに戻して変換し直します。Esc で元の文字に戻します"),
        ("associate", "選択中の文節を、似た意味や関連のある単語の一覧に切り替えます。入力中は変換してから切り替えます"),
    ];
}

/// UIStrings.RuleList
pub mod rule_list {
    pub const UPDATE: &str = "更新";
    pub const ENABLED: &str = "有効";
    pub const FULL: &str = "これ以上は追加できません。";
    pub const ALREADY_REGISTERED: &str = "すでに登録されています。";
}

/// UIStrings.Dictionaries
pub mod dictionaries {
    pub const USER_WORDS: &str = "登録した単語";
    pub const IMPORTED: &str = "取り込んだ辞書";
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
        ("punctuationCommits", "句読点で確定"),
        ("keypadDirect", "テンキーの数字を半角で確定"),
        ("typoCorrection", "タイプミスの修正"),
        ("candidatePresentation", "候補の表示"),
        ("initialFocus", "最初に選択する文節"),
        ("suggestionDisplay", "入力中の候補"),
        ("listCandidatesPerPage", "一覧の候補数"),
        ("branchCandidatesPerPage", "分岐図の候補数"),
        ("liveConversionDelay", "漢字にするまでの待ち時間"),
        ("correctionDelay", "見直すまでの待ち時間"),
        ("correctionSensitivity", "修正の基準"),
        ("showsSuggestions", "「もしかして」を表示"),
        ("correction", "補正"),
        ("okuriganaStyle", "送り仮名"),
        ("calculation", "計算"),
        ("postalCodeConversion", "郵便番号から住所に変換"),
        ("handwriting", "手書き入力"),
        ("homophoneNotes", "同音異義語の使い分けを表示"),
        ("misuseNotes", "誤用の注釈を表示"),
        ("proofreading", "校正支援"),
        ("misreadings", "読み違いの候補"),
        ("prefersKatakana", "カタカナ語を優先"),
        ("showsVariantRow", "候補の上に文字種の行を表示"),
        ("showsKeyHints", "キーの案内を表示"),
        ("numberKeySelection", "番号キーで候補を選択"),
        ("dateConversion", "日付と時刻に変換"),
        ("symbolConversion", "記号に変換"),
        ("emojiConversion", "絵文字に変換"),
        ("learning", "学習"),
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
    /// キーの書き方(macOS は押して記録するので無い)
    pub const KEY_NOTE: &str =
        "キーは「Ctrl Shift Space」のように、修飾キーとキーの名前を空白で区切って入力します。";
    /// 読めないキーの書き方
    pub const INVALID_KEY: &str = "キーの書き方が正しくありません";
    /// macOS の exclusionsNote の「アプリの固有ID」を，Windows で見分けに使う実行ファイルの名前にしたもの
    pub const EXCLUSIONS_NOTE: &str =
        "実行ファイルの名前を指定することで、アプリごとに入力方法を指定できます。昇順で適用されます。";
    /// 不正な実行ファイルの名前(macOS はアプリを選んで足すので無い)
    pub const INVALID_APP: &str = "実行ファイルの名前は英数字・「.」・「-」・「_」にしてください";
    /// macOS の languageNote から，試した結果を右クリックで足す説明を除いたもの(Windows の結果は文字で出す)
    pub const LANGUAGE_NOTE: &str =
        "英字入力(自動)と、ローマ字入力で英語にも読める単語に使用します。";
    /// 見分け方の決まりが無いとき(macOS は空の一覧を出すだけ)
    pub const LANGUAGE_RULES_EMPTY: &str = "判別ルールはありません";
    /// 変換エンジン(s90-engine-host)に設定を頼めないとき
    pub const ENGINE_UNAVAILABLE: &str = "変換エンジンが動いていないため、設定を読み込めません";
    /// 変換エンジンにつながらないときの案内(設定の画面がエンジンを起動し，つながるまでつなぎ直す)
    pub const ENGINE_UNAVAILABLE_DETAIL: &str =
        "変換エンジンが動いていないため、設定を読み込めません。エンジンを起動して、つながるまで待っています。しばらくしても変わらないときは、サインインし直してください。";
}

/// 上限の数を差し込む誤りの文言．数は目録(protocol/settings-catalog.json．DefaultSettings の写し)から入れる．
/// macOS の UIStrings も同じ文に DefaultSettings の値を差し込む
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
