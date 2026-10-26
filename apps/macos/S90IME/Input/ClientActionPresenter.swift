import AppKit
import InputMethodKit
import os
import S90Application
import S90Domain

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
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(session: InputSession, candidatePanel: CandidatePanelController, modeIndicator: ModeIndicatorController, note: NoteController, settings: any SettingsStoring,
         openSettings: @escaping () -> Void, handwriting: HandwritingController) {
        self.session = session
        self.openSettings = openSettings
        self.handwriting = handwriting
        self.candidatePanel = candidatePanel
        self.modeIndicator = modeIndicator
        self.note = note
        self.settings = settings
    }

    func apply(_ actions: [ClientAction], to client: any IMKTextInput) {
        for action in actions {
            switch action {
            case .commit(let text):
                client.insertText(text, replacementRange: Self.noReplacement)
            case .setMarkedText(let marked):
                let attributed = Self.attributedString(for: marked)
                client.setMarkedText(attributed, selectionRange: NSRange(location: attributed.length, length: 0), replacementRange: Self.noReplacement)
            case .showCandidates(let panel):
                note.hide()
                candidatePanel.show(panel, caret: caretRect(of: client), theme: ThemeChoice(settings.current), fontSize: settings.current.candidateFontSize)
            case .showLattice(let panel):
                note.hide()
                candidatePanel.showLattice(panel, caret: caretRect(of: client), theme: ThemeChoice(settings.current), fontSize: settings.current.candidateFontSize,
                                           keys: settings.current.keymap, showsHints: settings.current.showsKeyHints)
            case .hideCandidates:
                candidatePanel.hide()
                note.hide()
            case .openSettings:
                openSettings()
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
            case .showNote(let text):
                note.show(text, caret: caretRect(of: client), theme: ThemeChoice(settings.current))
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

    private func caretRect(of client: any IMKTextInput) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        return rect
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
