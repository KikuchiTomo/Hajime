import AppKit
import S90Domain
import SwiftUI

/// 外観．既成のテーマか，色・書体・形を自分で決めたカスタムテーマを選ぶ．
/// カスタムテーマは今のテーマを複製して作り，名前を付けて保存する(設定のファイルに入る)
struct AppearancePage: View {
    @ObservedObject var model: SettingsModel
    /// 動かしているあいだの値．手を離したときに保存し，1 段ごとに設定のファイルを書き直さない
    @State private var fontSize: Double?

    var body: some View {
        Form {
            Section {
                // 選んでいるテーマと文字の大きさで，分岐図の見本をその場で描く
                ThemePreview(choice: ThemeChoice(model.settings), fontSize: fontSize ?? model.settings.candidateFontSize)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            Section(UIStrings.More.theme) {
                ForEach(UIStrings.Choice.themes, id: \.self) { theme in
                    ThemeRow(choice: ThemeChoice(theme), title: UIStrings.Choice.label(for: theme),
                             isSelected: model.settings.customThemeID == nil && model.settings.theme == theme) {
                        model.selectTheme(theme)
                    }
                }
            }
            Section(UIStrings.More.customThemes) {
                ForEach(model.settings.customThemes, id: \.id) { theme in
                    ThemeRow(choice: ThemeChoice(theme.base, custom: theme), title: theme.name, isSelected: model.settings.customThemeID == theme.id) {
                        model.selectCustomTheme(id: theme.id)
                    }
                }
                HStack {
                    Button(UIStrings.More.duplicate) { model.duplicateCurrentTheme() }
                        .disabled(model.settings.customThemes.count >= DefaultSettings.maximumCustomThemes)
                    Spacer()
                    if let active = model.settings.activeCustomTheme {
                        Button(UIStrings.More.deleteTheme, role: .destructive) { model.deleteCustomTheme(id: active.id) }
                    }
                }
            }
            if let active = model.settings.activeCustomTheme {
                CustomThemeEditor(model: model, theme: active)
            }
            Section(UIStrings.More.font) {
                ResettableRow(model: model, keyPath: \.candidateFontSize) {
                    LabeledContent(UIStrings.Settings.fontSize(Int(fontSize ?? model.settings.candidateFontSize))) {
                        Slider(
                            value: Binding(get: { fontSize ?? model.settings.candidateFontSize }, set: { fontSize = $0 }),
                            in: DefaultSettings.candidateFontSizeRange,
                            step: 1
                        ) { isEditing in
                            guard !isEditing, let value = fontSize else { return }
                            model.update { $0.candidateFontSize = value }
                            fontSize = nil
                        }
                        .frame(width: 220)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// テーマの一行．名前の前に，地・文字・選択の色を小さく並べる
private struct ThemeRow: View {
    let choice: ThemeChoice
    let title: String
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                ThemeSwatch(theme: ResolvedTheme.resolve(choice))
                Text(title)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ThemeSwatch: View {
    let theme: ResolvedTheme

    var body: some View {
        let radius = theme.isRounded ? min(theme.cornerRadius / 2, 6) : 0
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(nsColor: theme.surface))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color(nsColor: theme.frame), lineWidth: 1))
            HStack(spacing: 3) {
                Text("あ").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(nsColor: theme.text))
                RoundedRectangle(cornerRadius: radius / 2)
                    .fill(Color(nsColor: theme.selection))
                    .frame(width: 12, height: 10)
            }
        }
        .frame(width: 40, height: 20)
    }
}

/// 使っているカスタムテーマの色・形・書体を変える．変えたらすぐに保存し，候補ウィンドウにも映る
private struct CustomThemeEditor: View {
    @ObservedObject var model: SettingsModel
    let theme: CustomTheme
    @State private var name = ""

    var body: some View {
        Section(UIStrings.More.colors) {
            LabeledContent(UIStrings.More.themeName) {
                TextField("", text: $name)
                    .onSubmit(saveName)
                    .frame(width: 220)
            }
            color(UIStrings.More.surface, \.surface)
            color(UIStrings.More.text, \.text)
            color(UIStrings.More.textMuted, \.textMuted)
            color(UIStrings.More.selection, \.selection)
            color(UIStrings.More.selectionText, \.selectionText)
            color(UIStrings.More.correction, \.correction)
            color(UIStrings.More.line, \.line)
        }
        .onAppear { name = theme.name }
        .onChange(of: theme.id) { name = theme.name }
        .onDisappear(perform: saveName)
        Section(UIStrings.More.shape) {
            LabeledContent(UIStrings.More.cornerRadius) {
                Slider(value: binding(\.cornerRadius), in: DefaultSettings.customThemeCornerRadiusRange, step: 1)
                    .frame(width: 220)
            }
            Picker(UIStrings.More.branchStyle, selection: binding(\.branchStyle)) {
                ForEach(CustomTheme.BranchStyle.allCases, id: \.self) { Text(UIStrings.More.label(for: $0)).tag($0) }
            }
            Picker(UIStrings.More.font, selection: binding(\.fontName)) {
                Text(UIStrings.More.themeFont).tag(String?.none)
                ForEach(Self.fonts, id: \.self) { font in
                    Text(NSFont(name: font, size: 13)?.displayName ?? font).tag(String?.some(font))
                }
            }
        }
    }

    /// 選べる候補の書体．この Mac にあるものだけ
    private static let fonts = [
        "HiraginoSans-W3", "HiraginoSans-W6", "HiraMinProN-W3", "HiraMinProN-W6", "HiraMaruProN-W4",
        "YuGothic-Medium", "YuMincho-Regular", "ToppanBunkyuGothicPr6N-DB", "ToppanBunkyuMinchoPr6N-RG", "Osaka", "Menlo-Regular",
    ].filter { NSFont(name: $0, size: 13) != nil }

    private func binding<Value>(_ keyPath: WritableKeyPath<CustomTheme, Value>) -> Binding<Value> {
        Binding(get: { theme[keyPath: keyPath] }, set: { value in model.updateCustomTheme(id: theme.id) { $0[keyPath: keyPath] = value } })
    }

    private func color(_ title: String, _ keyPath: WritableKeyPath<CustomTheme, HexColor>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(nsColor: theme[keyPath: keyPath].color) },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                let hex = HexColor(red: UInt8((rgb.redComponent * 255).rounded()), green: UInt8((rgb.greenComponent * 255).rounded()),
                                   blue: UInt8((rgb.blueComponent * 255).rounded()))
                model.updateCustomTheme(id: theme.id) { $0[keyPath: keyPath] = hex }
            }
        ), supportsOpacity: false)
    }

    private func saveName() {
        let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(DefaultSettings.maximumThemeNameLength))
        guard !trimmed.isEmpty, trimmed != theme.name else { return }
        model.updateCustomTheme(id: theme.id) { $0.name = trimmed }
    }
}

/// 分岐図の見本．テーマや文字の大きさを変えると，その場で描き直す
private struct ThemePreview: NSViewRepresentable {
    let choice: ThemeChoice
    let fontSize: Double

    func makeNSView(context: Context) -> BranchView {
        let view = BranchView()
        view.fillsSurface = true
        return view
    }

    func updateNSView(_ view: BranchView, context: Context) {
        view.theme = ResolvedTheme.resolve(choice, appearance: view.effectiveAppearance)
        view.fontSize = CGFloat(fontSize)
        view.panel = SamplePanels.lattice
        view.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: BranchView, context: Context) -> CGSize? {
        view.fittingSize(for: SamplePanels.lattice)
    }
}
