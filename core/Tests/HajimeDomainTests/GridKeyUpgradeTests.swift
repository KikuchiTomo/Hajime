import Foundation
@testable import HajimeDomain
import Testing

@Suite("候補を表に広げるキーを足す設定の引き上げ(バージョン 16 → 17)")
struct GridKeyUpgradeTests {
    /// バージョン 16 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(16)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let optionDown = KeyStroke(.down, option: true)

    @Test("ひな形のまま保存した表は，今のそのひな形の表にする(標準は変換中の ⌥↓，Windows 風・Mac 風・ATOK 風は Tab)")
    func presets() throws {
        for preset in KeymapPreset.allCases {
            let previous = GridKeyUpgrade.previous(preset)
            #expect(!previous.entries.contains { $0.command == .expandCandidates })
            #expect(try upgraded(previous) == preset.keymap)
        }
        for preset in [KeymapPreset.standard, .emacs, .vim] {
            #expect(preset.keymap.command(for: optionDown, in: .converting) == .expandCandidates)
            #expect(preset.keymap.command(for: KeyStroke(.tab), in: .converting) == .nextSegment)
        }
        for preset in [KeymapPreset.windows, .mac, .atok] {
            #expect(preset.keymap.command(for: KeyStroke(.tab), in: .converting) == .expandCandidates)
        }
    }

    @Test("変えた表には，変換中の ⌥↓ が空いていれば足し，使っていれば変えない")
    func custom() throws {
        var custom = GridKeyUpgrade.previous(.standard)
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        #expect(try upgraded(custom).command(for: optionDown, in: .converting) == .expandCandidates)
        var taken = GridKeyUpgrade.previous(.standard)
        taken.entries.append(KeymapEntry(.converting, optionDown, .lastCandidate))
        let result = try upgraded(taken)
        #expect(result.command(for: optionDown, in: .converting) == .lastCandidate)
        #expect(!result.entries.contains { $0.command == .expandCandidates })
    }
}
