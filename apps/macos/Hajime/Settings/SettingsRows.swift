import HajimeDomain
import SwiftUI

/// 既定から変えた項目に印と「既定に戻す」ボタンを付ける(項目 48．どこを変えたかを見て，一つずつ戻せるように)
struct ResettableRow<Value: Equatable, Content: View>: View {
    @ObservedObject var model: SettingsModel
    let keyPath: WritableKeyPath<HajimeDomain.Settings, Value>
    @ViewBuilder let content: () -> Content

    var body: some View {
        // 部品と「既定に戻す」は押し間違えないようにまとまりの間だけ離す
        HStack(spacing: DesignTokens.Size.Space.group) {
            content()
            if model.settings[keyPath: keyPath] != DefaultSettings.settings[keyPath: keyPath] {
                Button {
                    model.update { $0[keyPath: keyPath] = DefaultSettings.settings[keyPath: keyPath] }
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.borderless)
                .help(UIStrings.Features.restoreDefault)
                .accessibilityLabel(UIStrings.Features.restoreDefault)
            }
        }
    }
}

/// 既定から戻せる，整数を範囲の中で 1 段ずつ選ぶ項目．値はステッパーのすぐ左に置き，選ぶ項目やスライダーの値と同じく右に寄せる
struct ResettableStepper: View {
    @ObservedObject var model: SettingsModel
    let title: String
    let keyPath: WritableKeyPath<HajimeDomain.Settings, Int>
    let range: ClosedRange<Int>
    var step = 1
    /// 今の値を書いた文字(「4 番目」「2 文字以下」)
    let value: String

    var body: some View {
        ResettableRow(model: model, keyPath: keyPath) {
            LabeledContent(title) {
                HStack {
                    Text(value).monospacedDigit()
                    Stepper(title, value: model.binding(keyPath), in: range, step: step).labelsHidden()
                }
            }
        }
    }
}

/// 既定から戻せる，列挙の値を選ぶ項目
struct ResettablePicker<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    @ObservedObject var model: SettingsModel
    let title: String
    let keyPath: WritableKeyPath<HajimeDomain.Settings, Value>
    var values: [Value] = Array(Value.allCases)
    let label: (Value) -> String

    var body: some View {
        ResettableRow(model: model, keyPath: keyPath) {
            ChoicePicker(title: title, selection: model.binding(keyPath), values: values, label: label)
        }
    }
}

/// 既定から戻せる，オン・オフの項目
struct ResettableToggle: View {
    @ObservedObject var model: SettingsModel
    let title: String
    let keyPath: WritableKeyPath<HajimeDomain.Settings, Bool>
    /// スイッチに付ける説明．行全体に .help を付けると「既定に戻す」のボタンの説明まで置き換わるので，スイッチにだけ付ける
    var help: String?

    var body: some View {
        ResettableRow(model: model, keyPath: keyPath) {
            if let help {
                Toggle(title, isOn: model.binding(keyPath)).help(help)
            } else {
                Toggle(title, isOn: model.binding(keyPath))
            }
        }
    }
}

/// 取り込んだ辞書・連想の辞書の 1 行の見出し．開いて詳細を出すボタン・オン・オフのスイッチ・名前と件数・並べ替えのボタンを並べる．
/// DisclosureGroup の見出しに部品を入れると，開閉の部品に部品がまとめられ，VoiceOver ではスイッチを切り替えることも開くこともできないので，
/// 開閉もボタンにして 1 つずつ使えるようにする
struct DictionaryRowHeader: View {
    @Binding var isExpanded: Bool
    let isEnabled: Binding<Bool>
    let name: String
    let summary: String
    let isFirst: Bool
    let isLast: Bool
    let move: (Int) -> Void

    var body: some View {
        // スイッチは名前の 1 行目にそろうので，開閉と並べ替えのボタンも 1 行目の文字の並びにそろえる
        HStack(alignment: .firstTextBaseline) {
            Button { isExpanded.toggle() } label: {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help(isExpanded ? UIStrings.Dictionaries.hideDetails : UIStrings.Dictionaries.showDetails)
            .accessibilityLabel(isExpanded ? UIStrings.Dictionaries.hideDetails : UIStrings.Dictionaries.showDetails)
            // 名前と件数をスイッチのラベルにする(ラベルを隠すと VoiceOver でスイッチを切り替えられない)
            Toggle(isOn: isEnabled) {
                VStack(alignment: .leading) {
                    Text(name)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            Spacer()
            Button { move(-1) } label: { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(isFirst).help(UIStrings.Dictionaries.moveUp)
                .accessibilityLabel(UIStrings.Dictionaries.moveUp)
            Button { move(1) } label: { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(isLast).help(UIStrings.Dictionaries.moveDown)
                .accessibilityLabel(UIStrings.Dictionaries.moveDown)
        }
    }
}
