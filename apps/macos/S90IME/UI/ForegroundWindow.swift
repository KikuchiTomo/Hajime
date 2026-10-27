import AppKit

/// 入力メソッドの窓(設定の画面・初期設定)を前に出す．
///
/// 入力メソッドは前面に出られないアプリ(Info.plist の LSBackgroundOnly)なので，そのままでは窓がほかのアプリの窓の後ろに隠れ，
/// 入力欄にも打てない．開いているあいだだけ前面に出られる補助アプリ(.accessory)にし，閉じたら前面に出ないアプリ(.prohibited)に戻す．
/// macOS 14 からは前面のアプリが譲らない限りほかのアプリは前面に出られないので，窓を浮かせて(.floating)ほかのアプリの窓より上に見せる
@MainActor
enum ForegroundWindow {
    /// 窓を作ったときに一度だけ呼ぶ．浮かせ，今いる操作スペース(フルスクリーンのアプリの上を含む)に出し，閉じたら前面に出ないアプリに戻す
    static func configure(_ window: NSWindow) {
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { notification in
            MainActor.assumeIsolated {
                // ほかの s90 の窓がまだ開いていれば，前面に出られるままにする(閉じると残りの窓が後ろに隠れる)
                let closing = notification.object as? NSWindow
                let othersOpen = NSApp.windows.contains { $0 !== closing && $0.isVisible && $0.level == .floating && $0.styleMask.contains(.titled) }
                if !othersOpen { _ = NSApp.setActivationPolicy(.prohibited) }
            }
        }
    }

    /// 窓を前に出して，キーボードの入力を受けられるようにする
    static func present(_ window: NSWindow) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
