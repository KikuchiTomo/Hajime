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

    @Test("R-26: 標準のまま保存した表は，今の標準の表にする(⌃⌥E と ⌃⌥K でパレットを開く)")
    func standard() throws {
        #expect(!PaletteKeyUpgrade.previousStandard.entries.contains { $0.command == .emojiPalette })
        let result = try upgraded(PaletteKeyUpgrade.previousStandard)
        #expect(result == KeymapPreset.standard.keymap)
        #expect(result.command(for: emoji, in: .idle) == .emojiPalette)
        #expect(result.command(for: symbol, in: .direct) == .symbolPalette)
    }

    @Test("R-26: 変えた表には，キーが空いていれば足す．どこかの状態でキーを使っていれば変えない")
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

    @Test("R-26: ほかのひな形にもパレットのキーがある")
    func presets() {
        for preset in KeymapPreset.allCases {
            #expect(preset.keymap.command(for: emoji, in: .idle) == .emojiPalette)
        }
    }
}

@Suite("顔文字のパレットを開くキーを足す設定の引き上げ(バージョン 10 → 11)")
struct KaomojiKeyUpgradeTests {
    /// バージョン 10 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(10)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let kaomoji = KeyStroke(.character("f"), control: true, option: true)

    @Test("R-26: 標準のまま保存した表は，今の標準の表にする(⌃⌥F で顔文字のパレットを開く)")
    func standard() throws {
        #expect(!KaomojiKeyUpgrade.previousStandard.entries.contains { $0.command == .kaomojiPalette })
        let result = try upgraded(KaomojiKeyUpgrade.previousStandard)
        #expect(result == KeymapPreset.standard.keymap)
        #expect(result.command(for: kaomoji, in: .idle) == .kaomojiPalette)
        #expect(result.command(for: kaomoji, in: .direct) == .kaomojiPalette)
    }

    @Test("R-26: 変えた表には，キーが空いていれば足す．どこかの状態でキーを使っていれば変えない")
    func custom() throws {
        var custom = KaomojiKeyUpgrade.previousStandard
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        #expect(try upgraded(custom).command(for: kaomoji, in: .composing) == .kaomojiPalette)
        var taken = KaomojiKeyUpgrade.previousStandard
        taken.entries.append(KeymapEntry(.converting, kaomoji, .backToReading))
        let result = try upgraded(taken)
        #expect(result.command(for: kaomoji, in: .converting) == .backToReading)
        #expect(!result.entries.contains { $0.command == .kaomojiPalette })
    }

    @Test("R-26: バージョン 9 の標準の表も，今の標準の表(顔文字のキーを含む)になる")
    func fromVersion9() throws {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(PaletteKeyUpgrade.previousStandard))
        object[SettingsSchema.versionKey] = .number(9)
        let result = try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
        #expect(result == KeymapPreset.standard.keymap)
    }

    @Test("R-26: どのひな形にも顔文字のパレットのキーがある")
    func presets() {
        for preset in KeymapPreset.allCases {
            #expect(preset.keymap.command(for: kaomoji, in: .idle) == .kaomojiPalette)
        }
    }
}
