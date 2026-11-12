import Foundation
@testable import HajimeDomain
import Testing

@Suite("予測に表示しないキーを足す設定の引き上げ(バージョン 11 → 12)")
struct HidePredictionKeyUpgradeTests {
    /// バージョン 11 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(11)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let controlBackspace = KeyStroke(.backspace, control: true)
    private let controlDelete = KeyStroke(.delete, control: true)

    @Test("ひな形のまま保存した表は，今のそのひな形の表にする(標準は入力中の ⌃⌫，Windows 風・Mac 風・ATOK 風は Ctrl+Delete)")
    func presets() throws {
        for preset in KeymapPreset.allCases {
            let previous = HidePredictionKeyUpgrade.previous(preset)
            #expect(!previous.entries.contains { $0.command == .hidePrediction })
            #expect(try upgraded(previous) == preset.keymap)
        }
        #expect(KeymapPreset.standard.keymap.command(for: controlBackspace, in: .composing) == .hidePrediction)
        for preset in [KeymapPreset.windows, .mac, .atok] {
            #expect(preset.keymap.command(for: controlDelete, in: .composing) == .hidePrediction)
        }
    }

    @Test("変えた表には，入力中の ⌃⌫ が空いていれば足し，使っていれば変えない")
    func custom() throws {
        var custom = HidePredictionKeyUpgrade.previousStandard
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        #expect(try upgraded(custom).command(for: controlBackspace, in: .composing) == .hidePrediction)
        var taken = HidePredictionKeyUpgrade.previousStandard
        taken.entries.append(KeymapEntry(.composing, controlBackspace, .deleteBackward))
        let result = try upgraded(taken)
        #expect(result.command(for: controlBackspace, in: .composing) == .deleteBackward)
        #expect(!result.entries.contains { $0.command == .hidePrediction })
    }
}
