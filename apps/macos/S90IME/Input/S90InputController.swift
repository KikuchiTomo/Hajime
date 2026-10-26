import AppKit
import InputMethodKit
import S90Application
import S90Domain

/// InputMethodKit の入口．OS との受け渡しだけを行い，判断は InputSession に任せる．
///
/// InputMethodKit は入力先のアプリ(クライアント)ごとにこのクラスを作る．呼び出しはすべてメインスレッドから来る．
/// InputMethodKit には並行性の注釈が無いので，メソッドに @MainActor を付けてメインスレッドで動くことを示す
/// (このターゲットだけ Swift 5 の言語モードにしている理由．docs/dev/GUIDELINES.md)．
@objc(S90InputController)
final class S90InputController: IMKInputController {
    private let root: CompositionRoot
    private let session: InputSession
    private let presenter: ClientActionPresenter
    private let menuBuilder: InputMenuBuilder
    /// 打鍵が止まったことを知らせるタイマー(ライブ変換で，かなのまま見せていた語を変換して見せる)
    private var settleTimer: Timer?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        let (root, session, presenter, menuBuilder) = MainActor.assumeIsolated {
            guard let root = CompositionRoot.installed else {
                preconditionFailure("main.swift で CompositionRoot を組み立ててからサーバーを作る")
            }
            let menu = InputMenuBuilder(settings: root.settings, openSettings: { root.settingsWindow.show() })
            return (root, root.makeSession(), root.makePresenter(), menu)
        }
        self.root = root
        self.session = session
        self.presenter = presenter
        self.menuBuilder = menuBuilder
        super.init(server: server, delegate: delegate, client: inputClient)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue)
    }

    @MainActor
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event, let client = sender as? any IMKTextInput,
            let key = NSEventKeyTranslator.translate(event) else { return false }
        let context = root.contextProvider.context(for: client, includePrecedingText: !session.isComposing)
        let result = session.handle(key, context: context)
        presenter.apply(result.actions, to: client)
        scheduleSettle(client: client, context: context)
        return result.handled
    }

    /// 打鍵が止まったら変換した文を見せ(settle)，さらに止まったら打ち間違いを見直す(review)．
    /// 次のキーが来たらタイマーを止めるので，打ち続けているあいだは見直さない
    @MainActor
    private func scheduleSettle(client: any IMKTextInput, context: InputContext) {
        settleTimer?.invalidate()
        settleTimer = nil
        if session.awaitsSettle {
            settleTimer = Timer.scheduledTimer(withTimeInterval: DefaultSettings.liveConversionSettleDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.presenter.apply(self.session.settle(context: context), to: client)
                    self.scheduleReview(client: client, context: context, after: DefaultSettings.liveCorrectionDelay - DefaultSettings.liveConversionSettleDelay)
                }
            }
        } else {
            scheduleReview(client: client, context: context, after: DefaultSettings.liveCorrectionDelay)
        }
    }

    @MainActor
    private func scheduleReview(client: any IMKTextInput, context: InputContext, after delay: TimeInterval) {
        guard session.awaitsReview else { return }
        settleTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.presenter.apply(self.session.review(context: context), to: client)
            }
        }
    }

    @MainActor
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        if let client = sender as? any IMKTextInput {
            KeyboardLayoutOverride.apply(root.settings.current.keyboardLayout, to: client)
        }
        // Chromium 系のアプリでは，ここで入力位置を問い合わせると止まることがある(azooKey-Desktop の調査)．
        // そのため候補ウィンドウを閉じるだけにする
        presenter.hideWindows()
    }

    @MainActor
    override func deactivateServer(_ sender: Any!) {
        settleTimer?.invalidate()
        settleTimer = nil
        if let client = sender as? any IMKTextInput {
            presenter.apply(session.deactivate(), to: client)
        }
        presenter.hideWindows()
        root.engine.flushLearning()
        root.usage.flush()
        super.deactivateServer(sender)
    }

    @MainActor
    override func commitComposition(_ sender: Any!) {
        guard let client = sender as? any IMKTextInput else { return }
        presenter.apply(session.deactivate(), to: client)
    }

    @MainActor
    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        if let modeKey = value as? String, let client = sender as? any IMKTextInput {
            let mode: InputMode = modeKey == AppIdentity.directModeKey ? .direct : .japanese
            // モードを切り替えると OS が配列を戻すことがあるので，切り替えるたびに合わせ直す
            KeyboardLayoutOverride.apply(root.settings.current.keyboardLayout, to: client)
            presenter.apply(session.setMode(mode), to: client)
        }
        super.setValue(value, forTag: tag, client: sender)
    }

    @MainActor
    override func menu() -> NSMenu! {
        menuBuilder.makeMenu(actions: .init(toggleLiveConversion: #selector(toggleLiveConversion(_:)), openSettings: #selector(openSettings(_:))))
    }

    // 入力メニューの項目の動作．InputMethodKit はこのコントローラにだけ送る(InputMenuBuilder)

    @MainActor @objc private func toggleLiveConversion(_ sender: Any?) {
        menuBuilder.handleToggleLiveConversion()
    }

    @MainActor @objc private func openSettings(_ sender: Any?) {
        menuBuilder.handleOpenSettings()
    }
}
