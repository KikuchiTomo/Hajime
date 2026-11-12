import Foundation
@testable import HajimeDomain
import Testing

@Suite("単語の登録と入力メニューのキーを足す設定の引き上げ(バージョン 16 → 17)")
struct WordToolKeyUpgradeTests {
    /// バージョン 16 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(16)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let controlF7 = KeyStroke(.function(7), control: true)
    private let controlF10 = KeyStroke(.function(10), control: true)
    private let controlHenkan = KeyStroke(.henkan, control: true)

    @Test("ひな形のまま保存した表は，今のそのひな形の表にする．どのひな形も Ctrl+F7 で単語の登録，Ctrl+F10 と Ctrl+変換 で入力メニュー")
    func presets() throws {
        for preset in KeymapPreset.allCases {
            let previous = WordToolKeyUpgrade.previous(preset)
            #expect(!previous.entries.contains { WordToolKeyUpgrade.commands.contains($0.command) })
            #expect(try upgraded(previous) == preset.keymap)
            for state in KeymapState.concrete {
                #expect(preset.keymap.command(for: controlF7, in: state) == .registerWord)
                #expect(preset.keymap.command(for: controlF10, in: state) == .openMenu)
                #expect(preset.keymap.command(for: controlHenkan, in: state) == .openMenu)
            }
        }
    }

    @Test("変えた表には，キーが空いていれば足し，使っていれば変えない")
    func custom() throws {
        var custom = WordToolKeyUpgrade.previous(.standard)
        custom.entries.append(KeymapEntry(.composing, controlF10, .commit))
        let result = try upgraded(custom)
        #expect(result.command(for: controlF7, in: .idle) == .registerWord)
        #expect(result.command(for: controlF10, in: .composing) == .commit)
        #expect(result.command(for: controlF10, in: .idle) == nil)
        #expect(result.command(for: controlHenkan, in: .idle) == .openMenu)
    }
}
