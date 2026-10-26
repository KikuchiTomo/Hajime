import S90Domain
import SwiftUI

/// 同期(TODO 43・49)．フォルダを選ぶと，設定とユーザー辞書をそのフォルダのファイルと同期する．
/// まとまりごとに「同期する」「この Mac だけ」を選べる
struct SyncPage: View {
    @ObservedObject var sync: SyncCoordinator

    var body: some View {
        Form {
            Section {
                Toggle(UIStrings.Sync.enabled, isOn: Binding(get: { sync.state.isEnabled }, set: { sync.setEnabled($0) }))
                    .disabled(sync.state.folderBookmark == nil)
                LabeledContent(UIStrings.Sync.folder) {
                    HStack {
                        Text(sync.state.folderName ?? UIStrings.Sync.noFolder).foregroundStyle(.secondary)
                        Button(UIStrings.Sync.chooseFolder) { sync.chooseFolder() }
                    }
                }
                LabeledContent(UIStrings.Sync.lastSynced) {
                    HStack {
                        Text(sync.state.ledger.lastSyncedAt.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "—")
                            .foregroundStyle(.secondary)
                        Button(UIStrings.Sync.syncNow) { sync.syncNow() }
                            .disabled(!sync.state.isEnabled)
                    }
                }
                if let error = sync.lastError {
                    Text(error).foregroundStyle(.red)
                }
            } footer: {
                Text(UIStrings.Sync.note).font(.caption).foregroundStyle(.secondary)
            }
            Section(UIStrings.Sync.scopes) {
                ForEach(SyncGroup.allCases, id: \.self) { group in
                    Picker(UIStrings.Sync.label(for: group), selection: Binding(get: { sync.state.scope(of: group) }, set: { sync.setScope($0, for: group) })) {
                        ForEach(SyncScope.allCases, id: \.self) { Text(UIStrings.Sync.label(for: $0)).tag($0) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
