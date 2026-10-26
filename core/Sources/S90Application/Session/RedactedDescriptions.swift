import S90Domain

// 入力した文字・読み・候補を持つ型は，ログに出す表示(description・debugDescription)で中身を伏せ，長さと数だけを出す
// (docs/dev/SECURITY-MODEL.md)．String(describing:) や print で中身が漏れないようにするため

extension ClientAction: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String {
        switch self {
        case .commit(let text): "commit(length: \(text.count))"
        case .setMarkedText(let marked): "setMarkedText(\(marked))"
        case .showCandidates(let panel): "showCandidates(entries: \(panel.entries.count))"
        case .showLattice(let panel): "showLattice(columns: \(panel.columns.count))"
        case .hideCandidates: "hideCandidates"
        case .showModeIndicator(let mode): "showModeIndicator(\(mode))"
        case .selectMode(let mode): "selectMode(\(mode))"
        case .selectInputStyle(let style): "selectInputStyle(\(style))"
        case .showNote(let text): "showNote(length: \(text.count))"
        case .openSettings: "openSettings"
        case .toggleLiveConversion: "toggleLiveConversion"
        case .showHandwriting: "showHandwriting"
        }
    }

    public var debugDescription: String { description }
}

extension KeyResult: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "KeyResult(handled: \(handled), actions: \(actions))" }
    public var debugDescription: String { description }
}

extension MarkedText: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "MarkedText(segments: \(segments.count), length: \(text.count))" }
    public var debugDescription: String { description }
}

extension CandidateSelection: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "CandidateSelection(candidates: \(candidates.count))" }
    var debugDescription: String { description }
}

extension CandidatePanel: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "CandidatePanel(entries: \(entries.count), position: \(position)/\(total))" }
    public var debugDescription: String { description }
}

extension LatticePanel: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "LatticePanel(columns: \(columns.count))" }
    public var debugDescription: String { description }
}

extension MarkedText.Segment: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "Segment(length: \(text.count), style: \(style))" }
    public var debugDescription: String { description }
}

extension CandidatePanel.Entry: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "Entry(length: \(text.count))" }
    public var debugDescription: String { description }
}

extension LatticePanel.Column: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "Column(length: \(text.count), alternatives: \(alternatives.count))" }
    public var debugDescription: String { description }
}

extension EnglishWordCorrector.Correction: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String { "Correction(keysLength: \(keys.count), wordLength: \(word.count))" }
    var debugDescription: String { description }
}
