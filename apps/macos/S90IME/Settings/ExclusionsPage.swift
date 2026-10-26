import S90Domain
import SwiftUI

/// 除外設定．アプリごとに入力の扱いを変える(IME を使わない・記号を半角・コマンドを英字)．
/// アプリは /Applications から選んで足し，CSV で読み込み・書き出しできる
struct ExclusionsPage: View {
    @ObservedObject var model: SettingsModel
    @State private var selection = Set<ProfileRule>()
    @State private var newProfile = AppProfile.direct

    var body: some View {
        Form {
            Section {
                Table(model.settings.profileRules, selection: $selection) {
                    TableColumn(UIStrings.More.apps) { rule in
                        Text(rule.applicationPrefix).lineLimit(1).truncationMode(.middle)
                    }
                    TableColumn(UIStrings.More.behavior) { rule in
                        Picker("", selection: Binding(get: { rule.profile }, set: { change(rule, to: $0) })) {
                            ForEach(Self.profiles, id: \.self) { Text(UIStrings.Settings.label(for: $0)).tag($0) }
                        }
                        .labelsHidden()
                    }
                    .width(min: 150, ideal: 170)
                }
                .onDeleteCommand(perform: removeSelected)
                .contextMenu(forSelectionType: ProfileRule.self) { picked in
                    if !picked.isEmpty {
                        Button(UIStrings.Settings.remove) {
                            selection = picked
                            removeSelected()
                        }
                    }
                }
                .overlay {
                    if model.settings.profileRules.isEmpty {
                        ContentUnavailableView(UIStrings.More.exclusionsEmpty, systemImage: "app.dashed")
                    }
                }
                .frame(height: DesignTokens.Size.Settings.ruleTableHeight)
                HStack {
                    Picker("", selection: $newProfile) {
                        ForEach(Self.profiles, id: \.self) { Text(UIStrings.Settings.label(for: $0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button(UIStrings.More.addApps) { model.addApplications(profile: newProfile) }
                    Spacer()
                    // 上にある決まりが先に効くので，並びを変えられるようにする
                    Button { move(by: -1) } label: { Image(systemName: "chevron.up") }
                        .help(UIStrings.Dictionaries.moveUp)
                        .accessibilityLabel(UIStrings.Dictionaries.moveUp)
                        .disabled(!canMove(by: -1))
                    Button { move(by: 1) } label: { Image(systemName: "chevron.down") }
                        .help(UIStrings.Dictionaries.moveDown)
                        .accessibilityLabel(UIStrings.Dictionaries.moveDown)
                        .disabled(!canMove(by: 1))
                    Button(UIStrings.Settings.remove, action: removeSelected)
                        .disabled(selection.isEmpty)
                }
            } footer: {
                Text(UIStrings.More.exclusionsNote).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button(UIStrings.More.importCSV) { model.importProfileRules() }
                    Button(UIStrings.More.exportCSV) { model.exportProfileRules() }
                }
            }
            Section {
                ResettableToggle(model: model, title: UIStrings.More.terminalCommands, keyPath: \.terminalCommands)
                ResettableToggle(model: model, title: UIStrings.Settings.escapeSwitchesToDirect, keyPath: \.escapeSwitchesToDirect)
            }
        }
        .formStyle(.grouped)
    }

    /// 選べる扱い．標準はアプリを一覧から消すのと同じなので並べない
    private static let profiles: [AppProfile] = [.direct, .programming, .terminal]

    /// 選んだ 1 つの決まりを上か下へ 1 つ動かす
    private func move(by offset: Int) {
        guard canMove(by: offset), let rule = selection.first else { return }
        model.update { current in
            guard let index = current.profileRules.firstIndex(of: rule) else { return }
            current.profileRules.swapAt(index, index + offset)
        }
    }

    private func canMove(by offset: Int) -> Bool {
        guard selection.count == 1, let rule = selection.first, let index = model.settings.profileRules.firstIndex(of: rule) else { return false }
        return model.settings.profileRules.indices.contains(index + offset)
    }

    private func removeSelected() {
        model.update { $0.profileRules.removeAll { selection.contains($0) } }
        selection = []
    }

    private func change(_ rule: ProfileRule, to profile: AppProfile) {
        model.update { current in
            guard let index = current.profileRules.firstIndex(of: rule) else { return }
            current.profileRules[index].profile = profile
        }
    }
}
