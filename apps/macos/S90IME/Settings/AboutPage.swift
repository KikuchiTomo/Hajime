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

/// 情報．版と，利用しているソフトウェア・モデル・データの謝辞(THIRD_PARTY_NOTICES.md)
struct AboutPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                LabeledContent(UIStrings.More.version, value: model.versionString)
            }
            Section {
                if let notices = model.notices {
                    ForEach(Acknowledgement.parse(notices)) { AcknowledgementRow(item: $0) }
                } else {
                    Text(UIStrings.More.noticesMissing).foregroundStyle(.secondary)
                }
            } header: {
                Text(UIStrings.More.acknowledgements)
            } footer: {
                Text(UIStrings.More.acknowledgementsNote).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// 謝辞の 1 項目．THIRD_PARTY_NOTICES.md の「## 名前」から次の「## 」までを，出どころ(URL などの行)とライセンスの全文(コードブロック)に分ける．
/// ライセンスの全文の中にも「## 」で始まる行があるので，コードブロックの中では項目を区切らない
struct Acknowledgement: Identifiable, Equatable {
    var name: String
    var sources: [String] = []
    var licenseText: String?
    var id: String { name }

    static func parse(_ markdown: String) -> [Acknowledgement] {
        var items: [Acknowledgement] = []
        var license: [String] = []
        var inCode = false
        for line in markdown.components(separatedBy: "\n") {
            if line.hasPrefix("```") {
                if inCode, !items.isEmpty { items[items.count - 1].licenseText = license.joined(separator: "\n") }
                license = []
                inCode.toggle()
            } else if inCode {
                license.append(line)
            } else if line.hasPrefix("## ") {
                items.append(Acknowledgement(name: String(line.dropFirst(3))))
            } else if !line.isEmpty, !items.isEmpty {
                items[items.count - 1].sources.append(line)
            }
        }
        return items
    }
}

private struct AcknowledgementRow: View {
    let item: Acknowledgement

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name).font(.headline)
            ForEach(item.sources, id: \.self) { source in
                value(source).font(.callout)
            }
            if let text = item.licenseText {
                DisclosureGroup(UIStrings.More.licenseText) {
                    Text(text)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    /// 行の中の URL は押せるようにする(「改変したもの: https://…」のような前置きはそのまま文字で出す)
    @ViewBuilder
    private func value(_ text: String) -> some View {
        if let start = text.range(of: "https://")?.lowerBound, let url = URL(string: String(text[start...])) {
            HStack(spacing: 4) {
                if start > text.startIndex { Text(text[..<start]).foregroundStyle(.secondary) }
                Link(String(text[start...]), destination: url)
            }
        } else {
            Text(text).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}
