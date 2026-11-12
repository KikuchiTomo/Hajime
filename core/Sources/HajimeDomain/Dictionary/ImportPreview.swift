/// 辞書のファイルを取り込む前に見せる，ファイルの中身の読み方(R-16・R-18・R-21)．
/// 列が何として読まれたかと，行ごとに取り込めるか(品詞を名詞にした・読めない)を示す．
/// 取り込むのは利用者が「取り込む」を押したときだけで，これを作っても何も登録しない
public struct ImportPreview: Sendable, Equatable {
    /// 取り込む先
    public enum Kind: String, Sendable, CaseIterable {
        /// 登録した単語(ユーザー辞書に足す)
        case userDictionary
        /// 取り込んだ辞書(1 つの辞書として足す)
        case dictionary
        /// 連想の辞書
        case association
    }

    /// 見分けたファイルの形
    public enum Format: String, Sendable, CaseIterable {
        /// タブで区切った列(Google 日本語入力・Microsoft IME・ATOK の書き出しを含む)
        case tabSeparated
        /// 「,」か「、」で区切った語(連想の辞書のタブの無い行)
        case commaSeparated
        case skk
        /// macOS のユーザ辞書の書き出し(plist)
        case propertyList
    }

    /// 列が何として読まれたか
    public enum Column: String, Sendable, CaseIterable {
        case reading
        case word
        case wordClass
        case comment
        /// 連想の辞書の意味の説明
        case meaning
        /// 連想の辞書の同じ意味の語
        case words
    }

    /// 行を取り込めるか
    public enum Status: String, Sendable, CaseIterable {
        case ok
        /// 品詞の列が無い・知らない品詞なので名詞にする(取り込む)
        case defaultedWordClass
        /// 読めないので取り込まない(列が足りない・読みや語に使えない文字・長すぎる)
        case unreadable
    }

    /// 1 行(SKK は 1 行に語が並ぶので，語ごとに 1 行)
    public struct Row: Sendable, Equatable {
        /// ファイルの行の番号(1 から．plist は項目の番号)
        public var line: Int
        /// columns と同じ並びの値．読めた行は取り込む値(読みはひらがなにそろえたもの，品詞は WordClass の rawValue)，
        /// 読めない行はファイルの列のまま
        public var cells: [String]
        public var status: Status

        public init(line: Int, cells: [String], status: Status) {
            self.line = line
            self.cells = cells
            self.status = status
        }
    }

    public var kind: Kind
    public var format: Format
    public var columns: [Column]
    /// 見せる行(行の番号の順)．多いときは読めない行と名詞にする行を残して，先頭から上限まで
    public var rows: [Row]
    /// ファイル全体で取り込める行(品詞を名詞にする行を含む)・品詞を名詞にする行・読めない行の数
    public var importable: Int
    public var defaulted: Int
    public var unreadable: Int

    public init(kind: Kind, format: Format, columns: [Column], rows: [Row], importable: Int, defaulted: Int, unreadable: Int) {
        self.kind = kind
        self.format = format
        self.columns = columns
        self.rows = rows
        self.importable = importable
        self.defaulted = defaulted
        self.unreadable = unreadable
    }

    /// rows はファイルの一部だけか
    public var isTruncated: Bool {
        rows.count < importable + unreadable
    }
}

extension ImportPreview: CustomStringConvertible, CustomDebugStringConvertible {
    // 中身は入力内容と同じに扱うので，ログには数だけを出す
    public var description: String {
        "ImportPreview(kind: \(kind.rawValue), format: \(format.rawValue), importable: \(importable), defaulted: \(defaulted), unreadable: \(unreadable))"
    }

    public var debugDescription: String { description }
}
