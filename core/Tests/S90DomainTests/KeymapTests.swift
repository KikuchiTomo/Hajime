import Foundation
import S90Domain
import Testing

@Suite("キー設定の表(R-17)")
struct KeymapTests {
    private let standard = KeymapPreset.standard.keymap

    @Test("R-17: 同じキーでも状態ごとに違うコマンドになる")
    func commandsByState() {
        #expect(standard.command(for: KeyEvent(.space), in: .idle) == .insertSpace)
        #expect(standard.command(for: KeyEvent(.space), in: .composing) == .convert)
        #expect(standard.command(for: KeyEvent(.space), in: .converting) == .nextCandidate)
        #expect(standard.command(for: KeyEvent(.space), in: .direct) == nil)
        #expect(standard.command(for: KeyEvent(.backspace), in: .composing) == .deleteBackward)
        #expect(standard.command(for: KeyEvent(.backspace), in: .converting) == .backToReading)
        #expect(standard.command(for: KeyEvent(.backspace), in: .idle) == nil)
    }

    @Test("R-17: いつでも の行は，コマンドが効く状態でだけ効く")
    func anywhereRows() {
        let control = KeyEvent(.character("k"), modifiers: .control)
        #expect(standard.command(for: control, in: .composing) == .toKatakana)
        #expect(standard.command(for: control, in: .converting) == .toKatakana)
        #expect(standard.command(for: control, in: .idle) == nil)
        // 切り替えのキーは英数のときも効く
        #expect(standard.command(for: KeyEvent(.kana), in: .direct) == .japaneseMode)
        #expect(standard.command(for: KeyEvent(.eisu), in: .composing) == .directMode)
        // 設定を開くキーは英数のときも効く(ターミナルでは英数で打ち，入力メニューの操作も届かないため)
        #expect(standard.command(for: KeyEvent(.character(","), modifiers: [.control, .option]), in: .direct) == .openSettings)
        // 確定のような日本語の入力のコマンドは英数のときは効かない(アプリのキーを奪わない)
        #expect(standard.command(for: KeyEvent(.enter), in: .direct) == nil)
    }

    @Test("R-17: 修飾キーの組み合わせを区別する")
    func modifiers() {
        var keymap = Keymap([
            KeymapEntry(.idle, KeyStroke(.space, shift: true, control: true), .insertFullwidthSpace),
            KeymapEntry(.idle, KeyStroke(.space, control: true), .insertHalfwidthSpace),
            KeymapEntry(.composing, KeyStroke(.character("k"), command: true), .toKatakana),
        ])
        #expect(keymap.command(for: KeyEvent(.space, modifiers: [.control, .shift]), in: .idle) == .insertFullwidthSpace)
        #expect(keymap.command(for: KeyEvent(.space, modifiers: .control), in: .idle) == .insertHalfwidthSpace)
        #expect(keymap.command(for: KeyEvent(.space, modifiers: [.control, .option]), in: .idle) == nil)
        #expect(keymap.command(for: KeyEvent(.space), in: .idle) == nil)
        #expect(keymap.command(for: KeyEvent(.character("k"), modifiers: .command), in: .composing) == .toKatakana)
        #expect(keymap.command(for: KeyEvent(.character("K"), modifiers: [.command, .shift]), in: .composing) == nil)
        // 英字でない文字の Shift は文字に含まれるので見ない(US 配列の ⌃⇧; と JIS 配列の ⌃: を同じにする)
        keymap.entries.append(KeymapEntry(.composing, KeyStroke(notation: "Ctrl :")!, .toHalfwidthAlphanumeric))
        #expect(keymap.command(for: KeyEvent(.character(":"), modifiers: [.control, .shift]), in: .composing) == .toHalfwidthAlphanumeric)
        #expect(keymap.command(for: KeyEvent(.character(":"), modifiers: .control), in: .composing) == .toHalfwidthAlphanumeric)
    }

    @Test("R-17: 同じ状態の同じキーは下の行が勝ち，状態を書いた行は いつでも の行に勝つ")
    func overlaps() {
        let keymap = Keymap([
            KeymapEntry(.anywhere, KeyStroke(.character("j"), control: true), .toHiragana),
            KeymapEntry(.composing, KeyStroke(.character("j"), control: true), .toKatakana),
            KeymapEntry(.converting, KeyStroke(.tab), .nextSegment),
            KeymapEntry(.converting, KeyStroke(.tab), .nextUncertainSegment),
        ])
        #expect(keymap.command(for: KeyStroke(.character("j"), control: true), in: .composing) == .toKatakana)
        #expect(keymap.command(for: KeyStroke(.character("j"), control: true), in: .converting) == .toHiragana)
        #expect(keymap.command(for: KeyStroke(.tab), in: .converting) == .nextUncertainSegment)
        #expect(keymap.overlap(at: 0) == .partlyHidden(states: [.composing], by: [1]))
        #expect(keymap.overlap(at: 1) == nil)
        #expect(keymap.overlap(at: 2) == .hidden(by: [3]))
        #expect(keymap.overlap(at: 3) == nil)
        // 負けた行のキーは案内に出さない
        #expect(keymap.strokes(for: .nextSegment, in: .converting).isEmpty)
        #expect(keymap.strokes(for: .toHiragana, in: .composing).isEmpty)
        #expect(keymap.strokes(for: .toHiragana, in: .converting) == [KeyStroke(.character("j"), control: true)])
    }

    @Test("R-17: 案内に出すキーは状態を書いた行を先に，表の上から並べる")
    func strokesForHints() {
        #expect(standard.strokes(for: .nextCandidate, in: .converting).first == KeyStroke(.space))
        #expect(standard.strokes(for: .nextCandidate, in: .converting).contains(KeyStroke(.down)))
        #expect(standard.strokes(for: .previousSegment, in: .converting).first == KeyStroke(.left))
        #expect(standard.strokes(for: .cancel, in: .composing) == [KeyStroke(.escape)])
    }

    @Test("R-17: 確定と取り消しのキーが無ければ知らせる")
    func missingEssentials() {
        #expect(standard.missingEssentials.isEmpty)
        var keymap = standard
        keymap.entries.removeAll { $0.command == .cancel }
        #expect(keymap.missingEssentials.map(\.command) == [.cancel, .cancel])
        keymap.entries.append(KeymapEntry(.composing, KeyStroke(.escape), .cancel))
        #expect(keymap.missingEssentials.map(\.state) == [.converting])
    }

    @Test("R-17: キーは「Ctrl Shift Space」の形で書き，読み戻せる")
    func notation() {
        let keys: [KeyStroke.Key] = [
            .character("a"), .character(";"), .space, .enter, .tab, .backspace, .delete, .escape, .up, .down, .left, .right,
            .home, .end, .pageUp, .pageDown, .function(1), .function(20), .eisu, .kana, .hankakuZenkaku, .henkan, .muhenkan,
        ]
        for key in keys {
            let stroke = KeyStroke(key, shift: true, control: true, option: true, command: true)
            #expect(KeyStroke(notation: stroke.notation) == KeyStroke(key, shift: key != .character(";"), control: true, option: true, command: true))
        }
        #expect(KeyStroke(.space, shift: true, control: true).notation == "Ctrl Shift Space")
        #expect(KeyStroke(notation: "ctrl shift space") == KeyStroke(.space, shift: true, control: true))
        #expect(KeyStroke(notation: "ESC") == KeyStroke(.escape))
        #expect(KeyStroke(notation: "Alt F1") == KeyStroke(.function(1), option: true))
        #expect(KeyStroke(notation: "Hyper a") == nil)
        #expect(KeyStroke(notation: "F21") == nil)
        #expect(KeyStroke(notation: "") == nil)
        #expect(KeyStroke(.character("k"), shift: true, control: true).label == "⌃⇧K")
        #expect(KeyStroke(.function(7), option: true).label == "⌥F7")
        // Windows の候補ウィンドウと注記は Windows の書き方
        #expect(KeyStroke(.character("k"), shift: true, control: true).label(style: .windows) == "Ctrl+Shift+K")
        #expect(KeyStroke(.tab, control: true).label(style: .windows) == "Ctrl+Tab")
        #expect(KeyStroke(.backspace).label(style: .windows) == "BS")
    }

    @Test("R-17: 表は保存して読み直せ，知らないコマンドの行は消さずに残す")
    func coding() throws {
        var settings = Settings()
        settings.keymap.entries.append(KeymapEntry(.converting, KeyStroke(.character("7"), control: true), .toKatakana))
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(Settings.self, from: data).keymap == settings.keymap)
        let json = Data(#"{"keymap":[{"state":"idle","key":"Ctrl Shift Space","command":"insertFullwidthSpace"},{"state":"idle","key":"F1","command":"teleport"}]}"#.utf8)
        let decoded = try JSONDecoder().decode(Settings.self, from: json)
        #expect(decoded.keymap.entries == [KeymapEntry(.idle, KeyStroke(.space, shift: true, control: true), .insertFullwidthSpace)])
        #expect(decoded.keymap.unknownEntries.count == 1)
        let reencoded = try JSONDecoder().decode(Settings.self, from: try JSONEncoder().encode(decoded))
        #expect(reencoded.keymap.unknownEntries == decoded.keymap.unknownEntries)
    }

    @Test("R-17: 状態で効かないコマンドの行は読むときに捨てる")
    func clamp() throws {
        let json = Data(#"{"keymap":[{"state":"idle","key":"F7","command":"toKatakana"},{"state":"anywhere","key":"F7","command":"toKatakana"}]}"#.utf8)
        let keymap = try JSONDecoder().decode(Settings.self, from: json).keymap
        #expect(keymap.entries == [KeymapEntry(.anywhere, KeyStroke(.function(7)), .toKatakana)])
    }
}

@Suite("キー設定のひな形(R-17)")
struct KeymapPresetTests {
    @Test("ひな形の行はどれも読め，状態で効くコマンドだけを使う")
    func rowsParse() {
        for preset in KeymapPreset.allCases {
            let lines = preset.source.split(separator: "\n")
            #expect(preset.keymap.entries.count == lines.count, "\(preset)")
        }
    }

    @Test("ひな形はそれぞれ違い，今の表がどのひな形かを見分けられる")
    func distinct() {
        let keymaps = KeymapPreset.allCases.map(\.keymap)
        for (index, keymap) in keymaps.enumerated() {
            #expect(keymaps.filter { $0 == keymap }.count == 1)
            #expect(KeymapPreset.matching(keymap) == KeymapPreset.allCases[index])
            #expect(keymap.missingEssentials.isEmpty)
        }
        var changed = KeymapPreset.standard.keymap
        changed.entries.removeLast()
        #expect(KeymapPreset.matching(changed) == nil)
    }

    @Test("Windows 風・Mac 風・Emacs 風の代表的なキー")
    func typicalKeys() {
        let windows = KeymapPreset.windows.keymap
        #expect(windows.command(for: KeyEvent(.character("i"), modifiers: .control), in: .composing) == .toKatakana)
        #expect(windows.command(for: KeyEvent(.space, modifiers: [.control, .shift]), in: .idle) == .insertFullwidthSpace)
        #expect(windows.command(for: KeyEvent(.down, modifiers: .control), in: .converting) == .commitFirstSegment)
        #expect(windows.command(for: KeyEvent(.function(2)), in: .composing) == .convertWithoutLearning)
        #expect(windows.command(for: KeyEvent(.muhenkan), in: .composing) == .switchKanaType)
        #expect(windows.command(for: KeyEvent(.tab), in: .converting) == nil)
        // 連想は macOS の標準と同じ ⇧↑(Alt+↑ も使える)
        #expect(windows.command(for: KeyEvent(.up, modifiers: .shift), in: .converting) == .associate)
        #expect(windows.command(for: KeyEvent(.up, modifiers: .option), in: .converting) == .associate)
        let mac = KeymapPreset.mac.keymap
        #expect(mac.command(for: KeyEvent(.character("z"), modifiers: .option), in: .converting) == .toHiragana)
        #expect(mac.command(for: KeyEvent(.space, modifiers: .option), in: .composing) == .insertFullwidthSpace)
        #expect(mac.command(for: KeyEvent(.pageDown), in: .converting) == .nextCandidatePage)
        let emacs = KeymapPreset.emacs.keymap
        #expect(emacs.command(for: KeyEvent(.character("n"), modifiers: .control), in: .converting) == .nextCandidate)
        #expect(emacs.command(for: KeyEvent(.character("g"), modifiers: .control), in: .composing) == .cancel)
        let vim = KeymapPreset.vim.keymap
        #expect(vim.command(for: KeyEvent(.character("h")), in: .converting) == .previousSegment)
        #expect(vim.command(for: KeyEvent(.character("j")), in: .converting) == .nextCandidate)
        #expect(vim.command(for: KeyEvent(.character("L"), modifiers: .shift), in: .converting) == .extendSegment)
        #expect(vim.command(for: KeyEvent(.character("["), modifiers: .control), in: .converting) == .cancel)
        // 文字のキーは入力中・入力文字なしには置かない(打った文字のまま)．入力文字なしの Esc も置かない
        for state in [KeymapState.idle, .composing] {
            for letter in ["h", "j", "k", "l"] {
                #expect(vim.command(for: KeyEvent(.character(Character(letter))), in: state) == nil)
            }
        }
        #expect(vim.command(for: KeyEvent(.escape), in: .idle) == nil)
        for keymap in [windows, mac, emacs, vim] {
            // どのひな形にも切り替えのキーと設定を開くキーがある
            #expect(keymap.command(for: KeyEvent(.eisu), in: .composing) == .directMode)
            #expect(keymap.command(for: KeyEvent(.character(","), modifiers: [.control, .option]), in: .idle) == .openSettings)
        }
    }
}

@Suite("古いキーの設定の移し替え(R-17)")
struct LegacyKeySettingsTests {
    /// バージョン 2 で既定のまま保存した設定のファイルのキーの項目
    private let defaultConversionKeys = #"""
        {"commands":{"nextCandidate":[{"key":{"down":{}},"shift":false,"control":false,"option":false},{"key":{"space":{}},"shift":false,"control":false,"option":false}],
        "nextSegment":[{"key":{"right":{}},"shift":false,"control":false,"option":false}]}}
        """#
    private let defaultModeKeys = #"{"eisu":"direct","kana":"japanese","hankakuZenkaku":"toggle","henkan":"none","muhenkan":"none"}"#

    private func decode(_ json: String) throws -> Settings {
        try SettingsCoding.decode(Data(json.utf8))
    }

    @Test("既定のままの古い設定は既定の表にする")
    func defaultsBecomeStandard() throws {
        let settings = try decode(#"{"schemaVersion":2,"conversionKeys":\#(defaultConversionKeys),"modeKeys":\#(defaultModeKeys)}"#)
        #expect(settings.keymap == KeymapPreset.standard.keymap)
        #expect(settings.schemaVersion == SettingsSchema.currentVersion)
        #expect(settings.unknownFields.isEmpty)
    }

    @Test("変えた変換中のキーは表の行に移し，ほかの操作は既定の行のまま")
    func conversionKeys() throws {
        let keys = #"""
            {"commands":{"nextCandidate":[{"key":{"character":{"_0":"j"}},"shift":false,"control":true,"option":false}],
            "openSettings":[{"key":{"character":{"_0":";"}},"shift":true,"control":true,"option":true}]}}
            """#
        let keymap = try decode(#"{"conversionKeys":\#(keys)}"#).keymap
        #expect(keymap.command(for: KeyEvent(.character("j"), modifiers: .control), in: .converting) == .nextCandidate)
        // 変換中の Space は次の候補から外れ，Space はふつうの処理に回る
        #expect(keymap.command(for: KeyEvent(.space), in: .converting) == nil)
        #expect(keymap.command(for: KeyEvent(.character(";"), modifiers: [.control, .option, .shift]), in: .idle) == .openSettings)
        #expect(keymap.command(for: KeyEvent(.character(","), modifiers: [.control, .option]), in: .idle) == nil)
        #expect(keymap.command(for: KeyEvent(.right), in: .converting) == .nextSegment)
    }

    @Test("変えた切り替えのキーは いつでも の行にし，使わない にしたキーは切り替えの行を消す")
    func modeKeys() throws {
        let keymap = try decode(#"{"modeKeys":{"eisu":"none","kana":"toggle","henkan":"japanese","muhenkan":"direct"}}"#).keymap
        #expect(keymap.command(for: KeyEvent(.eisu), in: .composing) == nil)
        #expect(keymap.command(for: KeyEvent(.kana), in: .direct) == .toggleMode)
        // バージョン 2 では切り替えのキーがほかの働きより先に効いたので，入力中でも切り替える
        #expect(keymap.command(for: KeyEvent(.henkan), in: .composing) == .japaneseMode)
        #expect(keymap.command(for: KeyEvent(.muhenkan), in: .converting) == .directMode)
        #expect(keymap.command(for: KeyEvent(.hankakuZenkaku), in: .idle) == .toggleMode)
    }

    @Test("古いバージョンの Mac が書いた同期の値も表に移し替える")
    func syncedLegacyValues() throws {
        var object = try SettingsCoding.object(of: Settings())
        object["conversionKeys"] = try JSONDecoder().decode(JSONValue.self, from: Data(
            #"{"commands":{"nextSegment":[{"key":{"tab":{}},"shift":false,"control":false,"option":false}]}}"#.utf8))
        let settings = try SettingsCoding.settings(from: object)
        #expect(settings.keymap.command(for: KeyEvent(.tab), in: .converting) == .nextSegment)
        #expect(settings.unknownFields["conversionKeys"] == nil)
    }
}
