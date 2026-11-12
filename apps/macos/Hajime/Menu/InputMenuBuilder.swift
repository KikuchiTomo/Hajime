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
        var palette: Selector
        var openSettings: Selector
        var checkForUpdates: Selector
        var registerWord: Selector
        var openUserDictionary: Selector
    }

    private let settings: any SettingsStoring
    private let openSettings: () -> Void
    private let checkForUpdates: () -> Void
    /// 設定のユーザー辞書の画面を開き，語と読みを登録の欄に入れる(空なら入れない)
    private let openWordRegistration: (_ word: String, _ reading: String) -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(settings: any SettingsStoring, openSettings: @escaping () -> Void, checkForUpdates: @escaping () -> Void,
         openWordRegistration: @escaping (_ word: String, _ reading: String) -> Void) {
        self.settings = settings
        self.openSettings = openSettings
        self.checkForUpdates = checkForUpdates
        self.openWordRegistration = openWordRegistration
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
    private var paletteItem: NSMenuItem?

    func menu(actions: Actions) -> NSMenu {
        if let cachedMenu {
            liveConversionItem?.state = settings.current.liveConversion ? .on : .off
            syncHandwritingItem(in: cachedMenu)
            syncPaletteItem(in: cachedMenu)
            return cachedMenu
        }
        let menu = NSMenu()
        let live = NSMenuItem(title: UIStrings.Menu.liveConversion, action: actions.toggleLiveConversion, keyEquivalent: "")
        live.state = settings.current.liveConversion ? .on : .off
        menu.addItem(live)
        menu.addItem(.separator())
        for item in toolItems(actions: actions) { menu.addItem(item) }
        cachedMenu = menu
        liveConversionItem = live
        handwritingItem = NSMenuItem(title: UIStrings.Menu.handwriting, action: actions.handwriting, keyEquivalent: "")
        paletteItem = NSMenuItem(title: UIStrings.Menu.palette, action: actions.palette, keyEquivalent: "")
        syncHandwritingItem(in: menu)
        syncPaletteItem(in: menu)
        return menu
    }

    /// 手書き入力は設定で使うときだけ，ライブ変換の次に置く．隠した項目(isHidden)を入れておくと，
    /// InputMethodKit がメニューを入力メニューに渡せず，項目がすべて消えるので，使わないときは外す
    private func syncHandwritingItem(in menu: NSMenu) {
        guard let handwritingItem else { return }
        let present = menu.index(of: handwritingItem) >= 0
        if settings.current.handwriting, !present {
            menu.insertItem(handwritingItem, at: 1)
        } else if !settings.current.handwriting, present {
            menu.removeItem(handwritingItem)
        }
    }

    /// 絵文字と記号のパレット(R-26)は設定で使うときだけ，ライブ変換と手書き入力の次に置く(外し方は手書き入力と同じ)
    private func syncPaletteItem(in menu: NSMenu) {
        guard let paletteItem else { return }
        let present = menu.index(of: paletteItem) >= 0
        if settings.current.palette, !present {
            let afterHandwriting = handwritingItem.map { menu.index(of: $0) >= 0 } ?? false
            menu.insertItem(paletteItem, at: afterHandwriting ? 2 : 1)
        } else if !settings.current.palette, present {
            menu.removeItem(paletteItem)
        }
    }

    /// 区切りの線より下の項目(単語の登録・ユーザー辞書・設定・更新)．Windows の入力メニューと同じ順に並べる
    private func toolItems(actions: Actions) -> [NSMenuItem] {
        [
            NSMenuItem(title: UIStrings.Menu.registerWord, action: actions.registerWord, keyEquivalent: ""),
            NSMenuItem(title: UIStrings.Menu.userDictionary, action: actions.openUserDictionary, keyEquivalent: ""),
            NSMenuItem(title: UIStrings.Menu.openSettings, action: actions.openSettings, keyEquivalent: ""),
            NSMenuItem(title: UIStrings.Menu.checkForUpdates, action: actions.checkForUpdates, keyEquivalent: ""),
        ]
    }

    /// キー(入力メニューを開く)で入力位置に出す入力メニュー．入力メニューと同じ項目を，開くたびに今の設定で作る．
    /// InputMethodKit を通さず自分で出すので，項目の受け手(target)をコントローラにする
    func popUp(actions: Actions, target: AnyObject, at point: NSPoint) {
        let menu = NSMenu()
        let live = NSMenuItem(title: UIStrings.Menu.liveConversion, action: actions.toggleLiveConversion, keyEquivalent: "")
        live.state = settings.current.liveConversion ? .on : .off
        menu.addItem(live)
        if settings.current.handwriting { menu.addItem(NSMenuItem(title: UIStrings.Menu.handwriting, action: actions.handwriting, keyEquivalent: "")) }
        if settings.current.palette { menu.addItem(NSMenuItem(title: UIStrings.Menu.palette, action: actions.palette, keyEquivalent: "")) }
        menu.addItem(.separator())
        for item in toolItems(actions: actions) { menu.addItem(item) }
        for item in menu.items { item.target = target }
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    /// 単語の登録．word は入力先で選んでいた文字(無ければ空)，reading はその読み(分からなければ空)
    func handleRegisterWord(word: String, reading: String) {
        logger.notice("入力メニュー: 単語の登録を開きます")
        openWordRegistration(word, reading)
    }

    func handleOpenUserDictionary() {
        logger.notice("入力メニュー: ユーザー辞書を開きます")
        openWordRegistration("", "")
    }

    func handleToggleLiveConversion() {
        logger.notice("入力メニュー: ライブ変換を切り替えます")
        do {
            try settings.update { $0.liveConversion.toggle() }
        } catch {
            logger.error("設定を保存できませんでした: \(String(describing: error), privacy: .public)")
        }
    }

    /// 更新用のアプリを起動する(R-19)
    func handleCheckForUpdates() {
        logger.notice("入力メニュー: 更新を確認します")
        checkForUpdates()
    }

    func handleOpenSettings() {
        logger.notice("入力メニュー: 設定の画面を開きます")
        openSettings()
    }
}
