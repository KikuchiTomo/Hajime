import HajimeDomain

/// 更新用のアプリ(Hajime IME Updater)の画面に出す文言
enum UIStrings {
    static let checking = "更新を確認しています…"
    static let downloading = "ダウンロードしています…"
    static func downloadingPercent(_ percent: Int) -> String { "ダウンロードしています… \(percent)%" }
    static let verifying = "配布物を検証しています…"
    static let installing = "インストールしています…"
    static let cancel = "キャンセル"

    static let upToDate = "最新のバージョンです"
    static func upToDateDetail(_ version: ReleaseVersion) -> String { "Hajime IME v\(version) は最新のバージョンです。" }

    static func available(_ version: ReleaseVersion) -> String { "Hajime IME v\(version) があります" }
    static func availableDetail(current: ReleaseVersion) -> String {
        "今のバージョンは v\(current) です。ダウンロードしてインストールしますか？インストールには管理者のパスワードが必要です。"
    }
    static let update = "更新する"
    static let later = "あとで"
    static func noteHeading(_ note: ReleaseNote) -> String { "v\(note.version) (\(note.date))" }

    static func updated(_ version: ReleaseVersion) -> String { "Hajime IME v\(version) に更新しました" }
    static let updatedDetail = "次に文字を入力したときから新しいバージョンで動きます。"

    static let failed = "更新できませんでした"
    static let openDownloadPage = "ダウンロードページを開く"
    static let close = "閉じる"

    static func detail(_ failure: UpdateFailure) -> String {
        switch failure {
        case .network: "サーバーに接続できませんでした。ネットワークの接続を確認してください。"
        case .unreadable: "最新のバージョンの情報を読み取れませんでした。"
        case .noPackage: "macOS 用の配布物が見つかりませんでした。"
        case .tooLarge: "配布物が大きすぎます。"
        case .digestMismatch: "ダウンロードしたファイルのハッシュ値が一致しません。"
        case .signature: "配布物の署名を確認できませんでした。"
        case .unsignedApp: "このアプリは署名されていないため、配布物の署名を確認できません。"
        case .installFailed: "インストールに失敗しました。"
        case .cancelled: ""
        }
    }
}
