import AppKit
import os
import S90Application
import S90Domain

/// 入力メニュー(メニューバーの「あ」)を作り，項目を選んだときの処理を行う．
///
/// 入力メニューの項目の動作は，InputMethodKit が入力コントローラ(S90InputController)にだけ送る．
/// target をほかのオブジェクトにすると呼ばれないので，動作の selector はコントローラから受け取り，
/// コントローラはここの handle* を呼ぶ．
/// 項目は「ライブ変換」と「設定を開く…」だけにし，ほかの設定(入力方式を含む)は設定の画面とキー設定の表にまとめる
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

    /// 入力メニュー．一度だけ作って使い回し，チェックの印だけ合わせる．項目に受け手(target)は付けない．
    ///
    /// InputMethodKit のサーバーは受け取ったメニューを覚え(_setCachedMenu:)，選ばれた項目をそのメニューと突き合わせて
    /// 入力コントローラに動作を送る(_copySynchronizedActions:withMenuItems:)．打鍵のたびに作り直すと突き合わせがずれ，
    /// 実機では最初の 1 回しか届かなかった．受け手を付けると 1 回も届かなかった．そのため使い回し，受け手を付けない．
    /// なお cmux など一部のアプリは，選んだ動作を IME に取り次がない(テキストエディットでは届く)．そのため同じ操作をキーでも受ける(キー設定の表．Keymap)
    private var cachedMenu: NSMenu?
    private var liveConversionItem: NSMenuItem?

    func menu(actions: Actions) -> NSMenu {
        if let cachedMenu {
            liveConversionItem?.state = settings.current.liveConversion ? .on : .off
            return cachedMenu
        }
        let menu = NSMenu()
        let live = NSMenuItem(title: UIStrings.Menu.liveConversion, action: actions.toggleLiveConversion, keyEquivalent: "")
        live.state = settings.current.liveConversion ? .on : .off
        menu.addItem(live)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: UIStrings.Menu.openSettings, action: actions.openSettings, keyEquivalent: ""))
        cachedMenu = menu
        liveConversionItem = live
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
