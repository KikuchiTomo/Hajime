import AppKit
import S90Domain
import SwiftUI

/// 編集の画面で開くカスタムテーマ
struct ThemeDraft: Identifiable {
    var theme: CustomTheme
    /// まだ保存していない新しいテーマか
    var isNew: Bool
    var id: String { theme.id }
}

/// カスタムテーマを組み立てる画面．色・形・書体を選ぶと，上の分岐図の見本にすぐ映す．
/// 「保存」を押すまで設定は変えない(キャンセルすれば元のまま)
struct CustomThemeEditor: View {
    @ObservedObject var model: SettingsModel
    @State private var theme: CustomTheme
    private let isNew: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: SettingsModel, draft: ThemeDraft) {
        self.model = model
        _theme = State(initialValue: draft.theme)
        isNew = draft.isNew
    }

    private var trimmedName: String {
        String(theme.name.trimmingCharacters(in: .whitespaces).prefix(DefaultSettings.maximumThemeNameLength))
    }

    var body: some View {
        VStack(spacing: 0) {
            ThemePreview(choice: ThemeChoice(theme.base, custom: theme), fontSize: model.settings.candidateFontSize)
                .fixedSize()
                .padding(DesignTokens.Size.Settings.previewPadding)
                .frame(maxWidth: .infinity)
                .background(.background.secondary)
                .accessibilityLabel(UIStrings.More.preview)
            Divider()
            Form {
                Section {
                    TextField(UIStrings.More.themeName, text: $theme.name)
                }
                let issues = theme.lowContrastPairs
                if !issues.isEmpty {
                    Section(UIStrings.More.readability) {
                        ForEach(issues, id: \.self) { pair in
                            Label(UIStrings.More.lowContrast(pair, ratio: theme.contrastRatio(of: pair)), systemImage: "exclamationmark.triangle.fill")
                                .symbolRenderingMode(.multicolor)
                                .font(.callout)
                        }
                    }
                }
                Section(UIStrings.More.colors) {
                    color(UIStrings.More.surface, \.surface)
                    color(UIStrings.More.text, \.text, warns: issues.contains(.text))
                    color(UIStrings.More.textMuted, \.textMuted, warns: issues.contains(.textMuted))
                    color(UIStrings.More.selection, \.selection, warns: issues.contains(.selectionText))
                    color(UIStrings.More.selectionText, \.selectionText, warns: issues.contains(.selectionText))
                    color(UIStrings.More.correction, \.correction, warns: issues.contains(.correction))
                    color(UIStrings.More.line, \.line)
                }
                Section(UIStrings.More.shape) {
                    LabeledContent(UIStrings.More.cornerRadius) {
                        HStack {
                            Slider(value: $theme.cornerRadius, in: DefaultSettings.customThemeCornerRadiusRange, step: 1)
                            Text("\(Int(theme.cornerRadius))").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    Picker(UIStrings.More.branchStyle, selection: $theme.branchStyle) {
                        ForEach(CustomTheme.BranchStyle.allCases, id: \.self) { Text(UIStrings.More.label(for: $0)).tag($0) }
                    }
                    Picker(UIStrings.More.font, selection: $theme.fontName) {
                        Text(UIStrings.More.themeFont).tag(String?.none)
                        ForEach(Self.fonts, id: \.self) { font in
                            Text(NSFont(name: font, size: 13)?.displayName ?? font).tag(String?.some(font))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                if !isNew {
                    Button(UIStrings.More.duplicateTheme) {
                        var copy = theme
                        copy.id = UUID().uuidString
                        copy.name = String(UIStrings.More.copyName(trimmedName).prefix(DefaultSettings.maximumThemeNameLength))
                        if model.saveCustomTheme(copy) { dismiss() }
                    }
                    .disabled(model.settings.customThemes.count >= DefaultSettings.maximumCustomThemes)
                }
                Spacer()
                Button(UIStrings.Settings.cancel, role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(UIStrings.Settings.save) {
                    theme.name = trimmedName
                    if model.saveCustomTheme(theme) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
            }
            .padding()
        }
        .frame(width: DesignTokens.Size.Settings.themeEditorWidth, height: DesignTokens.Size.Settings.themeEditorHeight)
    }

    /// 選べる候補の書体．この Mac にあるものだけ
    private static let fonts = [
        "HiraginoSans-W3", "HiraginoSans-W6", "HiraMinProN-W3", "HiraMinProN-W6", "HiraMaruProN-W4",
        "YuGothic-Medium", "YuMincho-Regular", "ToppanBunkyuGothicPr6N-DB", "ToppanBunkyuMinchoPr6N-RG", "Osaka", "Menlo-Regular",
    ].filter { NSFont(name: $0, size: 13) != nil }

    /// 色を選ぶ行．読みにくい組み合わせに入る色には印を付ける
    private func color(_ title: String, _ keyPath: WritableKeyPath<CustomTheme, HexColor>, warns: Bool = false) -> some View {
        HStack {
            ColorPicker(title, selection: Binding(
                get: { Color(nsColor: theme[keyPath: keyPath].color) },
                set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    theme[keyPath: keyPath] = HexColor(red: UInt8((rgb.redComponent * 255).rounded()), green: UInt8((rgb.greenComponent * 255).rounded()),
                                                       blue: UInt8((rgb.blueComponent * 255).rounded()))
                }
            ), supportsOpacity: false)
            if warns {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(UIStrings.More.readability)
                    .accessibilityLabel(UIStrings.More.readability)
            }
            Text(theme[keyPath: keyPath].hex).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
