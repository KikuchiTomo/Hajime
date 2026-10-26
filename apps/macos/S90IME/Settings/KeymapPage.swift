import AppKit
import S90Domain
import SwiftUI

/// キー設定(R-17)．「状態 | キー | コマンド」の表を一覧し，行を足す・消す・変える．
/// キーは押して記録し，状態とコマンドは選ぶ．コマンド名・キーで絞り込み，ひな形を読み込み，重なった行を知らせる
struct KeymapPage: View {
    @ObservedObject var model: SettingsModel
    @State private var query = ""
    @State private var stateFilter: KeymapState?
    /// 押したキーで絞り込むときのキー
    @State private var keyFilter: KeyStroke?
    @State private var selection = Set<Int>()
    /// キーを記録しているところ．同時に 1 か所だけ
    @State private var recording: RecordingTarget?
    @State private var draft = Draft()
    /// 読み込む前に確かめているひな形
    @State private var pendingPreset: KeymapPreset?
    @State private var confirmsRestore = false

    private typealias Keys = UIStrings.Keys

    /// キーを記録する欄
    enum RecordingTarget: Hashable {
        case row(Int)
        case draft
        case search
    }

    /// 足す前の新しい行
    struct Draft {
        var state = KeymapState.composing
        var stroke: KeyStroke?
        var command = KeymapCommand.commit
    }

    /// 表の行．位置を ID にする(表の順は「下の行を使う」の判断に効くので並べ替えない)
    struct Row: Identifiable {
        let id: Int
        let entry: KeymapEntry
    }

    private var keymap: Keymap { model.settings.keymap }

    private var rows: [Row] {
        keymap.entries.enumerated().map { Row(id: $0.offset, entry: $0.element) }.filter(matches)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            missingWarning
            composer
            table
            footer
        }
        .padding()
        .alert(Keys.loadPresetTitle, isPresented: Binding(get: { pendingPreset != nil }, set: { if !$0 { pendingPreset = nil } }),
               presenting: pendingPreset) { preset in
            Button(Keys.load) { load(preset) }
            Button(Keys.cancel, role: .cancel) {}
        } message: { preset in
            Text(Keys.loadPresetMessage(Keys.label(for: preset)))
        }
        .alert(Keys.restoreTitle, isPresented: $confirmsRestore) {
            Button(Keys.restore, role: .destructive) { load(.standard) }
            Button(Keys.cancel, role: .cancel) {}
        } message: {
            Text(Keys.restoreMessage)
        }
        .onChange(of: stateFilter) { _, state in
            // 状態で絞り込んでいるときは，新しい行もその状態にする
            if let state { setDraftState(state) }
        }
    }

    // MARK: 検索とひな形

    private var toolbar: some View {
        HStack(spacing: 8) {
            TextField(Keys.searchPrompt, text: $query)
                .textFieldStyle(.roundedBorder)
            if recording == .search {
                KeyCapture(onCapture: { stroke in
                    keyFilter = stroke
                    recording = nil
                }, onCancel: { if recording == .search { recording = nil } })
                .frame(width: DesignTokens.Size.Settings.keymapKeyWidth)
                .overlay(Text(Keys.press).font(.caption).foregroundStyle(.secondary).allowsHitTesting(false))
            } else if let keyFilter {
                // 押したキーで絞り込んでいる．押すと絞り込みをやめる
                Button {
                    self.keyFilter = nil
                } label: {
                    Label(keyFilter.label, systemImage: "xmark.circle.fill")
                }
                .controlSize(.small)
                .help(Keys.clearKeyFilter)
            } else {
                Button {
                    recording = .search
                } label: {
                    Label(Keys.searchByKey, systemImage: "keyboard")
                }
                .help(Keys.searchByKeyHelp)
            }
            Picker(Keys.state, selection: $stateFilter) {
                Text(Keys.allStates).tag(KeymapState?.none)
                Divider()
                ForEach(KeymapState.allCases, id: \.self) { Text(Keys.label(for: $0)).tag(KeymapState?.some($0)) }
            }
            .labelsHidden()
            .fixedSize()
            Menu {
                Section(Keys.presetMenu) {
                    ForEach(KeymapPreset.allCases, id: \.self) { preset in
                        Button(Keys.label(for: preset)) { requestLoad(preset) }
                    }
                }
            } label: {
                Text(Keys.currentPreset(KeymapPreset.matching(keymap).map(Keys.label(for:)) ?? Keys.customPreset))
            }
            .fixedSize()
        }
    }

    /// 確定・取り消しのキーが無い状態を知らせる
    @ViewBuilder
    private var missingWarning: some View {
        let missing = keymap.missingEssentials
        if !missing.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(missing.enumerated()), id: \.offset) { _, item in
                        Label(Keys.missing(state: Keys.label(for: item.state), command: Keys.label(for: item.command)),
                              systemImage: "exclamationmark.triangle.fill")
                            .symbolRenderingMode(.multicolor)
                    }
                    Text(Keys.missingNote).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 新しい行

    private var composer: some View {
        GroupBox(Keys.newRow) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    statePicker(selection: Binding(get: { draft.state }, set: setDraftState), command: nil)
                        .frame(width: DesignTokens.Size.Settings.keymapStateWidth)
                    KeyField(stroke: draft.stroke, isRecording: recording == .draft,
                             onRecord: { recording = $0 ? .draft : (recording == .draft ? nil : recording) },
                             onChange: { draft.stroke = $0 })
                        .frame(width: DesignTokens.Size.Settings.keymapKeyWidth)
                    commandPicker(selection: $draft.command, state: draft.state)
                    Button(Keys.add) { addDraft() }
                        .disabled(draft.stroke == nil)
                }
                if let note = draftNote {
                    Text(note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 新しい行と同じ状態・同じキーの行や，文字を打てなくなるキーを知らせる
    private var draftNote: String? {
        guard let stroke = draft.stroke else { return nil }
        if let existing = keymap.entries.last(where: { $0.state == draft.state && $0.stroke == stroke }) {
            return Keys.duplicateWarning(Keys.describe(existing))
        }
        return blocksTyping(KeymapEntry(draft.state, stroke, draft.command)) ? Keys.plainCharacter : nil
    }

    private func setDraftState(_ state: KeymapState) {
        draft.state = state
        if !draft.command.isAvailable(in: state) {
            draft.command = KeymapCommand.allCases.first { $0.isAvailable(in: state) } ?? .commit
        }
    }

    private func addDraft() {
        guard let stroke = draft.stroke else { return }
        let index = keymap.entries.count
        model.update { $0.keymap.entries.append(KeymapEntry(draft.state, stroke, draft.command)) }
        draft.stroke = nil
        // 足した行が絞り込みで隠れないようにする
        if !matches(Row(id: index, entry: KeymapEntry(draft.state, stroke, draft.command))) {
            query = ""
            keyFilter = nil
            stateFilter = nil
        }
        selection = [index]
    }

    // MARK: 表

    private var table: some View {
        Table(rows, selection: $selection) {
            TableColumn(Keys.state) { row in
                statePicker(selection: Binding(get: { row.entry.state }, set: { state in change(row.id) { $0.state = state } }), command: row.entry.command)
                    .opacity(dimming(row))
            }
            .width(DesignTokens.Size.Settings.keymapStateWidth)
            TableColumn(Keys.key) { row in
                KeyField(stroke: row.entry.stroke, isRecording: recording == .row(row.id),
                         onRecord: { recording = $0 ? .row(row.id) : (recording == .row(row.id) ? nil : recording) },
                         onChange: { stroke in change(row.id) { $0.stroke = stroke } })
                    .opacity(dimming(row))
            }
            .width(DesignTokens.Size.Settings.keymapKeyWidth)
            TableColumn(Keys.command) { row in
                commandPicker(selection: Binding(get: { row.entry.command }, set: { command in change(row.id) { $0.command = command } }),
                              state: row.entry.state)
                    .opacity(dimming(row))
            }
            TableColumn("") { row in
                mark(for: row)
            }
            .width(DesignTokens.Size.Settings.keymapMarkWidth)
        }
        .contextMenu(forSelectionType: Int.self) { ids in
            Button(Keys.duplicate) { duplicate(ids) }.disabled(ids.isEmpty)
            Button(Keys.remove, role: .destructive) { remove(ids) }.disabled(ids.isEmpty)
        }
        .onDeleteCommand { remove(selection) }
        .overlay {
            if rows.isEmpty {
                Text(Keys.noMatches).foregroundStyle(.secondary)
            }
        }
    }

    /// 重なって使われない行・文字を打てなくなる行の印
    @ViewBuilder
    private func mark(for row: Row) -> some View {
        switch keymap.overlap(at: row.id) {
        case .hidden(let winners)?:
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .help(Keys.hidden(by: describe(winners)))
                .accessibilityLabel(Keys.hidden(by: describe(winners)))
        case .partlyHidden(let states, let winners)?:
            let text = Keys.partlyHidden(states: states.map(Keys.label(for:)).joined(separator: "・"), by: describe(winners))
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .help(text)
                .accessibilityLabel(text)
        case nil:
            if blocksTyping(row.entry) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
                    .help(Keys.plainCharacter)
                    .accessibilityLabel(Keys.plainCharacter)
            }
        }
    }

    /// 使われない行は薄く見せる(どの行が効いていないかを一目で分かるように)
    private func dimming(_ row: Row) -> Double {
        if case .hidden? = keymap.overlap(at: row.id) { return Self.hiddenOpacity }
        return 1
    }

    /// 使われない行の濃さ(無効の項目と同じくらいの薄さ)
    private static let hiddenOpacity = 0.45

    private func describe(_ indices: [Int]) -> String {
        indices.filter(keymap.entries.indices.contains).map { Keys.describe(keymap.entries[$0]) }.joined(separator: "，")
    }

    /// 修飾キーの無い文字のキーを，文字を打つ状態に置いた行か(その文字を打てなくなる)
    private func blocksTyping(_ entry: KeymapEntry) -> Bool {
        entry.stroke.isPlainCharacter && [.anywhere, .idle, .composing].contains(entry.state)
    }

    // MARK: 状態とコマンドを選ぶ

    /// 状態を選ぶ．command を渡したときは，そのコマンドが効く状態だけを並べる
    private func statePicker(selection: Binding<KeymapState>, command: KeymapCommand?) -> some View {
        Picker(Keys.state, selection: selection) {
            ForEach(KeymapState.allCases.filter { command?.isAvailable(in: $0) ?? true }, id: \.self) {
                Text(Keys.label(for: $0)).tag($0)
            }
        }
        .labelsHidden()
        .accessibilityLabel(Keys.state)
    }

    /// コマンドを選ぶ．状態で効くコマンドだけを，まとまりごとに並べる
    private func commandPicker(selection: Binding<KeymapCommand>, state: KeymapState) -> some View {
        Picker(Keys.command, selection: selection) {
            ForEach(KeymapCommand.Group.allCases, id: \.self) { group in
                let commands = KeymapCommand.allCases.filter { $0.group == group && $0.isAvailable(in: state) }
                if !commands.isEmpty {
                    Section(Keys.label(for: group)) {
                        ForEach(commands, id: \.self) { Text(Keys.label(for: $0)).tag($0) }
                    }
                }
            }
        }
        .labelsHidden()
        .help(Keys.help(for: selection.wrappedValue) ?? Keys.label(for: selection.wrappedValue))
        .accessibilityLabel(Keys.command)
    }

    // MARK: 下の操作

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(Keys.remove) { remove(selection) }
                    .disabled(selection.isEmpty)
                Text(Keys.rowCount(rows.count, keymap.entries.count)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(Keys.restore) { confirmsRestore = true }
                    .disabled(keymap == KeymapPreset.standard.keymap)
            }
            Text(Keys.note).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 変える

    private func matches(_ row: Row) -> Bool {
        if let stateFilter, row.entry.state != stateFilter { return false }
        if let keyFilter, row.entry.stroke != keyFilter { return false }
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return true }
        let texts = [Keys.label(for: row.entry.command), Keys.label(for: row.entry.state), row.entry.stroke.label, row.entry.stroke.notation,
                     Keys.help(for: row.entry.command) ?? ""]
        return texts.contains { $0.localizedCaseInsensitiveContains(words) }
    }

    /// 行を変える．画面を開いたまま同期などで表が変わっていたら何もしない
    private func change(_ index: Int, _ edit: @escaping (inout KeymapEntry) -> Void) {
        model.update { settings in
            guard settings.keymap.entries.indices.contains(index) else { return }
            edit(&settings.keymap.entries[index])
        }
    }

    private func remove(_ indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        model.update { settings in
            for index in indices.sorted(by: >) where settings.keymap.entries.indices.contains(index) {
                settings.keymap.entries.remove(at: index)
            }
        }
        selection = []
    }

    private func duplicate(_ indices: Set<Int>) {
        model.update { settings in
            for index in indices.sorted(by: >) where settings.keymap.entries.indices.contains(index) {
                settings.keymap.entries.insert(settings.keymap.entries[index], at: index + 1)
            }
        }
        selection = []
    }

    /// 利用者が変えた表は，読み込む前に確かめる(変えていなければすぐ読み込む)
    private func requestLoad(_ preset: KeymapPreset) {
        if KeymapPreset.matching(keymap) == nil {
            pendingPreset = preset
        } else {
            load(preset)
        }
    }

    private func load(_ preset: KeymapPreset) {
        model.update { $0.keymap = preset.keymap }
        selection = []
    }
}

/// キーの欄．押すと記録を始め，次に押したキーを入れる．押しにくいキー(Windows のキーなど)と修飾キーはメニューから選べる
struct KeyField: View {
    let stroke: KeyStroke?
    let isRecording: Bool
    /// 記録を始める(true)・やめる(false)
    let onRecord: (Bool) -> Void
    let onChange: (KeyStroke) -> Void

    private typealias Keys = UIStrings.Keys

    var body: some View {
        HStack(spacing: 2) {
            if isRecording {
                KeyCapture(onCapture: { stroke in
                    onRecord(false)
                    if let stroke { onChange(stroke) }
                }, onCancel: { onRecord(false) })
                .overlay(Text(Keys.press).font(.caption).foregroundStyle(.secondary).allowsHitTesting(false))
                Button {
                    onRecord(false)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(Keys.stopRecording)
                .accessibilityLabel(Keys.stopRecording)
            } else {
                Button {
                    onRecord(true)
                } label: {
                    Text(stroke?.label ?? Keys.record)
                        .foregroundStyle(stroke == nil ? .secondary : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(Keys.record)
                .accessibilityLabel(stroke.map { "\(Keys.key) \($0.label)" } ?? Keys.record)
                menu
            }
        }
    }

    /// 押して記録しにくいキーと，修飾キーを選ぶメニュー
    private var menu: some View {
        Menu {
            Section(Keys.specialKeys) {
                ForEach(Keys.specialKeyChoices, id: \.self) { key in
                    Button(KeyStroke(key).label) { onChange(replacing(key)) }
                }
            }
            Menu(Keys.functionKeys) {
                ForEach(Array(KeyStroke.functionKeys), id: \.self) { number in
                    Button("F\(number)") { onChange(replacing(.function(number))) }
                }
            }
            if let stroke {
                Section(Keys.modifiers) {
                    Toggle(Keys.control, isOn: modifier(\.control, of: stroke))
                    Toggle(Keys.option, isOn: modifier(\.option, of: stroke))
                    Toggle(Keys.shift, isOn: modifier(\.shift, of: stroke))
                    Toggle(Keys.commandKey, isOn: modifier(\.command, of: stroke))
                }
            }
        } label: {
            Image(systemName: "chevron.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Keys.chooseKey)
        .accessibilityLabel(Keys.chooseKey)
    }

    /// 今の修飾キーのまま，キーだけを変える
    private func replacing(_ key: KeyStroke.Key) -> KeyStroke {
        var next = stroke ?? KeyStroke(key)
        next.key = key
        return next
    }

    private func modifier(_ keyPath: WritableKeyPath<KeyStroke, Bool>, of stroke: KeyStroke) -> Binding<Bool> {
        Binding(get: { stroke[keyPath: keyPath] }, set: { value in
            var next = stroke
            next[keyPath: keyPath] = value
            onChange(next)
        })
    }
}

/// 次に押したキーを受け取る．⌘ の組み合わせもメニューより先に受け取る．
/// ほかを押して離れたら記録をやめる(onCancel)．修飾キーだけや表に書けないキーは受け取らずに待つ
struct KeyCapture: NSViewRepresentable {
    let onCapture: (KeyStroke?) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> CaptureView {
        let view = CaptureView()
        view.onCapture = onCapture
        view.onCancel = onCancel
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: CaptureView, context: Context) {
        view.onCapture = onCapture
        view.onCancel = onCancel
    }

    final class CaptureView: NSView {
        var onCapture: ((KeyStroke?) -> Void)?
        var onCancel: (() -> Void)?
        private var finished = false
        override var acceptsFirstResponder: Bool { true }
        override var intrinsicContentSize: NSSize {
            NSSize(width: NSView.noIntrinsicMetric, height: DesignTokens.Size.Settings.keymapCaptureHeight)
        }

        override func keyDown(with event: NSEvent) {
            guard !finished, let key = NSEventKeyTranslator.translate(event), let stroke = KeyStroke(key) else { return }
            finished = true
            onCapture?(stroke)
        }

        /// ⌘ の組み合わせはメニューのショートカットより先に受け取る(⌘W で窓を閉じずに記録する)
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, event.type == .keyDown else { return false }
            keyDown(with: event)
            return true
        }

        override func resignFirstResponder() -> Bool {
            if !finished {
                finished = true
                // 表示を変えている途中に呼ばれることがあるので，次の回で知らせる
                let cancel = onCancel
                DispatchQueue.main.async { cancel?() }
            }
            return super.resignFirstResponder()
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 5, yRadius: 5).fill()
        }
    }
}
