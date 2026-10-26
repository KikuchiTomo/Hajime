import AppKit
import S90Domain
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
                        .frame(width: 220)
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

/// 分岐図の見本．テーマや文字の大きさを変えると，その場で描き直す
struct ThemePreview: NSViewRepresentable {
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
