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
        format!("{count} 語を追加しました")
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
    pub const RESTORE_DEFAULTS: &str = "初期設定に戻す";
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
    pub const FONT_SIZE: &str = "候補の文字サイズ";
    pub const ADD: &str = "追加";
    pub const ESCAPE_SWITCHES_TO_DIRECT: &str = "Escape で英数に切り替え";
    pub const ROMAJI_KEYS: &str = "入力";
    pub const READING: &str = "読み";
    pub const WORD: &str = "単語";
    pub const DICTIONARY_EMPTY: &str = "登録した単語はありません";
    pub const INVALID_ENTRY: &str =
        "読みはひらがなで入力し、読みと単語は長すぎないようにしてください";
    pub const ROMAJI_KANA: &str = "出力";
    pub const ROMAJI_EMPTY: &str = "追加した組み合わせはありません";
    pub const INVALID_ROMAJI: &str =
        "入力は英小文字・「-」・「'」で 4 文字まで、出力は 6 文字までにしてください";
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
        "オンにすると、英語の辞書にない語をローマ字として日本語にして見せます。Esc で英字に戻せます。";
    pub const ENGLISH_AUTO_NOTE: &str =
        "英語で打ちながら、日本語にできる語は自動で日本語にします。見分け方は「英語と日本語」で変えられます。";
    pub const VARIANT_ROW: &str = "候補の上に文字種の行を表示";
    pub const KEY_HINTS: &str = "キーの案内を表示";
    pub const TYPO_CORRECTION: &str = "タイプミスの修正";
    pub const YEN_KEY: &str = "¥ キーで入力する文字";
    pub const THEME: &str = "テーマ";
    pub const PRESENTATION: &str = "候補の表示";
    pub const INITIAL_FOCUS: &str = "最初に選ぶ文節";
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
    pub const ENGLISH_WORDS: &str = "いつも英語にする語";
    pub const JAPANESE_WORDS: &str = "いつも日本語にする語";
    pub const LANGUAGE_RULES: &str = "見分け方の決まり";
    pub const TRY_LANGUAGE: &str = "試す";
    pub const LANGUAGE_JUDGING: &str = "見分け方";
    pub const USES_CONTEXT: &str = "前の語で見分ける";
    pub const USES_CONTEXT_NOTE: &str =
        "make・shine のように英語にも日本語にも読める語を、前が英語なら英語、日本語なら日本語にします。";
    pub const AVOIDS_OFFENSIVE: &str = "不適切な変換を避ける";
    pub const WORD_PLACEHOLDER: &str = "英字で打つ語";
    pub const LANGUAGE_RULE_WORD: &str = "語";
    pub const LANGUAGE_RULE_CONTEXT: &str = "前";
    pub const LANGUAGE_RULE_RESULT: &str = "結果";
    pub const TRY_PLACEHOLDER: &str = "英字で打つ文(空白で区切る)";
    pub const TRY_PRECEDING: &str = "前の文字列";
    pub const INVALID_WORD: &str = "語は 32 文字までの英字にしてください";
    pub const ENGLISH_WORDS_EMPTY: &str = "いつも英語にする語はありません";
    pub const JAPANESE_WORDS_EMPTY: &str = "いつも日本語にする語はありません";
    pub const CORRECTION_PAGE: &str = "補正";
    pub const CORRECTS_ENGLISH: &str = "英単語";
    pub const EXCEPTIONS: &str = "直さない語句";
    pub const RULES: &str = "置き換え";
    pub const SYMBOLS_PAGE: &str = "記号";
    pub const SEQUENCES: &str = "連続入力によるサジェスト";
    pub const READINGS: &str = "読み仮名入力によるサジェスト";
    pub const SEARCH: &str = "検索";
    pub const CORRECTION_KINDS: &str = "直すもの";
    pub const CORRECTS_JAPANESE: &str = "日本語の打ち間違い";
    pub const CORRECTS_REPEATED_KEYS: &str = "同じキーの重なり";
    pub const EXCEPTION_PLACEHOLDER: &str = "英字か読み";
    pub const TYPED: &str = "打った英字";
    pub const REPLACEMENT: &str = "置き換える語句";
    pub const INVALID_RULE: &str =
        "打った英字は 2〜24 文字の英字、置き換える語句は 64 文字までにしてください";
    pub const INVALID_EXCEPTION: &str = "直さない語句は 64 文字までにしてください";
    pub const RULES_EMPTY: &str = "置き換えはありません";
    pub const EXCEPTIONS_EMPTY: &str = "直さない語句はありません";
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
    pub const FONT: &str = "書体";
    pub const BACKUP: &str = "バックアップ";
    pub const IMPORT_CSV: &str = "CSV を読み込む…";
    pub const EXPORT_CSV: &str = "CSV に書き出す…";
    pub const EXPORT_CSV_FILE_NAME: &str = "s90-exclusions.csv";
    pub fn imported_rules(count: u32) -> String {
        format!("{count} 件を追加しました")
    }
    pub const CSV_FAILED: &str = "読み込めませんでした。CSV のファイルではないか、大きすぎます";
    pub const BACKUP_NOTE: &str = "すべての設定を JSON としてインポート・エクスポート可能です。";
    pub const EXPORT_SETTINGS: &str = "設定を書き出す…";
    pub const IMPORT_SETTINGS: &str = "設定を読み込む…";
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
    pub const LOAD_PRESET_TITLE: &str = "ひな形を読み込みますか？";
    pub const RESTORE_TITLE: &str = "既定の表に戻しますか？";
    pub const RESTORE_MESSAGE: &str = "足した行と変えた行は消えます。";
    pub const PLAIN_CHARACTER: &str =
        "修飾キーの無い文字のキーです。この状態ではその文字を打てなくなります";
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
        ("acceptSuggestion", "「もしかして」に直す"),
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
        ("nextUncertainSegment", "次の迷う文節"),
        ("previousUncertainSegment", "前の迷う文節"),
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
}

/// UIStrings.RuleList
pub mod rule_list {
    pub const FULL: &str = "これ以上は追加できません。";
    pub const ALREADY_REGISTERED: &str = "もう登録してあります。";
}

/// UIStrings.Dictionaries
pub mod dictionaries {
    pub const IMPORTED: &str = "取り込んだ辞書";
}

/// UIStrings.Sync
pub mod sync {
    pub const PAGE: &str = "同期";
    pub const FOLDER: &str = "フォルダ";
    pub const SCOPES: &str = "同期する項目";
    pub const DICTIONARY: &str = "ユーザー辞書";
}

/// 辞書のページの検索の言葉(UIStrings.Settings.reading・word)
pub mod words {
    pub const READING: &str = "読み";
    pub const WORD: &str = "単語";
}

/// Windows の画面だけの文言
pub mod windows {
    pub const ON: &str = "オン";
    pub const OFF: &str = "オフ";
    pub const OPEN_SETTINGS_FILE: &str = "設定ファイルを開く";
    /// ファイルを選ぶ窓の種類の名前(macOS は種類を名前で出さない)
    pub const JSON_FILES: &str = "JSON ファイル";
    pub const TEXT_FILES: &str = "テキストファイル";
    pub const CSV_FILES: &str = "CSV ファイル";

    /// バージョンの表示(ADR 0008．macOS と同じ「v0.1.0 (Windows)」の形)
    pub fn version(version: &str) -> String {
        format!("v{version} (Windows)")
    }
    /// キーの書き方(macOS は押して記録するので無い)
    pub const KEY_NOTE: &str =
        "キーは「Ctrl Shift Space」のように、修飾キー(Ctrl・Alt・Shift)とキーの名前を空白で区切って入力します。";
    /// 読めないキーの書き方
    pub const INVALID_KEY: &str = "キーの書き方が正しくありません";
    /// macOS の exclusionsNote の「アプリの固有ID」を，Windows で見分けに使う実行ファイルの名前にしたもの
    pub const EXCLUSIONS_NOTE: &str =
        "実行ファイルの名前(code.exe など)を指定することで、アプリごとに入力方法を指定できます。昇順で適用されます。";
    /// 不正な実行ファイルの名前(macOS はアプリを選んで足すので無い)
    pub const INVALID_APP: &str = "実行ファイルの名前は英数字・「.」・「-」・「_」にしてください";
    /// macOS の languageNote から，試した結果を右クリックで足す説明を除いたもの(Windows の結果は文字で出す)
    pub const LANGUAGE_NOTE: &str = "英字入力(自動)と、ローマ字入力で英語にも読める語に使います。";
    /// 見分け方の決まりが無いとき(macOS は空の一覧を出すだけ)
    pub const LANGUAGE_RULES_EMPTY: &str = "見分け方の決まりはありません";
    /// 変換エンジン(s90-engine-host)に設定を頼めないとき
    pub const ENGINE_UNAVAILABLE: &str = "変換エンジンが動いていないため、設定を読み込めません";
}
