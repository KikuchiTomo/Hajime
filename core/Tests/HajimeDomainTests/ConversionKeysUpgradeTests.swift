import Foundation
@testable import HajimeDomain
import Testing

@Suite("変換中のキーを足す設定の引き上げ(バージョン 8 → 9)")
struct ConversionKeysUpgradeTests {
    /// バージョン 8 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(8)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    @Test("標準のまま保存した表は，今の標準の表にする")
    func standard() throws {
        let previous = ConversionKeysUpgrade.previousStandard
        #expect(!previous.entries.contains { $0.command == .undoConversionEdit || $0.command == .resumeEditing })
        #expect(previous.command(for: KeyStroke(.escape), in: .converting) == .cancel)
        #expect(try upgraded(previous) == KeymapPreset.standard.keymap)
    }

    @Test("変えた表には，変換中に空いているキーの行だけを足す．F6〜F8 と Esc は いつでも の行で使っているので変えない")
    func custom() throws {
        var custom = ConversionKeysUpgrade.previousStandard
        custom.entries.append(KeymapEntry(.converting, KeyStroke(.home), .firstCandidate))
        let result = try upgraded(custom)
        #expect(result.command(for: KeyStroke(.home), in: .converting) == .firstCandidate)
        #expect(result.command(for: KeyStroke(.end), in: .converting) == .lastSegment)
        #expect(result.command(for: KeyStroke(.pageDown), in: .converting) == .nextCandidatePage)
        #expect(result.command(for: KeyStroke(.delete), in: .converting) == .resumeEditing)
        #expect(result.command(for: KeyStroke(.escape), in: .converting) == .cancel)
        #expect(result.command(for: KeyStroke(.function(7)), in: .converting) == .toKatakana)
    }

    @Test("バージョン 7 で標準のまま保存した表も，今の標準の表にする")
    func fromVersionSeven() throws {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(ForgetKeyUpgrade.previousStandard))
        object[SettingsSchema.versionKey] = .number(7)
        #expect(try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap == KeymapPreset.standard.keymap)
    }
}
