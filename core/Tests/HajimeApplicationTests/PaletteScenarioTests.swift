import Foundation
import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 絵文字と記号のパレット(R-26)．キーとマウスの操作から，出すパレットと入れる文字を確かめる
@MainActor
@Suite("絵文字と記号のパレット")
struct PaletteScenarioTests {
    private static func line(_ kind: String, _ category: String, _ text: String, _ name: String, _ nameReading: String, _ english: String,
                             readings: String = "", keywords: String = "", shortcodes: String = "", tones: String = "") -> String {
        [kind, category, text, kind == "emoji" ? "0.6" : "", name, nameReading, english, readings, keywords, shortcodes, tones].joined(separator: "\t")
    }

    /// 顔が 7 個(2 行)，人が 3 個，記号が 2 個，顔文字が 5 個
    static let table = [
        line("emoji", "smileys", "😀", "にっこり笑う", "にっこりわらう", "grinning face", readings: "えがお", shortcodes: "grinning"),
        line("emoji", "smileys", "😃", "大きな目で笑う", "おおきなめでわらう", "grinning face with big eyes", readings: "えがお", shortcodes: "smiley"),
        line("emoji", "smileys", "😄", "目も笑う", "めもわらう", "grinning face with smiling eyes", readings: "えがお", shortcodes: "smile"),
        line("emoji", "smileys", "😁", "にやっと笑う", "にやっとわらう", "beaming face", readings: "えがお", shortcodes: "grin"),
        line("emoji", "smileys", "😆", "目を閉じて笑う", "めをとじてわらう", "squinting face", readings: "えがお", shortcodes: "laughing"),
        line("emoji", "smileys", "😅", "冷や汗", "ひやあせ", "grinning face with sweat", readings: "あせ", shortcodes: "sweat_smile"),
        line("emoji", "smileys", "😂", "嬉し泣き", "うれしなき", "face with tears of joy", readings: "わらい", keywords: "joy", shortcodes: "joy"),
        line("emoji", "people", "🙇", "おじぎする人", "おじぎするひと", "person bowing", readings: "おじぎ|ごめんなさい", keywords: "bow", shortcodes: "bow",
             tones: "🙇🏻|🙇🏼|🙇🏽|🙇🏾|🙇🏿"),
        line("emoji", "people", "👍", "サムズアップ", "さむずあっぷ", "thumbs up", readings: "いいね", keywords: "good", shortcodes: "+1|thumbsup",
             tones: "👍🏻|👍🏼|👍🏽|👍🏾|👍🏿"),
        line("emoji", "people", "👋", "手を振る", "てをふる", "waving hand", readings: "ばいばい", shortcodes: "wave", tones: "👋🏻|👋🏼|👋🏽|👋🏾|👋🏿"),
        line("symbol", "arrows", "→", "右向矢印", "みぎむきやじるし", "rightwards arrow", readings: "やじるし|みぎ"),
        line("symbol", "punctuation", "※", "米印", "こめじるし", "reference mark", readings: "こめ"),
        // 顔文字は笑顔が 3 個，悲しみと挨拶が 1 個ずつ．絵文字と同じ読み(えがお・おじぎ)を持たせ，探した結果に混ざらないことを確かめる
        line("kaomoji", "joy", "(^o^)", "にこにこ", "にこにこ", "", readings: "にこにこ|えがお"),
        line("kaomoji", "joy", "(*^^*)", "てれ", "てれ", "", readings: "てれ|にこにこ"),
        line("kaomoji", "joy", "＼(^o^)／", "ばんざい", "ばんざい", "", readings: "ばんざい"),
        line("kaomoji", "sorrow", "(T_T)", "しくしく", "しくしく", "", readings: "しくしく|なみだ"),
        line("kaomoji", "greeting", "m(_ _)m", "ぺこり", "ぺこり", "", readings: "ぺこり|おじぎ"),
    ].joined(separator: "\n")

    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func harness(settings change: (inout Settings) -> Void = { _ in }, usage: FakePaletteUsageStore = FakePaletteUsageStore(),
                         catalog: FakePaletteCatalog = FakePaletteCatalog(table)) -> Harness {
        var settings = DefaultSettings.settings
        settings.paletteColumns = 6
        settings.paletteRows = 3
        change(&settings)
        let now = start
        return Harness(converter: FakeConverter(["かな": [("仮名", nil)]]), settings: settings,
                       palette: { _ in PaletteServices(catalog: catalog, usage: usage, now: { now }) })
    }

    private func openEmoji(_ harness: Harness) {
        harness.press(.character("e"), [.control, .option])
    }

    private func texts(_ panel: PalettePanel?) -> [[String]] {
        panel?.rows.map { $0.cells.map(\.text) } ?? []
    }

    @Test("R-26: ⌃⌥E で絵文字のパレットを開き，組み立て中の文字は先に確定する")
    func opens() throws {
        let harness = harness()
        harness.type("kana")
        openEmoji(harness)
        let panel = try #require(harness.palette)
        #expect(harness.committed == "かな")
        #expect(panel.modes.first { $0.isSelected }?.kind == .emoji)
        #expect(texts(panel) == [["😀", "😃", "😄", "😁", "😆", "😅"], ["😂"], ["🙇", "👍", "👋"]])
        #expect(panel.rowCount == 3)
        #expect(panel.selection == PalettePanel.Position(row: 0, column: 0))
        #expect(panel.heading == "顔と感情")
        #expect(panel.tabs.map(\.title) == ["顔と感情", "人と体"])
        #expect(panel.preview?.japaneseName == "にっこり笑う")
        #expect(panel.preview?.shortcodes == [":grinning:"])
        #expect(panel.preview?.codePoints == "U+1F600")
        #expect(panel.showsPreview)
        // 説明を出さない設定なら説明も欄も無い
        let hidden = self.harness { $0.paletteShowsPreview = false }
        openEmoji(hidden)
        #expect(hidden.palette?.preview == nil)
        #expect(hidden.palette?.showsPreview == false)
    }

    @Test("R-26: ローマ字で打つとかなにして探し，Enter で先頭の文字を入れて閉じる")
    func searchAndInsert() throws {
        let harness = harness()
        openEmoji(harness)
        harness.type("ojigi")
        let panel = try #require(harness.palette)
        #expect(panel.query == "おじぎ")
        #expect(texts(panel).first == ["🙇"])
        #expect(panel.tabs.isEmpty)
        harness.press(.enter)
        #expect(harness.committed == "🙇")
        #expect(harness.palette == nil)
        #expect(harness.lastResult.handled)
    }

    @Test("R-26: 英語の綴りは打ったままを見せ，英語の名前とショートコードで探す")
    func englishQuery() {
        let harness = harness()
        openEmoji(harness)
        harness.type("thumb")
        #expect(harness.palette?.query == "thumb")
        #expect(texts(harness.palette).first?.first == "👍")
    }

    @Test("R-26: 「:bow:」と閉じたショートコードは，そのまま入れる")
    func closedShortcode() {
        let harness = harness()
        openEmoji(harness)
        harness.type(":bow:")
        #expect(harness.committed == "🙇")
        #expect(harness.palette == nil)
    }

    @Test("R-26: Esc は探す語を消し，次の Esc で閉じる．⌫ は 1 文字ずつ消す")
    func escapeAndBackspace() {
        let harness = harness()
        openEmoji(harness)
        harness.type("joy")
        harness.press(.backspace)
        // 日本語入力ではかなにして見せる(英語の綴りとしても探す)
        #expect(harness.palette?.query == "じょ")
        harness.press(.escape)
        #expect(harness.palette?.query == "")
        #expect(harness.palette?.rowCount == 3)
        harness.press(.escape)
        #expect(harness.palette == nil)
        #expect(harness.committed == "")
    }

    @Test("R-26: 矢印で動き，見えない行に動いたらスクロールする．Tab で次のまとまりの頭へ")
    func navigation() {
        let harness = harness { $0.paletteRows = 2 }
        openEmoji(harness)
        harness.press(.right)
        harness.press(.down)
        // 2 行目は 1 個しかないので，その行の最後に寄せる
        #expect(harness.palette?.selection == PalettePanel.Position(row: 1, column: 0))
        harness.press(.down)
        #expect(harness.palette?.selection == PalettePanel.Position(row: 2, column: 0))
        #expect(harness.palette?.firstRow == 1)
        #expect(harness.palette?.rows.map(\.index) == [1, 2])
        harness.press(.left)
        #expect(harness.palette?.selection == PalettePanel.Position(row: 1, column: 0))
        // まとまりの途中なら頭へ，頭なら前のまとまりへ
        harness.press(.tab, .shift)
        #expect(harness.palette?.selection == PalettePanel.Position(row: 0, column: 0))
        harness.press(.tab, .shift)
        #expect(harness.palette?.selection == PalettePanel.Position(row: 2, column: 0))
        harness.press(.tab)
        #expect(harness.palette?.selection == PalettePanel.Position(row: 0, column: 0))
        harness.press(.tab)
        #expect(harness.palette?.selection == PalettePanel.Position(row: 2, column: 0))
        #expect(harness.palette?.tabs.first { $0.isSelected }?.title == "人と体")
        harness.press(.end)
        #expect(harness.palette?.selection == PalettePanel.Position(row: 2, column: 2))
    }

    @Test("R-26: ⌃Tab と ⌃⌥K で記号に切り替え，開いている種類のキーで閉じる")
    func switchKind() {
        let harness = harness()
        openEmoji(harness)
        harness.press(.tab, .control)
        #expect(harness.palette?.modes.first { $0.isSelected }?.kind == .symbol)
        #expect(texts(harness.palette) == [["※"], ["→"]])
        harness.press(.character("e"), [.control, .option])
        #expect(harness.palette?.modes.first { $0.isSelected }?.kind == .emoji)
        harness.press(.character("e"), [.control, .option])
        #expect(harness.palette == nil)
        // 次は前に見ていた種類で開く(入力メニューから開くとき)
        harness.press(.character("k"), [.control, .option])
        harness.press(.enter)
        #expect(harness.committed == "※")
    }

    @Test("R-26: ⌃Tab で絵文字・記号・顔文字の順に切り替え，顔文字は広いマスに並べる")
    func kaomoji() throws {
        let harness = harness { $0.paletteRows = 4 }
        openEmoji(harness)
        harness.press(.tab, .control)
        harness.press(.tab, .control)
        let panel = try #require(harness.palette)
        #expect(panel.modes.map(\.kind) == [.emoji, .symbol, .kaomoji])
        #expect(panel.modes.first { $0.isSelected }?.kind == .kaomoji)
        // 窓の幅(列の数)は変えず，1 行に 6 / 3 = 2 個の広いマスを並べる
        #expect(panel.columns == 6)
        #expect(panel.cellsPerRow == 2)
        #expect(texts(panel) == [["(^o^)", "(*^^*)"], ["＼(^o^)／"], ["(T_T)"], ["m(_ _)m"]])
        #expect(panel.tabs.map(\.title) == ["笑顔", "悲しみ", "挨拶と動作"])
        #expect(panel.placeholder == "顔文字を検索")
        #expect(panel.preview?.japaneseName == "にこにこ")
        // 名前と同じ読みは説明の読みに重ねて出さない
        #expect(panel.preview?.readings == ["えがお"])
        // 符号位置は長いだけなので出さない
        #expect(panel.preview?.codePoints == "")
        harness.press(.right)
        harness.press(.down)
        #expect(harness.palette?.selection == PalettePanel.Position(row: 1, column: 0))
        harness.press(.enter)
        #expect(harness.committed == "＼(^o^)／")
        // 前に見ていた顔文字で開き，⌃Tab で絵文字に戻る
        harness.press(.character("e"), [.control, .option])
        harness.press(.tab, .control)
        harness.press(.tab, .control)
        harness.press(.tab, .control)
        #expect(harness.palette?.modes.first { $0.isSelected }?.kind == .emoji)
        #expect(harness.palette?.cellsPerRow == 6)
    }

    @Test("R-26: 顔文字のパレットのキーは既定では割り当てず，割り当てれば顔文字で開き，もう一度押すと閉じる")
    func kaomojiKey() {
        #expect(KeymapPreset.allCases.allSatisfy { $0.keymap.strokes(for: .kaomojiPalette, in: .idle).isEmpty })
        let harness = harness { $0.keymap.entries.append(KeymapEntry(.anywhere, KeyStroke(.character("j"), control: true, option: true), .kaomojiPalette)) }
        harness.press(.character("j"), [.control, .option])
        #expect(harness.palette?.modes.first { $0.isSelected }?.kind == .kaomoji)
        // ほかの種類のキーで切り替え，開いている種類のキーで閉じる
        harness.press(.character("e"), [.control, .option])
        #expect(harness.palette?.modes.first { $0.isSelected }?.kind == .emoji)
        harness.press(.character("j"), [.control, .option])
        harness.press(.character("j"), [.control, .option])
        #expect(harness.palette == nil)
    }

    @Test("R-26: 顔文字は顔文字のパレットでだけ探し，絵文字と記号の結果には混ぜない")
    func kaomojiSearch() {
        let harness = harness()
        openEmoji(harness)
        harness.type("ojigi")
        #expect(texts(harness.palette) == [["🙇"]])
        harness.click(.mode(.kaomoji))
        #expect(texts(harness.palette) == [["m(_ _)m"]])
        harness.press(.enter)
        #expect(harness.committed == "m(_ _)m")
    }

    @Test("R-26: ピン留めとよく使う文字は，マスの形が同じ種類のパレットにだけ出す")
    func kaomojiShortcuts() {
        let usage = FakePaletteUsageStore()
        let harness = harness(usage: usage)
        openEmoji(harness)
        harness.type("thumbsup")
        harness.press(.enter)
        openEmoji(harness)
        harness.click(.mode(.kaomoji))
        harness.type("shikushiku")
        harness.press(.enter)
        #expect(harness.committed == "👍(T_T)")

        openEmoji(harness)
        #expect(texts(harness.palette).first == ["👍"])
        harness.click(.mode(.kaomoji))
        #expect(harness.palette?.tabs.first?.title == "よく使う")
        #expect(texts(harness.palette).first == ["(T_T)"])
        // 顔文字をピン留めしても，絵文字のパレットには出さない
        harness.press(.down)
        harness.press(.character("d"), .control)
        #expect(usage.usage.pinned == ["(^o^)"])
        #expect(harness.palette?.tabs.first?.title == "ピン留め")
        harness.click(.mode(.emoji))
        #expect(harness.palette?.tabs.map(\.title).contains("ピン留め") == false)
    }

    @Test("R-26: 探しているときは，今見ている種類の文字を先に出す")
    func searchPrefersKind() {
        let harness = harness()
        harness.press(.character("k"), [.control, .option])
        harness.type("kome")
        #expect(texts(harness.palette).first?.first == "※")
    }

    @Test("R-26: ⇧Enter は閉じずに続けて入れる．閉じない設定なら Enter でも閉じない")
    func insertAndContinue() {
        let harness = harness()
        openEmoji(harness)
        harness.press(.enter, .shift)
        harness.press(.right)
        harness.press(.enter, .shift)
        #expect(harness.committed == "😀😃")
        #expect(harness.palette != nil)

        let keeps = self.harness { $0.paletteClosesAfterInsert = false }
        openEmoji(keeps)
        keeps.press(.enter)
        #expect(keeps.committed == "😀")
        #expect(keeps.palette != nil)
    }

    @Test("R-26: ⌥Enter で肌の色の帯を開き，選んだ肌の色で入れて，その絵文字の肌の色として覚える")
    func skinTone() throws {
        let usage = FakePaletteUsageStore()
        let harness = harness(usage: usage)
        openEmoji(harness)
        harness.type("ojigi")
        harness.press(.enter, .option)
        let picker = try #require(harness.palette?.skinTonePicker)
        #expect(picker.options == ["🙇", "🙇🏻", "🙇🏼", "🙇🏽", "🙇🏾", "🙇🏿"])
        #expect(picker.selected == 0)
        harness.press(.right)
        harness.press(.right)
        harness.press(.enter)
        #expect(harness.committed == "🙇🏼")
        #expect(usage.usage.skinTone(for: "🙇") == .mediumLight)
        // 次に開いたときは覚えた肌の色で見せて入れる．使った度合いは基本の形に積む
        openEmoji(harness)
        harness.type("ojigi")
        #expect(texts(harness.palette).first == ["🙇🏼"])
        harness.press(.enter)
        #expect(harness.committed == "🙇🏼🙇🏼")
        #expect(usage.usage.score(of: "🙇", at: start) == 2)
    }

    @Test("R-26: 肌の色を変えられない絵文字では帯を開かない．既定の肌の色は足元のボタンで変える")
    func defaultSkinTone() {
        let usage = FakePaletteUsageStore()
        let harness = harness(usage: usage)
        openEmoji(harness)
        harness.press(.enter, .option)
        #expect(harness.palette?.skinTonePicker == nil)
        harness.click(.skinToneButton)
        #expect(harness.palette?.skinTonePicker?.options.first == "👋")
        harness.click(.skinTone(.dark))
        #expect(usage.usage.defaultSkinTone == .dark)
        #expect(harness.palette?.skinTone == .dark)
        harness.press(.tab)
        #expect(texts(harness.palette).last == ["🙇🏿", "👍🏿", "👋🏿"])
    }

    @Test("R-26: よく使う文字の行は開いたときに作り，表の上に出す")
    func frequentRow() {
        let usage = FakePaletteUsageStore()
        let harness = harness(usage: usage)
        openEmoji(harness)
        harness.type("thumbsup")
        harness.press(.enter)
        openEmoji(harness)
        #expect(harness.palette?.tabs.first?.title == "よく使う")
        #expect(texts(harness.palette).first == ["👍"])
        #expect(harness.palette?.heading == "よく使う")
        // 履歴を残さない設定なら出さない
        let off = self.harness(settings: { $0.paletteRecordsHistory = false }, usage: usage)
        openEmoji(off)
        #expect(off.palette?.tabs.first?.title == "顔と感情")
    }

    @Test("R-26: ⌃D でピン留めし，ピン留めの行を先頭に出す．もう一度押すと外す")
    func pin() {
        let usage = FakePaletteUsageStore()
        let harness = harness(usage: usage)
        openEmoji(harness)
        harness.press(.right)
        harness.press(.character("d"), .control)
        #expect(usage.usage.pinned == ["😃"])
        #expect(harness.palette?.tabs.first?.title == "ピン留め")
        #expect(texts(harness.palette).first == ["😃"])
        #expect(harness.palette?.preview?.isPinned == true)
        harness.press(.character("d"), .control)
        #expect(usage.usage.pinned.isEmpty)
    }

    @Test("R-26: マウスで押した文字を入れ，ポインタを置いた文字を選ぶ．タブで飛び，ホイールでスクロールする")
    func pointer() {
        let harness = harness { $0.paletteRows = 2 }
        openEmoji(harness)
        harness.click(.hover(PalettePanel.Position(row: 0, column: 2)))
        #expect(harness.palette?.preview?.text == "😄")
        harness.click(.scroll(5))
        #expect(harness.palette?.firstRow == 1)
        harness.click(.tab(.category(.people)))
        #expect(harness.palette?.selection == PalettePanel.Position(row: 2, column: 0))
        harness.click(.mode(.symbol))
        #expect(harness.palette?.modes.first { $0.isSelected }?.kind == .symbol)
        harness.click(.mode(.emoji))
        harness.click(.cell(PalettePanel.Position(row: 2, column: 1)))
        #expect(harness.committed == "👍")
        #expect(harness.palette == nil)
    }

    @Test("R-26: ⌘ との組み合わせはパレットを閉じてアプリに渡す．入力先から外れたら閉じる")
    func closesForCommandAndFocus() {
        let harness = harness()
        openEmoji(harness)
        harness.press(.character("v"), .command)
        #expect(harness.palette == nil)
        #expect(!harness.lastResult.handled)
        openEmoji(harness)
        #expect(harness.session.deactivate().contains(.hidePalette))
        #expect(!harness.session.isPaletteOpen)
    }

    @Test("R-26: 英数入力では探す欄に打ったままを見せる．かなにした読みでも探す")
    func directMode() {
        let harness = harness()
        harness.press(.eisu)
        openEmoji(harness)
        harness.type("ojigi")
        #expect(harness.palette?.query == "ojigi")
        #expect(texts(harness.palette).first?.first == "🙇")
    }

    @Test("R-26: パレットを使わない設定か，アプリがパレットを描けないときは，キーを受けずにアプリに渡す")
    func unavailable() {
        let off = harness { $0.palette = false }
        openEmoji(off)
        #expect(off.palette == nil)
        #expect(!off.lastResult.handled)
        let unsupported = Harness()
        unsupported.press(.character("e"), [.control, .option])
        #expect(!unsupported.lastResult.handled)
        #expect(unsupported.session.openPalette().isEmpty)
    }

    @Test("R-26: 表を読み込んでいるあいだは知らせを出し，見つからなければそう知らせる")
    func messages() {
        let catalog = FakePaletteCatalog(Self.table)
        catalog.index = nil
        let loading = harness(catalog: catalog)
        openEmoji(loading)
        #expect(loading.palette?.message == PaletteStrings.loading)
        let harness = harness()
        openEmoji(harness)
        harness.type("zzzz")
        #expect(harness.palette?.message == PaletteStrings.notFound)
        harness.press(.enter)
        #expect(harness.committed == "")
    }

    @Test("R-26: 探して選んだ文字は，次に同じ語で探したときに先に出す．履歴を残さない設定なら並びを変えない")
    func learnsChoice() {
        let usage = FakePaletteUsageStore()
        let harness = harness(usage: usage)
        openEmoji(harness)
        harness.type("ega")
        #expect(texts(harness.palette).first?.first == "😀")
        harness.press(.right)
        harness.press(.enter)
        #expect(harness.committed == "😃")
        openEmoji(harness)
        harness.type("ega")
        #expect(texts(harness.palette).first?.first == "😃")
        #expect(usage.usage.lastKind == .emoji)

        let off = self.harness(settings: { $0.paletteRecordsHistory = false }, usage: usage)
        openEmoji(off)
        off.type("ega")
        #expect(texts(off.palette).first?.first == "😀")
    }
}
