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
                .frame(minHeight: 220)
                HStack {
                    Picker("", selection: $newProfile) {
                        ForEach(Self.profiles, id: \.self) { Text(UIStrings.Settings.label(for: $0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    Button(UIStrings.More.addApps) { model.addApplications(profile: newProfile) }
                    Spacer()
                    Button(UIStrings.Settings.remove) {
                        model.update { $0.profileRules.removeAll { selection.contains($0) } }
                        selection = []
                    }
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
                Toggle(UIStrings.More.terminalCommands, isOn: model.binding(\.terminalCommands))
                Toggle(UIStrings.Settings.escapeSwitchesToDirect, isOn: model.binding(\.escapeSwitchesToDirect))
            }
        }
        .formStyle(.grouped)
    }

    /// 選べる扱い．標準はアプリを一覧から消すのと同じなので並べない
    private static let profiles: [AppProfile] = [.direct, .programming, .terminal]

    private func change(_ rule: ProfileRule, to profile: AppProfile) {
        model.update { current in
            guard let index = current.profileRules.firstIndex(of: rule) else { return }
            current.profileRules[index].profile = profile
        }
    }
}
