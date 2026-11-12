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
    /// 既定から変えた・足したことを示す短いタグ(「変更あり」「追加」)
    var badge: String?
    var removal = Removal.remove
    /// 左の欄を書き換えられないか(既定の決まりの入力)
    var isKeyFixed = false
    /// 種類(RuleKinds)を選ぶ一覧での種類の ID と，表に出す名前
    var kind: String?
    var kindTitle = ""
    /// 添え書きの欄(Labels.note)のある一覧での添え書き(ユーザー辞書のコメント)．空なら無し
    var note = ""
}

/// 外から入力欄に入れる左と右の値(単語の登録で，選んでいた語と読みを入れる)
struct RuleDraft: Equatable {
    var key: String
    var value: String
}

/// 行ごとに選ぶ種類(ユーザー辞書の品詞)．入力欄の右のポップアップで選び，表の右の列に出す
struct RuleKinds {
    struct Option: Hashable {
        var id: String
        var title: String
    }

    /// ポップアップの中の組．title があれば組の見出しにする
    struct Group: Hashable {
        var title: String?
        var options: [Option]
    }

    var label: String
    var groups: [Group]
    /// 新しく足すときに選んでおく種類
    var defaultID: String
    /// 選んだ種類について，入力欄の下に出す説明(無ければ nil)
    var note: (String) -> String? = { _ in nil }
}

/// 決まりの一覧を編集する部品．補正の置き換え・直さない語・ローマ字・ユーザー辞書・記号で共通に使う．
/// ユーザー辞書では行ごとに種類(品詞)も選ぶ(RuleKinds)．
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
        /// 一覧が空のときに表の中に出す文
        var empty: String
        /// 空でもよい添え書きの欄(ユーザー辞書のコメント)．nil なら出さない．入力欄の下の行に置き，表の右の列に出す
        var note: String?
        var notePrompt: String?
    }

    let labels: Labels
    let items: [RuleItem]
    /// 行ごとに種類を選ぶ一覧なら渡す(値の列のある一覧だけ)
    let kinds: RuleKinds?
    /// 足す前に確かめる．問題があれば利用者に見せる文を返す
    let problem: (_ key: String, _ value: String) -> String?
    /// 保存する．kind は選んだ種類(kinds が無ければ nil)，note は添え書き(欄が無ければ nil)，editing は書き換える行(新しく足すときは nil)．
    /// 保存できたら true(入力欄を空にする)
    let save: (_ key: String, _ value: String, _ kind: String?, _ note: String?, _ editing: RuleItem?) -> Bool
    let remove: (_ items: [RuleItem]) -> Void
    /// 行ごとにオン・オフできる一覧なら渡す
    let setEnabled: ((RuleItem, Bool) -> Void)?
    let importFile: (() -> Void)?
    let exportFile: (() -> Void)?
    /// 左が重ならない一覧か．重なってよい一覧(ユーザー辞書の読み)では，左と右の両方が同じ行だけを重なりとみなす
    let keysAreUnique: Bool
    let tableHeight: CGFloat
    /// 上の欄の左に打っている文字が変わるたびに知らせる(変換マクロの書いている途中の形を試すため)
    let draftChanged: ((String) -> Void)?
    /// 外から入力欄に入れる値．入れたら nil に戻す
    var prefill: Binding<RuleDraft?>?

    @State private var key = ""
    @State private var value = ""
    @State private var kind: String
    @State private var note = ""
    @State private var editing: RuleItem?
    @State private var query = ""
    @State private var selection = Set<RuleItem.ID>()
    @State private var sortOrder: [KeyPathComparator<RuleItem>] = []
    @FocusState private var focusedField: Field?

    private enum Field { case key, value, note }

    init(labels: Labels, items: [RuleItem], problem: @escaping (_ key: String, _ value: String) -> String?,
         save: @escaping (_ key: String, _ value: String, _ editing: RuleItem?) -> Bool, remove: @escaping (_ items: [RuleItem]) -> Void,
         setEnabled: ((RuleItem, Bool) -> Void)? = nil, importFile: (() -> Void)? = nil, exportFile: (() -> Void)? = nil,
         keysAreUnique: Bool = true, tableHeight: CGFloat = DesignTokens.Size.Settings.ruleTableHeight,
         draftChanged: ((String) -> Void)? = nil) {
        self.init(labels: labels, items: items, kinds: nil, problem: problem, save: { key, value, _, _, editing in save(key, value, editing) },
                  remove: remove, setEnabled: setEnabled, importFile: importFile, exportFile: exportFile, keysAreUnique: keysAreUnique,
                  tableHeight: tableHeight, draftChanged: draftChanged)
    }

    init(labels: Labels, items: [RuleItem], kinds: RuleKinds?, problem: @escaping (_ key: String, _ value: String) -> String?,
         save: @escaping (_ key: String, _ value: String, _ kind: String?, _ note: String?, _ editing: RuleItem?) -> Bool,
         remove: @escaping (_ items: [RuleItem]) -> Void, setEnabled: ((RuleItem, Bool) -> Void)? = nil, importFile: (() -> Void)? = nil,
         exportFile: (() -> Void)? = nil, keysAreUnique: Bool = true, tableHeight: CGFloat = DesignTokens.Size.Settings.ruleTableHeight,
         draftChanged: ((String) -> Void)? = nil) {
        self.labels = labels
        self.items = items
        self.kinds = labels.value == nil ? nil : kinds
        _kind = State(initialValue: kinds?.defaultID ?? "")
        self.problem = problem
        self.save = save
        self.remove = remove
        self.setEnabled = setEnabled
        self.importFile = importFile
        self.exportFile = exportFile
        self.keysAreUnique = keysAreUnique
        self.tableHeight = tableHeight
        self.draftChanged = draftChanged
    }

    /// 外から入力欄に値を入れられるようにした部品(単語の登録)
    func prefilled(_ draft: Binding<RuleDraft?>) -> Self {
        var copy = self
        copy.prefill = draft
        return copy
    }

    private var hasValue: Bool { labels.value != nil }

    private var trimmedKey: String { key.trimmingCharacters(in: .whitespaces) }
    private var trimmedValue: String { value.trimmingCharacters(in: .whitespaces) }
    private var trimmedNote: String { note.trimmingCharacters(in: .whitespaces) }
    private var hasNote: Bool { labels.value != nil && labels.note != nil }
    private var isFilled: Bool { !trimmedKey.isEmpty && (!hasValue || !trimmedValue.isEmpty) }

    /// 入力欄の下に出す文．形が合わなければ理由，同じ入力の行があれば上書きすること
    private var message: (text: String, isProblem: Bool)? {
        guard isFilled else { return nil }
        if let problem = problem(trimmedKey, trimmedValue) { return (problem, true) }
        let others = items.filter { $0.id != editing?.id }
        if keysAreUnique {
            if others.contains(where: { $0.key == trimmedKey }) { return (UIStrings.RuleList.overwrites(trimmedKey), false) }
        } else if let same = others.first(where: { $0.key == trimmedKey && $0.value == trimmedValue }) {
            // 種類か添え書きだけが違えば，その行の種類と添え書きを書き換える
            if (kinds != nil && same.kind != kind) || (hasNote && same.note != trimmedNote) { return (UIStrings.RuleList.changesKind, false) }
            return (UIStrings.RuleList.alreadyRegistered, true)
        }
        return nil
    }

    /// 選んだ種類の説明．形の問題や重なりを知らせているときは出さない
    private var kindNote: String? {
        guard message == nil else { return nil }
        return kinds?.note(kind)
    }

    private var shownItems: [RuleItem] {
        var result = items
        if !query.isEmpty {
            result = result.filter {
                $0.key.localizedCaseInsensitiveContains(query) || $0.value.localizedCaseInsensitiveContains(query) || $0.kindTitle.localizedCaseInsensitiveContains(query)
                    || $0.note.localizedCaseInsensitiveContains(query)
            }
        }
        if !sortOrder.isEmpty { result.sort(using: sortOrder) }
        return result
    }

    var body: some View {
        // 添え書きの欄は，入力の行と同じまとまり(Form の 1 行)に置き，あいだに区切りの線を入れない
        VStack(alignment: .leading, spacing: DesignTokens.Size.Settings.ruleNoteFieldGap) {
            editor
            if hasNote, let noteLabel = labels.note {
                TextField(noteLabel, text: $note, prompt: Text(labels.notePrompt ?? noteLabel))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .focused($focusedField, equals: .note)
                    .onSubmit(commit)
            }
        }
        if let message {
            Label(message.text, systemImage: message.isProblem ? "exclamationmark.triangle.fill" : "info.circle")
                .font(.caption)
                .foregroundStyle(message.isProblem ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
        }
        if let kindNote {
            Label(kindNote, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
        }
        header
        table
        footer
    }

    /// 列の見出し(表の外に描く．FormTableHeader)．読み・入力と値の列は，押すと並べ替える
    private var header: some View {
        var columns: [FormTableHeader.Column] = []
        if setEnabled != nil {
            columns.append(.init(title: UIStrings.RuleList.enabled, width: DesignTokens.Size.Settings.ruleCheckColumnWidth))
        }
        columns.append(.init(title: labels.key, width: hasValue ? DesignTokens.Size.Settings.ruleKeyColumnWidth : nil,
                             sort: { toggleSort(\.key) }, ascending: sortDirection(\.key)))
        if let valueLabel = labels.value {
            columns.append(.init(title: valueLabel, width: kinds == nil ? nil : DesignTokens.Size.Settings.ruleValueColumnWidth,
                                 sort: { toggleSort(\.value) }, ascending: sortDirection(\.value)))
        }
        if let kinds {
            columns.append(.init(title: kinds.label, width: hasNote ? DesignTokens.Size.Settings.ruleKindColumnWidth : nil,
                                 sort: { toggleSort(\.kindTitle) }, ascending: sortDirection(\.kindTitle)))
        }
        if hasNote, let noteLabel = labels.note {
            columns.append(.init(title: noteLabel, sort: { toggleSort(\.note) }, ascending: sortDirection(\.note)))
        }
        return FormTableHeader(columns: columns)
    }

    /// 同じ列を押すたびに昇順と降順を入れ替える．別の列を押せばその列の昇順にする
    private func toggleSort(_ keyPath: KeyPath<RuleItem, String>) {
        if var current = sortOrder.first, current.keyPath == keyPath {
            current.order = current.order == .forward ? .reverse : .forward
            sortOrder = [current]
        } else {
            sortOrder = [KeyPathComparator(keyPath)]
        }
    }

    private func sortDirection(_ keyPath: KeyPath<RuleItem, String>) -> Bool? {
        guard let current = sortOrder.first, current.keyPath == keyPath else { return nil }
        return current.order == .forward
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
            if let kinds {
                Picker(kinds.label, selection: $kind) {
                    ForEach(kinds.groups, id: \.self) { group in
                        Section {
                            ForEach(group.options, id: \.id) { Text($0.title).tag($0.id) }
                        } header: {
                            if let title = group.title { Text(title) }
                        }
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            if editing != nil {
                Button(UIStrings.Settings.cancel, action: clear)
                    .keyboardShortcut(.cancelAction)
            }
            Button(editing == nil ? UIStrings.Settings.add : UIStrings.RuleList.update, action: commit)
                .disabled(!isFilled || message?.isProblem == true)
        }
        .labelsHidden()
        .onChange(of: key) { _, typed in draftChanged?(typed) }
        .onAppear(perform: applyPrefill)
        .onChange(of: prefill?.wrappedValue) { _, _ in applyPrefill() }
    }

    /// 外から渡された値を入力欄に入れる．読み(左)が空なら左の欄に，あれば右の欄に入力位置を置く
    private func applyPrefill() {
        guard let draft = prefill?.wrappedValue else { return }
        clear()
        key = draft.key
        value = draft.value
        focusedField = draft.key.isEmpty ? .key : .value
        prefill?.wrappedValue = nil
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
        } else if kinds != nil, hasNote {
            decorated(Table(shownItems, selection: $selection, sortOrder: $sortOrder) {
                keyColumn
                valueColumn
                kindColumn
                noteColumn
            })
        } else if kinds != nil {
            decorated(Table(shownItems, selection: $selection, sortOrder: $sortOrder) {
                keyColumn
                valueColumn
                kindColumn
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
        // 右に値の列があるときは，表の外の見出し(FormTableHeader)とそろえるため幅を決める
        .width(min: hasValue ? DesignTokens.Size.Settings.ruleKeyColumnWidth : 80,
               ideal: hasValue ? DesignTokens.Size.Settings.ruleKeyColumnWidth : 400,
               max: hasValue ? DesignTokens.Size.Settings.ruleKeyColumnWidth : .infinity)
    }

    private var valueColumn: some TableColumnContent<RuleItem, KeyPathComparator<RuleItem>> {
        TableColumn(labels.value ?? "", value: \.value) { item in
            HStack {
                Text(item.value).foregroundStyle(item.isEnabled ? .primary : .secondary)
                Spacer()
                // 既定から変えた・足したことを示すタグ
                if let badge = item.badge {
                    Text(badge).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        // 最後の列は表の幅いっぱいに広がるので，小さめにしておく(大きいと右にはみ出す)．
        // 右に種類の列があるときは，表の外の見出し(FormTableHeader)とそろえるため幅を決める
        .width(min: kinds == nil ? 120 : DesignTokens.Size.Settings.ruleValueColumnWidth,
               ideal: kinds == nil ? 240 : DesignTokens.Size.Settings.ruleValueColumnWidth,
               max: kinds == nil ? .infinity : DesignTokens.Size.Settings.ruleValueColumnWidth)
    }

    private var kindColumn: some TableColumnContent<RuleItem, KeyPathComparator<RuleItem>> {
        TableColumn(kinds?.label ?? "", value: \.kindTitle) { item in
            Text(item.kindTitle).lineLimit(1).foregroundStyle(.secondary)
        }
        // 右に添え書きの列があるときは，表の外の見出しとそろえるため幅を決める
        .width(min: hasNote ? DesignTokens.Size.Settings.ruleKindColumnWidth : 80,
               ideal: hasNote ? DesignTokens.Size.Settings.ruleKindColumnWidth : 120,
               max: hasNote ? DesignTokens.Size.Settings.ruleKindColumnWidth : .infinity)
    }

    private var noteColumn: some TableColumnContent<RuleItem, KeyPathComparator<RuleItem>> {
        TableColumn(labels.note ?? "", value: \.note) { item in
            Text(item.note).lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary)
        }
        .width(min: 80, ideal: 120)
    }

    /// 表に共通の操作(ダブルクリックで編集，右クリック，Delete キーで削除，空のときの案内)．
    /// Form の中でも表の中でスクロールできるよう，FormTableHost に入れる．列の見出しは表の外に描く(header)
    private func decorated(_ table: some View) -> some View {
        FormTableHost {
            table
                .tableColumnHeaders(.hidden)
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
        }
        .frame(height: tableHeight)
    }

    @ViewBuilder
    private var emptyState: some View {
        if items.isEmpty {
            EmptyListLabel(text: labels.empty)
        } else if shownItems.isEmpty {
            EmptyListLabel(text: UIStrings.RuleList.noMatches)
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
        if let kinds { kind = item.kind ?? kinds.defaultID }
        note = item.note
        focusedField = hasValue ? .value : .key
    }

    private func commit() {
        guard isFilled, message?.isProblem != true else { return }
        if save(trimmedKey, trimmedValue, kinds == nil ? nil : kind, hasNote ? trimmedNote : nil, editing) { clear() }
    }

    private func clear() {
        editing = nil
        key = ""
        value = ""
        if let kinds { kind = kinds.defaultID }
        note = ""
        focusedField = .key
    }
}
