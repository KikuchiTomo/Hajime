import AppKit

/// 候補・予測・案内の窓(アプリで 1 組)を，今どの入力先が使っているか．
///
/// 入力先(アプリ)ごとに入力コントローラと ClientActionPresenter があり，窓は共有する．入力先を離れても，その入力先の遅れた処理
/// (打鍵が止まったときの表示・見直し・予測のタイマー，窓を置く場所の問い合わせ)が動くことがある．OS が前の入力先に離れたことを
/// 知らせる(deactivateServer)のは次の入力先に知らせる(activateServer)より遅れることも，知らせないこともあるので，
/// 最後にキーを受けたか入力先になったものだけが窓を出せるようにし，ほかの入力先の処理では窓を出さない
@MainActor
final class WindowOwnership {
    private weak var owner: AnyObject?

    /// presenter が窓を使う．前に使っていたのがほかの入力先なら true(出ている窓はその入力先のものなので，呼んだ側が消す)
    func claim(_ presenter: AnyObject) -> Bool {
        defer { owner = presenter }
        return owner != nil && owner !== presenter
    }

    /// presenter が窓を出してよいか(だれも使っていなければ出してよい)
    func isOwned(by presenter: AnyObject) -> Bool {
        owner == nil || owner === presenter
    }
}
