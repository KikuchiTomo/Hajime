import AppKit
import HajimeApplication
import HajimeDomain
import SwiftUI

/// 絵文字と記号のパレット(R-26)．使うか・開くキー・入れたあとの動き・使った文字の記録と，窓の見た目(列数・行数・マスの大きさ・
/// 説明と説明に出す項目・よく使う文字の行数)を決める．見た目はテーマに合わせた見本をその場で描く
struct PalettePage: View {
    @ObservedObject var model: SettingsModel
    /// 動かしているあいだのマスの大きさ．手を離したときに保存し，1 段ごとに設定のファイルを書き直さない
    @State private var cellSize: Double?
    /// 使った文字の記録を消してよいかを尋ねているか
    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section {
                PalettePreview(choice: ThemeChoice(model.settings), settings: model.settings, cellSize: cellSize ?? model.settings.paletteCellSize)
                    .padding(DesignTokens.Size.Settings.previewPadding)
                    .frame(maxWidth: .infinity)
            }
            Section(UIStrings.Palette.behavior) {
                ResettableToggle(model: model, title: UIStrings.Palette.enabled, keyPath: \.palette)
                Group {
                    LabeledContent(UIStrings.Palette.emojiKey, value: keys(for: .emojiPalette))
                    LabeledContent(UIStrings.Palette.symbolKey, value: keys(for: .symbolPalette))
                    LabeledContent(UIStrings.Palette.kaomojiKey, value: keys(for: .kaomojiPalette))
                    ResettableToggle(model: model, title: UIStrings.Palette.closesAfterInsert, keyPath: \.paletteClosesAfterInsert)
                    ResettableToggle(model: model, title: UIStrings.Palette.recordsHistory, keyPath: \.paletteRecordsHistory)
                    if let clear = model.clearPaletteHistory {
                        Button(UIStrings.Palette.clearHistory) { confirmingClear = true }
                            .confirmationDialog(UIStrings.Palette.clearHistoryQuestion, isPresented: $confirmingClear) {
                                Button(UIStrings.Palette.clearHistory, role: .destructive) { clear() }
                            } message: {
                                Text(UIStrings.Palette.clearHistoryNote)
                            }
                    }
                }
                .disabled(!model.settings.palette)
            }
            Section(UIStrings.Palette.look) {
                ResettableRow(model: model, keyPath: \.paletteColumns) {
                    Stepper(value: model.binding(\.paletteColumns), in: DefaultSettings.paletteColumnsRange) {
                        LabeledContent(UIStrings.Palette.columns, value: "\(model.settings.paletteColumns)")
                    }
                }
                ResettableRow(model: model, keyPath: \.paletteRows) {
                    Stepper(value: model.binding(\.paletteRows), in: DefaultSettings.paletteRowsRange) {
                        LabeledContent(UIStrings.Palette.rows, value: "\(model.settings.paletteRows)")
                    }
                }
                ResettableRow(model: model, keyPath: \.paletteCellSize) {
                    LabeledContent(UIStrings.Palette.cellSizeValue(Int(cellSize ?? model.settings.paletteCellSize))) {
                        Slider(value: Binding(get: { cellSize ?? model.settings.paletteCellSize }, set: { cellSize = $0 }),
                               in: DefaultSettings.paletteCellSizeRange, step: DefaultSettings.paletteCellSizeStep) { isEditing in
                            guard !isEditing, let value = cellSize else { return }
                            model.update { $0.paletteCellSize = value }
                            cellSize = nil
                        }
                    }
                }
                ResettableRow(model: model, keyPath: \.paletteFrequentRows) {
                    Stepper(value: model.binding(\.paletteFrequentRows), in: DefaultSettings.paletteFrequentRowsRange) {
                        LabeledContent(UIStrings.Palette.frequentRows, value: "\(model.settings.paletteFrequentRows)")
                    }
                }
                .disabled(!model.settings.paletteRecordsHistory)
                ResettableToggle(model: model, title: UIStrings.Palette.showsPreview, keyPath: \.paletteShowsPreview)
                Group {
                    ResettableToggle(model: model, title: UIStrings.Palette.showsUnicodeName, keyPath: \.paletteShowsUnicodeName)
                    ResettableToggle(model: model, title: UIStrings.Palette.showsReadings, keyPath: \.paletteShowsReadings)
                    ResettableToggle(model: model, title: UIStrings.Palette.showsShortcodes, keyPath: \.paletteShowsShortcodes)
                    ResettableToggle(model: model, title: UIStrings.Palette.showsCodePoints, keyPath: \.paletteShowsCodePoints)
                }
                .disabled(!model.settings.paletteShowsPreview)
                Text(UIStrings.Palette.themeNote).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// コマンドに割り当てたキー(キー設定の表から引く)．割り当てていなければ「なし」
    private func keys(for command: KeymapCommand) -> String {
        let strokes = model.settings.keymap.strokes(for: command, in: .idle)
        return strokes.isEmpty ? UIStrings.Palette.noKey : strokes.map(UIStrings.Keys.name(of:)).joined(separator: "、")
    }
}

/// 設定のとおりの列数・行数・マスの大きさで，パレットの見本をテーマに合わせて描く．欄より広いときは見本ごと縮める
struct PalettePreview: NSViewRepresentable {
    let choice: ThemeChoice
    let settings: HajimeDomain.Settings
    let cellSize: Double

    private var panel: PalettePanel {
        SamplePalettes.preview(columns: settings.paletteColumns, rows: settings.paletteRows, frequentRows: settings.paletteRecordsHistory ? settings.paletteFrequentRows : 0,
                               showsPreview: settings.paletteShowsPreview,
                               previewFields: PalettePanel.PreviewFields(unicodeName: settings.paletteShowsUnicodeName, readings: settings.paletteShowsReadings,
                                                                         shortcodes: settings.paletteShowsShortcodes, codePoints: settings.paletteShowsCodePoints))
    }

    func makeNSView(context: Context) -> ScaledPalette {
        ScaledPalette()
    }

    func updateNSView(_ view: ScaledPalette, context: Context) {
        view.palette.theme = ResolvedTheme.resolve(choice, appearance: view.effectiveAppearance)
        view.palette.cellSize = CGFloat(cellSize)
        view.palette.panel = panel
        view.natural = view.palette.fittingSize(for: panel)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ScaledPalette, context: Context) -> CGSize? {
        view.palette.cellSize = CGFloat(cellSize)
        let natural = view.palette.fittingSize(for: panel)
        guard natural.width > 0 else { return natural }
        let width = min(natural.width, proposal.width ?? natural.width)
        return CGSize(width: width, height: (natural.height * width / natural.width).rounded(.up))
    }

    /// パレットを描いた大きさのまま持ち，枠が狭ければ座標の比(bounds)で縮めて描く
    @MainActor
    final class ScaledPalette: NSView {
        let palette: PaletteView = {
            let view = PaletteView()
            view.fillsSurface = true
            return view
        }()
        var natural: NSSize = .zero {
            didSet { if natural != oldValue { updateScale() } }
        }

        override var isFlipped: Bool { true }

        init() {
            super.init(frame: .zero)
            addSubview(palette)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) は使わない") }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            updateScale()
        }

        private func updateScale() {
            palette.frame = NSRect(origin: .zero, size: natural)
            guard natural.width > 0, frame.width > 0 else { return }
            let scale = min(1, frame.width / natural.width)
            setBoundsSize(NSSize(width: frame.width / scale, height: frame.height / scale))
            palette.needsDisplay = true
        }
    }
}
