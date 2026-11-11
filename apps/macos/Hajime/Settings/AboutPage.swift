import HajimeDomain
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

/// 情報．バージョンと，利用しているソフトウェア・モデル・データの謝辞(THIRD_PARTY_NOTICES.md)
struct AboutPage: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section {
                // Hajime のアイコンと名前・バージョンを並べ，右に「更新を確認」を置く
                HStack(alignment: .center) {
                    Image(nsImage: model.appIcon)
                        .resizable()
                        .frame(width: DesignTokens.Size.Settings.aboutIcon, height: DesignTokens.Size.Settings.aboutIcon)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading) {
                        Text(model.appName).font(.title2.weight(.semibold))
                        LabeledContent(UIStrings.More.version, value: model.versionString)
                            .labelsHidden()
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer()
                    if let check = model.checkForUpdates {
                        Button(UIStrings.More.checkForUpdates, action: check)
                    }
                }
                if let open = model.openOnboarding {
                    LabeledContent(UIStrings.Onboarding.redoLabel) {
                        Button(UIStrings.Onboarding.redo, action: open)
                    }
                }
            }
            Section {
                if let acknowledgements = model.acknowledgements {
                    ForEach(acknowledgements) { AcknowledgementRow(item: $0) }
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

    /// 行の中の URL の範囲．URL は「https://」から，空白・ASCII でない文字・括弧の手前までとし，末尾の句読点は含めない
    /// (「…/hajime-dictionary(v0.1.1)．」の括弧や句点まで URL にしない)．Windows の notices::split_url と同じ決まり
    static func urlRange(in text: String) -> Range<String.Index>? {
        let scheme = "https://"
        guard let start = text.range(of: scheme)?.lowerBound else { return nil }
        var end = text[start...].firstIndex { !$0.isASCII || $0.isWhitespace || "()<>\"'`".contains($0) } ?? text.endIndex
        while end > start, let last = text[start..<end].last, ".,;:!?".contains(last) {
            end = text.index(before: end)
        }
        return text.distance(from: start, to: end) > scheme.count ? start..<end : nil
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

    /// 行の中の URL だけを押せるようにする．前置き(「改変したもの: 」)と URL のあとの文はそのまま文字で出し，左にそろえて折り返す
    @ViewBuilder
    private func value(_ text: String) -> some View {
        if let range = Acknowledgement.urlRange(in: text), let url = URL(string: String(text[range])) {
            Text(Self.linked(text, range: range, url: url))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(text)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// range の部分だけにリンクを付けた文字列．リンクの部分はアクセントの色になる
    private static func linked(_ text: String, range: Range<String.Index>, url: URL) -> AttributedString {
        var attributed = AttributedString(text)
        if let lower = AttributedString.Index(range.lowerBound, within: attributed),
           let upper = AttributedString.Index(range.upperBound, within: attributed) {
            attributed[lower..<upper].link = url
        }
        return attributed
    }
}
