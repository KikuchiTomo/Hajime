import Foundation
import HajimeDomain
import os

/// 確かめた配布物を OS のインストーラー(/usr/sbin/installer)で入れる．
/// 入れる場所(/Library/Input Methods)は管理者の権限が要るので，OS の管理者のパスワードの窓を出して頼む．
/// 新しいバージョンはログアウトしてログインし直したあとに動く(配布物はログアウトを求める．このコマンドで入れたときは知らせの文で伝える)
@MainActor
struct PackageInstaller {
    private let logger = Logger(subsystem: UpdaterIdentity.subsystem, category: "update")

    func install(_ package: URL) async throws(UpdateFailure) {
        // パスはスクリプトに埋め込まず引数で渡し，quoted form of でシェルに渡す
        let script = [
            "on run argv",
            "do shell script \"/usr/sbin/installer -pkg \" & quoted form of (item 1 of argv) & \" -target /\" with administrator privileges",
            "end run",
        ]
        let arguments = script.flatMap { ["-e", $0] } + [package.path]
        guard let outcome = await ProcessRunner.run("/usr/bin/osascript", arguments, timeout: DefaultSettings.updateInstallTimeout) else {
            throw .installFailed
        }
        if outcome.status == 0, !outcome.timedOut { return }
        // パスワードの窓でキャンセルを押した(AppleScript の -128)
        if outcome.output.contains("(-128)") { throw .cancelled }
        logger.error("インストールに失敗しました: status=\(outcome.status, privacy: .public) timedOut=\(outcome.timedOut, privacy: .public)")
        throw .installFailed
    }
}
