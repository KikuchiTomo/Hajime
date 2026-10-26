import AppKit
import os
import S90Application
import S90Domain

/// 入力メニュー(メニューバーの「あ」)を作り，項目を選んだときの処理を行う．
///
/// 入力メニューの項目の動作は，InputMethodKit が入力コントローラ(S90InputController)にだけ送る．
/// target をほかのオブジェクトにすると呼ばれないので，動作の selector はコントローラから受け取り，
/// コントローラはここの handle* を呼ぶ．
/// 項目はよく切り替えるものだけにし，ほかの設定は設定の画面にまとめる
@MainActor
final class InputMenuBuilder {
    struct Actions {
        var toggleLiveConversion: Selector
        var openSettings: Selector
    }

    private let settings: any SettingsStoring
    private let openSettings: () -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(settings: any SettingsStoring, openSettings: @escaping () -> Void) {
        self.settings = settings
        self.openSettings = openSettings
    }

    /// 入力メニュー．InputMethodKit は打鍵のたびに menu を求めるので，一度だけ作って使い回し，チェックの印だけ合わせる
    /// (作り直すと，選んだ項目の動作が届かないことがある．azooKey-Desktop・Squirrel も使い回している)
    private var cachedMenu: NSMenu?
    private var liveConversionItem: NSMenuItem?

    func menu(actions: Actions) -> NSMenu {
        if cachedMenu == nil {
            let menu = NSMenu()
            let live = NSMenuItem(title: UIStrings.Menu.liveConversion, action: actions.toggleLiveConversion, keyEquivalent: "")
            menu.addItem(live)
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(title: UIStrings.Menu.openSettings, action: actions.openSettings, keyEquivalent: ""))
            cachedMenu = menu
            liveConversionItem = live
        }
        liveConversionItem?.state = settings.current.liveConversion ? .on : .off
        return cachedMenu!
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
