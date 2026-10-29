import AppKit
import HajimeDomain

/// 設定と OS の外観から決めた，描画に使う色と書体．寸法とテーマの色は DesignTokens(design/tokens から生成)から取り，
/// glass の色は OS の意味の色(labelColor・controlAccentColor など)を使う．ライト・ダークとアクセントカラーに OS が合わせるため．
///
/// 描き方は 2 通り．
/// - 角丸と曲線の枝(isRounded): glass と，和紙・ネオン・端末・北欧・高コントラスト．glass だけ地をぼかし，ほかは地を色で塗る
/// - 四角い枠と立体の縁: platinum と desk
struct ResolvedTheme {
    enum Kind {
        /// すりガラスの地に角丸と曲線の枝．既定
        case glass
        case platinum
        case desk
        case washi
        case neon
        case terminal
        case nordic
        case contrast
    }

    /// 書体の系統．テーマの個性を出す
    enum Typeface {
        case system
        /// 明朝体(和紙)
        case mincho
        /// 等幅(端末)
        case monospaced
        /// 丸みのある書体(ネオン)
        case rounded
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
    /// 番号の丸とキーキャップの地
    let badge: NSColor
    var typeface: Typeface = .system
    /// 角の丸さ(角丸のテーマ)．カスタムテーマで変えられる
    var cornerRadius: CGFloat = DesignTokens.Size.Glass.cornerRadius
    /// 枝を曲線でなく直線で描く(カスタムテーマ)
    var straightBranches = false
    /// 候補の書体の名前(カスタムテーマ)．nil ならテーマの書体
    var customFontName: String?

    /// 設定から描き方を決める．カスタムテーマを使っていれば，元のテーマの描き方に色・書体・形を重ねる
    @MainActor
    static func resolve(_ choice: ThemeChoice, appearance: NSAppearance? = nil) -> ResolvedTheme {
        guard let custom = choice.custom else { return resolve(choice.preference, appearance: appearance) }
        var theme = resolve(custom.base, appearance: appearance)
        let text = custom.text.color
        theme = ResolvedTheme(
            kind: theme.kind == .glass ? .nordic : theme.kind,
            surface: custom.surface.color,
            bevelLight: theme.bevelLight,
            bevelShadow: theme.bevelShadow,
            frame: custom.line.color,
            text: text,
            textMuted: custom.textMuted.color,
            selection: custom.selection.color,
            selectionText: custom.selectionText.color,
            correction: custom.correction.color,
            line: custom.line.color,
            focusTint: custom.selection.color.withAlphaComponent(DesignTokens.Opacity.Rounded.focusTint),
            badge: text.withAlphaComponent(DesignTokens.Opacity.Rounded.badge),
            typeface: theme.typeface
        )
        theme.cornerRadius = CGFloat(custom.cornerRadius)
        theme.straightBranches = custom.branchStyle == .straight
        theme.customFontName = custom.fontName
        return theme
    }

    @MainActor
    static func resolve(_ preference: ThemePreference, appearance: NSAppearance? = nil) -> ResolvedTheme {
        let increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast
        switch preference {
        case .automatic, .native: return standard(increaseContrast: increaseContrast)
        case .platinum: return palette(DesignTokens.Palette.platinum, kind: .platinum, increaseContrast: increaseContrast)
        case .desk: return palette(DesignTokens.Palette.desk, kind: .desk, increaseContrast: increaseContrast)
        case .washi: return rounded(DesignTokens.Palette.washi, kind: .washi, typeface: .mincho, increaseContrast: increaseContrast)
        case .neon: return rounded(DesignTokens.Palette.neon, kind: .neon, typeface: .rounded, increaseContrast: increaseContrast)
        case .terminal: return rounded(DesignTokens.Palette.terminal, kind: .terminal, typeface: .monospaced, increaseContrast: increaseContrast)
        case .nordic: return rounded(DesignTokens.Palette.nordic, kind: .nordic, typeface: .system, increaseContrast: increaseContrast)
        case .contrast: return rounded(DesignTokens.Palette.contrast, kind: .contrast, typeface: .system, increaseContrast: true)
        }
    }

    /// 標準のテーマの書体(ヒラギノ丸ゴ)．標準のテーマは枝を直線で描く
    static let standardFontName = "HiraMaruProN-W4"

    /// 標準のテーマ．暗い地に青い選択と赤い補正，丸い書体と直線の枝(色は tokens.json の theme.standard)．
    /// カスタムテーマと同じく，角丸の描き方に色・書体・形を重ねる．ライトとダークで色を変えない
    private static func standard(increaseContrast: Bool) -> ResolvedTheme {
        var theme = rounded(DesignTokens.Palette.standard, kind: .nordic, typeface: .rounded, increaseContrast: increaseContrast)
        theme.cornerRadius = DesignTokens.Size.StandardTheme.cornerRadius
        theme.straightBranches = true
        theme.customFontName = standardFontName
        return theme
    }

    /// 角丸のテーマを色のトークンで塗る．線は外枠の色，番号の丸とキーキャップは文字の色を薄くしたもの
    private static func rounded(_ palette: ThemePalette, kind: Kind, typeface: Typeface, increaseContrast: Bool) -> ResolvedTheme {
        let text = palette.text.color
        return ResolvedTheme(
            kind: kind,
            surface: palette.surface.color,
            bevelLight: palette.bevelLight.color,
            bevelShadow: palette.bevelShadow.color,
            frame: palette.frame.color,
            text: text,
            textMuted: increaseContrast ? text : palette.textMuted.color,
            selection: palette.selection.color,
            selectionText: palette.selectionText.color,
            correction: palette.correction.color,
            line: increaseContrast ? palette.textMuted.color : palette.frame.color,
            focusTint: palette.selection.color.withAlphaComponent(increaseContrast ? 0.35 : 0.2),
            badge: text.withAlphaComponent(increaseContrast ? 0.25 : 0.12),
            typeface: typeface
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
            badge: palette.surface.color
        )
    }

    /// 角丸と曲線の枝で描くか(platinum と desk のほか)
    var isRounded: Bool { kind != .platinum && kind != .desk }
    /// 地をぼかすか(glass だけ)．ほかの角丸のテーマは地を色で塗る
    var usesBackdrop: Bool { kind == .glass }
    var hasBevel: Bool { !isRounded }
    var hasDropShadow: Bool { kind == .desk }

    // MARK: - 書体

    private func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let customFontName, let custom = NSFont(name: customFontName, size: size) {
            return custom
        }
        switch typeface {
        case .system:
            return .systemFont(ofSize: size, weight: weight)
        case .mincho:
            let name = weight >= .medium ? "HiraMinProN-W6" : "HiraMinProN-W3"
            return NSFont(name: name, size: size) ?? .systemFont(ofSize: size, weight: weight)
        case .monospaced:
            return .monospacedSystemFont(ofSize: size, weight: weight)
        case .rounded:
            let base = NSFont.systemFont(ofSize: size, weight: weight)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
        }
    }

    /// 番号・案内・札の書体
    func labelFont(size: CGFloat) -> NSFont {
        font(size: size, weight: .medium)
    }

    /// 案内の主な語(「修正」「もしかして」)の書体
    func emphasisFont(size: CGFloat) -> NSFont {
        font(size: size, weight: .semibold)
    }

    /// 補正の色を薄く敷いた地(候補の横の「修正」の札と，案内の頭のアイコンの丸)
    var correctionTint: NSColor {
        let increased = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast || kind == .contrast
        return correction.withAlphaComponent(increased ? DesignTokens.Opacity.Glass.correctionTagContrast : DesignTokens.Opacity.Glass.correctionTag)
    }

    /// 番号の丸とキーキャップの中の文字．数字の幅をそろえる
    func keyFont(size: CGFloat) -> NSFont {
        typeface == .system ? .monospacedDigitSystemFont(ofSize: size, weight: .semibold) : font(size: size, weight: .semibold)
    }

    /// 候補の文字．日本語はテーマの書体に合うものを OS が代わりに使う(システムの書体ならヒラギノ角ゴシック)
    func candidateFont(size: CGFloat) -> NSFont {
        font(size: size, weight: kind == .contrast ? .medium : .regular)
    }

    /// 分岐図の幹の文字．候補より少し太くし，文として読めるようにする
    func trunkFont(size: CGFloat) -> NSFont {
        font(size: size, weight: kind == .contrast ? .semibold : .medium)
    }
}

/// どのテーマで描くか．既成のテーマか，保存したカスタムテーマ
struct ThemeChoice: Equatable {
    var preference: ThemePreference
    var custom: CustomTheme?

    init(_ preference: ThemePreference, custom: CustomTheme? = nil) {
        self.preference = preference
        self.custom = custom
    }

    init(_ settings: HajimeDomain.Settings) {
        self.init(settings.theme, custom: settings.activeCustomTheme)
    }
}

extension HexColor {
    var color: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

extension RGB {
    var color: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}
