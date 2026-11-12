import Foundation
@testable import HajimeDomain
import Testing

@Suite("予測の確定を取り消すキーを足す設定の引き上げ(バージョン 12 → 13)")
struct PredictionUndoKeyUpgradeTests {
    /// バージョン 12 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(12)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let backspace = KeyStroke(.backspace)
    private let controlBackspace = KeyStroke(.backspace, control: true)

    @Test("ひな形のまま保存した表は，今のそのひな形の表にする(標準・Mac 風は入力文字なしの Backspace，Windows 風・ATOK 風は Ctrl+Backspace)")
    func presets() throws {
        for preset in KeymapPreset.allCases {
            let previous = PredictionUndoKeyUpgrade.previous(preset)
            #expect(!previous.entries.contains { $0.command == .undoPrediction })
            #expect(try upgraded(previous) == preset.keymap)
        }
        for preset in [KeymapPreset.standard, .mac, .emacs, .vim] {
            #expect(preset.keymap.command(for: backspace, in: .idle) == .undoPrediction)
        }
        // Windows 風・ATOK 風の Ctrl+Backspace は，バージョン 16 で確定の取り消しに替えた
        for preset in [KeymapPreset.windows, .atok] {
            #expect(UndoCommitKeyUpgrade.previous(preset).command(for: controlBackspace, in: .idle) == .undoPrediction)
        }
    }

    @Test("変えた表には，入力文字なしの Backspace が空いていれば足し，使っていれば変えない")
    func custom() throws {
        var custom = PredictionUndoKeyUpgrade.previous(.standard)
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        #expect(try upgraded(custom).command(for: backspace, in: .idle) == .undoPrediction)
        var taken = PredictionUndoKeyUpgrade.previous(.standard)
        taken.entries.append(KeymapEntry(.idle, backspace, .forgetLastCommit))
        let result = try upgraded(taken)
        #expect(result.command(for: backspace, in: .idle) == .forgetLastCommit)
        #expect(!result.entries.contains { $0.command == .undoPrediction })
    }
}
