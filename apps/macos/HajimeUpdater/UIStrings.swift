import HajimeDomain

/// 更新用のアプリ(Hajime IME Updater)の画面に出す文言
enum UIStrings {
    static let checking = "更新を確認中…"
    static let downloading = "ダウンロード中…"
    static func downloadingPercent(_ percent: Int) -> String { "ダウンロード中… \(percent)%" }
    static let verifying = "検証中…"
    static let installing = "インストール中…"
    static let cancel = "キャンセル"

    static let upToDate = "最新のバージョンです"
    static func upToDateDetail(_ version: ReleaseVersion) -> String { "Hajime IME v\(version) は最新のバージョンです。" }

    static func available(_ version: ReleaseVersion) -> String { "Hajime IME v\(version) が利用可能です" }
    static func availableDetail(current: ReleaseVersion) -> String {
        "現在のバージョン: v\(current)\nダウンロードしてインストールしますか？インストールには管理者のパスワードが必要です。"
    }
    static let update = "更新する"
    static let later = "あとで"
    static func noteHeading(_ note: ReleaseNote) -> String { "v\(note.version) (\(note.date))" }

    static func updated(_ version: ReleaseVersion) -> String { "Hajime IME v\(version) に更新しました" }
    static let updatedDetail = "次の入力から有効になります。"

    static let failed = "更新できませんでした"
    static let openDownloadPage = "ダウンロードページを開く"
    static let close = "閉じる"

    static func detail(_ failure: UpdateFailure) -> String {
        switch failure {
        case .network: "サーバーに接続できませんでした。ネットワーク接続を確認してください。"
        case .unreadable: "最新バージョンの情報を取得できませんでした。"
        case .noPackage: "macOS 用のパッケージが見つかりませんでした。"
        // 内訳は利用者がすることを変えない(ダウンロードページから入れる)ので，同じ文にする
        case .tooLarge, .digestMismatch, .signature: "ダウンロードしたファイルを検証できませんでした。"
        case .unsignedApp: "署名のないアプリのため、自動更新できません。"
        case .installFailed: "インストールに失敗しました。"
        case .cancelled: ""
        }
    }
}
