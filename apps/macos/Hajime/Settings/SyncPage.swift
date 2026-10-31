import HajimeDomain
import SwiftUI

/// 同期(R-15)．フォルダを選ぶと，設定とユーザー辞書をそのフォルダのファイルと同期する．
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
            Section {
                ForEach(SyncGroup.syncableCases, id: \.self) { group in
                    Picker(UIStrings.Sync.label(for: group), selection: Binding(get: { sync.state.scope(of: group) }, set: { sync.setScope($0, for: group) })) {
                        ForEach(SyncScope.allCases, id: \.self) { Text(UIStrings.Sync.label(for: $0)).tag($0) }
                    }
                    // 同期するまとまりの中でも，項目ごとにこの Mac だけで持てる．設定の画面のほかの行と同じく，名前は左・スイッチは右(オンで同期)
                    if sync.state.scope(of: group) == .synced, group.fieldNames.count > 1 {
                        DisclosureGroup(UIStrings.Sync.items) {
                            ForEach(group.fieldNames, id: \.self) { field in
                                Toggle(UIStrings.Sync.label(forField: field),
                                       isOn: Binding(get: { !sync.state.localFields.contains(field) }, set: { sync.setLocal(!$0, field: field) }))
                                    .toggleStyle(.switch)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            } header: {
                Text(UIStrings.Sync.scopes)
            }
        }
        .formStyle(.grouped)
    }
}
