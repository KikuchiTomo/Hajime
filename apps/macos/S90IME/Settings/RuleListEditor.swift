import SwiftUI

/// 決まりの一覧の 1 行(「打った英字 → 置き換える語」「読み → 単語」など)
struct RuleItem: Identifiable, Hashable {
    /// 消すときの扱い
    enum Removal: Hashable {
        /// 消せる
        case remove
        /// 既定の決まりを変えたもの．消すと既定に戻る
        case restore
        /// 既定の決まりそのもの．消せない(無効にはできる)
        case none
    }

    var id: String
    var key: String
    var value: String
    var isEnabled = true
    /// 既定から変えた・足したことを示す短い札(「変更あり」「追加」)
    var badge: String?
    var removal = Removal.remove
    /// 左の欄を書き換えられないか(既定の決まりの入力)
    var isKeyFixed = false
}

/// 決まりの一覧を編集する部品．補正の置き換え・直さない語・ローマ字・ユーザー辞書・記号で共通に使う．
/// Form の Section の中に置く．上の欄で足し(ダブルクリックした行は上の欄で書き換え)，下の表で選んで消す．
///
/// 表(Table)は見えている行だけを作るので，数百行あっても重くならない
struct RuleListEditor: View {
    struct Labels {
        var key: String
        /// nil なら 1 列だけの一覧(直さない語)
        var value: String?
        var keyPrompt: String?
        var valuePrompt: String?
        /// 一覧が空のときの見出しと説明
        var empty: String
        var emptyHint: String
    }

    let labels: Labels
    let items: [RuleItem]
    /// 足す前に確かめる．問題があれば利用者に見せる文を返す
    let problem: (_ key: String, _ value: String) -> String?
    /// 保存する．editing は書き換える行(新しく足すときは nil)．保存できたら true(入力欄を空にする)
    let save: (_ key: String, _ value: String, _ editing: RuleItem?) -> Bool
    let remove: (_ items: [RuleItem]) -> Void
    /// 行ごとにオン・オフできる一覧なら渡す
    let setEnabled: ((RuleItem, Bool) -> Void)?
    let importFile: (() -> Void)?
    let exportFile: (() -> Void)?
    /// 左が重ならない一覧か．重なってよい一覧(ユーザー辞書の読み)では，左と右の両方が同じ行だけを重なりとみなす
    let keysAreUnique: Bool
    let tableHeight: CGFloat

    @State private var key = ""
    @State private var value = ""
    @State private var editing: RuleItem?
    @State private var query = ""
    @State private var selection = Set<RuleItem.ID>()
    @State private var sortOrder: [KeyPathComparator<RuleItem>] = []
    @FocusState private var focusedField: Field?

    private enum Field { case key, value }

    init(labels: Labels, items: [RuleItem], problem: @escaping (_ key: String, _ value: String) -> String?,
         save: @escaping (_ key: String, _ value: String, _ editing: RuleItem?) -> Bool, remove: @escaping (_ items: [RuleItem]) -> Void,
         setEnabled: ((RuleItem, Bool) -> Void)? = nil, importFile: (() -> Void)? = nil, exportFile: (() -> Void)? = nil,
         keysAreUnique: Bool = true, tableHeight: CGFloat = DesignTokens.Size.Settings.ruleTableHeight) {
        self.labels = labels
        self.items = items
        self.problem = problem
        self.save = save
        self.remove = remove
        self.setEnabled = setEnabled
        self.importFile = importFile
        self.exportFile = exportFile
        self.keysAreUnique = keysAreUnique
        self.tableHeight = tableHeight
    }

    private var hasValue: Bool { labels.value != nil }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespaces) }
    private var trimmedValue: String { value.trimmingCharacters(in: .whitespaces) }
    private var isFilled: Bool { !trimmedKey.isEmpty && (!hasValue || !trimmedValue.isEmpty) }

    /// 入力欄の下に出す文．形が合わなければ理由，同じ入力の行があれば上書きすること
    private var message: (text: String, isProblem: Bool)? {
        guard isFilled else { return nil }
        if let problem = problem(trimmedKey, trimmedValue) { return (problem, true) }
        let others = items.filter { $0.id != editing?.id }
        if keysAreUnique {
            if others.contains(where: { $0.key == trimmedKey }) { return (UIStrings.RuleList.overwrites(trimmedKey), false) }
        } else if others.contains(where: { $0.key == trimmedKey && $0.value == trimmedValue }) {
            return (UIStrings.RuleList.alreadyRegistered, true)
        }
        return nil
    }

    private var shownItems: [RuleItem] {
        var result = items
        if !query.isEmpty {
            result = result.filter { $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) }
        }
        if !sortOrder.isEmpty { result.sort(using: sortOrder) }
        return result
    }

    var body: some View {
        editor
        if let message {
            Label(message.text, systemImage: message.isProblem ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.caption)
                .foregroundStyle(message.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        table
        footer
    }

    private var editor: some View {
        HStack {
            TextField(labels.key, text: $key, prompt: Text(labels.keyPrompt ?? labels.key))
                .textFieldStyle(.roundedBorder)
                .focused($focusedField, equals: .key)
                .disabled(editing?.isKeyFixed ?? false)
                .onSubmit { hasValue ? (focusedField = .value) : commit() }
            if let valueLabel = labels.value {
                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(valueLabel, text: $value, prompt: Text(labels.valuePrompt ?? valueLabel))
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .value)
                    .onSubmit(commit)
            }
            if editing != nil {
                Button(UIStrings.Settings.cancel, action: clear)
                    .keyboardShortcut(.cancelAction)
            }
            Button(editing == nil ? UIStrings.Settings.add : UIStrings.RuleList.update, action: commit)
                .disabled(!isFilled || message?.isProblem == true)
        }
        .labelsHidden()
    }

    /// 列を隠すと最後の列が表の幅に広がらないので，列の組み合わせごとに表を分ける(macOS 14.0 では列の if が使えない)
    @ViewBuilder
    private var table: some View {
        if setEnabled != nil {
            decorated(Table(shownItems, selection: $selection, sortOrder: $sortOrder) {
                enabledColumn
                keyColumn
                valueColumn
            })
        } else if hasValue {
            decorated(Table(shownItems, selection: $selection, sortOrder: $sortOrder) {
                keyColumn
                valueColumn
            })
        } else {
            decorated(Table(shownItems, selection: $selection, sortOrder: $sortOrder) {
                keyColumn
            })
        }
    }

    private var enabledColumn: some TableColumnContent<RuleItem, KeyPathComparator<RuleItem>> {
        // オン・オフでは並べ替えない(並べ替えの比べ方は入力の順にしておく)
        TableColumn(UIStrings.RuleList.enabled, sortUsing: KeyPathComparator(\RuleItem.key)) { (item: RuleItem) in
            Toggle("", isOn: Binding(get: { item.isEnabled }, set: { setEnabled?(item, $0) }))
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .width(DesignTokens.Size.Settings.ruleCheckColumnWidth)
    }

    private var keyColumn: some TableColumnContent<RuleItem, KeyPathComparator<RuleItem>> {
        TableColumn(labels.key, value: \.key) { item in
            Text(item.key).monospaced().foregroundStyle(item.isEnabled ? .primary : .secondary)
        }
        .width(min: 80, ideal: hasValue ? 160 : 400, max: hasValue ? 320 : .infinity)
    }

    private var valueColumn: some TableColumnContent<RuleItem, KeyPathComparator<RuleItem>> {
        TableColumn(labels.value ?? "", value: \.value) { item in
            HStack {
                Text(item.value).foregroundStyle(item.isEnabled ? .primary : .secondary)
                Spacer()
                // 既定から変えた・足したことを示す札
                if let badge = item.badge {
                    Text(badge).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        // 最後の列は表の幅いっぱいに広がるので，小さめにしておく(大きいと右にはみ出す)
        .width(min: 120, ideal: 240)
    }

    /// 表に共通の操作(ダブルクリックで編集，右クリック，Delete キーで削除，空のときの案内)
    private func decorated(_ table: some View) -> some View {
        table
            .contextMenu(forSelectionType: RuleItem.ID.self) { ids in
                let picked = items.filter { ids.contains($0.id) }
                if picked.count == 1, let item = picked.first {
                    Button(UIStrings.RuleList.edit) { edit(item) }
                }
                if !picked.filter({ $0.removal != .none }).isEmpty {
                    Button(removeTitle(for: picked)) { removeItems(picked) }
                }
            } primaryAction: { ids in
                if ids.count == 1, let item = items.first(where: { ids.contains($0.id) }) { edit(item) }
            }
            .onDeleteCommand { removeItems(items.filter { selection.contains($0.id) }) }
            .overlay { emptyState }
            .frame(height: tableHeight)
    }

    @ViewBuilder
    private var emptyState: some View {
        if items.isEmpty {
            ContentUnavailableView(labels.empty, systemImage: "list.bullet.rectangle", description: Text(labels.emptyHint))
        } else if shownItems.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private var footer: some View {
        HStack {
            Button(removeTitle(for: selectedItems)) { removeItems(selectedItems) }
                .disabled(selectedItems.allSatisfy { $0.removal == .none })
            Spacer()
            TextField(UIStrings.Features.search, text: $query, prompt: Text(UIStrings.Features.search))
                .textFieldStyle(.roundedBorder)
                .frame(width: DesignTokens.Size.Settings.ruleSearchWidth)
                .labelsHidden()
            if let importFile { Button(UIStrings.Settings.importDictionary, action: importFile) }
            if let exportFile { Button(UIStrings.Settings.exportDictionary, action: exportFile).disabled(items.isEmpty) }
        }
    }

    private var selectedItems: [RuleItem] { items.filter { selection.contains($0.id) } }

    /// 既定に戻すだけの行なら「既定に戻す」，それ以外は「削除」
    private func removeTitle(for picked: [RuleItem]) -> String {
        !picked.isEmpty && picked.allSatisfy { $0.removal == .restore } ? UIStrings.Features.restoreDefault : UIStrings.Settings.remove
    }

    private func removeItems(_ picked: [RuleItem]) {
        let removable = picked.filter { $0.removal != .none }
        guard !removable.isEmpty else { return }
        remove(removable)
        selection.subtract(removable.map(\.id))
        if let editing, removable.contains(where: { $0.id == editing.id }) { clear() }
    }

    private func edit(_ item: RuleItem) {
        editing = item
        key = item.key
        value = item.value
        focusedField = hasValue ? .value : .key
    }

    private func commit() {
        guard isFilled, message?.isProblem != true else { return }
        if save(trimmedKey, trimmedValue, editing) { clear() }
    }

    private func clear() {
        editing = nil
        key = ""
        value = ""
        focusedField = .key
    }
}
