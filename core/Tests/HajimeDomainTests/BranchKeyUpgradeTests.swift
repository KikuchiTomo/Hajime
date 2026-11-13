import Foundation
@testable import HajimeDomain
import Testing

@Suite("変換中の → を候補の先の枝へ移るキーに替える設定の引き上げ(バージョン 19 → 20)")
struct BranchKeyUpgradeTests {
    /// バージョン 19 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(19)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    @Test("ひな形のまま保存した表は，今のそのひな形の表にする．標準・Emacs 風・Vim 風は → が先の枝へ移るキーになり，Tab は次の文節のまま")
    func presets() throws {
        for preset in KeymapPreset.allCases {
            let previous = BranchKeyUpgrade.previous(preset)
            #expect(!previous.entries.contains { $0.command == .enterBranch })
            #expect(try upgraded(previous) == preset.keymap)
        }
        for preset in [KeymapPreset.standard, .emacs, .vim] {
            #expect(preset.keymap.command(for: KeyStroke(.right), in: .converting) == .enterBranch)
            #expect(preset.keymap.command(for: KeyStroke(.tab), in: .converting) == .nextSegment)
            #expect(preset.keymap.command(for: KeyStroke(.left), in: .converting) == .previousSegment)
        }
    }

    @Test("変えた表は変えない(利用者の決めたキーを変えない)")
    func custom() throws {
        var custom = BranchKeyUpgrade.previous(.standard)
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        let result = try upgraded(custom)
        #expect(result.command(for: KeyStroke(.right), in: .converting) == .nextSegment)
        #expect(!result.entries.contains { $0.command == .enterBranch })
    }
}
