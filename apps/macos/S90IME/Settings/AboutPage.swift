import S90Domain
import SwiftUI

/// バックアップ．すべての設定を JSON で書き出し，読み込む
struct BackupPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                HStack {
                    Button(UIStrings.More.exportSettings) { model.exportSettings() }
                    Button(UIStrings.More.importSettings) { model.importSettings() }
                }
            } footer: {
                Text(UIStrings.More.backupNote).font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button(UIStrings.Settings.restoreDefaults, role: .destructive) { model.restoreDefaults() }
            }
        }
        .formStyle(.grouped)
    }
}

/// 情報．版と，利用しているオープンソースソフトウェアの謝辞(THIRD_PARTY_NOTICES.md)
struct AboutPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent(UIStrings.More.version, value: model.versionString)
            }
            Section(UIStrings.More.acknowledgements) {
                Text(UIStrings.More.acknowledgementsNote).font(.callout)
                ScrollView {
                    Text(model.notices ?? UIStrings.More.noticesMissing)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 320)
            }
        }
        .formStyle(.grouped)
    }
}
