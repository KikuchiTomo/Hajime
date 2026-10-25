import AppKit
import InputMethodKit
import S90Application
import S90Domain

/// ClientAction を InputMethodKit の操作に置き換える．判断はしない(docs/dev/ARCHITECTURE.md)．
@MainActor
final class ClientActionPresenter {
    private let candidatePanel: CandidatePanelController
    private let modeIndicator: ModeIndicatorController
    private let settings: any SettingsReading

    init(candidatePanel: CandidatePanelController, modeIndicator: ModeIndicatorController, settings: any SettingsReading) {
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
            case .hideCandidates:
                candidatePanel.hide()
            case .showModeIndicator(let mode):
                modeIndicator.show(mode, caret: caretRect(of: client), theme: settings.current.theme)
            case .selectMode(let mode):
                client.selectMode(mode == .japanese ? AppIdentity.japaneseModeID : AppIdentity.directModeID)
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
