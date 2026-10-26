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

    /// 入力メニュー．呼ばれるたびに作り直し，項目に受け手(target)を付けない．
    /// InputMethodKit はメニューを別のプロセス(TextInputMenuAgent)に写して出し，選ばれた動作の名前を入力コントローラに送り返す．
    /// 受け手を付けたり項目を使い回したりすると送り返されないことがあった(macSKK・vChewing も毎回作り，受け手を付けない)
    func menu(actions: Actions) -> NSMenu {
        let menu = NSMenu()
        let live = NSMenuItem(title: UIStrings.Menu.liveConversion, action: actions.toggleLiveConversion, keyEquivalent: "")
        live.state = settings.current.liveConversion ? .on : .off
        menu.addItem(live)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: UIStrings.Menu.openSettings, action: actions.openSettings, keyEquivalent: ""))
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
