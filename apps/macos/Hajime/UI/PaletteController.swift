import AppKit
import CoreText
import HajimeApplication
import HajimeDomain

/// 絵文字と記号のパレットの窓を出し入れする(R-26)．窓はアプリ全体で 1 つだけ使い回す．
///
/// 窓は候補の窓と同じくキーボードの入力を受けず，入力先のアプリを前面のまま残す．キーは入力メソッドが受けて InputSession に渡す．
/// 窓は開いたときの入力位置の近くに置き，開いているあいだは動かさない(マス目の位置を覚えて選べるように)
@MainActor
final class PaletteController {
    private let window: NSPanel
    private let view = PaletteView()
    private let backdrop = GlassBackdrop()
    private var lastAnnounced: String?

    /// 窓をマウスで操作したときに知らせる先
    var onTarget: ((PaletteTarget) -> Void)? {
        didSet { view.onTarget = onTarget }
    }

    init() {
        window = FloatingPanel.make(contentView: view)
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
    }

    var isVisible: Bool { window.isVisible }

    func show(_ panel: PalettePanel, caret: NSRect, theme: ThemeChoice, cellSize: Double) {
        let resolved = ResolvedTheme.resolve(theme)
        view.theme = resolved
        view.cellSize = CGFloat(cellSize)
        view.panel = panel
        backdrop.cornerRadius = resolved.cornerRadius
        let wasVisible = window.isVisible
        _ = FloatingPanel.attach(view, to: window, backdrop: resolved.isRounded ? backdrop : nil)
        let size = view.fittingSize(for: panel)
        if wasVisible {
            // 出ているあいだは上の辺と左の辺を保つ(大きさは設定を変えたときだけ変わる)
            let current = window.frame
            if current.size != size {
                window.setFrame(NSRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height), display: true)
                window.invalidateShadow()
            }
        } else {
            let placed = FloatingPanel.place(size, caret: caret, keeping: nil, holding: nil).frame
            window.setFrame(NSRect(x: placed.x, y: placed.y, width: placed.width, height: placed.height), display: true)
            window.invalidateShadow()
            window.orderFrontRegardless()
        }
        announce(panel)
    }

    func hide() {
        lastAnnounced = nil
        view.panel = nil
        window.orderOut(nil)
    }

    /// VoiceOver が動いているときだけ，選んでいる文字の名前と探した結果の数を読み上げる．
    /// 説明の欄に Unicode の名前を出していれば，欄では省いた部分も含めて全体を読む
    private func announce(_ panel: PalettePanel) {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let selected = panel.selection.flatMap { position in
            panel.rows.first { $0.index == position.row }.flatMap { $0.cells.indices.contains(position.column) ? $0.cells[position.column].name : nil }
        }
        let unicodeName = panel.preview.map(\.unicodeName).flatMap { $0.isEmpty ? nil : $0 }
        let text = [selected, unicodeName, panel.message].compactMap { $0 }.joined(separator: "、")
        guard !text.isEmpty, text != lastAnnounced else { return }
        lastAnnounced = text
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }
}

/// OS の絵文字の書体がその絵文字を 1 つの字として描けるか(R-26)．新しいバージョンの絵文字は，OS が古いと
/// 部品に分かれて描かれるので，パレットに出さない．CoreText はどのスレッドからでも使える
enum EmojiRendering {
    static func canRender(_ text: String) -> Bool {
        let font = CTFontCreateWithName(PaletteIcons.emojiFontName as CFString, DesignTokens.Size.Palette.probeFontSize, nil)
        let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(string)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1, CTRunGetGlyphCount(runs[0]) == 1 else { return false }
        var glyph = CGGlyph()
        CTRunGetGlyphs(runs[0], CFRange(location: 0, length: 1), &glyph)
        guard glyph != 0 else { return false }
        // 絵文字の書体に無い字は，OS が別の書体で代わりに描く．代わりの書体で描いた字は描けないものとする
        let attributes = CTRunGetAttributes(runs[0]) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as String], CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { return false }
        // 型を CTFontGetTypeID で確かめたので，必ず CTFont になる
        let used = CTFontCopyPostScriptName(value as! CTFont) as String
        return used == PaletteIcons.emojiFontName
    }
}
