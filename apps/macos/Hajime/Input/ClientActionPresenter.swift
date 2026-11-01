import AppKit
import InputMethodKit
import os
import HajimeApplication
import HajimeDomain

/// ClientAction を InputMethodKit の操作に置き換える．判断はしない(docs/dev/ARCHITECTURE.md)．
@MainActor
final class ClientActionPresenter {
    /// 手書きの窓で選んだ文字を，組み立て中の文字と合わせて入れるのに使う
    private let session: InputSession
    private let candidatePanel: CandidatePanelController
    private let modeIndicator: ModeIndicatorController
    private let note: NoteController
    private let openSettings: () -> Void
    private let handwriting: HandwritingController
    private let settings: any SettingsStoring
    /// コマンドの候補を選んで確定したときに動かす(R-22)
    private let runCommand: (LauncherCommand) -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(session: InputSession, candidatePanel: CandidatePanelController, modeIndicator: ModeIndicatorController, note: NoteController, settings: any SettingsStoring,
         openSettings: @escaping () -> Void, handwriting: HandwritingController, runCommand: @escaping (LauncherCommand) -> Void) {
        self.session = session
        self.runCommand = runCommand
        self.openSettings = openSettings
        self.handwriting = handwriting
        self.candidatePanel = candidatePanel
        self.modeIndicator = modeIndicator
        self.note = note
        self.settings = settings
    }

    /// 最後にキーを受けたときの入力先の文脈．候補をマウスで押したときも同じ文脈で処理する
    var context = InputContext()
    /// 次に組み立て中の文字を出すか確定するときに置き換える入力先の範囲(再変換で選んでいた文字)．1 回使ったら消す
    var replacement: NSRange?

    func apply(_ actions: [ClientAction], to client: any IMKTextInput) {
        // 候補をマウスで押したら，キーで選んだのと同じに処理して入力先に反映する
        candidatePanel.onChoose = { [weak self, weak client = client as AnyObject] target in
            guard let self, let client = client as? any IMKTextInput else { return }
            self.apply(self.session.choose(target, context: self.context), to: client)
        }
        for action in actions {
            switch action {
            case .commit(let text):
                client.insertText(text, replacementRange: takeReplacement())
            case .setMarkedText(let marked):
                let attributed = Self.attributedString(for: marked)
                markedLength = (marked.text as NSString).length
                client.setMarkedText(attributed, selectionRange: NSRange(location: (marked.textBeforeCaret as NSString).length, length: 0), replacementRange: takeReplacement())
            case .showCandidates(let panel):
                note.hide()
                candidatePanel.show(panel, caret: panelAnchor(of: client, at: panel.anchor), theme: ThemeChoice(settings.current), fontSize: settings.current.candidateFontSize,
                                    keys: settings.current.keymap)
            case .showLattice(let panel):
                note.hide()
                candidatePanel.showLattice(panel, caret: panelAnchor(of: client, at: nil), theme: ThemeChoice(settings.current), fontSize: settings.current.candidateFontSize,
                                           keys: settings.current.keymap, showsHints: settings.current.showsKeyHints)
            case .hideCandidates:
                candidatePanel.hide()
                note.hide()
            case .requestReconversion:
                // 入力コントローラが入力先の選んでいる文字を読んで再変換する(HajimeInputController.reconvert)
                break
            case .awaitCorrections:
                // 入力コントローラが裏で訂正を求め，届いたら変換を直す(HajimeInputController.correctAfterConversion)
                break
            case .openSettings:
                openSettings()
            case .runCommand(let command):
                // 確定したときの設定にまだあり，使う設定のときだけ動かす(Windows の EngineService と同じ)
                guard settings.current.launcherCommands, settings.current.commands.contains(command) else { break }
                runCommand(command)
            case .showHandwriting:
                // 窓はフォーカスを奪わないので，選んだときも入力先は開いたときのまま(入力先から外れたら窓を閉じる)
                handwriting.show(caret: caretRect(of: client), owner: self) { [weak self] text in
                    guard let self else { return }
                    self.apply(self.session.insert(text), to: client)
                }
            case .toggleLiveConversion:
                do {
                    try settings.update { $0.liveConversion.toggle() }
                } catch {
                    logger.error("ライブ変換の設定を保存できませんでした: \(String(describing: error), privacy: .public)")
                }
            case .showNote(let shown):
                note.show(shown, caret: caretRect(of: client), theme: ThemeChoice(settings.current))
            case .showModeIndicator(let mode):
                modeIndicator.show(mode, caret: caretRect(of: client), theme: ThemeChoice(settings.current), duration: settings.current.modeIndicatorDuration)
            case .selectMode(let mode):
                client.selectMode(mode == .japanese ? AppIdentity.japaneseModeID : AppIdentity.directModeID)
            case .selectInputStyle(let style):
                do {
                    try settings.update { $0.inputStyle = style }
                    // 切り替えたことを入力位置の近くに出す
                    if settings.current.showsModeIndicator {
                        modeIndicator.show(style, caret: caretRect(of: client), theme: ThemeChoice(settings.current), duration: settings.current.modeIndicatorDuration)
                    }
                } catch {
                    logger.error("入力方式を保存できませんでした: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    func hideWindows() {
        candidatePanel.hide()
        note.hide()
    }

    /// この入力先で開いた手書きの窓を閉じる
    func closeHandwriting() {
        handwriting.close(openedBy: self)
    }

    private static let noReplacement = NSRange(location: NSNotFound, length: 0)

    private func takeReplacement() -> NSRange {
        defer { replacement = nil }
        return replacement ?? Self.noReplacement
    }

    private func caretRect(of client: any IMKTextInput) -> NSRect {
        lineRect(of: client, at: 0)
    }

    /// 組み立て中の文字の index 番目(UTF-16)の字がある行の長方形．アプリが教えなければ .zero
    private func lineRect(of client: any IMKTextInput, at index: Int) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        return rect
    }

    /// 最後に出した組み立て中の文字の長さ(UTF-16)
    private var markedLength = 0

    /// 候補の窓を置く基準．左端は anchor の字(無ければ組み立て中の文字の頭)，上の辺は頭の行の上，下の辺は最後の行の下．
    /// 組み立て中の文字が何行かに折り返しても，窓を文字に重ねない(下に置くときは最後の行の下，上に置くときは頭の行の上)
    private func panelAnchor(of client: any IMKTextInput, at anchor: Int?) -> NSRect {
        let start = lineRect(of: client, at: 0)
        guard start != .zero, markedLength > 1 else { return start }
        let end = lineRect(of: client, at: markedLength - 1)
        let left = anchor.map { lineRect(of: client, at: min(max($0, 0), markedLength - 1)) } ?? start
        let lines = [start, end, left].filter { $0 != .zero }
        let bottom = lines.map(\.minY).min() ?? start.minY
        let top = max(start.maxY, bottom)
        return NSRect(x: left == .zero ? start.minX : left.minX, y: bottom, width: max(left.width, 1), height: top - bottom)
    }

    private static func attributedString(for marked: MarkedText) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, segment) in marked.segments.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [
                // 文節の区切りをアプリに伝える．区切りごとに下線が分かれて見える
                .markedClauseSegment: index,
            ]
            switch segment.style {
            case .reading, .converted:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .focused:
                attributes[.underlineStyle] = NSUnderlineStyle.thick.rawValue
            case .correction:
                attributes[.underlineStyle] = NSUnderlineStyle([.single, .patternDot]).rawValue
            }
            result.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        return result
    }
}
