import AppKit
import S90Domain

/// 設定と OS の外観から決めた，描画に使う色と書体．寸法と platinum・desk の色は DesignTokens(design/tokens から生成)から取り，
/// glass の色は OS の意味の色(labelColor・controlAccentColor など)を使う．ライト・ダークとアクセントカラーに OS が合わせるため．
struct ResolvedTheme {
    enum Kind {
        /// すりガラスの地に角丸と曲線の枝．既定
        case glass
        case platinum
        case desk
    }

    let kind: Kind
    let surface: NSColor
    let bevelLight: NSColor
    let bevelShadow: NSColor
    let frame: NSColor
    let text: NSColor
    let textMuted: NSColor
    let selection: NSColor
    let selectionText: NSColor
    let correction: NSColor
    /// 枝と区切りの線
    let line: NSColor
    /// 注目している文節の地(glass だけ．選択より弱い色)
    let focusTint: NSColor
    /// 番号の丸とキーキャップの地(glass だけ)
    let badge: NSColor

    @MainActor
    static func resolve(_ preference: ThemePreference, appearance: NSAppearance? = nil) -> ResolvedTheme {
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        switch preference {
        case .automatic, .native: return glass(increaseContrast: increaseContrast)
        case .platinum: return palette(DesignTokens.Palette.platinum, kind: .platinum, increaseContrast: increaseContrast)
        case .desk: return palette(DesignTokens.Palette.desk, kind: .desk, increaseContrast: increaseContrast)
        }
    }

    /// 色は OS の意味の色なので，描くときの外観(ライト・ダーク)で決まる
    private static func glass(increaseContrast: Bool) -> ResolvedTheme {
        // 「コントラストを上げる」が有効なときは，線と弱い文字を 1 段濃くする
        ResolvedTheme(
            kind: .glass,
            surface: .windowBackgroundColor,
            bevelLight: .clear,
            bevelShadow: .clear,
            frame: increaseContrast ? .secondaryLabelColor : .separatorColor,
            text: .labelColor,
            textMuted: increaseContrast ? .labelColor : .secondaryLabelColor,
            selection: .controlAccentColor,
            selectionText: .alternateSelectedControlTextColor,
            correction: .systemPink,
            line: increaseContrast ? .secondaryLabelColor : .tertiaryLabelColor,
            focusTint: NSColor.controlAccentColor.withAlphaComponent(increaseContrast ? 0.3 : 0.16),
            badge: increaseContrast ? .tertiaryLabelColor : .quaternaryLabelColor
        )
    }

    private static func palette(_ palette: ThemePalette, kind: Kind, increaseContrast: Bool) -> ResolvedTheme {
        let frame = palette.frame.color
        // 「コントラストを上げる」が有効なときは，立体の縁を外枠と同じ色にする(docs/dev/DESIGN-SYSTEM.md)
        let bevelLight = increaseContrast ? frame : palette.bevelLight.color
        let bevelShadow = increaseContrast ? frame : palette.bevelShadow.color
        return ResolvedTheme(
            kind: kind,
            surface: palette.surface.color,
            bevelLight: bevelLight,
            bevelShadow: bevelShadow,
            frame: frame,
            text: palette.text.color,
            textMuted: palette.textMuted.color,
            selection: palette.selection.color,
            selectionText: palette.selectionText.color,
            correction: palette.correction.color,
            // 区画を分ける線は，platinum は影の縁，desk は暗い面なので光の縁の色
            line: kind == .desk ? bevelLight : bevelShadow,
            focusTint: palette.selection.color,
            badge: .clear
        )
    }

    var isGlass: Bool { kind == .glass }
    var hasBevel: Bool { kind != .glass }
    var hasDropShadow: Bool { kind == .desk }

    // MARK: - 書体

    /// 番号・案内・札の書体．glass はシステムの書体，platinum と desk はブランドの書体(BIZ UDゴシック)
    func labelFont(size: CGFloat) -> NSFont {
        if isGlass { return .systemFont(ofSize: size, weight: .medium) }
        return NSFont(name: FontRegistry.labelFontName, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    /// 番号の丸とキーキャップの中の文字．数字の幅をそろえる
    func keyFont(size: CGFloat) -> NSFont {
        isGlass ? .monospacedDigitSystemFont(ofSize: size, weight: .semibold) : labelFont(size: size)
    }

    /// 候補の文字．glass はシステムの書体(日本語はヒラギノ角ゴシックが自動で代わりに使われる)
    func candidateFont(size: CGFloat) -> NSFont {
        if isGlass { return .systemFont(ofSize: size) }
        return NSFont(name: "HiraginoSans-W3", size: size) ?? .systemFont(ofSize: size)
    }

    /// 分岐図の幹の文字．候補より少し太くし，文として読めるようにする
    func trunkFont(size: CGFloat) -> NSFont {
        if isGlass { return .systemFont(ofSize: size, weight: .medium) }
        return candidateFont(size: size)
    }
}

extension RGB {
    var color: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
