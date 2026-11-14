import Foundation
@testable import HajimeDomain
import Testing

@Suite("利用者が変えた表の変換中の → を候補の先の枝へ移るキーに替える設定の引き上げ(バージョン 20 → 21)")
struct BranchKeyCustomUpgradeTests {
    /// そのバージョンで保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap, from version: Int = 20) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(Double(version))
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    /// バージョン 8 までに読み込んだひな形の表．あとからひな形に足した行(変換中の Esc・F6〜F8，文節へ移るキー)が無く，→ は次の文節
    private func old(_ preset: KeymapPreset) -> Keymap {
        let later: Set<KeymapCommand> = [.undoConversionEdit, .segmentToHiragana, .segmentToKatakana, .segmentToHalfwidthKatakana]
        return Keymap(BranchKeyUpgrade.previous(preset).entries.filter {
            !($0.state == .converting && later.contains($0.command)) && $0.command.segmentJumpIndex == nil
        })
    }

    @Test("古いバージョンの Emacs 風・Vim 風の表は，どのひな形とも一致しなくても，→ が先の枝へ移るキーになる．ほかの行は変わらない")
    func oldPresets() throws {
        for preset in [KeymapPreset.emacs, .vim] {
            let before = old(preset)
            #expect(KeymapPreset.allCases.allSatisfy { BranchKeyUpgrade.previous($0).entries != before.entries })
            for version in [18, 19, 20] {
                let result = try upgraded(before, from: version)
                #expect(result.command(for: KeyStroke(.right), in: .converting) == .enterBranch)
                #expect(result.command(for: KeyStroke(.left), in: .converting) == .previousSegment)
                #expect(result.command(for: KeyStroke(.tab), in: .converting) == .nextSegment)
                #expect(!result.strokes(for: .enterBranch, in: .converting).isEmpty)
            }
            let result = try upgraded(before)
            let right = KeymapEntry(.converting, KeyStroke(.right), .nextSegment)
            #expect(result.entries.filter { $0.command != .enterBranch } == before.entries.filter { $0 != right })
        }
    }

    @Test("Windows 風・Mac 風・ATOK 風から 1 行変えた表は変えない(→ は次の文節のまま)")
    func otherFamilies() throws {
        for preset in [KeymapPreset.windows, .mac, .atok] {
            var custom = preset.keymap
            custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
            let result = try upgraded(custom)
            #expect(result == custom)
            #expect(!result.entries.contains { $0.command == .enterBranch })
        }
    }

    @Test("→ か ← か Tab を利用者が変えた表は変えない")
    func changedArrows() throws {
        for (stroke, command) in [(KeyStroke(.right), KeymapCommand.nextCandidate), (KeyStroke(.left), .previousCandidate), (KeyStroke(.tab), .nextCandidate)] {
            var custom = old(.emacs)
            let index = try #require(custom.entries.firstIndex { $0.state == .converting && $0.stroke == stroke })
            custom.entries[index] = KeymapEntry(.converting, stroke, command)
            #expect(try upgraded(custom) == custom)
        }
        var noTab = old(.emacs)
        noTab.entries.removeAll { $0.state == .converting && $0.stroke == KeyStroke(.tab) }
        #expect(try upgraded(noTab) == noTab)
    }

    @Test("今のひな形の表と，先の枝へ移るキーをほかのキーに割り当てた表は変えない")
    func current() throws {
        for preset in KeymapPreset.allCases {
            #expect(try upgraded(preset.keymap) == preset.keymap)
        }
        var custom = old(.emacs)
        custom.entries.append(KeymapEntry(.converting, KeyStroke(.character("]")), .enterBranch))
        #expect(try upgraded(custom) == custom)
    }
}
