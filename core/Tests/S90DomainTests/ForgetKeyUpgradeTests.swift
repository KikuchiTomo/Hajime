import Foundation
@testable import S90Domain
import Testing

@Suite("学習から消すキーを足す設定の引き上げ(バージョン 7 → 8)")
struct ForgetKeyUpgradeTests {
    /// バージョン 7 で保存した表を読み込んだときの表
    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(7)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    private let forget = KeyStroke(.backspace, control: true)

    @Test("標準のまま保存した表は，今の標準の表にする(変換中の ⌃⌫ で学習から消す)")
    func standard() throws {
        #expect(!ForgetKeyUpgrade.previousStandard.entries.contains { $0.command == .forgetCandidate })
        let result = try upgraded(ForgetKeyUpgrade.previousStandard)
        #expect(result == KeymapPreset.standard.keymap)
        #expect(result.command(for: forget, in: .converting) == .forgetCandidate)
    }

    @Test("変えた表には，学習から消すキーが無く ⌃⌫ が空いていれば足す．⌃⌫ を使っていれば変えない")
    func custom() throws {
        var custom = ForgetKeyUpgrade.previousStandard
        custom.entries.append(KeymapEntry(.idle, KeyStroke(.henkan), .directMode))
        #expect(try upgraded(custom).command(for: forget, in: .converting) == .forgetCandidate)
        var taken = ForgetKeyUpgrade.previousStandard
        taken.entries.append(KeymapEntry(.converting, forget, .backToReading))
        #expect(try upgraded(taken).command(for: forget, in: .converting) == .backToReading)
    }
}
