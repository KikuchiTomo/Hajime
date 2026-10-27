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
            let session = root.makeSession()
            return (root, session, root.makePresenter(session: session), root.inputMenu)
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
        presenter.context = context
        presenter.apply(result.actions, to: client)
        // 再変換できなかった(選んでいる文字が無い・読めない)ときは，キーをアプリに渡す(Ctrl+Shift+R などをアプリで使えるように)
        if result.actions.contains(.requestReconversion), !reconvert(client: client, context: context) {
            return false
        }
        if result.actions.contains(.awaitCorrections) {
            correctAfterConversion(client: client, context: context)
        } else {
            scheduleSettle(client: client, context: context)
        }
        return result.handled
    }

    /// Space で変換したときに打ち間違いの訂正がまだ求め終わっていなければ，変換は出したまま訂正を裏で求め，
    /// 届いたら変換を直す(直した候補にするか「もしかして」と示す)．次のキーが来たら待ちをやめる(settleTask を取り消す)．
    /// 訂正が DefaultSettings.lateCorrectionTimeout を過ぎても終わらなければあきらめる
    @MainActor
    private func correctAfterConversion(client: any IMKTextInput, context: InputContext) {
        settleTask?.cancel()
        settleTask = nil
        guard let request = session.lateCorrectionRequest, let service = root.typoService else { return }
        settleTask = Task { @MainActor [weak self] in
            let corrections = await Deadline.run(seconds: DefaultSettings.lateCorrectionTimeout) {
                await service.corrections(forKeys: request.keys, leftContext: request.leftContext)
            }
            guard !Task.isCancelled, let self, let corrections else { return }
            self.presenter.apply(self.session.applyLateCorrections(corrections, context: context), to: client)
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
            let start = ContinuousClock.now
            if settles {
                try? await Task.sleep(for: .seconds(settleDelay))
                guard !Task.isCancelled, let self else { return }
                self.presenter.apply(self.session.settle(context: context), to: client)
                // 見直しを待つあいだに，Space で出す分岐図の候補を前もって求める
                await self.warmLattice()
            }
            guard let self, self.session.awaitsReview else { return }
            // 見直すのは，打鍵が止まってから correctionDelay たったとき(前もって求めた時間を含める)
            try? await Task.sleep(until: start + .seconds(correctionDelay), clock: .continuous)
            guard !Task.isCancelled else { return }
            // 訂正はメインスレッドの外で求め，求め終わったときに打ったキーが変わっていなければ見直す
            if let request = self.session.correctionRequest, let service = self.root.typoService {
                let corrections = await Deadline.run(seconds: DefaultSettings.reviewCorrectionTimeout) {
                    await service.corrections(forKeys: request.keys, leftContext: request.leftContext)
                }
                guard !Task.isCancelled else { return }
                guard let corrections else {
                    // 求め終わらないときはやめ，この入力は見直したことにする
                    self.session.skipReview()
                    return
                }
                self.session.provideCorrections(corrections)
            }
            self.presenter.apply(self.session.review(context: context), to: client)
            // 見直しで読みを直したときは，直した読みの候補も前もって求める(変わらない文節はためたものを使う)
            await self.warmLattice()
        }
    }

    /// 分岐図の候補を 1 文節ずつ前もって求める．文節ごとにほかの処理(次のキー)に譲り，取り消されたらやめる
    @MainActor
    private func warmLattice() async {
        for step in session.latticeWarmingSteps {
            await Task.yield()
            guard !Task.isCancelled else { return }
            step()
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

    /// 再変換．入力先で選んでいる文字を読み，読みに戻して変換する．選んでいなければ何もしない．
    /// 最初に出す組み立て中の文字で選んでいた文字を置き換え，Esc なら元の文字を入れ直す
    @MainActor
    /// 再変換を始めたら true
    private func reconvert(client: any IMKTextInput, context: InputContext) -> Bool {
        let selection = client.selectedRange()
        guard selection.location != NSNotFound, selection.length > 0, selection.length <= DefaultSettings.maximumReconversionLength,
              let text = client.attributedSubstring(from: selection)?.string else { return false }
        let actions = session.reconvert(text, transcriber: root.transcriber, context: context)
        guard !actions.isEmpty else { return false }
        presenter.replacement = selection
        presenter.apply(actions, to: client)
        return true
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
