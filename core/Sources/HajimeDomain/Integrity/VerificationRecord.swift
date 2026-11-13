/// 起動のときに同梱のファイル(Zenzai モデル・jinen モデル・同梱の辞書)を確かめて合った結果の記録(ADR 0017)．
///
/// 次の起動で，ファイルの大きさ・更新日時・ファイル ID とアプリのバージョンが前回と同じなら，ハッシュを求め直さずにこの結果を使う．
/// 中身は確かめた結果だけで，入力した文字は含まない．合わなかったものは記録しない(次の起動でもう一度確かめる)
public struct VerificationRecord: Codable, Sendable, Equatable {
    /// 記録の形の番号．形を変えたら上げ，古い形の記録は使わずに確かめ直す
    public static let currentFormat = 1

    public var format: Int
    /// 記録を書いたアプリのバージョン．変われば(入れ直したら)すべて確かめ直す
    public var appVersion: String
    /// 確かめたもの(StartupResources の Zenzai・jinen・辞書)ごとの記録
    public var entries: [String: Entry]

    public init(appVersion: String, entries: [String: Entry] = [:]) {
        self.format = Self.currentFormat
        self.appVersion = appVersion
        self.entries = entries
    }

    /// 確かめて合った 1 つのもの(モデルなら 1 ファイル，辞書なら一覧にあるすべてのファイル)の記録
    public struct Entry: Codable, Sendable, Equatable {
        /// 確かめた場所(インストール先を移したら確かめ直す)
        public var location: String
        /// 照らし合わせた SHA-256(リポジトリに書いた値．版を上げて値が変われば確かめ直す)
        public var expectedSHA256: String
        /// ファイルごとの大きさ・更新日時・ファイル ID をまとめた SHA-256(FileStamp)
        public var files: String

        public init(location: String, expectedSHA256: String, files: String) {
            self.location = location
            self.expectedSHA256 = expectedSHA256
            self.files = files
        }
    }

    /// このバージョンのアプリが使ってよい記録．形かバージョンが違えば何も使わない
    public func entries(for appVersion: String) -> [String: Entry] {
        format == Self.currentFormat && self.appVersion == appVersion && !appVersion.isEmpty ? entries : [:]
    }
}

/// ファイルが前回と同じものかを見分ける属性．中身を読まずに OS から得られる
public struct FileStamp: Sendable, Equatable {
    public var size: Int64
    /// 更新日時(OS の単位のまま．比べるだけなので単位をそろえない)
    public var modified: Int64
    /// ファイル ID．macOS・Linux は st_dev と inode，Windows はボリュームのシリアル番号とファイルのインデックス
    public var volume: UInt64
    public var file: UInt64

    public init(size: Int64, modified: Int64, volume: UInt64, file: UInt64) {
        self.size = size
        self.modified = modified
        self.volume = volume
        self.file = file
    }

    /// 名前ごとの属性を 1 つの値にまとめる(記録の Entry.files)．名前の順に並べるので，渡す順によらない
    public static func digest(of stamps: [(name: String, stamp: FileStamp)]) -> String {
        var digest = SHA256Digest()
        for (name, stamp) in stamps.sorted(by: { $0.name < $1.name }) {
            digest.update("\(name)\u{0}\(stamp.size)\u{0}\(stamp.modified)\u{0}\(stamp.volume)\u{0}\(stamp.file)\n".utf8)
        }
        return digest.finalizeHex()
    }
}
