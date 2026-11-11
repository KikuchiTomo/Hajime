import Foundation
@testable import HajimeDomain
import Testing

@Suite("パレットを開くキーを足す設定の引き上げ(バージョン 9 → 10)")
struct PaletteKeyUpgradeTests {
    /// バージョン 9 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(9)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let emoji = KeyStroke(.character("e"), control: true, option: true)
    private let symbol = KeyStroke(.character("k"), control: true, option: true)

    @Test("R-25: 標準のまま保存した表は，今の標準の表にする(⌃⌥E と ⌃⌥K でパレットを開く)")
    func standard() throws {
        #expect(!PaletteKeyUpgrade.previousStandard.entries.contains { $0.command == .emojiPalette })
        let result = try upgraded(PaletteKeyUpgrade.previousStandard)
        #expect(result == KeymapPreset.standard.keymap)
        #expect(result.command(for: emoji, in: .idle) == .emojiPalette)
        #expect(result.command(for: symbol, in: .direct) == .symbolPalette)
    }

    @Test("R-25: 変えた表には，キーが空いていれば足す．どこかの状態でキーを使っていれば変えない")
    func custom() throws {
        var custom = PaletteKeyUpgrade.previousStandard
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        #expect(try upgraded(custom).command(for: emoji, in: .composing) == .emojiPalette)
        var taken = PaletteKeyUpgrade.previousStandard
        taken.entries.append(KeymapEntry(.converting, emoji, .backToReading))
        let result = try upgraded(taken)
        #expect(result.command(for: emoji, in: .converting) == .backToReading)
        #expect(!result.entries.contains { $0.command == .emojiPalette })
        #expect(result.command(for: symbol, in: .idle) == .symbolPalette)
    }

    @Test("R-25: ほかのひな形にもパレットのキーがある")
    func presets() {
        for preset in KeymapPreset.allCases {
            #expect(preset.keymap.command(for: emoji, in: .idle) == .emojiPalette)
        }
    }
}
