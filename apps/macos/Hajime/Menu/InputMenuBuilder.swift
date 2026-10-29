import AppKit
import os
import HajimeApplication
import HajimeDomain

/// 入力メニュー(メニューバーの「あ」)を作り，項目を選んだときの処理を行う．
///
/// 入力メニューの項目の動作は，InputMethodKit が入力コントローラ(HajimeInputController)にだけ送る．
/// target をほかのオブジェクトにすると呼ばれないので，動作の selector はコントローラから受け取り，
/// コントローラはここの handle* を呼ぶ．
/// 項目はよく切り替えるものだけにし，ほかの設定は設定の画面にまとめる
@MainActor
final class InputMenuBuilder {
    struct Actions {
        var toggleLiveConversion: Selector
        var handwriting: Selector
        var openSettings: Selector
    }

    private let settings: any SettingsStoring
    private let openSettings: () -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(settings: any SettingsStoring, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
    }

    /// 入力メニュー．プロセスで一度だけ作って使い回し，チェックの印だけ合わせる．項目に受け手(target)は付けない．
    ///
    /// InputMethodKit のサーバーは受け取ったメニューを覚え(_setCachedMenu:)，選ばれた項目をそのメニューと突き合わせて
    /// 入力コントローラに動作を送る(_copySynchronizedActions:withMenuItems:)．作り直すと突き合わせがずれて届かない．
    /// コントローラは入力欄ごとに作られるので，コントローラごとにメニューを作ると，入力欄が次々に変わるアプリ(cmux など)では
    /// 別のメニューと突き合わせることになり届かなかった．そのため 1 つを全部のコントローラで共有する(CompositionRoot.inputMenu)．
    /// 受け手を付けると 1 回も届かなかった．同じ操作はキーでも受ける(キー設定の表．Keymap)
    private var cachedMenu: NSMenu?
    private var liveConversionItem: NSMenuItem?
    private var handwritingItem: NSMenuItem?

    func menu(actions: Actions) -> NSMenu {
        if let cachedMenu {
            liveConversionItem?.state = settings.current.liveConversion ? .on : .off
            // 手書き入力は設定で使うときだけ出す
            handwritingItem?.isHidden = !settings.current.handwriting
            return cachedMenu
        }
        let menu = NSMenu()
        let live = NSMenuItem(title: UIStrings.Menu.liveConversion, action: actions.toggleLiveConversion, keyEquivalent: "")
        live.state = settings.current.liveConversion ? .on : .off
        menu.addItem(live)
        let handwriting = NSMenuItem(title: UIStrings.Menu.handwriting, action: actions.handwriting, keyEquivalent: "")
        handwriting.isHidden = !settings.current.handwriting
        menu.addItem(handwriting)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: UIStrings.Menu.openSettings, action: actions.openSettings, keyEquivalent: ""))
        cachedMenu = menu
        liveConversionItem = live
        handwritingItem = handwriting
        return menu
    }

    func handleToggleLiveConversion() {
        logger.notice("入力メニュー: ライブ変換を切り替えます")
        do {
            try settings.update { $0.liveConversion.toggle() }
        } catch {
            logger.error("設定を保存できませんでした: \(String(describing: error), privacy: .public)")
        }
    }

    func handleOpenSettings() {
        logger.notice("入力メニュー: 設定の画面を開きます")
        openSettings()
    }
}
