import AppKit
import HajimeApplication
import HajimeDomain
import SwiftUI

/// 外観．既成のテーマか，色・書体・形を自分で決めたカスタムテーマを選ぶ．
/// カスタムテーマは今のテーマを複製して作り，名前を付けて保存する(設定のファイルに入る)
struct AppearancePage: View {
    @ObservedObject var model: SettingsModel
    /// 動かしているあいだの値．手を離したときに保存し，1 段ごとに設定のファイルを書き直さない
    @State private var fontSize: Double?
    /// 編集の画面で開いているカスタムテーマ
    @State private var editing: ThemeDraft?
    /// 消してよいかを尋ねているカスタムテーマ
    @State private var deleting: CustomTheme?

    var body: some View {
        Form {
            Section {
                // 選んでいるテーマと文字の大きさで，分岐図の見本をその場で描く
                // 見本は描いた大きさのまま真ん中に置き，まわりに余白をとる(幅いっぱいに伸ばすと字が左に寄って詰まって見える)．
                // 欄より広いときは見本ごと縮める(そのままの幅で置くと，ページが横にはみ出して左端が切れる)
                ThemePreview(choice: ThemeChoice(model.settings), fontSize: fontSize ?? model.settings.candidateFontSize)
                    .padding(DesignTokens.Size.Settings.previewPadding)
                    .frame(maxWidth: .infinity)
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
                if model.settings.customThemes.isEmpty {
                    Text(UIStrings.More.noCustomThemes).foregroundStyle(.secondary)
                }
                ForEach(model.settings.customThemes, id: \.id) { theme in
                    CustomThemeRow(model: model, theme: theme, edit: { editing = ThemeDraft(theme: theme, isNew: false) },
                                   delete: { deleting = theme })
                }
                HStack {
                    Button(UIStrings.More.createTheme) { editing = ThemeDraft(theme: model.draftCustomTheme(), isNew: true) }
                    Button(UIStrings.More.duplicate) { model.duplicateCurrentTheme() }
                    Spacer()
                }
                .disabled(model.settings.customThemes.count >= DefaultSettings.maximumCustomThemes)
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
                        .frame(width: DesignTokens.Size.Settings.fontSliderWidth)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { draft in
            CustomThemeEditor(model: model, draft: draft)
        }
        .confirmationDialog(deleting.map { UIStrings.More.confirmDeleteTheme($0.name) } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button(UIStrings.More.deleteTheme, role: .destructive) {
                if let deleting { model.deleteCustomTheme(id: deleting.id) }
            }
        }
    }
}

/// カスタムテーマの一行．押すと使い，右のボタンで編集・複製・削除する
private struct CustomThemeRow: View {
    @ObservedObject var model: SettingsModel
    let theme: CustomTheme
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            ThemeRow(choice: ThemeChoice(theme.base, custom: theme), title: theme.name, isSelected: model.settings.customThemeID == theme.id) {
                model.selectCustomTheme(id: theme.id)
            }
            if !theme.lowContrastPairs.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(UIStrings.More.readability)
                    .accessibilityLabel(UIStrings.More.readability)
            }
            button(UIStrings.More.editTheme, systemImage: "pencil", action: edit)
            button(UIStrings.More.duplicateTheme, systemImage: "plus.square.on.square") { model.duplicateCustomTheme(id: theme.id) }
                .disabled(model.settings.customThemes.count >= DefaultSettings.maximumCustomThemes)
            button(UIStrings.More.deleteTheme, systemImage: "trash", action: delete)
        }
        .contextMenu {
            Button(UIStrings.More.editTheme, action: edit)
            Button(UIStrings.More.duplicateTheme) { model.duplicateCustomTheme(id: theme.id) }
            Button(UIStrings.More.deleteTheme, role: .destructive, action: delete)
        }
    }

    private func button(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: systemImage) }
            .buttonStyle(.borderless)
            .help(title)
            .accessibilityLabel(title)
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
    private typealias Size = DesignTokens.Size.Settings
    let theme: ResolvedTheme

    var body: some View {
        let radius = theme.isRounded ? min(theme.cornerRadius / 2, Size.themeSwatchRadius) : 0
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(Color(nsColor: theme.surface))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color(nsColor: theme.frame), lineWidth: 1))
            HStack(spacing: Size.themeSwatchGap) {
                Text(IndicatorLabels.label(for: InputMode.japanese))
                    .font(.system(size: Size.themeSwatchFontSize, weight: .semibold)).foregroundStyle(Color(nsColor: theme.text))
                RoundedRectangle(cornerRadius: radius / 2)
                    .fill(Color(nsColor: theme.selection))
                    .frame(width: Size.themeSwatchSelectionWidth, height: Size.themeSwatchSelectionHeight)
            }
        }
        .frame(width: Size.themeSwatchWidth, height: Size.themeSwatchHeight)
    }
}

/// 分岐図の見本．テーマや文字の大きさを変えると，その場で描き直す
/// 欄の幅が描いた大きさより狭いときは，見本全体を同じ比で縮めて収める
struct ThemePreview: NSViewRepresentable {
    let choice: ThemeChoice
    let fontSize: Double

    func makeNSView(context: Context) -> ScaledPreview<BranchView> {
        let view = BranchView()
        view.fillsSurface = true
        return ScaledPreview(content: view)
    }

    func updateNSView(_ view: ScaledPreview<BranchView>, context: Context) {
        view.content.theme = ResolvedTheme.resolve(choice, appearance: view.effectiveAppearance)
        view.content.fontSize = CGFloat(fontSize)
        view.content.panel = SamplePanels.lattice
        view.natural = view.content.fittingSize(for: SamplePanels.lattice)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ScaledPreview<BranchView>, context: Context) -> CGSize? {
        ScaledPreview<BranchView>.size(natural: view.content.fittingSize(for: SamplePanels.lattice), proposal: proposal)
    }
}

/// 候補の窓の見本を描いた大きさのまま持ち，枠が狭ければ座標の比(bounds)で縮めて描く
@MainActor
final class ScaledPreview<Content: NSView>: NSView {
    let content: Content
    var natural: NSSize = .zero {
        didSet { if natural != oldValue { updateScale() } }
    }

    override var isFlipped: Bool { true }

    init(content: Content) {
        self.content = content
        super.init(frame: .zero)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) は使わない") }

    /// 描いた大きさ natural の見本を，提案された幅に収まるよう同じ比で縮めた大きさ
    static func size(natural: NSSize, proposal: ProposedViewSize) -> CGSize {
        guard natural.width > 0 else { return natural }
        let width = min(natural.width, proposal.width ?? natural.width)
        return CGSize(width: width, height: (natural.height * width / natural.width).rounded(.up))
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateScale()
    }

    private func updateScale() {
        content.frame = NSRect(origin: .zero, size: natural)
        guard natural.width > 0, frame.width > 0 else { return }
        let scale = min(1, frame.width / natural.width)
        setBoundsSize(NSSize(width: frame.width / scale, height: frame.height / scale))
        content.needsDisplay = true
    }
}
