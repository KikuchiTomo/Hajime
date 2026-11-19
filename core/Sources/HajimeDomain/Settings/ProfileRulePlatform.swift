/// アプリを見分ける名前の書き方が違う OS．macOS は固有 ID(com.apple.Terminal)，Windows は実行ファイルの名前(cmd.exe)
public enum ApplicationPlatform: Sendable, Equatable {
    case macOS
    case windows
}

extension ProfileRule {
    /// Windows の実行ファイルの名前の終わり
    private static let executableSuffix = ".exe"

    /// その OS のアプリの決まりか．設定は同期で両方の OS が同じものを読むので，除外設定の一覧にはもう一方の OS のアプリも入っている．
    /// もう一方の OS の決まりは設定の画面に出さず，消さずに残す．
    /// 実行ファイルの名前(.exe で終わる)は Windows，点を含むほかの名前(固有 ID)は macOS，点を含まない名前はどちらにも出す
    /// (Windows の設定の画面の apps/windows/crates/settings/src/list.rs の is_mac_application と同じ分け方)
    public func isShown(on platform: ApplicationPlatform) -> Bool {
        let isExecutable = applicationPrefix.lowercased().hasSuffix(Self.executableSuffix)
        switch platform {
        case .macOS: return !isExecutable
        case .windows: return isExecutable || !applicationPrefix.contains(".")
        }
    }
}

extension [ProfileRule] {
    /// その OS の設定の画面に出す除外設定の決まり．並びは元のまま
    public func shown(on platform: ApplicationPlatform) -> [ProfileRule] {
        filter { $0.isShown(on: platform) }
    }

    /// 決まりを，画面に出している並びの中で offset だけ動かせるか
    public func canMove(_ rule: ProfileRule, by offset: Int, shownOn platform: ApplicationPlatform) -> Bool {
        swapPositions(rule, by: offset, shownOn: platform) != nil
    }

    /// 決まりを，画面に出している並びの中で offset だけ動かす(上にある決まりが先に効く)．
    /// 画面に出していない決まり(もう一方の OS のアプリ)の位置は変えない
    public mutating func move(_ rule: ProfileRule, by offset: Int, shownOn platform: ApplicationPlatform) {
        guard let (source, destination) = swapPositions(rule, by: offset, shownOn: platform) else { return }
        swapAt(source, destination)
    }

    /// 動かす決まりと，入れ替える相手の位置
    private func swapPositions(_ rule: ProfileRule, by offset: Int, shownOn platform: ApplicationPlatform) -> (Int, Int)? {
        let shown = indices.filter { self[$0].isShown(on: platform) }
        guard let position = shown.firstIndex(where: { self[$0] == rule }), shown.indices.contains(position + offset) else { return nil }
        return (shown[position], shown[position + offset])
    }
}
