import AppKit
import os
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
    private var settleTask: Task<Void, Never>?

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        let (root, session, presenter, menuBuilder) = MainActor.assumeIsolated {
            guard let root = CompositionRoot.installed else {
                preconditionFailure("main.swift で CompositionRoot を組み立ててからサーバーを作る")
            }
            let menu = InputMenuBuilder(settings: root.settings, openSettings: { root.settingsWindow.show() })
            let session = root.makeSession()
            return (root, session, root.makePresenter(session: session), menu)
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
        if result.actions.contains(.awaitCorrections) {
            convertAfterCorrections(client: client, context: context)
        } else {
            scheduleSettle(client: client, context: context)
        }
        return result.handled
    }

    /// Space を押したときに打ち間違いの訂正がまだ求め終わっていなければ，求めてから変換を続ける．
    /// 長くかかるときは待つのをやめて変換する(DefaultSettings.correctionWaitBeforeConversion)．次のキーが来たら session が変換をやめる
    @MainActor
    private func convertAfterCorrections(client: any IMKTextInput, context: InputContext) {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if let request = self.session.conversionCorrectionRequest, let service = self.root.typoService {
                let corrections = await withTaskGroup(of: [String: [ReadingCorrection]]?.self) { group in
                    group.addTask { await service.corrections(forKeys: request.keys, leftContext: request.leftContext) }
                    group.addTask {
                        try? await Task.sleep(for: .seconds(DefaultSettings.correctionWaitBeforeConversion))
                        return nil
                    }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
                if let corrections { self.session.provideCorrections(corrections) }
            }
            guard !Task.isCancelled else { return }
            self.presenter.apply(self.session.resumeConversion(context: context), to: client)
        }
    }

    /// 打鍵が止まったら変換した文を見せ(settle)，さらに止まったら打ち間違いを見直す(review)．
    /// 次のキーが来たら待ちを取り消すので，打ち続けているあいだは見直さない．
    /// 待つのはメインスレッドの Task にし，入力コントローラと入力先を別のスレッドへ渡さない
    @MainActor
    private func scheduleSettle(client: any IMKTextInput, context: InputContext) {
        settleTask?.cancel()
        settleTask = nil
        let settles = session.awaitsSettle
        // 待ち時間は設定で変えられる(ライブ変換で漢字にするまで・打ち間違いを見直すまで)
        let settleDelay = root.settings.current.liveConversionDelay
        let correctionDelay = root.settings.current.correctionDelay
        guard settles || session.awaitsReview else { return }
        settleTask = Task { @MainActor [weak self] in
            if settles {
                try? await Task.sleep(for: .seconds(settleDelay))
                guard !Task.isCancelled, let self else { return }
                self.presenter.apply(self.session.settle(context: context), to: client)
            }
            let remaining = max(correctionDelay - (settles ? settleDelay : 0), 0)
            guard let self, self.session.awaitsReview else { return }
            try? await Task.sleep(for: .seconds(remaining))
            guard !Task.isCancelled else { return }
            // 訂正はメインスレッドの外で求め，求め終わったときに打ったキーが変わっていなければ見直す
            if let request = self.session.correctionRequest, let service = self.root.typoService {
                let corrections = await service.corrections(forKeys: request.keys, leftContext: request.leftContext)
                guard !Task.isCancelled else { return }
                self.session.provideCorrections(corrections)
            }
            self.presenter.apply(self.session.review(context: context), to: client)
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
        settleTask?.cancel()
        settleTask = nil
        if let client = sender as? any IMKTextInput {
            presenter.apply(session.deactivate(), to: client)
        }
        presenter.hideWindows()
        // 手書きの窓は開いたときの入力先に文字を入れるので，入力先から外れたら閉じる
        presenter.closeHandwriting()
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
        menuBuilder.menu(actions: .init(toggleLiveConversion: #selector(toggleLiveConversion(_:)), handwriting: #selector(openHandwriting(_:)),
                                        openSettings: #selector(showPreferences(_:))))
    }

    /// 入力メニューの「手書き入力」．キーの「手書き入力」と同じく，組み立て中の文字を確定してから窓を開く
    @MainActor @objc func openHandwriting(_ sender: Any) {
        guard let client = client() else { return }
        presenter.apply(session.openHandwriting(), to: client)
    }

    @MainActor @objc func toggleLiveConversion(_ sender: Any) {
        menuBuilder.handleToggleLiveConversion()
    }

    /// 設定の画面を開く．InputMethodKit が入力メソッドの設定を開くときに呼ぶメソッドなので，
    /// 入力メニューの「設定を開く…」もこれに送る
    @MainActor
    override func showPreferences(_ sender: Any!) {
        menuBuilder.handleOpenSettings()
    }
}
