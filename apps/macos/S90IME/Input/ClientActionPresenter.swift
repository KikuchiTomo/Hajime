import AppKit
import InputMethodKit
import os
import S90Application
import S90Domain

/// ClientAction を InputMethodKit の操作に置き換える．判断はしない(docs/dev/ARCHITECTURE.md)．
@MainActor
final class ClientActionPresenter {
    private let candidatePanel: CandidatePanelController
    private let modeIndicator: ModeIndicatorController
    private let settings: any SettingsStoring
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(candidatePanel: CandidatePanelController, modeIndicator: ModeIndicatorController, settings: any SettingsStoring) {
        self.candidatePanel = candidatePanel
        self.modeIndicator = modeIndicator
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
                candidatePanel.show(panel, caret: caretRect(of: client), theme: settings.current.theme, fontSize: settings.current.candidateFontSize)
            case .showLattice(let panel):
                candidatePanel.showLattice(panel, caret: caretRect(of: client), theme: settings.current.theme, fontSize: settings.current.candidateFontSize)
            case .hideCandidates:
                candidatePanel.hide()
            case .showModeIndicator(let mode):
                modeIndicator.show(mode, caret: caretRect(of: client), theme: settings.current.theme)
            case .selectMode(let mode):
                client.selectMode(mode == .japanese ? AppIdentity.japaneseModeID : AppIdentity.directModeID)
            case .selectInputStyle(let style):
                do {
                    try settings.update { $0.inputStyle = style }
                    // 切り替えたことを入力位置の近くに出す
                    if settings.current.showsModeIndicator {
                        modeIndicator.show(style, caret: caretRect(of: client), theme: settings.current.theme)
                    }
                } catch {
                    logger.error("入力方式を保存できませんでした: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    func hideWindows() {
        candidatePanel.hide()
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
