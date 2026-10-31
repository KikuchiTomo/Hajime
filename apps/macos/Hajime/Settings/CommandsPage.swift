import AppKit
import HajimeDomain
import SwiftUI

/// 読みで呼び出すコマンド(R-22)と，変換マクロ(R-18)
struct CommandsPage: View {
    @ObservedObject var model: SettingsModel
    let bookmarks: CommandBookmarks?
    @State private var editing: CommandDraft?
    @State private var selection = Set<LauncherCommand.ID>()

    var body: some View {
        Form {
            Section {
                ResettableToggle(model: model, title: UIStrings.Extras.launcherCommands, keyPath: \.launcherCommands)
                commandTable
                HStack {
                    Button(UIStrings.Extras.addCommand) { editing = CommandDraft() }
                        .disabled(model.settings.commands.count >= DefaultSettings.maximumCommands)
                    Button(UIStrings.Extras.editCommand) {
                        if let id = selection.first, let command = model.settings.commands.first(where: { $0.id == id }) { editing = CommandDraft(command) }
                    }
                    .disabled(selection.count != 1)
                    Button(UIStrings.Extras.removeCommand) { removeSelected() }
                        .disabled(selection.isEmpty)
                    Spacer()
                }
            } header: {
                Text(UIStrings.Extras.commandsSection)
            } footer: {
                Text(UIStrings.Extras.commandsNote).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                ResettableToggle(model: model, title: UIStrings.Extras.conversionMacros, keyPath: \.conversionMacros)
                RuleListEditor(
                    labels: .init(key: UIStrings.Extras.macroPattern, value: nil, empty: UIStrings.Extras.macrosEmpty),
                    items: model.settings.macros.map { RuleItem(id: $0.id, key: $0.pattern, value: "", isEnabled: $0.isEnabled) },
                    problem: { pattern, _ in ConversionMacro(pattern: pattern).isValid ? nil : UIStrings.Extras.invalidMacro },
                    save: { pattern, _, editing in saveMacro(pattern: pattern, replacing: editing?.id) },
                    remove: { items in
                        let ids = Set(items.map(\.id))
                        model.update { $0.macros.removeAll { ids.contains($0.id) } }
                    },
                    setEnabled: { item, enabled in
                        model.update { settings in
                            if let index = settings.macros.firstIndex(where: { $0.id == item.id }) { settings.macros[index].isEnabled = enabled }
                        }
                    }
                )
            } header: {
                Text(UIStrings.Extras.macrosSection)
            } footer: {
                Text(UIStrings.Extras.macrosNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $editing) { draft in
            CommandEditor(draft: draft, bookmarks: bookmarks) { command in
                saveCommand(command)
            }
        }
    }

    private var commandTable: some View {
        FormTableHost {
            Table(model.settings.commands, selection: $selection) {
                TableColumn(UIStrings.Extras.commandReading, value: \.reading)
                TableColumn(UIStrings.Extras.commandTitle, value: \.title)
                TableColumn(UIStrings.Extras.commandKind) { Text(UIStrings.Extras.label(for: $0.kind)) }
                TableColumn(UIStrings.Extras.commandTarget, value: \.target)
            }
            .contextMenu(forSelectionType: LauncherCommand.ID.self) { _ in
            } primaryAction: { ids in
                if let id = ids.first, let command = model.settings.commands.first(where: { $0.id == id }) { editing = CommandDraft(command) }
            }
            .overlay {
                if model.settings.commands.isEmpty {
                    Text(UIStrings.Extras.commandsEmpty).foregroundStyle(.secondary)
                }
            }
        }
        .frame(height: DesignTokens.Size.Settings.ruleTableHeight)
    }

    private func saveCommand(_ command: LauncherCommand) {
        model.update { settings in
            if let index = settings.commands.firstIndex(where: { $0.id == command.id }) {
                settings.commands[index] = command
            } else if settings.commands.count < DefaultSettings.maximumCommands {
                settings.commands.append(command)
            }
        }
    }

    private func removeSelected() {
        let ids = selection
        model.update { $0.commands.removeAll { ids.contains($0.id) } }
        bookmarks?.prune(keeping: Set(model.settings.commands.map(\.id)))
        selection = []
    }

    private func saveMacro(pattern: String, replacing id: String?) -> Bool {
        let macro = ConversionMacro(id: id ?? UUID().uuidString, pattern: pattern)
        guard macro.isValid else { return false }
        return model.update { settings in
            if let id, let index = settings.macros.firstIndex(where: { $0.id == id }) {
                settings.macros[index].pattern = pattern
            } else if settings.macros.count < DefaultSettings.maximumMacros {
                settings.macros.append(macro)
            }
        }
    }
}

/// 編集しているコマンド
struct CommandDraft: Identifiable {
    var id: String
    var reading: String
    var title: String
    var kind: LauncherCommand.Kind
    var target: String

    init(_ command: LauncherCommand? = nil) {
        id = command?.id ?? UUID().uuidString
        reading = command?.reading ?? ""
        title = command?.title ?? ""
        kind = command?.kind ?? .openApplication
        target = command?.target ?? ""
    }

    var command: LauncherCommand {
        LauncherCommand(id: id, reading: reading.trimmingCharacters(in: .whitespaces), title: title.trimmingCharacters(in: .whitespaces),
                        kind: kind, target: target.trimmingCharacters(in: .whitespaces))
    }
}

/// コマンドを足す・書き換えるシート．アプリとファイルは開くパネルで選ぶ(サンドボックスの外のファイルは選んだときにしか開けないため)
private struct CommandEditor: View {
    @State var draft: CommandDraft
    let bookmarks: CommandBookmarks?
    let save: (LauncherCommand) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosenFile: URL?

    init(draft: CommandDraft, bookmarks: CommandBookmarks?, save: @escaping (LauncherCommand) -> Void) {
        _draft = State(initialValue: draft)
        self.bookmarks = bookmarks
        self.save = save
    }

    var body: some View {
        Form {
            TextField(UIStrings.Extras.commandReading, text: $draft.reading)
            TextField(UIStrings.Extras.commandTitle, text: $draft.title)
            Picker(UIStrings.Extras.commandKind, selection: $draft.kind) {
                ForEach(LauncherCommand.Kind.allCases, id: \.self) { Text(UIStrings.Extras.label(for: $0)).tag($0) }
            }
            HStack {
                TextField(UIStrings.Extras.commandTarget, text: $draft.target, prompt: Text(prompt))
                    .disabled(draft.kind == .openFile)
                if draft.kind == .openApplication || draft.kind == .openFile {
                    Button(draft.kind == .openApplication ? UIStrings.Extras.chooseApplication : UIStrings.Extras.chooseFile) { choose() }
                }
            }
            if !isValid, !draft.reading.isEmpty || !draft.title.isEmpty || !draft.target.isEmpty {
                Label(UIStrings.Extras.invalidCommand, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .frame(width: DesignTokens.Size.Settings.commandEditorWidth)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(UIStrings.Extras.cancel) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(UIStrings.Extras.save) {
                    if draft.kind == .openFile, let chosenFile { try? bookmarks?.store(chosenFile, id: draft.id) }
                    save(draft.command)
                    dismiss()
                }
                .disabled(!isValid)
            }
        }
    }

    private var isValid: Bool { draft.command.isValid }

    private var prompt: String {
        switch draft.kind {
        case .openURL: UIStrings.Extras.targetPlaceholderURL
        case .runShortcut: UIStrings.Extras.targetPlaceholderShortcut
        case .openApplication, .openFile: ""
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = draft.kind == .openFile
        panel.allowsMultipleSelection = false
        if draft.kind == .openApplication {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        draft.target = url.path
        if draft.kind == .openFile { chosenFile = url }
        if draft.title.isEmpty { draft.title = url.deletingPathExtension().lastPathComponent }
    }
}
