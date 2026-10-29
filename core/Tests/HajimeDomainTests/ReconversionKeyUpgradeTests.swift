import Foundation
@testable import HajimeDomain
import Testing

@Suite("再変換のキーを足す設定の引き上げ(バージョン 5 → 6)")
struct ReconversionKeyUpgradeTests {
    /// バージョン 5 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(5)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    @Test("標準のまま保存した表は，今の標準の表にする")
    func standard() throws {
        #expect(!ReconversionKeyUpgrade.previousStandard.entries.contains { $0.command == .reconvert })
        #expect(try upgraded(ReconversionKeyUpgrade.previousStandard) == KeymapPreset.standard.keymap)
    }

    @Test("変えた表には，入力文字なしでキーが空いていれば再変換を足し，利用者の決めたキーは変えない")
    func custom() throws {
        var custom = ReconversionKeyUpgrade.previousStandard
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        let result = try upgraded(custom)
        #expect(result.command(for: KeyStroke(.henkan), in: .idle) == .directMode)
        #expect(result.command(for: KeyStroke(.character("r"), shift: true, control: true), in: .idle) == .reconvert)
    }
}
