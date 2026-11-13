import Foundation
@testable import HajimeDomain
import Testing

@Suite("分岐図の文節へ移るキーを足す設定の引き上げ(バージョン 18 → 19)")
struct SegmentJumpKeyUpgradeTests {
    /// バージョン 18 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(18)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let optionA = KeyStroke(.character("a"), option: true)

    @Test("ひな形のまま保存した表は，今のそのひな形の表にする．標準・Emacs 風・Vim 風は ⌥ とホームポジションの 8 つのキーで文節へ移る")
    func presets() throws {
        let letters = ["a", "s", "d", "f", "j", "k", "l", ";"]
        for preset in KeymapPreset.allCases {
            let previous = SegmentJumpKeyUpgrade.previous(preset)
            #expect(!previous.entries.contains { $0.command.segmentJumpIndex != nil })
            #expect(try upgraded(previous) == preset.keymap)
        }
        for preset in [KeymapPreset.standard, .emacs, .vim] {
            for (index, letter) in letters.enumerated() {
                #expect(preset.keymap.command(for: KeyStroke(.character(letter), option: true), in: .converting) == KeymapCommand.segmentJumps[index])
            }
        }
        // Option と英字をほかの操作に使うひな形には足さない
        for preset in [KeymapPreset.windows, .mac, .atok] {
            #expect(!preset.keymap.entries.contains { $0.command.segmentJumpIndex != nil })
        }
    }

    @Test("変えた表には，変換中に 8 つのキーがすべて空いていれば足し，1 つでも使っていれば足さない")
    func custom() throws {
        var custom = SegmentJumpKeyUpgrade.previous(.standard)
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        let added = try upgraded(custom)
        #expect(added.command(for: optionA, in: .converting) == .jumpToSegment1)
        #expect(added.entries.filter { $0.command.segmentJumpIndex != nil }.count == KeymapCommand.segmentJumps.count)
        var taken = SegmentJumpKeyUpgrade.previous(.standard)
        taken.entries.append(KeymapEntry(.converting, optionA, .lastCandidate))
        let result = try upgraded(taken)
        #expect(result.command(for: optionA, in: .converting) == .lastCandidate)
        #expect(!result.entries.contains { $0.command.segmentJumpIndex != nil })
    }

    @Test("文節へ移るキーを自分で割り当てた表は変えない")
    func assigned() throws {
        var assigned = SegmentJumpKeyUpgrade.previous(.standard)
        assigned.entries.append(KeymapEntry(.converting, KeyStroke(.character("1"), control: true), .jumpToSegment1))
        let result = try upgraded(assigned)
        #expect(result.entries.filter { $0.command.segmentJumpIndex != nil }.count == 1)
    }
}
