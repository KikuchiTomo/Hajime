import Foundation
@testable import HajimeDomain
import Testing

@Suite("確定を取り消すキーを足す設定の引き上げ(バージョン 15 → 16)")
struct UndoCommitKeyUpgradeTests {
    /// バージョン 15 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(15)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let controlBackspace = KeyStroke(.backspace, control: true)

    @Test("ひな形のまま保存した表は，今のそのひな形の表にする．Windows 風・ATOK 風の予測の確定の取り消しは確定の取り消しに替える")
    func presets() throws {
        for preset in KeymapPreset.allCases {
            let previous = UndoCommitKeyUpgrade.previous(preset)
            #expect(!previous.entries.contains { $0.command == .undoCommit })
            #expect(try upgraded(previous) == preset.keymap)
            #expect(preset.keymap.command(for: controlBackspace, in: .idle) == .undoCommit)
        }
        for preset in [KeymapPreset.windows, .atok] {
            #expect(UndoCommitKeyUpgrade.previous(preset).command(for: controlBackspace, in: .idle) == .undoPrediction)
            #expect(!preset.keymap.entries.contains { $0.command == .undoPrediction })
        }
    }

    @Test("変えた表には，入力文字なしの Ctrl+Backspace が空いていれば足し，使っていれば変えない")
    func custom() throws {
        var custom = UndoCommitKeyUpgrade.previous(.standard)
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        #expect(try upgraded(custom).command(for: controlBackspace, in: .idle) == .undoCommit)
        var taken = UndoCommitKeyUpgrade.previous(.windows)
        taken.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        let result = try upgraded(taken)
        #expect(result.command(for: controlBackspace, in: .idle) == .undoPrediction)
        #expect(!result.entries.contains { $0.command == .undoCommit })
    }
}
