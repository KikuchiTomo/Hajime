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

    @Test("ひな形のまま保存した表は，今のそのひな形の表にする．どのひな形でも ⌥ とホームポジションの 8 つのキー(Mac 風は ⇧⌥ と中段の左の 8 つのキー)で文節へ移る")
    func presets() throws {
        for preset in KeymapPreset.allCases {
            let previous = SegmentJumpKeyUpgrade.previous(preset)
            #expect(!previous.entries.contains { $0.command.segmentJumpIndex != nil })
            #expect(try upgraded(previous) == preset.keymap)
            // Mac 風は変換中の ⌥A・⌥S・⌥K をほかの操作に使うので，Shift を足したキーにしてある．その操作は変えない
            let shift = preset == .mac
            let letters = shift ? ["a", "s", "d", "f", "g", "h", "j", "k"] : ["a", "s", "d", "f", "j", "k", "l", ";"]
            for (index, letter) in letters.enumerated() {
                #expect(preset.keymap.command(for: KeyStroke(.character(letter), shift: shift, option: true), in: .converting) == KeymapCommand.segmentJumps[index])
            }
        }
        #expect(KeymapPreset.mac.keymap.command(for: optionA, in: .converting) == .toHalfwidthKatakana)
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
