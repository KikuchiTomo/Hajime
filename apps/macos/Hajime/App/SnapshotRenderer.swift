#if DEBUG
import AppKit
import HajimeApplication
import HajimeDomain
import HajimePersistence
import SwiftUI

/// 候補ウィンドウの見た目を画像に書き出す(デバッグビルドだけ)．
/// 入力メソッドとして動かさずに描画を確かめ，PR に貼るスクリーンショットを作るため．
///
/// 使い方: Debug でビルドした "Hajime Debug.app/Contents/MacOS/Hajime Debug" --render-snapshots
/// サンドボックスの中で動くので，書き出し先はサンドボックスの一時ディレクトリになる．場所は標準出力に出す
@MainActor
enum SnapshotRenderer {
    static let argument = "--render-snapshots"

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.contains(argument) else { return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-snapshots", isDirectory: true)
        print(output.path)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sample = CustomTheme(id: "sample", name: "夕焼け", base: .automatic, surface: HexColor("#2B1B17")!, text: HexColor("#FFE8D6")!,
                                 textMuted: HexColor("#C9A68F")!, selection: HexColor("#FF7A3D")!, selectionText: HexColor("#1A0E0A")!,
                                 correction: HexColor("#FFD23F")!, line: HexColor("#6B4A3E")!, fontName: "HiraMaruProN-W4", cornerRadius: 4, branchStyle: .straight)
        let looks: [(theme: ThemeChoice, appearance: NSAppearance.Name, name: String)] = [
            (ThemeChoice(.automatic, custom: sample), .darkAqua, "custom"),
            (ThemeChoice(.automatic), .aqua, "glass-light"), (ThemeChoice(.automatic), .darkAqua, "glass-dark"), (ThemeChoice(.platinum), .aqua, "platinum"), (ThemeChoice(.desk), .darkAqua, "desk"),
            (ThemeChoice(.washi), .aqua, "washi"), (ThemeChoice(.neon), .darkAqua, "neon"), (ThemeChoice(.terminal), .darkAqua, "terminal"), (ThemeChoice(.nordic), .aqua, "nordic"),
            (ThemeChoice(.contrast), .darkAqua, "contrast"), (ThemeChoice(.indigo), .aqua, "indigo"), (ThemeChoice(.indigoNight), .darkAqua, "indigo-night"),
        ]
        checkPointerTargets()
        checkGridPointerTargets()
        for look in looks {
            let appearance = NSAppearance(named: look.appearance)
            // 色を今の外観で決める部品があるので，その外観を描くときの外観にして組み立てる
            (appearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
                render(listView(theme: look.theme, appearance: appearance), name: "list-\(look.name)", to: output, appearance: appearance)
                render(gridView(SamplePanels.grid, theme: look.theme, appearance: appearance), name: "list-grid-\(look.name)", to: output, appearance: appearance)
                render(suggestionView(theme: look.theme, appearance: appearance), name: "suggestion-\(look.name)", to: output, appearance: appearance)
                render(latticeView(theme: look.theme, appearance: appearance), name: "branch-\(look.name)", to: output, appearance: appearance)
                render(previewView(theme: look.theme, appearance: appearance), name: "branch-preview-\(look.name)", to: output, appearance: appearance)
                render(latticeView(fewerItemsLattice(), theme: look.theme, appearance: appearance), name: "branch-fewer-\(look.name)", to: output,
                       appearance: appearance)
                // 先の枝(語の意味・連想・変換マクロ)．候補にいるとき・連想の丸の上・マクロの丸の中身
                for (suffix, panel) in [("", stationLattice(current: nil, inside: false)), ("-association", stationLattice(current: 1, inside: false)),
                                        ("-macro", stationLattice(current: 2, inside: true))] {
                    render(latticeView(panel, theme: look.theme, appearance: appearance), name: "branch-station\(suffix)-\(look.name)", to: output,
                           appearance: appearance)
                }
                // 先の枝を，キーの案内を押し続けているあいだだけ出す設定(既定)で．公式サイトのトップの画像に使う
                var quietStations = stationLattice(current: nil, inside: false)
                quietStations.hintsOnHold = true
                render(latticeView(quietStations, theme: look.theme, appearance: appearance), name: "branch-station-hold-\(look.name)", to: output,
                       appearance: appearance)
                // 矢印キーで木をたどっていて，幹の上(文節)にいるところ．ページの位置は縦の線の下の点
                render(latticeView(trunkLattice(), theme: look.theme, appearance: appearance), name: "branch-trunk-\(look.name)", to: output,
                       appearance: appearance)
                // キーの案内を，修飾キーを押し続けているあいだだけ出す設定(既定)．押していないとき・Shift・Option
                for (suffix, modifiers) in [("", NSEvent.ModifierFlags()), ("-shift", .shift), ("-option", .option)] {
                    render(latticeView(heldHintsLattice(), theme: look.theme, appearance: appearance, heldModifiers: modifiers),
                           name: "branch-hold\(suffix)-\(look.name)", to: output, appearance: appearance)
                }
                render(splitView(theme: look.theme, appearance: appearance), name: "branch-split-\(look.name)", to: output, appearance: appearance)
                // 文節をその場で打ち直しているところ(⇧⌫)．読みを打っている途中と，まだ何も打っていないところ
                render(latticeView(editingLattice(typed: "なかの"), theme: look.theme, appearance: appearance), name: "branch-editing-\(look.name)",
                       to: output, appearance: appearance)
                render(latticeView(editingLattice(typed: ""), theme: look.theme, appearance: appearance), name: "branch-editing-empty-\(look.name)",
                       to: output, appearance: appearance)
                render(panelView(editingList, theme: look.theme, appearance: appearance), name: "list-editing-\(look.name)", to: output, appearance: appearance)
                render(correctionView(theme: look.theme, appearance: appearance), name: "correction-\(look.name)", to: output, appearance: appearance)
                render(readingCorrectionView(theme: look.theme, appearance: appearance), name: "correction-reading-\(look.name)", to: output, appearance: appearance)
                render(correctedLatticeView(theme: look.theme, appearance: appearance), name: "branch-correction-\(look.name)", to: output, appearance: appearance)
                render(noteView(Note(tone: .correction, title: "修正", subject: "オン外します", key: "Esc", keyAction: "元に戻す"), theme: look.theme, appearance: appearance),
                       name: "note-correction-\(look.name)", to: output, appearance: appearance)
                render(noteView(Note(tone: .suggestion, title: "もしかして", subject: "お願いします", key: "Tab", keyAction: "修正"), theme: look.theme, appearance: appearance),
                       name: "note-suggestion-\(look.name)", to: output, appearance: appearance)
                render(modeView(theme: look.theme, appearance: appearance), name: "mode-\(look.name)", to: output, appearance: appearance)
                render(associationListView(theme: look.theme, appearance: appearance), name: "association-list-\(look.name)", to: output, appearance: appearance)
                render(associationBranchView(theme: look.theme, appearance: appearance), name: "association-branch-\(look.name)", to: output, appearance: appearance)
                render(homophoneListView(theme: look.theme, appearance: appearance), name: "homophone-list-\(look.name)", to: output, appearance: appearance)
                render(homophoneListView(theme: look.theme, appearance: appearance, nearRightEdge: true), name: "homophone-list-left-\(look.name)",
                       to: output, appearance: appearance)
                render(homophoneBranchView(theme: look.theme, appearance: appearance), name: "homophone-branch-\(look.name)", to: output, appearance: appearance)
                // 1 番目といちばん下を選んだところ(吹き出しの上の端は窓の上の端にそろえ，三角だけが動く)
                render(homophoneListView(theme: look.theme, appearance: appearance, selected: 3), name: "homophone-list-lower-\(look.name)",
                       to: output, appearance: appearance)
                render(homophoneBranchView(theme: look.theme, appearance: appearance, selected: 0, note: took),
                       name: "homophone-branch-first-\(look.name)", to: output, appearance: appearance)
                render(homophoneBranchView(theme: look.theme, appearance: appearance, selected: 3, note: adopted),
                       name: "homophone-branch-lower-\(look.name)", to: output, appearance: appearance)
                render(meaningListView(theme: look.theme, appearance: appearance), name: "meaning-list-\(look.name)", to: output, appearance: appearance)
                render(homophoneListView(theme: look.theme, appearance: appearance, placement: .below), name: "homophone-list-below-\(look.name)", to: output, appearance: appearance)
                render(homophoneBranchView(theme: look.theme, appearance: appearance, placement: .below), name: "homophone-branch-below-\(look.name)", to: output, appearance: appearance)
                render(meaningEmptyListView(theme: look.theme, appearance: appearance), name: "meaning-list-empty-\(look.name)", to: output, appearance: appearance)
                render(homophoneBranchView(theme: look.theme, appearance: appearance, selected: 2), name: "homophone-branch-empty-\(look.name)", to: output, appearance: appearance)
                render(commandListView(theme: look.theme, appearance: appearance, selected: 0), name: "command-list-\(look.name)", to: output, appearance: appearance)
                render(commandListView(theme: look.theme, appearance: appearance, selected: 1), name: "command-list-selected-\(look.name)", to: output, appearance: appearance)
                render(commandBranchView(theme: look.theme, appearance: appearance), name: "command-branch-\(look.name)", to: output, appearance: appearance)
                render(commentListView(theme: look.theme, appearance: appearance), name: "comment-list-\(look.name)", to: output, appearance: appearance)
                render(commentBranchView(theme: look.theme, appearance: appearance), name: "comment-branch-\(look.name)", to: output, appearance: appearance)
                render(paletteView(SamplePalettes.emoji, theme: look.theme, appearance: appearance), name: "palette-emoji-\(look.name)", to: output, appearance: appearance)
                render(paletteView(SamplePalettes.search, theme: look.theme, appearance: appearance), name: "palette-search-\(look.name)", to: output, appearance: appearance)
                render(paletteView(SamplePalettes.flag, theme: look.theme, appearance: appearance), name: "palette-flag-\(look.name)", to: output, appearance: appearance)
                render(paletteView(SamplePalettes.longName, theme: look.theme, appearance: appearance), name: "palette-long-\(look.name)", to: output, appearance: appearance)
                render(paletteView(SamplePalettes.reduced, theme: look.theme, appearance: appearance), name: "palette-reduced-\(look.name)", to: output, appearance: appearance)
                render(paletteView(SamplePalettes.symbol, theme: look.theme, appearance: appearance), name: "palette-symbol-\(look.name)", to: output, appearance: appearance)
                render(paletteView(SamplePalettes.kaomoji, theme: look.theme, appearance: appearance), name: "palette-kaomoji-\(look.name)", to: output, appearance: appearance)
                // スクロールして選んでいる文字の行が見えなくなったところと，選択の枠が滑っている途中でスクロールしたところ
                render(paletteView(SamplePalettes.scrolledUp, theme: look.theme, appearance: appearance), name: "palette-scrolled-up-\(look.name)", to: output,
                       appearance: appearance)
                render(paletteView(SamplePalettes.scrolledDown, theme: look.theme, appearance: appearance), name: "palette-scrolled-down-\(look.name)",
                       to: output, appearance: appearance)
                let scroll = SamplePalettes.scrollWhileSliding
                render(paletteMotionView(from: scroll.from, to: scroll.sliding, then: scroll.scrolled, at: scroll.time, theme: look.theme, appearance: appearance),
                       name: "palette-scroll-sliding-\(look.name)", to: output, appearance: appearance)
                // 動きの途中のコマ(選択の枠とタブの印が滑る・種類を切り替えて中身を送る・肌の色の帯が浮かび上がる)
                for (step, sample) in SamplePalettes.motionSteps.enumerated() {
                    render(paletteMotionView(from: sample.from, to: sample.to, at: sample.time, theme: look.theme, appearance: appearance),
                           name: "palette-motion-\(step + 1)-\(look.name)",
                           to: output, appearance: appearance)
                }
                render(associationHintListView(theme: look.theme, appearance: appearance), name: "association-hint-list-\(look.name)", to: output, appearance: appearance)
                render(predictionView(theme: look.theme, appearance: appearance), name: "prediction-\(look.name)", to: output, appearance: appearance)
                render(panelView(SamplePanels.emojiList, theme: look.theme, appearance: appearance), name: "emoji-list-\(look.name)", to: output, appearance: appearance)
                render(panelView(SamplePanels.emojiSuggestion, theme: look.theme, appearance: appearance), name: "emoji-suggestion-\(look.name)", to: output,
                       appearance: appearance)
                render(latticeView(SamplePanels.emojiLattice, theme: look.theme, appearance: appearance), name: "emoji-branch-\(look.name)", to: output,
                       appearance: appearance)
                render(associationHintBranchView(theme: look.theme, appearance: appearance), name: "association-hint-branch-\(look.name)", to: output, appearance: appearance)
            }
        }
        // 長い文: 窓は幅の上限に収め，一覧は末尾を省き，分岐図は注目している文節が見えるように幹をずらす
        for look in looks where ["glass-dark", "platinum"].contains(look.name) {
            let appearance = NSAppearance(named: look.appearance)
            (appearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
                for focus in [0, 6, 13] {
                    render(longLatticeView(theme: look.theme, appearance: appearance, focus: focus), name: "branch-long-\(focus)-\(look.name)", to: output, appearance: appearance)
                    // 長い文をまとまりに区切って出す(1 つのまとまりは 5 文節まで)．最初・途中・最後のまとまり
                    render(groupLatticeView(theme: look.theme, appearance: appearance, focus: focus), name: "branch-group-\(focus)-\(look.name)", to: output,
                           appearance: appearance)
                }
                // 窓の幅を固定する設定．最後の文節の枝が右に入らないので，左右に反転して左へ出す
                var fixed = SamplePanels.withKeys(SamplePanels.lattice)
                fixed.keepsWidth = true
                render(latticeView(fixed, theme: look.theme, appearance: appearance), name: "branch-fixed-\(look.name)", to: output, appearance: appearance)
                render(longListView(theme: look.theme, appearance: appearance), name: "list-long-\(look.name)", to: output, appearance: appearance)
                render(gridView(longGrid, theme: look.theme, appearance: appearance), name: "list-grid-long-\(look.name)", to: output, appearance: appearance)
            }
        }
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            let look = NSAppearance(named: appearance)
            (look ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
                render(keymapView(edited: false, appearance: look), name: "keymap-\(name)", to: output, appearance: look)
                render(keymapView(edited: true, appearance: look), name: "keymap-warnings-\(name)", to: output, appearance: look)
                render(handwritingView(appearance: look), name: "handwriting-\(name)", to: output, appearance: look)
                // 窓を横に広げても，書く欄は正方形のまま真ん中に置く
                render(handwritingView(appearance: look, size: NSSize(width: DesignTokens.Size.Handwriting.width * 1.6, height: DesignTokens.Size.Handwriting.height)),
                       name: "handwriting-wide-\(name)", to: output, appearance: look)
            }
        }
        renderSettings(to: output)
        exit(0)
    }

    /// ページ(Form)を下の端まで送る．表の中のスクロールは動かさない
    private static func scrollPageToBottom(_ window: NSWindow) {
        guard let content = window.contentView else { return }
        var stack: [NSView] = [content]
        while let view = stack.popLast() {
            if view is any FormTableContainer { continue }
            if let scroll = view as? NSScrollView, let document = scroll.documentView, !(document is NSTableView) {
                let bottom = document.isFlipped ? max(document.frame.height - scroll.contentView.bounds.height, 0) : 0
                scroll.contentView.scroll(to: NSPoint(x: 0, y: bottom))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            stack.append(contentsOf: view.subviews)
        }
    }

    /// 一時ディレクトリに置いた設定．利用者の設定に触れない
    private static func snapshotStore(_ name: String) -> FileSettingsStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-snapshot-\(name).json")
        try? FileManager.default.removeItem(at: url)
        return FileSettingsStore(fileURL: url)
    }

    /// 設定の画面の各ページ(ライトとダーク)と，カスタムテーマの編集の画面．設定は一時ディレクトリに置き，利用者の設定に触れない．
    /// 窓の枠(見出しと検索欄のあるツールバー)ごと写し，ページの中身がツールバーの下から始まるかも確かめられるようにする
    private static func renderSettings(to output: URL) {
        _ = NSApplication.shared
        let fixture = SettingsFixture.make(name: "snapshot")
        fixture.model.update { settings in
            settings.correction.rules = [CorrectionRule(typed: "teh", word: "the"), CorrectionRule(typed: "recieve", word: "receive"),
                                         CorrectionRule(typed: "adn", word: "and")]
            settings.customRomaji = [RomajiRule(keys: "wyi", kana: "ゐ"), RomajiRule(keys: "wye", kana: "ゑ")]
            settings.userDictionary = [UserDictionaryEntry(reading: "えすきゅー", word: "Hajime IME", wordClass: .properNoun),
                                       UserDictionaryEntry(reading: "かいしゃ", word: "会社", comment: "東京都千代田区千代田1-1"),
                                       UserDictionaryEntry(reading: "やまだ", word: "山田", wordClass: .surname),
                                       UserDictionaryEntry(reading: "おつ", word: "お疲れさまでした", wordClass: .abbreviation)]
            settings.symbolRules = [SymbolRule(kind: .sequence, input: "->", output: "⇢"), SymbolRule(kind: .sequence, input: "<<", output: "«"),
                                    SymbolRule(kind: .sequence, input: "=>", output: "⇒", isEnabled: false)]
            settings.profileRules = [ProfileRule(applicationPrefix: "com.apple.Terminal", profile: .imeOff),
                                     ProfileRule(applicationPrefix: "com.apple.Terminal", profile: .terminal),
                                     ProfileRule(applicationPrefix: "com.apple.Notes", profile: .remembersMode),
                                     ProfileRule(applicationPrefix: "com.tinyspeck.slackmacgap", profile: .imeOn)]
            settings.commands = [LauncherCommand(reading: "めも", title: "メモ", kind: .openApplication, target: "/System/Applications/Notes.app"),
                                 LauncherCommand(reading: "はじめ", title: "Hajime IME のサイト", kind: .openURL, target: "https://haji.men/")]
        }
        for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            let navigation = SettingsNavigation()
            let window = SettingsWindowController.makeWindow(model: fixture.model, sync: fixture.sync, navigation: navigation)
            window.orderFrontRegardless()
            for page in SettingsView.Page.allCases {
                navigation.page = page
                SettingsFixture.settle(window)
                guard let frame = window.contentView?.superview else { continue }
                render(frame, name: "settings-\(page)\(suffix)", to: output, appearance: NSAppearance(named: appearance))
            }
            window.close()
        }
        // 初期設定の各ページ(実演は最後の場面で止めて写す)
        DemoStageView.showsLastFrameOnly = true
        for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            let model = OnboardingModel(store: SettingsFixture.make(name: "onboarding").store)
            let window = OnboardingWindowController.makeWindow()
            window.contentView = OnboardingWindowController.makeContent(model: model)
            window.orderFrontRegardless()
            for page in OnboardingPage.allCases {
                // ページを切り替える動きを止め，切り替えたあとの画面を写す
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { model.page = page }
                SettingsFixture.settle(window)
                guard let frame = window.contentView?.superview else { continue }
                render(frame, name: "onboarding-\(page)\(suffix)", to: output, appearance: NSAppearance(named: appearance))
            }
            window.close()
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        // 行の多い表を下までスクロールしたとき，行が列の見出しの下に潜らないか
        fixture.model.update { $0.profileRules = (0..<14).map { ProfileRule(applicationPrefix: "com.example.app\($0)", profile: .terminal) } }
        let manyNavigation = SettingsNavigation()
        let scrolled = SettingsWindowController.makeWindow(model: fixture.model, sync: fixture.sync, navigation: manyNavigation)
        manyNavigation.page = .apps
        scrolled.orderFrontRegardless()
        SettingsFixture.settle(scrolled)
        // ホイールと同じ道筋で，下まで動かしてから上の端まで戻す
        if let content = scrolled.contentView {
            var stack: [NSView] = [content]
            while let view = stack.popLast() {
                if let container = view as? any FormTableContainer {
                    container.scrollTable(by: -10_000)
                    container.scrollTable(by: 10_000)
                }
                stack.append(contentsOf: view.subviews)
            }
        }
        SettingsFixture.settle(scrolled)
        if let frame = scrolled.contentView?.superview { render(frame, name: "settings-apps-scrolled", to: output, appearance: NSAppearance(named: .aqua)) }
        // スクロールの途中(行が見出しの下を通るところ)．上の端に戻した画像だけでは，見出しと行の重なりが写らない
        for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            if let content = scrolled.contentView {
                var stack: [NSView] = [content]
                while let view = stack.popLast() {
                    if let container = view as? any FormTableContainer {
                        container.scrollTable(by: 10_000)
                        container.scrollTable(by: -DesignTokens.Size.Settings.ruleTableHeight / 2)
                    }
                    stack.append(contentsOf: view.subviews)
                }
            }
            SettingsFixture.settle(scrolled)
            if let frame = scrolled.contentView?.superview {
                render(frame, name: "settings-apps-scrolled-middle\(suffix)", to: output, appearance: NSAppearance(named: appearance))
            }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        scrolled.close()
        // ユーザー辞書の一覧(品詞の列)．一覧はページの下にあるので，ページを下まで送って写す
        let dictionaryNavigation = SettingsNavigation()
        let dictionaryWindow = SettingsWindowController.makeWindow(model: fixture.model, sync: fixture.sync, navigation: dictionaryNavigation)
        dictionaryNavigation.page = .dictionary
        dictionaryWindow.orderFrontRegardless()
        // 組み直しのあとにページの高さが変わることがあるので，落ち着くまで 2 回送る
        for _ in 0..<2 {
            SettingsFixture.settle(dictionaryWindow)
            scrollPageToBottom(dictionaryWindow)
        }
        SettingsFixture.settle(dictionaryWindow)
        if let frame = dictionaryWindow.contentView?.superview {
            render(frame, name: "settings-dictionary-words", to: output, appearance: NSAppearance(named: .aqua))
        }
        dictionaryWindow.close()
        // 下のほうに項目のあるページは，ページを下まで送った画像も写す(補正・英語と日本語・コマンド・除外・同期・情報)
        for page in [SettingsView.Page.correction, .language, .commands, .apps, .sync, .about] {
            let navigation = SettingsNavigation()
            let window = SettingsWindowController.makeWindow(model: fixture.model, sync: fixture.sync, navigation: navigation)
            navigation.page = page
            window.orderFrontRegardless()
            for _ in 0..<2 {
                SettingsFixture.settle(window)
                scrollPageToBottom(window)
            }
            SettingsFixture.settle(window)
            if let frame = window.contentView?.superview {
                render(frame, name: "settings-\(page)-bottom", to: output, appearance: NSAppearance(named: .aqua))
            }
            window.close()
        }
        // 単語と変換マクロの書き方のチップ(R-21・R-22)．縦に長い窓でページを開き，欄・欄の下の結果・チップをまとめて写す．
        // 前に開いた窓の欄が単語の下書きを受け取らないよう，別の設定で開く
        let templateFixture = SettingsFixture.make(name: "templates")
        // 変換マクロの一覧の結果の列と形の欄の下の結果を写すため，「試す」の仕組みを持たせた設定にする
        let macroPreview = ConversionMacroPreview(settings: templateFixture.store, calendar: SystemCalendar(clock: Date.init))
        // 単語の下書きは開いているすべての窓の欄が受け取るので，窓ごとに別の SettingsModel を作る(設定の入れ物は同じ)
        let makeTemplateModel = {
            SettingsModel(store: templateFixture.store, usage: nil, resetLearning: {},
                          previewMacros: { macroPreview.preview(text: $0, reading: $1, pattern: $2) })
        }
        // チップを開いているかはページごとに UserDefaults に覚えるので，写すあいだだけの入れ物を使う(Debug 版の記録を変えない)
        let storageName = "men.haji.snapshot.templates"
        let storage = UserDefaults(suiteName: storageName) ?? .standard
        // 閉じた状態(結果の行だけ)・ボタンで開いた状態・「{da」で絞り込んだ状態・スイッチがオフの状態と，変換マクロ(開いた状態)．
        // 単語の欄には，読める書き方と知らない名前を入れておく(結果と誤りの印)
        let dictionary = { (model: SettingsModel) in AnyView(DictionaryPage(model: model)) }
        let templatePages: [(name: String, dynamic: Bool, open: Bool, word: String, page: (SettingsModel) -> AnyView)] = [
            ("settings-templates-dictionary", true, false, "{date:M月D日(ddd)} {dat}", dictionary),
            ("settings-templates-dictionary-open", true, true, "{date:M月D日(ddd)} {dat}", dictionary),
            ("settings-templates-dictionary-typing", true, true, "締切 {da", dictionary),
            ("settings-templates-dictionary-off", false, true, "{date:M月D日(ddd)} {dat}", dictionary),
            ("settings-templates-macros", true, true, "", { AnyView(CommandsPage(model: $0, bookmarks: nil)) }),
        ]
        for (name, dynamic, open, word, page) in templatePages {
            makeTemplateModel().update { $0.dynamicDictionary = dynamic }
            storage.set(open, forKey: "settings.templates.dictionary.open")
            storage.set(open, forKey: "settings.templates.macros.open")
            // ダークの外観では，表の中を写すために窓を作り直す(外観を変えたあとの表の行が描き直されないことがある)
            for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
                NSApp.appearance = NSAppearance(named: appearance)
                let templateModel = makeTemplateModel()
                let pageSize = NSSize(width: SettingsView.size.width - DesignTokens.Size.Settings.sidebarWidth, height: SettingsView.size.height * 2)
                let host = NSHostingView(rootView: page(templateModel).defaultAppStorage(storage).frame(width: pageSize.width, height: pageSize.height))
                let pageWindow = NSWindow(contentRect: NSRect(origin: .zero, size: pageSize), styleMask: [.borderless], backing: .buffered, defer: false)
                pageWindow.contentView = host
                pageWindow.orderFrontRegardless()
                SettingsFixture.settle(pageWindow)
                if !word.isEmpty {
                    templateModel.userWordDraft = RuleDraft(key: "dt", value: word)
                    SettingsFixture.settle(pageWindow)
                    // 単語の欄は選ぶと中身をすべて選ぶので，入力位置を末尾に置く(打ちかけの「{da」で絞り込む)
                    (pageWindow.firstResponder as? NSTextView)?.setSelectedRange(NSRange(location: word.utf16.count, length: 0))
                    SettingsFixture.settle(pageWindow)
                }
                // 欄に入力位置があると選んだ文字が写るので，入力位置を外す
                pageWindow.makeFirstResponder(nil)
                SettingsFixture.settle(pageWindow)
                render(host, name: "\(name)\(suffix)", to: output, appearance: NSAppearance(named: appearance))
                pageWindow.close()
            }
        }
        storage.removePersistentDomain(forName: storageName)
        NSApp.appearance = NSAppearance(named: .aqua)
        // 左の一覧は窓の中では写らない(背景のぼかしの層を写せない)ので，一覧だけを別に描く
        let sidebar = NSHostingView(rootView: SettingsSidebar(query: "", selection: .constant(.correction)).listStyle(.inset))
        let sidebarWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DesignTokens.Size.Settings.sidebarWidth, height: SettingsView.size.height),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        sidebarWindow.contentView = sidebar
        sidebarWindow.orderFrontRegardless()
        SettingsFixture.settle(sidebarWindow)
        render(sidebar, name: "settings-sidebar", to: output, appearance: NSAppearance(named: .aqua))
        sidebarWindow.close()
        // 辞書のページの「専門用語」の中身(R-29．タブは窓の外から切り替えられないので中身だけを描く)．1 つの分野を切り，既定に戻すボタンも写す
        fixture.model.update { $0.termFields.religion = false }
        for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            let terms = NSHostingView(rootView: TermDictionaryView(model: fixture.model))
            let termsWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsView.size.width - DesignTokens.Size.Settings.sidebarWidth,
                                                           height: SettingsView.size.height),
                                       styleMask: [.borderless], backing: .buffered, defer: false)
            termsWindow.contentView = terms
            termsWindow.orderFrontRegardless()
            SettingsFixture.settle(termsWindow)
            render(terms, name: "settings-dictionary-terms\(suffix)", to: output, appearance: NSAppearance(named: appearance))
            termsWindow.close()
        }
        fixture.model.update { $0.termFields = TermFieldSettings() }
        // 辞書のファイルを取り込む前に中身を見せるシート(R-16・R-18・R-21)．名詞にする行と読めない行を含む見本のファイルを読む
        let importSamples: [(name: String, kind: ImportPreview.Kind, file: String, text: String)] = [
            ("settings-import-preview-words", .userDictionary, "ユーザー辞書.txt", """
            !Microsoft IME Dictionary Tool
            はじめ\tHajime IME\t固有名詞\t
            しぶや\t渋谷\t地名
            かぶしきがいしゃ\t株式会社
            めーる\thajime@example.com\t短縮よみ
            はしる\t走る\t動詞
            ひとつだけ
            とうきょう\t東京\t地名\t首都
            漢字\t読みがひらがなでない
            """),
            ("settings-import-preview-association", .association, "連想.txt", """
            明るい\t明るい\t朗らか\t陽気
            嬉しい,楽しい,喜ばしい
            ひとつ
            """),
        ]
        for (name, kind, file, text) in importSamples {
            guard let preview = try? ImportPreviewReader.preview(kind, data: Data(text.utf8)) else { continue }
            let pending = PendingImport(kind: kind, path: "/tmp/\(file)", preview: preview, replacing: nil)
            for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
                NSApp.appearance = NSAppearance(named: appearance)
                // 写す窓は前に出ていないので，既定のボタンが灰色になる．前に出ている窓と同じに描く
                let sheet = NSHostingView(rootView: ImportPreviewSheet(pending: pending, commit: {}, cancel: {}).background(.background)
                    .environment(\.controlActiveState, .key))
                let sheetWindow = NSWindow(contentRect: NSRect(origin: .zero, size: sheet.fittingSize), styleMask: [.borderless], backing: .buffered, defer: false)
                sheetWindow.contentView = sheet
                sheetWindow.orderFrontRegardless()
                SettingsFixture.settle(sheetWindow)
                render(sheet, name: "\(name)\(suffix)", to: output, appearance: NSAppearance(named: appearance))
                sheetWindow.close()
            }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        // 変換のページの「絵文字」(ページの下のほうにあるので，まとまりだけを描く)．既定(ライトとダーク)と，
        // 位置と数と名前を変えたとき，文節を絵文字にしない(語だけを絵文字にする)ときに，下の見本の並びが変わるか
        let emojiCases: [(String, NSAppearance.Name, (inout HajimeDomain.Settings) -> Void)] = [
            ("", .aqua, { _ in }), ("-dark", .darkAqua, { _ in }),
            ("-changed", .aqua, { $0.emojiCandidatePosition = 6; $0.emojiCandidateCount = 3; $0.showsEmojiNames = false }),
            ("-word", .aqua, { $0.emojiConversion = false }),
            ("-off", .aqua, { $0.emojiConversion = false; $0.emojiWordConversion = false }),
        ]
        for (suffix, appearance, change) in emojiCases {
            NSApp.appearance = NSAppearance(named: appearance)
            fixture.model.update(change)
            let emoji = NSHostingView(rootView: Form { EmojiSection(model: fixture.model) }.formStyle(.grouped)
                .frame(width: SettingsView.size.width - DesignTokens.Size.Settings.sidebarWidth))
            emoji.frame = NSRect(origin: .zero, size: emoji.fittingSize)
            let emojiWindow = NSWindow(contentRect: emoji.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            emojiWindow.contentView = emoji
            emojiWindow.orderFrontRegardless()
            SettingsFixture.settle(emojiWindow)
            render(emoji, name: "settings-emoji\(suffix)", to: output, appearance: NSAppearance(named: appearance))
            emojiWindow.close()
            fixture.model.update { settings in
                for keyPath in [\HajimeDomain.Settings.emojiConversion, \.emojiWordConversion, \.showsEmojiNames] {
                    settings[keyPath: keyPath] = DefaultSettings.settings[keyPath: keyPath]
                }
                settings.emojiCandidatePosition = DefaultSettings.emojiCandidatePosition
                settings.emojiCandidateCount = DefaultSettings.emojiCandidateCount
            }
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        // 読みにくい色を選んだカスタムテーマの編集の画面(知らせが出るか)
        var theme = fixture.model.draftCustomTheme()
        theme.textMuted = HexColor("#B0B0B0")!
        theme.surface = HexColor("#FFFFFF")!
        let editor = NSHostingView(rootView: CustomThemeEditor(model: fixture.model, draft: ThemeDraft(theme: theme, isNew: true)))
        editor.frame = NSRect(x: 0, y: 0, width: DesignTokens.Size.Settings.themeEditorWidth, height: DesignTokens.Size.Settings.themeEditorHeight)
        editor.layoutSubtreeIfNeeded()
        render(editor, name: "settings-theme-editor", to: output, appearance: NSAppearance(named: .aqua))
        // 書体のファミリーとスタイル(太さ)を選んだときの行と見本
        theme.fontName = "HiraginoSans-W8"
        let font = NSHostingView(rootView: VStack(spacing: 0) {
            ThemePreview(choice: ThemeChoice(theme.base, custom: theme), fontSize: fixture.model.settings.candidateFontSize)
                .padding(DesignTokens.Size.Settings.previewPadding)
            Form { ThemeFontPicker(fontName: .constant(theme.fontName)) }.formStyle(.grouped)
        }.frame(width: DesignTokens.Size.Settings.themeEditorWidth))
        font.frame = NSRect(origin: .zero, size: font.fittingSize)
        font.layoutSubtreeIfNeeded()
        render(font, name: "settings-theme-font", to: output, appearance: NSAppearance(named: .aqua))
    }

    /// キー設定のページ(R-17)．edited なら，重なった行・文字のキー・取り消しの無い状態の印が出る表にする
    private static func keymapView(edited: Bool, appearance: NSAppearance?) -> NSView {
        let store = snapshotStore(edited ? "keymap-edited" : "keymap")
        if edited {
            try? store.update { settings in
                settings.keymap.entries.removeAll { $0.command == .cancel && $0.state == .anywhere }
                // 印が見えるよう，表の先頭に入れる(1 行目は 2 行目と重なって使われず，3 行目は文字のキー)
                settings.keymap.entries.insert(contentsOf: [
                    KeymapEntry(.composing, KeyStroke(.character("k"), control: true), .toHiragana),
                    KeymapEntry(.composing, KeyStroke(.character("k"), control: true), .toHalfwidthKatakana),
                    KeymapEntry(.composing, KeyStroke(.character("q")), .commit),
                    KeymapEntry(.converting, KeyStroke(.character("7"), control: true), .toKatakana),
                    KeymapEntry(.composing, KeyStroke(.escape), .cancel),
                ], at: 0)
            }
        }
        let size = NSSize(width: SettingsView.size.width - DesignTokens.Size.Settings.sidebarWidth, height: SettingsView.size.height)
        let view = NSHostingView(rootView: KeymapPage(model: SettingsModel(store: store, usage: nil, resetLearning: {})).frame(width: size.width, height: size.height))
        view.frame = NSRect(origin: .zero, size: size)
        // 表の行は窓に載って描かれるまで作られないので，画面の外の窓に載せてから描く
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view
        window.orderFrontRegardless()
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        window.displayIfNeeded()
        return view
    }

    /// 手書きの窓(R-14)．「田」の線を書き，Vision で読んだ候補が並ぶまで待ってから描く
    private static func handwritingView(appearance: NSAppearance?,
                                        size: NSSize = NSSize(width: DesignTokens.Size.Handwriting.width, height: DesignTokens.Size.Handwriting.height)) -> NSView {
        let model = HandwritingModel(recognizer: VisionHandwritingRecognizer())
        model.theme = ResolvedTheme.resolve(ThemeChoice(.automatic), appearance: appearance)
        let view = NSHostingView(rootView: HandwritingView(model: model))
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -10_000, y: -10_000), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = view
        window.orderFrontRegardless()
        // 書く欄の大きさが決まってから書く(大きさが変わると書いた線を消すため)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        // 書く欄(一辺 260 ほど)の座標
        let strokes: [[CGPoint]] = [
            [CGPoint(x: 70, y: 55), CGPoint(x: 71, y: 205)], [CGPoint(x: 70, y: 55), CGPoint(x: 190, y: 57), CGPoint(x: 189, y: 205)],
            [CGPoint(x: 130, y: 57), CGPoint(x: 131, y: 203)], [CGPoint(x: 71, y: 130), CGPoint(x: 189, y: 129)],
            [CGPoint(x: 71, y: 203), CGPoint(x: 189, y: 204)],
        ]
        for stroke in strokes {
            model.draw(to: stroke[0])
            // 指で書いたように点を細かく打つ
            for (start, end) in zip(stroke, stroke.dropFirst()) {
                for step in 1...20 {
                    let t = CGFloat(step) / 20
                    model.draw(to: CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
                }
            }
            model.end()
        }
        // 線を書き終えてから認識するまでの待ちと，認識にかかる時間
        RunLoop.main.run(until: Date(timeIntervalSinceNow: DefaultSettings.handwritingRecognitionDelay + 2))
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return view
    }

    private static func modeView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = ModeIndicatorView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.label = UIStrings.ModeIndicator.label(for: InputMode.japanese)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        return backdropped(view)
    }

    /// glass の背景のぼかしは画像に写らないので，書き出すときだけ面を塗り，影の代わりに余白を付けて背景の上に置く
    /// 候補の窓と，その横に出す語の意味の吹き出しを並べる(吹き出しは MeaningBubbleController と同じ置き方．画面は十分に広いとみなす)．
    /// row は選んでいる候補の行(候補の窓の座標．上が y の小さい側)
    /// nearRightEdge なら，候補の窓が画面の右の端にあるとみなす(吹き出しは左に出る)
    private static func withBubble(_ view: NSView, note: HomophoneNote, others: [String], row: NSRect?, obstacles: [NSRect], theme: ResolvedTheme,
                                   nearRightEdge: Bool = false) -> NSView {
        guard let row else { return backdropped(view) }
        let metrics = MeaningBubbleLayout.Metrics.tokens(rounded: theme.isRounded)
        let header = MeaningCardDrawing.headerHeight(theme: theme)
        let content = MeaningCardDrawing.layout(note, others: others, width: metrics.width - metrics.padding * 2,
                                                placement: .init(left: 0, headerMidY: header / 2), theme: theme)
        let box = { (rect: NSRect) in MeaningBubbleLayout.Box(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height) }
        let placement = MeaningBubbleLayout(
            row: box(row), window: .init(x: 0, y: 0, width: view.frame.width, height: view.frame.height),
            size: (metrics.width, content.size.height + metrics.padding * 2),
            screen: .init(x: -1000, y: -1000, width: nearRightEdge ? 1000 + Double(view.frame.width) + metrics.screenMargin : 4000, height: 4000),
            obstacles: obstacles.map(box), metrics: metrics)
        let bubble = MeaningBubbleView()
        bubble.fillsSurface = true
        bubble.configure(content: content, placement: placement, metrics: metrics, theme: theme)
        let margin: CGFloat = 16
        let top = min(0, placement.window.y)
        let bottom = max(view.frame.height, placement.window.maxY)
        let left = min(0, placement.window.x)
        let right = max(view.frame.width, placement.window.maxX)
        let container = SnapshotDesk(frame: NSRect(x: 0, y: 0, width: right - left + margin * 2, height: bottom - top + margin * 2))
        // 背景は左下が原点なので，上の端から測った位置を直す
        view.frame.origin = NSPoint(x: margin - left, y: margin + bottom - view.frame.height)
        bubble.frame = NSRect(x: margin - left + placement.window.x, y: margin + bottom - placement.window.maxY,
                              width: placement.window.width, height: placement.window.height)
        container.addSubview(view)
        container.addSubview(bubble)
        return container
    }

    private static func backdropped(_ view: NSView) -> NSView {
        let margin: CGFloat = 16
        let container = SnapshotDesk(frame: NSRect(x: 0, y: 0, width: view.frame.width + margin * 2, height: view.frame.height + margin * 2))
        view.frame.origin = NSPoint(x: margin, y: margin)
        container.addSubview(view)
        return container
    }

    private static func listView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = SamplePanels.list
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 打っているあいだの候補の窓．選び始めるキーをキーごとのキーキャップで足元に出す
    private static func suggestionView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = SamplePanels.suggestion
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 打っているあいだの続く語句の予測の窓．打った部分(エピ)はふつうの色，補う部分(ソード)は薄い色で，確定のキーを添える
    private static func predictionView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = PredictionView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.prediction = Prediction(typed: "エピ", completion: "ソード", key: "Tab")
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        return backdropped(view)
    }

    /// 選んでいる候補に連想がある一覧．連想変換のキーをキーキャップで出す
    private static func associationHintListView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var panel = SamplePanels.list
        panel.associationHint = AssociationHint(key: "⌃Tab", label: "連想")
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 選んでいる候補に連想がある分岐図
    private static func associationHintBranchView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var panel = SamplePanels.lattice
        panel.associationHint = AssociationHint(key: "⌃Tab", label: "連想")
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    private static func correctionView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = CandidatePanel(
            variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
            selectedVariant: nil,
            entries: [.init(text: "python", annotation: nil), .init(text: "pyてょn", annotation: "入力のまま"), .init(text: "Python", annotation: nil)],
            selectedEntry: 0, focus: .candidate, position: 1, total: 3, note: Note(tone: .correction, title: "修正", key: "Space", keyAction: "元に戻す")
        )
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 日本語の打ち間違いを直した一覧．候補の中の直した語句に補正の点線を引く
    private static func readingCorrectionView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = CandidatePanel(
            variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
            selectedVariant: nil,
            entries: [.init(text: "今日の天気は良いですね", annotation: nil, corrected: 6..<8), .init(text: "今日の天気はいいですね", annotation: nil, corrected: 6..<8),
                      .init(text: "今日の天気は好いですね", annotation: nil, corrected: 6..<8)],
            selectedEntry: 0, focus: .candidate, position: 1, total: 3, note: Note(tone: .correction, title: "修正", key: "Esc", keyAction: "元に戻す")
        )
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 入力位置の下に出す案内の窓．tone は直したときと「もしかして」と示すとき
    /// 絵文字と記号のパレット(R-26)
    private static func paletteView(_ panel: PalettePanel, theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = PaletteView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// from から to へ動き始めてから time 秒たったところのパレット．then があれば，動き始めてすぐに then を出したところ
    private static func paletteMotionView(from: PalettePanel, to: PalettePanel, then: PalettePanel? = nil, at time: Double, theme: ThemeChoice,
                                          appearance: NSAppearance?) -> NSView {
        let view = PaletteView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.forcesMotion = true
        view.clock = { 0 }
        view.panel = from
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: to))
        view.panel = to
        if let then { view.panel = then }
        view.clock = { time }
        return backdropped(view)
    }

    private static func noteView(_ note: Note, theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = NoteView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.note = note
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        return backdropped(view)
    }

    /// 打ち間違いを直した文節(良いですね)に「修正」と添えた分岐図．注目しているのは別の文節
    private static func correctedLatticeView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var corrected = LatticePanel.Column(text: "良いですね", isFocused: false, isUncertain: true, preview: "様ですね")
        corrected.isCorrected = true
        let panel = LatticePanel(columns: [
            .init(text: "今日の", isFocused: false, isUncertain: false),
            .init(text: "天気は", alternatives: ["天気は", "転記は"], selectedAlternative: 0, isFocused: true, isUncertain: true),
            corrected,
        ], position: 1, total: 2, note: Note(tone: .correction, title: "修正", subject: "今日の天気は様ですね", key: "Esc", keyAction: "元に戻す"))
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 押した位置から対象を求める処理(候補をマウスで選ぶ)を確かめる．窓を細かく区切って押してみて，
    /// 見えている幹・枝・行・字種・コメントのタグがどれも押せることと，上から下への並びが候補の順と合うことを確かめ，合わなければ知らせる．
    /// コメントのタグは，タグの中を押すとコメントに，タグの外の行を押すと候補になることも確かめる
    private static func checkPointerTargets() {
        for (name, theme) in [("glass", ThemeChoice(.automatic)), ("platinum", ThemeChoice(.platinum))] {
            let resolved = ResolvedTheme.resolve(theme, appearance: NSAppearance(named: .aqua))
            var checks: [(sample: String, view: NSView, find: (NSPoint) -> PointerTarget?, expected: Set<PointerTarget>)] = []
            for (sample, panel) in [("分岐図", SamplePanels.lattice), ("分岐図・コメント", SamplePanels.commentLattice)] {
                let branch = BranchView()
                branch.theme = resolved
                branch.panel = panel
                branch.frame = NSRect(origin: .zero, size: branch.fittingSize(for: panel))
                checks.append((sample, branch, branch.target(at:), expectedTargets(panel)))
            }
            for (sample, panel) in [("一覧", SamplePanels.list), ("一覧・コメント", SamplePanels.comment)] {
                let list = CandidateView()
                list.theme = resolved
                list.panel = panel
                list.frame = NSRect(origin: .zero, size: list.fittingSize(for: panel))
                checks.append((sample, list, list.target(at:), expectedTargets(panel)))
            }
            for check in checks {
                var found: [PointerTarget] = []
                for y in stride(from: 0, to: check.view.bounds.height, by: 2) {
                    for x in stride(from: 0, to: check.view.bounds.width, by: 4) {
                        if let target = check.find(NSPoint(x: x, y: y)), found.last != target, !found.contains(target) { found.append(target) }
                    }
                }
                let rows = found.compactMap { if case .alternative(let index) = $0 { index } else if case .entry(let index) = $0 { index } else { nil } }
                let ok = Set(found) == check.expected && rows == rows.sorted()
                print("押した位置の確かめ(\(name)・\(check.sample)): \(ok ? "ok" : "合わない \(found)")")
            }
        }
    }

    /// 分岐図で押せるはずの対象．幹の文節と，注目している文節の上下の枝と，コメントのタグ
    private static func expectedTargets(_ panel: LatticePanel) -> Set<PointerTarget> {
        let focused = panel.columns.first(where: \.isFocused)
        let comments = focused.map { column in column.alternatives.indices.filter { column.comment(at: $0) != nil } } ?? []
        return Set(panel.columns.indices.map(PointerTarget.segment) + (focused?.alternatives.indices.map(PointerTarget.alternative) ?? [])
                   + (focused?.variants.indices.map(PointerTarget.variant) ?? []) + comments.map(PointerTarget.comment))
    }

    /// 一覧で押せるはずの対象．候補の行と，使える字種と，コメントのタグ
    private static func expectedTargets(_ panel: CandidatePanel) -> Set<PointerTarget> {
        Set(panel.entries.indices.map(PointerTarget.entry)
            + panel.variants.indices.filter { panel.variants[$0].isAvailable }.map(PointerTarget.listVariant)
            + panel.entries.indices.filter { panel.entries[$0].comment != nil }.map(PointerTarget.comment))
    }

    /// 表に広げた一覧でも，見えている候補がどれも押せ，押した候補が描いた位置の候補であることを確かめる
    private static func checkGridPointerTargets() {
        for (name, theme) in [("glass", ThemeChoice(.automatic)), ("platinum", ThemeChoice(.platinum))] {
            let view = CandidateView()
            view.theme = ResolvedTheme.resolve(theme, appearance: NSAppearance(named: .aqua))
            view.maximumWidth = DesignTokens.Size.Candidate.gridMaxWidth
            let panel = SamplePanels.grid
            view.panel = panel
            view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
            var found = Set<PointerTarget>()
            for y in stride(from: 0, to: view.bounds.height, by: 2) {
                for x in stride(from: 0, to: view.bounds.width, by: 4) {
                    if let target = view.target(at: NSPoint(x: x, y: y)) { found.insert(target) }
                }
            }
            let expected = expectedTargets(panel)
            print("押した位置の確かめ(\(name)・表): \(found == expected ? "ok" : "合わない \(found.subtracting(expected)) \(expected.subtracting(found))")")
        }
    }

    private static let longSentence = ["今日は", "朝から", "とても", "良い", "天気だったので", "近所の", "公園まで", "散歩に", "出かけて", "久しぶりに",
                                       "友達と", "ゆっくり", "話を", "しました"]

    /// 幅の上限を超える長い文の分岐図．focus の文節に注目する
    private static func longLatticeView(theme: ThemeChoice, appearance: NSAppearance?, focus: Int) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.maximumWidth = DesignTokens.Size.Candidate.maxWidth
        // 前の文節から順に注目を移したときの幹のずれを再現する
        for index in 0...focus {
            view.panel = SamplePanels.withKeys(LatticePanel(columns: longSentence.enumerated().map { column, text in
                column == index ? .init(text: text, alternatives: [text, text + "候補", "ひらがなの" + text], selectedAlternative: 0, isFocused: true, isUncertain: false)
                    : .init(text: text, isFocused: false, isUncertain: false)
            }, position: 1, total: 3))
        }
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: view.panel!))
        return backdropped(view)
    }

    /// 長い文をまとまりに区切って出す分岐図(core の InputSession が入れるものと同じ)．文節へ移るキーは，出しているまとまりの中で数える
    private static func groupLatticeView(theme: ThemeChoice, appearance: NSAppearance?, focus: Int) -> NSView {
        var panel = LatticePanel(columns: longSentence.enumerated().map { column, text in
            column == focus ? .init(text: text, alternatives: [text, text + "候補", "ひらがなの" + text], selectedAlternative: 0, isFocused: true, isUncertain: false)
                : .init(text: text, isFocused: false, isUncertain: false)
        }, position: 1, total: 3)
        panel.pageSize = DefaultSettings.latticeCandidatesPerSegment
        panel.group = SegmentGrouping.group(containing: focus, texts: longSentence, size: 5)
        let keymap = KeymapPreset.standard.keymap
        for (command, index) in zip(KeymapCommand.segmentJumps, panel.group ?? panel.columns.indices) {
            panel.columns[index].jumpKey = keymap.strokes(for: command, in: .converting).first.map(UIStrings.Keys.name(of:))
        }
        return latticeView(panel, theme: theme, appearance: appearance)
    }

    /// 候補を表に広げた一覧．窓の幅は表の上限まで広げる
    private static func gridView(_ panel: CandidatePanel, theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.maximumWidth = DesignTokens.Size.Candidate.gridMaxWidth
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 長い文の候補を表に広げた一覧．列の幅をそろえて表の幅の上限に収め，収まらない候補は末尾を省く．最後のページで 3 列目の途中まで
    private static var longGrid: CandidatePanel {
        let sentence = longSentence.prefix(6).joined()
        let entries = (0..<22).map { index in index.isMultiple(of: 3) ? sentence : String(longSentence[index % longSentence.count]) }
        var panel = CandidatePanel(variants: [], selectedVariant: nil, entries: entries.map { .init(text: $0, annotation: nil) },
                                   selectedEntry: 20, focus: .candidate, position: 57, total: 58, note: nil)
        panel.columnLength = DefaultSettings.candidatesPerPage
        return panel
    }

    /// 幅の上限を超える長い文の一覧
    private static func longListView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let sentence = longSentence.joined()
        let entries = [sentence, sentence.replacingOccurrences(of: "話", with: "噺"), "短い候補"]
        let panel = CandidatePanel(variants: [], selectedVariant: nil, entries: entries.map { .init(text: $0, annotation: nil) },
                                   selectedEntry: 0, focus: .candidate, position: 1, total: entries.count, note: nil)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 表示項目を減らす設定の分岐図．文字種の枝と候補の先の枝を畳み，続きがある印だけを出す(core の PanelBuilder.reduced と同じ形)
    private static func fewerItemsLattice() -> LatticePanel {
        var panel = SamplePanels.lattice
        if let focused = panel.columns.firstIndex(where: \.isFocused) {
            panel.columns[focused].variants = []
            panel.columns[focused].homophone = nil
        }
        panel.associationHint = nil
        panel.collapsesVariants = true
        panel.collapsesDetail = true
        return panel
    }

    /// 先の枝を丸として出した分岐図(core の InputSession.applyBranch と同じ形)．current は今いる丸，inside なら丸の中身を選んでいる
    private static func stationLattice(current: Int?, inside: Bool) -> LatticePanel {
        var column = LatticePanel.Column(text: "撮る", alternatives: ["取る", "撮る", "とる", "採る"], selectedAlternative: 1, variants: ["とる", "トル", "ﾄﾙ"],
                                         isFocused: true, isUncertain: true)
        var detail = BranchDetail(stations: [.init(kind: .meaning, title: "意味"), .init(kind: .association, title: "連想"), .init(kind: .macro, title: "マクロ")],
                                  current: current)
        if current == 1 {
            detail.items = ["撮影する", "写す", "収める"]
            detail.label = "写真に収める"
            detail.groupCount = 2
            detail.total = 3
        } else if current == 2 {
            detail.items = ["「撮る」", "【撮る】", "撮る（とる）", "**撮る**"]
            detail.total = 4
        }
        if current == nil || current == 0 { column.homophone = SamplePanels.homophone }
        if inside {
            detail.selectedItem = 1
            detail.candidates = column.alternatives
            detail.selectedCandidate = 1
            column.text = detail.items[1]
            column.alternatives = detail.items
        }
        var panel = SamplePanels.withKeys(LatticePanel(columns: [.init(text: "写真を", isFocused: false, isUncertain: false), column], position: 1, total: 7))
        if inside { panel.association = AssociationHeading(headword: "撮る", label: "", group: 1, groupCount: 1) }
        panel.detail = detail
        return panel
    }

    /// 幹の上にいる分岐図．案内は押し続けて出す設定(既定)，候補は 2 ページ
    private static func trunkLattice() -> LatticePanel {
        var panel = SamplePanels.lattice
        panel.trunkFocused = true
        panel.hintsOnHold = true
        panel.pageSize = 4
        return panel
    }

    /// キーの案内を押し続けているあいだだけ出す設定の分岐図(core の InputSession が入れるものと同じ)
    private static func heldHintsLattice() -> LatticePanel {
        var panel = SamplePanels.lattice
        panel.hintsOnHold = true
        return panel
    }

    private static func latticeView(_ panel: LatticePanel = SamplePanels.lattice, theme: ThemeChoice, appearance: NSAppearance?,
                                    heldModifiers: NSEvent.ModifierFlags = []) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.heldModifiers = heldModifiers
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 決まった中身の一覧(絵文字の候補など)
    private static func panelView(_ panel: CandidatePanel, theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 確信の低い文節が 2 つあり，注目していない方に次の候補を添えた分岐図
    private static func previewView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = LatticePanel(columns: [
            .init(text: "Cloudflareで", isFocused: false, isUncertain: false),
            .init(text: "撮った", isFocused: false, isUncertain: true, preview: "取った"),
            .init(text: "ドメイン", alternatives: ["ドメイン", "どめいん"], selectedAlternative: 0,
                  variants: ["どめいん", "ドメイン", "ﾄﾞﾒｲﾝ"], isFocused: true, isUncertain: true),
        ], position: 1, total: 2)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 文節を区切っているところ(⇧↓)．注目している文節の読みの文字のあいだに番号を挟む
    /// 見本の分岐図で，注目している文節(中野です)をその場で打ち直しているところ．幹は打っている読み，枝は打ち直す前の候補
    private static func editingLattice(typed: String) -> LatticePanel {
        var panel = SamplePanels.lattice
        panel.columns[2].text = typed
        panel.columns[2].isEditing = true
        panel.columns[2].selectedAlternative = nil
        panel.columns[2].isUncertain = false
        panel.columns[2].shorter = nil
        panel.note = Note(tone: .info, title: "再入力", subject: "中野です", key: "Tab", keyAction: "変換")
        return panel
    }

    /// 文節ごとの一覧で，注目している文節をその場で打ち直しているところ．候補は打ち直す前のもので，薄く出して選んでいない形にする
    private static var editingList: CandidatePanel {
        var panel = SamplePanels.list
        panel.isEditing = true
        panel.selectedEntry = nil
        panel.homophone = nil
        panel.note = Note(tone: .info, title: "再入力", subject: "変換", key: "Tab", keyAction: "変換")
        return panel
    }

    private static func splitView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var focused = LatticePanel.Column(text: "問題がある", isFocused: true, isUncertain: true)
        focused.split = .init(pieces: ["問題", "が", "ある"])
        let panel = LatticePanel(columns: [.init(text: "それは", isFocused: false, isUncertain: false), focused,
                                           .init(text: "と思う", isFocused: false, isUncertain: false)], position: 1, total: 4)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 連想の一覧(R-18)を一覧で出したところ
    private static func associationListView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var panel = CandidatePanel(variants: [], selectedVariant: nil, entries: ["綺麗", "麗しい", "華麗", "端麗"].map { .init(text: $0, annotation: nil) },
                                   selectedEntry: 1, focus: .candidate, position: 2, total: 4, note: nil)
        panel.association = AssociationHeading(headword: "美しい", label: "見た目が快い", group: 1, groupCount: 3)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 連想の一覧(R-18)を分岐図で出したところ
    private static func associationBranchView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var panel = LatticePanel(columns: [
            .init(text: "麗しい", alternatives: ["綺麗", "麗しい", "華麗", "端麗"], selectedAlternative: 1, isFocused: true, isUncertain: false),
            .init(text: "景色", isFocused: false, isUncertain: false),
        ], position: 1, total: 4)
        panel.association = AssociationHeading(headword: "美しい", label: "見た目が快い", group: 1, groupCount: 3)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 撮る以外の候補を選んだときの見本の語の意味(意味が 1 つで，吹き出しが短いもの)
    private static let held = HomophoneNote(word: "執る", partOfSpeech: .verb, senses: [.init(meaning: "仕事や事務を取り扱う", example: "指揮を執る")],
                                            others: ["取る", "撮る", "採る", "捕る"])
    private static let took = HomophoneNote(word: "取る", partOfSpeech: .verb, senses: [.init(meaning: "手に持つ", example: "本を手に取る")],
                                            others: ["執る", "捕る"])
    private static let adopted = HomophoneNote(word: "採る", partOfSpeech: .verb, senses: [.init(meaning: "選んで用いる", example: "新人を採る")],
                                               others: ["執る", "捕る"])

    /// 同音異義語の使い分け(R-08)を一覧で出したところ．既定では候補の窓の横の吹き出しにし，三角で選んでいる候補を指す
    private static func homophoneListView(theme: ThemeChoice, appearance: NSAppearance?, placement: MeaningPlacement = .side,
                                          nearRightEdge: Bool = false, selected: Int = 0) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var panel = CandidatePanel(variants: [], selectedVariant: nil, entries: ["撮る", "取る", "採る", "執る"].map { .init(text: $0, annotation: nil) },
                                   selectedEntry: selected, focus: .candidate, position: selected + 1, total: 6, note: nil)
        let note = selected == 3 ? held : SamplePanels.homophone
        panel.homophone = note
        panel.meaningPlacement = placement
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        guard placement == .side else { return backdropped(view) }
        return withBubble(view, note: note, others: note.others,
                          row: view.selectedRowRect(size: view.frame.size), obstacles: view.bubbleObstacles(size: view.frame.size), theme: view.theme,
                          nearRightEdge: nearRightEdge)
    }

    /// 同音異義語の無い語の意味を一覧で出したところ．同音語の行を出さず，長い意味は折り返す
    private static func meaningListView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var panel = CandidatePanel(variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) }, selectedVariant: nil,
                                   entries: ["動く", "うごく", "ウゴク"].map { .init(text: $0, annotation: nil) },
                                   selectedEntry: 0, focus: .candidate, position: 1, total: 3, note: nil)
        panel.homophone = SamplePanels.meaning
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return withBubble(view, note: SamplePanels.meaning, others: SamplePanels.meaning.others,
                          row: view.selectedRowRect(size: view.frame.size), obstacles: view.bubbleObstacles(size: view.frame.size), theme: view.theme)
    }

    /// 意味のある候補から意味の無い候補(ひらがな)に移ったところ．吹き出しを出さず，候補の窓の大きさは変えない
    private static func meaningEmptyListView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var panel = CandidatePanel(variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) }, selectedVariant: nil,
                                   entries: ["動く", "うごく", "ウゴク"].map { .init(text: $0, annotation: nil) },
                                   selectedEntry: 0, focus: .candidate, position: 1, total: 3, note: nil)
        panel.homophone = SamplePanels.meaning
        view.panel = panel
        panel.homophone = nil
        panel.selectedEntry = 1
        panel.position = 2
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 同音異義語の使い分けを分岐図で出したところ．既定では，選んでいる候補の先の枝(意味の丸の下)に出す．
    /// 候補の下に出す設定では，同音語のタグに枝に出ていない語だけを出す．selected を意味の無い候補にすると，意味を出さない
    private static func homophoneBranchView(theme: ThemeChoice, appearance: NSAppearance?, placement: MeaningPlacement = .side, selected: Int = 1,
                                            note: HomophoneNote? = nil) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var column = LatticePanel.Column(text: "撮る", alternatives: ["取る", "撮る", "とる", "採る"], selectedAlternative: 1, isFocused: true, isUncertain: true)
        column.homophone = SamplePanels.homophone
        var panel = LatticePanel(columns: [.init(text: "写真を", isFocused: false, isUncertain: false), column], position: 1, total: 7)
        panel.meaningPlacement = placement
        view.panel = panel
        if selected != 1 {
            panel.columns[1].selectedAlternative = selected
            panel.columns[1].text = panel.columns[1].alternatives[selected]
            panel.columns[1].homophone = note
            view.panel = panel
        }
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// コマンドの候補(R-22)を一覧で出したところ．selected は選んでいる行
    private static func commandListView(theme: ThemeChoice, appearance: NSAppearance?, selected: Int) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = SamplePanels.commands(selected: selected)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// コマンドの候補を分岐図で出し，Web のページを開くコマンドを選んだところ(幹は入力中の文字と同じく印を付けた名前)
    private static func commandBranchView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let list = SamplePanels.commands(selected: 2)
        var column = LatticePanel.Column(text: DefaultSettings.commandCandidateMark + list.entries[2].text, alternatives: list.entries.map(\.text),
                                         selectedAlternative: 2, isFocused: true, isUncertain: false)
        column.alternativeNotes = list.entries.map(\.annotation)
        column.alternativeCommands = list.entries.map(\.command)
        let panel = LatticePanel(columns: [column], position: 1, total: list.entries.count, note: list.note)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// ユーザー辞書の語のコメント(R-21)をタグに出した一覧．選んでいる行のタグは選択の背景の上に描く
    private static func commentListView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = SamplePanels.comment
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// ユーザー辞書の語のコメントを下の枝に添えた分岐図
    private static func commentBranchView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = SamplePanels.commentLattice
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 書き出した画像の背景．入力先のアプリの画面の代わりに，薄い色の面を敷く
    private final class SnapshotDesk: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.underPageBackgroundColor.setFill()
            bounds.fill()
        }
    }

    private static func render(_ view: NSView, name: String, to directory: URL, appearance: NSAppearance?) {
        view.appearance = appearance
        // 2 倍(Retina)で描き，1 ドットの線がデバイスのピクセルにそろうかを確かめられるようにする
        let scale: CGFloat = 2
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        (appearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
            view.cacheDisplay(in: view.bounds, to: rep)
            drawNestedTables(of: view, into: rep, dark: appearance?.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua)
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Form の中の表(FormTableHost)は別の NSHostingView で描くので，外のビューの cacheDisplay では写らない(白く抜ける)．
    /// 表のすぐ左(Form の行の背景)の色で塗り，表の入れ物と見えている行を 1 つずつ写して乗算で重ねる．
    /// cacheDisplay は透明なところを白で埋めるので，乗算で白を背景の色に戻す．
    /// ダークの外観では白い文字が乗算で消えるので，透明な背景のまま描いて上に重ねる
    static func drawNestedTables(of root: NSView, into rep: NSBitmapImageRep, dark: Bool) {
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        let scale = CGFloat(rep.pixelsWide) / root.bounds.width
        // rep は左下が原点
        let flip = { (rect: NSRect) -> NSRect in
            var rect = rect
            if root.isFlipped { rect.origin.y = root.bounds.height - rect.maxY }
            return rect
        }
        var stack = root.subviews
        while let view = stack.popLast() {
            guard !view.isHiddenOrHasHiddenAncestor else { continue }
            guard view is FormTableContainer else {
                stack.append(contentsOf: view.subviews)
                continue
            }
            let frame = view.convert(view.bounds, to: root)
            // colorAt は左上が原点
            let fromTop = root.isFlipped ? frame.midY : root.bounds.height - frame.midY
            guard let ground = rep.colorAt(x: Int((frame.minX - 4) * scale), y: Int(fromTop * scale)) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            ground.setFill()
            flip(frame).fill()
            NSGraphicsContext.restoreGraphicsState()
            draw(view, at: flip(frame), into: context, clip: nil, dark: dark)
            var rows = view.subviews
            while let row = rows.popLast() {
                guard row is NSTableRowView, let scroll = row.enclosingScrollView else {
                    rows.append(contentsOf: row.subviews)
                    continue
                }
                // 見出しの下(contentInsets.top より下)の，行が見えている範囲で切る
                let clip = scroll.contentView
                var visible = clip.bounds
                visible.size.height -= scroll.contentInsets.top
                if clip.isFlipped { visible.origin.y += scroll.contentInsets.top }
                draw(row, at: flip(row.convert(row.bounds, to: root)), into: context, clip: flip(clip.convert(visible, to: root)), dark: dark)
            }
        }
    }

    private static func draw(_ view: NSView, at rect: NSRect, into context: NSGraphicsContext, clip: NSRect?, dark: Bool) {
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        if dark, let viewContext = NSGraphicsContext(bitmapImageRep: image) {
            view.displayIgnoringOpacity(view.bounds, in: viewContext)
        } else {
            view.cacheDisplay(in: view.bounds, to: image)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        if let clip { NSBezierPath(rect: clip).setClip() }
        image.draw(in: rect, from: .zero, operation: dark ? .sourceOver : .multiply, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif
