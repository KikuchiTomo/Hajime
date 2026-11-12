import AppKit
import HajimeApplication
import HajimeDomain
import SwiftUI

/// 取り込む前に中身を見せているファイル(R-16・R-18・R-21)
struct PendingImport: Identifiable {
    let id = UUID()
    let kind: ImportPreview.Kind
    let path: String
    let preview: ImportPreview
    /// 取り込み直す辞書(新しく足すときは nil)
    let replacing: String?

    var fileName: String { URL(fileURLWithPath: path).lastPathComponent }
}

/// 辞書のファイルを選んで，取り込む前に中身を見せる．「取り込む」を押すまで何も登録しない
extension SettingsModel {
    /// ファイルを選び，読み方を求めてシートに出す(SettingsView)．replacing は取り込み直す辞書
    func chooseImport(_ kind: ImportPreview.Kind, replacing: String? = nil) {
        guard let files else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if kind == .userDictionary {
            panel.allowedContentTypes = [.plainText, .tabSeparatedText, .commaSeparatedText, .propertyList]
        }
        // 開く窓は設定の窓のシートで出す(runModal はメインスレッドを止めるため．FilePanel)
        FilePanel.chooseOne(panel) { [self] source in
            isImportingDictionary = true
            // 大きな辞書は読むのに数秒かかる．読むのはメインスレッドの外(SettingsFiles)なので，画面は止まらない
            Task {
                defer { isImportingDictionary = false }
                do throws(SettingsFileFailure) {
                    let preview = try await files.previewImport(kind, from: source.path)
                    pendingImport = PendingImport(kind: kind, path: source.path, preview: preview, replacing: replacing)
                } catch {
                    logger.error("取り込む前に辞書を読めませんでした: \(String(describing: error), privacy: .public)")
                    message = switch kind {
                    case .userDictionary: UIStrings.Settings.importFailed
                    case .dictionary: UIStrings.Dictionaries.importFailed
                    case .association: UIStrings.Association.importFailed
                    }
                }
            }
        }
    }

    /// シートで「取り込む」を押した
    func commitImport(_ pending: PendingImport) {
        pendingImport = nil
        switch pending.kind {
        case .userDictionary: importUserDictionary(path: pending.path)
        case .dictionary: importDictionary(path: pending.path, replacing: pending.replacing)
        case .association: importAssociation(path: pending.path, replacing: pending.replacing)
        }
    }
}

/// 取り込む前に中身を見せるシート．列の見出しは，その列が何として読まれたか(読み・単語・品詞・コメント・意味・語)．
/// 品詞を名詞にする行は品詞をアクセントでない注意の色で，読めない行は行の番号に注意の印を付けて薄く出す．
/// 名詞にする行・読めない行があれば，上の切り替えでその行だけを出せる
struct ImportPreviewSheet: View {
    let pending: PendingImport
    let commit: () -> Void
    let cancel: () -> Void

    private enum Filter: Hashable { case all, defaulted, unreadable }
    @State private var filter = Filter.all
    /// 表で選んでいる行(shownRows の番号)．表にフォーカスがあるとき色を付け，↑↓ で移る
    @State private var selection = 0
    @FocusState private var tableFocused: Bool
    /// VoiceOver の読む行を選んだ行に合わせる
    @AccessibilityFocusState private var spokenRow: Int?

    private typealias Space = DesignTokens.Size.Space
    private typealias Part = DesignTokens.Size.Part
    private typealias Size = DesignTokens.Size.Settings
    private typealias Strings = UIStrings.ImportPreview

    private var preview: ImportPreview { pending.preview }

    private var shownRows: [ImportPreview.Row] {
        switch filter {
        case .all: preview.rows
        case .defaulted: preview.rows.filter { $0.status == .defaultedWordClass }
        case .unreadable: preview.rows.filter { $0.status == .unreadable }
        }
    }

    /// 列の幅．品詞は決まった幅，ほかは中身の長さで配る(空いている列は見出しの幅まで縮めて，長い列に回す)
    private var columnWidths: [CGFloat] {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let measure = { (text: String) in Double((text as NSString).size(withAttributes: [.font: font]).width.rounded(.up)) }
        let sample = preview.rows.prefix(DefaultSettings.maximumImportPreviewRows)
        let flexible = preview.columns.indices.filter { preview.columns[$0] != .wordClass }
        let natural = flexible.map { index in sample.map { measure($0.cells.indices.contains(index) ? $0.cells[index] : "") }.max() ?? 0 }
        let minimum = flexible.map { measure(title(preview.columns[$0])) }
        let fixed = preview.columns.contains(.wordClass) ? Size.importPreviewKindColumnWidth : 0
        let gaps = Space.group * CGFloat(preview.columns.count)
        let available = Size.importPreviewWidth - Space.page * 2 - Part.fieldPaddingX * 2 - Size.importPreviewLineColumnWidth - gaps - fixed
        var shares = ColumnWidths.distribute(natural: natural, minimum: minimum, available: Double(available)).makeIterator()
        return preview.columns.map { $0 == .wordClass ? Size.importPreviewKindColumnWidth : CGFloat(shares.next() ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.section) {
            HStack(alignment: .firstTextBaseline, spacing: Space.group) {
                Text(pending.fileName).font(.headline).lineLimit(1).truncationMode(.middle)
                Text(Strings.format(preview.format))
                    .font(.system(size: DesignTokens.Size.Text.tag))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Part.tagPaddingX)
                    .frame(height: Part.tagHeight)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: Part.tagRadius))
            }
            if preview.defaulted > 0 || preview.unreadable > 0 {
                Picker("", selection: $filter) {
                    Text(Strings.filter(Strings.all, preview.importable + preview.unreadable)).tag(Filter.all)
                    if preview.defaulted > 0 { Text(Strings.filter(Strings.defaulted, preview.defaulted)).tag(Filter.defaulted) }
                    if preview.unreadable > 0 { Text(Strings.filter(Strings.unreadable, preview.unreadable)).tag(Filter.unreadable) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            table
            HStack(spacing: Space.group) {
                Spacer()
                Button(UIStrings.Settings.cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                // 既定のボタン(アクセントの色．Return で押せる)
                Button(Strings.importButton(preview.importable, preview.kind), action: commit)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview.importable == 0)
            }
        }
        .padding(Space.page)
        .frame(width: Size.importPreviewWidth)
    }

    /// 見出しと行．行は表の中で送る(多いファイルでも見せる行は上限まで)．
    /// 表は Tab で止まり，↑↓・Page Up/Down・Home/End で行を選ぶ．見出しは送る部分の外に置き，選んだ行を隠さない
    private var table: some View {
        let widths = columnWidths
        let rows = shownRows
        // キーはフォーカスのある表の外枠が受ける(中の ScrollView ではなく)
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                header(widths)
                Divider()
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            let selected = tableFocused && index == selection
                            rowView(row, widths, selected: selected)
                                .background(rowBackground(index, selected: selected))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selection = index
                                    tableFocused = true
                                }
                                .id(index)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(rowLabel(row))
                                .accessibilityAddTraits(index == selection ? .isSelected : [])
                                .accessibilityFocused($spokenRow, equals: index)
                        }
                    }
                }
            }
            .frame(height: Size.importPreviewTableHeight)
            .background(.background, in: RoundedRectangle(cornerRadius: Part.fieldRadius))
            .overlay(RoundedRectangle(cornerRadius: Part.fieldRadius).strokeBorder(.separator))
            .clipShape(RoundedRectangle(cornerRadius: Part.fieldRadius))
            .focusable()
            .focused($tableFocused)
            .onMoveCommand { direction in
                switch direction {
                case .up: select(selection - 1, in: rows.count, proxy)
                case .down: select(selection + 1, in: rows.count, proxy)
                default: break
                }
            }
            .onKeyPress(keys: [.pageUp, .pageDown, .home, .end]) { press in
                let page = max(Int(Size.importPreviewTableHeight / Part.rowHeight) - 2, 1)
                switch press.key {
                case .pageUp: select(selection - page, in: rows.count, proxy)
                case .pageDown: select(selection + page, in: rows.count, proxy)
                case .home: select(0, in: rows.count, proxy)
                default: select(rows.count - 1, in: rows.count, proxy)
                }
                return .handled
            }
            .onChange(of: filter) {
                selection = 0
                proxy.scrollTo(0, anchor: .top)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(pending.fileName)
        }
    }

    /// 表の行を選び(端で止める)，見えるところまで送る．VoiceOver もその行を読む
    private func select(_ index: Int, in count: Int, _ proxy: ScrollViewProxy) {
        guard count > 0 else { return }
        selection = min(max(index, 0), count - 1)
        proxy.scrollTo(selection)
        spokenRow = selection
    }

    /// 選んだ行はシステムの選択の色，ほかは 1 行おきに薄く敷く(表の縞)
    private func rowBackground(_ index: Int, selected: Bool) -> AnyShapeStyle {
        if selected { return AnyShapeStyle(Color(nsColor: .selectedContentBackgroundColor)) }
        return index % 2 == 1 ? AnyShapeStyle(.quinary) : AnyShapeStyle(.clear)
    }

    /// 行の読み上げ(行の番号・列の値・名詞にする・取り込まない意味)
    private func rowLabel(_ row: ImportPreview.Row) -> String {
        var values = preview.columns.enumerated().compactMap { index, column -> String? in
            let value = row.cells.indices.contains(index) ? row.cells[index] : ""
            guard !value.isEmpty else { return nil }
            if column == .wordClass, row.status != .unreadable, let wordClass = WordClass(rawValue: value) {
                return UIStrings.Settings.label(for: wordClass)
            }
            return value
        }
        switch row.status {
        case .defaultedWordClass: values.append(Strings.defaultedHelp)
        case .unreadable: values.append(Strings.unreadableHelp)
        case .ok: break
        }
        return Strings.row(line: row.line, values: values)
    }

    private func header(_ widths: [CGFloat]) -> some View {
        HStack(spacing: Space.group) {
            Text(Strings.line).frame(width: Size.importPreviewLineColumnWidth, alignment: .trailing)
            ForEach(Array(preview.columns.enumerated()), id: \.offset) { index, column in
                cellFrame(Text(title(column)), width: widths[index])
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, Part.fieldPaddingX)
        .frame(height: Part.rowHeight)
    }

    /// 行．選んだ行は文字をすべて選択の上の色にする(表の作法．注意の色も選択の色に揃える)
    private func rowView(_ row: ImportPreview.Row, _ widths: [CGFloat], selected: Bool) -> some View {
        let unreadable = row.status == .unreadable
        let onSelection = AnyShapeStyle(Color(nsColor: .alternateSelectedControlTextColor))
        let caution = selected ? onSelection : AnyShapeStyle(.orange)
        return HStack(alignment: .firstTextBaseline, spacing: Space.group) {
            HStack(spacing: Space.inline) {
                if unreadable {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(caution)
                }
                Text(row.line.formatted()).monospacedDigit().foregroundStyle(selected ? onSelection : AnyShapeStyle(.secondary))
            }
            .frame(width: Size.importPreviewLineColumnWidth, alignment: .trailing)
            .help(unreadable ? Strings.unreadableHelp : "")
            ForEach(Array(preview.columns.enumerated()), id: \.offset) { index, column in
                cellFrame(cell(row, column: column, value: row.cells.indices.contains(index) ? row.cells[index] : "", caution: caution), width: widths[index])
            }
        }
        .foregroundStyle(selected ? onSelection : unreadable ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
        .padding(.horizontal, Part.fieldPaddingX)
        .frame(height: Part.rowHeight)
    }

    /// 列の中身．品詞は名前にし，名詞にした行はその印を付ける
    @ViewBuilder
    private func cell(_ row: ImportPreview.Row, column: ImportPreview.Column, value: String, caution: AnyShapeStyle) -> some View {
        if column == .wordClass, row.status != .unreadable, let wordClass = WordClass(rawValue: value) {
            let label = Text(UIStrings.Settings.label(for: wordClass))
            if row.status == .defaultedWordClass {
                label.foregroundStyle(caution).help(Strings.defaultedHelp)
            } else {
                label
            }
        } else {
            Text(value)
        }
    }

    private func cellFrame(_ content: some View, width: CGFloat) -> some View {
        content
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: .leading)
    }

    private func title(_ column: ImportPreview.Column) -> String {
        switch column {
        case .reading: UIStrings.Settings.reading
        case .word: UIStrings.Settings.word
        case .wordClass: UIStrings.Settings.wordClass
        case .comment: UIStrings.Settings.comment
        case .meaning: Strings.meaning
        case .words: Strings.words
        }
    }
}
