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

    override init!(server: IMKServer!, delegate: Any!, client inputClient: Any!) {
        let (root, session, presenter, menuBuilder) = MainActor.assumeIsolated {
            guard let root = CompositionRoot.installed else {
                preconditionFailure("main.swift で CompositionRoot を組み立ててからサーバーを作る")
            }
            return (root, root.makeSession(), root.makePresenter(), InputMenuBuilder(settings: root.settings))
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
        return result.handled
    }

    @MainActor
    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        // Chromium 系のアプリでは，ここで入力位置を問い合わせると止まることがある(azooKey-Desktop の調査)．
        // そのため候補ウィンドウを閉じるだけにする
        presenter.hideWindows()
    }

    @MainActor
    override func deactivateServer(_ sender: Any!) {
        if let client = sender as? any IMKTextInput {
            presenter.apply(session.deactivate(), to: client)
        }
        presenter.hideWindows()
        root.engine.flushLearning()
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
            presenter.apply(session.setMode(mode), to: client)
        }
        super.setValue(value, forTag: tag, client: sender)
    }

    @MainActor
    override func menu() -> NSMenu! {
        menuBuilder.makeMenu()
    }
}
