import AppKit
import S90Domain

/// 設定と OS の外観から決めた，描画に使う色と書体．値は DesignTokens(design/tokens から生成)だけから取る．
struct ResolvedTheme {
    enum Kind {
        case platinum
        case desk
        case native
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

    @MainActor
    static func resolve(_ preference: ThemePreference, appearance: NSAppearance? = nil) -> ResolvedTheme {
        let appearance = appearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let kind: Kind = switch preference {
        case .automatic: isDark ? .desk : .platinum
        case .platinum: .platinum
        case .desk: .desk
        case .native: .native
        }
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        switch kind {
        case .platinum: return palette(DesignTokens.Palette.platinum, kind: kind, increaseContrast: increaseContrast)
        case .desk: return palette(DesignTokens.Palette.desk, kind: kind, increaseContrast: increaseContrast)
        case .native:
            return ResolvedTheme(
                kind: .native,
                surface: .windowBackgroundColor,
                bevelLight: .clear,
                bevelShadow: .clear,
                frame: .separatorColor,
                text: .labelColor,
                textMuted: .secondaryLabelColor,
                selection: .selectedContentBackgroundColor,
                selectionText: .alternateSelectedControlTextColor,
                correction: .systemPink
            )
        }
    }

    private static func palette(_ palette: ThemePalette, kind: Kind, increaseContrast: Bool) -> ResolvedTheme {
        let frame = palette.frame.color
        // 「コントラストを上げる」が有効なときは，立体の縁を外枠と同じ色にする(docs/dev/DESIGN-SYSTEM.md)
        return ResolvedTheme(
            kind: kind,
            surface: palette.surface.color,
            bevelLight: increaseContrast ? frame : palette.bevelLight.color,
            bevelShadow: increaseContrast ? frame : palette.bevelShadow.color,
            frame: frame,
            text: palette.text.color,
            textMuted: palette.textMuted.color,
            selection: palette.selection.color,
            selectionText: palette.selectionText.color,
            correction: palette.correction.color
        )
    }

    /// 区画を分ける線の色．desk は暗い面なので光の縁の色，native は OS の区切り線の色
    var separator: NSColor {
        switch kind {
        case .platinum: bevelShadow
        case .desk: bevelLight
        case .native: .separatorColor
        }
    }

    var hasBevel: Bool { kind != .native }
    var hasDropShadow: Bool { kind == .desk }
    var cornerRadius: CGFloat { kind == .native ? DesignTokens.Size.Candidate.cornerRadiusNative : 0 }

    static func labelFont(size: CGFloat) -> NSFont {
        NSFont(name: FontRegistry.labelFontName, size: size) ?? .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    static func candidateFont(size: CGFloat) -> NSFont {
        // 候補の文字は OS の日本語書体で読む(docs/dev/DESIGN-SYSTEM.md)
        NSFont(name: "HiraginoSans-W3", size: size) ?? .systemFont(ofSize: size)
    }
}

extension RGB {
    var color: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
