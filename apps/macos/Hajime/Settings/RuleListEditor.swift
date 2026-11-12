import AppKit
import HajimeDomain
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

/// 入力欄に書き方(TextTemplate)を入れる手助け(R-21・R-22)．欄の右の「{ }」のボタンで，欄の下に書き方のチップを開け閉めする．
/// 欄で「{」を打つと開き，続けて打った文字でチップを絞り込む．チップを押すと入力位置に入る(打ちかけの書き方は置き換える)
struct TemplateAssist {
    enum Target { case key, value }

    var reference: TemplateReference
    /// 変換マクロの {text} と {reading} に入れる語と読み(単語では nil)
    var sample: (text: String, reading: String)?
    /// 書き方を入れる欄(単語は右の欄，変換マクロは左の欄)
    var target: Target
    /// チップを開いているか．ページごとに覚える
    var isOpen: Binding<Bool>
}

/// 入力欄に入れたときの結果と，置き換えられない部分(書き方の誤り)
struct RuleResult: Equatable {
    var text: String
    var problems: [String] = []
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
    /// 外から入力欄に入れる値．入れたら nil に戻す
    var prefill: Binding<RuleDraft?>?
    /// 書き方を入れる手助け(単語・変換マクロ)．nil なら出さない(書き方を値にしない設定のときも)
    var templateAssist: TemplateAssist?
    /// 入力欄の文字(左と右)を入れたときの結果．入力欄のすぐ下に出す(書き方を入れた単語・変換マクロの形)．無ければ nil
    var draftResult: ((_ key: String, _ value: String) -> RuleResult?)?
    /// 一覧の行を入れたときの結果．左の列の右の「結果」の列に出す(変換マクロの形)．無ければ nil
    var itemResult: ((RuleItem) -> String?)?

    @State private var key = ""
    @State private var value = ""
    @State private var kind: String
    @State private var note = ""
    @State private var editing: RuleItem?
    @State private var query = ""
    @State private var selection = Set<RuleItem.ID>()
    @State private var sortOrder: [KeyPathComparator<RuleItem>] = []
    @FocusState private var focusedField: Field?
    /// 書き方を入れる欄で最後に選んでいた範囲(UTF-16)．欄を離れても，チップを押したときはここに入れる
    @State private var templateSelection: NSRange?
    /// キーボードで選んでいるチップ(書き方)
    @FocusState private var focusedChip: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Field { case key, value, note }

    init(labels: Labels, items: [RuleItem], problem: @escaping (_ key: String, _ value: String) -> String?,
         save: @escaping (_ key: String, _ value: String, _ editing: RuleItem?) -> Bool, remove: @escaping (_ items: [RuleItem]) -> Void,
         setEnabled: ((RuleItem, Bool) -> Void)? = nil, importFile: (() -> Void)? = nil, exportFile: (() -> Void)? = nil,
         keysAreUnique: Bool = true, tableHeight: CGFloat = DesignTokens.Size.Settings.ruleTableHeight) {
        self.init(labels: labels, items: items, kinds: nil, problem: problem, save: { key, value, _, _, editing in save(key, value, editing) },
                  remove: remove, setEnabled: setEnabled, importFile: importFile, exportFile: exportFile, keysAreUnique: keysAreUnique,
                  tableHeight: tableHeight)
    }

    init(labels: Labels, items: [RuleItem], kinds: RuleKinds?, problem: @escaping (_ key: String, _ value: String) -> String?,
         save: @escaping (_ key: String, _ value: String, _ kind: String?, _ note: String?, _ editing: RuleItem?) -> Bool,
         remove: @escaping (_ items: [RuleItem]) -> Void, setEnabled: ((RuleItem, Bool) -> Void)? = nil, importFile: (() -> Void)? = nil,
         exportFile: (() -> Void)? = nil, keysAreUnique: Bool = true, tableHeight: CGFloat = DesignTokens.Size.Settings.ruleTableHeight) {
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
    }

    /// 外から入力欄に値を入れられるようにした部品(単語の登録)
    func prefilled(_ draft: Binding<RuleDraft?>) -> Self {
        var copy = self
        copy.prefill = draft
        return copy
    }

    /// 入力欄に書き方を入れる手助けを付けた部品(単語・変換マクロ)
    func assistingTemplates(_ assist: TemplateAssist?) -> Self {
        var copy = self
        copy.templateAssist = assist
        return copy
    }

    /// 入力欄の文字を入れたときの結果を，入力欄のすぐ下に出す部品(書き方を試す)
    func showingResult(_ result: @escaping (_ key: String, _ value: String) -> RuleResult?) -> Self {
        var copy = self
        copy.draftResult = result
        return copy
    }

    /// 一覧の行ごとに，入れたときの結果を「結果」の列に出す部品(変換マクロの形)
    func showingItemResults(_ result: @escaping (RuleItem) -> String?) -> Self {
        var copy = self
        copy.itemResult = result
        return copy
    }

    private var hasValue: Bool { labels.value != nil }
    /// 右の列に，値の代わりに行の結果を出すか(値の無い一覧だけ)
    private var showsResults: Bool { !hasValue && itemResult != nil }
    /// 左の列の右にもう 1 つ列があるか．あれば左の列の幅を決めて，右の列の左の端をそろえる
    private var hasSecondColumn: Bool { hasValue || showsResults }

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
            // 入れたときの結果は，結果を求めた欄(右の欄．無ければ左の欄)の左端にそろえて，そのすぐ下に出す
            VStack(alignment: .resultField, spacing: DesignTokens.Size.Settings.ruleNoteFieldGap) {
                editor
                if let result = shownDraftResult {
                    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Size.Space.group) {
                        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Size.Space.inline) {
                            Image(systemName: "arrow.turn.down.right").accessibilityHidden(true)
                            Text(result.text).textSelection(.enabled)
                        }
                        .foregroundStyle(.secondary)
                        // 置き換えられない部分(書き方の誤り)を，その書き方のまま印を付けて見せる
                        if !result.problems.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Size.Space.inline) {
                                Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                                Text(result.problems.joined(separator: " ")).monospaced()
                            }
                            .foregroundStyle(.orange)
                        }
                    }
                    .alignmentGuide(.resultField) { $0[.leading] }
                }
            }
            // 書き方のチップ．欄(と結果)のすぐ下に開く
            if let templateAssist, templateAssist.isOpen.wrappedValue {
                TemplatePalette(reference: templateAssist.reference, sample: templateAssist.sample,
                                matches: templateAssist.reference.matches(for: templateTyping), focus: $focusedChip) { item, kind in
                    insertTemplate(item, kind: kind)
                }
                // 欄と結果(上)・コメントの欄(下)とのあいだを section にし，入力の行とは別のまとまりに見せる
                .padding(.vertical, DesignTokens.Size.Space.section - DesignTokens.Size.Settings.ruleNoteFieldGap)
                .transition(.opacity)
            }
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
        columns.append(.init(title: labels.key, width: hasSecondColumn ? DesignTokens.Size.Settings.ruleKeyColumnWidth : nil,
                             sort: { toggleSort(\.key) }, ascending: sortDirection(\.key)))
        if showsResults {
            columns.append(.init(title: UIStrings.RuleList.result))
        }
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
                .resultFieldGuide(!hasValue)
                .focused($focusedField, equals: .key)
                .disabled(editing?.isKeyFixed ?? false)
                .onSubmit { hasValue ? (focusedField = .value) : commit() }
            if templateAssist?.target == .key { templateButton }
            if let valueLabel = labels.value {
                Image(systemName: "arrow.right").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(valueLabel, text: $value, prompt: Text(labels.valuePrompt ?? valueLabel))
                    .textFieldStyle(.roundedBorder)
                    .alignmentGuide(.resultField) { $0[.leading] }
                    .focused($focusedField, equals: .value)
                    .onSubmit(commit)
                if templateAssist?.target == .value { templateButton }
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
                // チップを開いているあいだの Esc は，チップを閉じるほうに使う
                Button(UIStrings.Settings.cancel, action: clear)
                    .keyboardShortcut(templateAssist?.isOpen.wrappedValue == true ? nil : .cancelAction)
            }
            Button(editing == nil ? UIStrings.Settings.add : UIStrings.RuleList.update, action: commit)
                .disabled(!isFilled || message?.isProblem == true)
        }
        .labelsHidden()
        // 書き方のボタンを欄と同じ高さに伸ばす
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: applyPrefill)
        .onChange(of: prefill?.wrappedValue) { _, _ in applyPrefill() }
        // 欄で「{」を打って書き方を打ち始めたら，チップを開く
        .onChange(of: templateTyping != nil) { _, typing in
            if typing { setTemplatesOpen(true) }
        }
        // 書き方を入れる欄の入力位置を覚える．文字を打ったときは，欄の文字が変わったあとで読む(打った途中の通知は欄の文字とずれる)．
        // 欄を離れるときに編集の部品が空になる通知は，欄の文字と合わないので受け取らない(離れたあとも入力位置を残す)
        .onReceive(NotificationCenter.default.publisher(for: NSTextView.didChangeSelectionNotification)) { notification in
            guard let editor = notification.object as? NSTextView, editor.string == templateText else { return }
            readTemplateSelection(from: editor)
        }
        .onChange(of: templateText) { _, _ in readTemplateSelection(from: nil) }
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
            // 長い形は列の中で「…」で切る
            Text(item.key).monospaced().lineLimit(1).truncationMode(.tail)
                .foregroundStyle(item.isEnabled ? .primary : .secondary)
        }
        // 右に値や結果の列があるときは，表の外の見出し(FormTableHeader)とそろえるため幅を決める
        .width(min: hasSecondColumn ? DesignTokens.Size.Settings.ruleKeyColumnWidth : 80,
               ideal: hasSecondColumn ? DesignTokens.Size.Settings.ruleKeyColumnWidth : 400,
               max: hasSecondColumn ? DesignTokens.Size.Settings.ruleKeyColumnWidth : .infinity)
    }

    private var valueColumn: some TableColumnContent<RuleItem, KeyPathComparator<RuleItem>> {
        TableColumn(labels.value ?? "", value: \.value) { item in
            HStack {
                if showsResults {
                    // 行の形を試す語と読みに当てた結果．形の列とは別に「…」で切る
                    Text(itemResult?(item) ?? "").lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary)
                } else {
                    Text(item.value).foregroundStyle(item.isEnabled ? .primary : .secondary)
                }
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

    // MARK: 書き方を入れる手助け

    /// 書き方を入れる欄
    private var templateField: Field? {
        switch templateAssist?.target {
        case .key: .key
        case .value: .value
        case nil: nil
        }
    }

    private var templateText: String {
        templateAssist?.target == .key ? key : value
    }

    /// 書き方を入れる欄の入力位置(選んでいる範囲)．まだ選んでいなければ末尾
    private var templateRange: Range<Int> {
        let count = templateText.utf16.count
        guard let selection = templateSelection, selection.location != NSNotFound else { return count..<count }
        let lower = min(selection.location, count)
        return lower..<min(selection.location + selection.length, count)
    }

    /// 入れたときの結果．打っている途中の書き方(入力位置の前の閉じていない `{da`)は，誤りの印を付けない
    private var shownDraftResult: RuleResult? {
        guard var result = draftResult?(key, value) else { return nil }
        if templateAssist != nil, let typing = TextTemplate.openPlaceholder(before: templatePrefix) {
            result.problems.removeAll { $0 == typing }
        }
        return result
    }

    /// 書き方を入れる欄を編集しているなら，編集の部品(欄の編集を受け持つ NSTextView)から入力位置を読む
    private func readTemplateSelection(from editor: NSTextView?) {
        guard let field = templateField, focusedField == field,
              let editor = editor ?? (NSApp.keyWindow?.firstResponder as? NSTextView), editor.isFieldEditor, editor.string == templateText else { return }
        templateSelection = editor.selectedRange()
    }

    /// 書き方を入れる欄の，入力位置より前の文字
    private var templatePrefix: String {
        String(decoding: Array(templateText.utf16)[..<templateRange.lowerBound], as: UTF16.self)
    }

    /// 入力位置の前で打ちかけの書き方(チップの絞り込みと，「{」で開くのに使う)
    private var templateTyping: TextTemplate.Typing? {
        guard templateAssist != nil else { return nil }
        return TextTemplate.typing(before: templatePrefix)
    }

    /// 欄の右の「{ }」のボタン．押すとチップを開け閉めする．開いているあいだは Esc でも閉じる
    private var templateButton: some View {
        Toggle(isOn: Binding(get: { templateAssist?.isOpen.wrappedValue ?? false }, set: { setTemplatesOpen($0) })) {
            Image(systemName: "curlybraces")
                .accessibilityLabel(UIStrings.Templates.button)
        }
        .toggleStyle(FieldAccessoryToggleStyle())
        .help(UIStrings.Templates.buttonHelp)
        .keyboardShortcut(templateAssist?.isOpen.wrappedValue == true ? .cancelAction : nil)
    }

    /// チップを開け閉めする．動きを減らす設定ではすぐ切り替える．チップを選んでいたときに閉じたら，書き方を入れる欄に戻す
    private func setTemplatesOpen(_ open: Bool) {
        guard let assist = templateAssist, assist.isOpen.wrappedValue != open else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: DesignTokens.Motion.Settings.disclosure / 1000)) {
            assist.isOpen.wrappedValue = open
        }
        if !open, focusedChip != nil { focusedField = templateField }
    }

    /// 押したチップを入力位置に入れる．欄を編集中なら欄の編集として入れ(取り消しで戻せる)，そうでなければ文字を書き換える．
    /// ポインターで押したときは欄に入力位置を戻し，続けて打てるようにする．キーボードで押したときはチップに残る
    private func insertTemplate(_ item: TemplateReference.Item, kind: TemplateReference.Kind) {
        guard let field = templateField else { return }
        let byKeyboard = focusedChip != nil
        let edit = TemplateReference.insertion(of: item, kind: kind, in: templateText, selection: templateRange)
        let range = NSRange(location: edit.range.lowerBound, length: edit.range.count)
        let caret = edit.range.lowerBound + edit.replacement.utf16.count
        if focusedField == field, let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
            editor.insertText(edit.replacement, replacementRange: range)
            return
        }
        let replaced = (templateText as NSString).replacingCharacters(in: range, with: edit.replacement)
        if field == .key { key = replaced } else { value = replaced }
        templateSelection = NSRange(location: caret, length: 0)
        guard !byKeyboard else { return }
        focusedField = field
        // 欄は選ばれると中身をすべて選ぶので，入力位置は次の回で置く
        DispatchQueue.main.async {
            guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor else { return }
            editor.setSelectedRange(NSRange(location: caret, length: 0))
        }
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

private extension HorizontalAlignment {
    /// 入れたときの結果を，結果を求めた欄の左端にそろえる
    enum ResultField: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[.leading] }
    }

    static let resultField = HorizontalAlignment(ResultField.self)
}

private extension View {
    /// 入れたときの結果をこの欄の左端にそろえる(enabled のときだけ)
    @ViewBuilder
    func resultFieldGuide(_ enabled: Bool) -> some View {
        if enabled {
            alignmentGuide(.resultField) { $0[.leading] }
        } else {
            self
        }
    }
}
