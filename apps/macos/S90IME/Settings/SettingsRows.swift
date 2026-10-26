import S90Domain
import SwiftUI

/// 既定から変えた項目に印と「既定に戻す」ボタンを付ける(項目 48．どこを変えたかを見て，一つずつ戻せるように)
struct ResettableRow<Value: Equatable, Content: View>: View {
    @ObservedObject var model: SettingsModel
    let keyPath: WritableKeyPath<S90Domain.Settings, Value>
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
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

/// 既定から戻せる，列挙の値を選ぶ項目
struct ResettablePicker<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    @ObservedObject var model: SettingsModel
    let title: String
    let keyPath: WritableKeyPath<S90Domain.Settings, Value>
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
    let keyPath: WritableKeyPath<S90Domain.Settings, Bool>

    var body: some View {
        ResettableRow(model: model, keyPath: keyPath) {
            Toggle(title, isOn: model.binding(keyPath))
        }
    }
}
