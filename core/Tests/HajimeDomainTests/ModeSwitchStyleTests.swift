import Testing
@testable import HajimeDomain

@Suite("英数とかなの切り替え方(初期設定)")
struct ModeSwitchStyleTests {
    @Test("標準の表は「英数キーとかなキーで分ける」で，推奨の使い方と同じ")
    func standardIsSeparate() {
        #expect(ModeSwitchStyle.current(in: KeymapPreset.standard.keymap) == .separate)
        #expect(ModeSwitchStyle.recommended == .separate)
    }

    @Test("「1 つのキーで切り替え」にすると，英数キーとかなキーが切り替えになり，ほかの行は変わらない")
    func single() {
        let standard = KeymapPreset.standard.keymap
        let single = ModeSwitchStyle.single.applied(to: standard)
        #expect(ModeSwitchStyle.current(in: single) == .single)
        #expect(single.command(for: KeyStroke(.eisu), in: .idle) == .toggleMode)
        #expect(single.command(for: KeyStroke(.kana), in: .composing) == .toggleMode)
        let others = { (keymap: Keymap) in keymap.entries.filter { ![KeyStroke(.eisu), KeyStroke(.kana)].contains($0.stroke) } }
        #expect(Set(others(single)) == Set(others(standard)))
        // 戻すと元の表と同じ行になる
        #expect(Set(ModeSwitchStyle.separate.applied(to: single).entries) == Set(standard.entries))
    }

    @Test("英数キーとかなキーを利用者が別のコマンドにしていれば，どちらの使い方でもない")
    func custom() {
        var keymap = KeymapPreset.standard.keymap
        keymap.entries.append(KeymapEntry(.anywhere, KeyStroke(.kana), .nextInputStyle))
        #expect(ModeSwitchStyle.current(in: keymap) == nil)
    }
}
