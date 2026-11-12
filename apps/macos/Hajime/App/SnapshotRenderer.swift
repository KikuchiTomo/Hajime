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
            (ThemeChoice(.contrast), .darkAqua, "contrast"),
        ]
        checkPointerTargets()
        for look in looks {
            let appearance = NSAppearance(named: look.appearance)
            // 色を今の外観で決める部品があるので，その外観を描くときの外観にして組み立てる
            (appearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
                render(listView(theme: look.theme, appearance: appearance), name: "list-\(look.name)", to: output, appearance: appearance)
                render(suggestionView(theme: look.theme, appearance: appearance), name: "suggestion-\(look.name)", to: output, appearance: appearance)
                render(latticeView(theme: look.theme, appearance: appearance), name: "branch-\(look.name)", to: output, appearance: appearance)
                render(previewView(theme: look.theme, appearance: appearance), name: "branch-preview-\(look.name)", to: output, appearance: appearance)
                render(splitView(theme: look.theme, appearance: appearance), name: "branch-split-\(look.name)", to: output, appearance: appearance)
                render(correctionView(theme: look.theme, appearance: appearance), name: "correction-\(look.name)", to: output, appearance: appearance)
                render(readingCorrectionView(theme: look.theme, appearance: appearance), name: "correction-reading-\(look.name)", to: output, appearance: appearance)
                render(correctedLatticeView(theme: look.theme, appearance: appearance), name: "branch-correction-\(look.name)", to: output, appearance: appearance)
                render(noteView(Note(tone: .correction, title: "修正", subject: "オン外します", key: "Esc", keyAction: "戻す"), theme: look.theme, appearance: appearance),
                       name: "note-correction-\(look.name)", to: output, appearance: appearance)
                render(noteView(Note(tone: .suggestion, title: "もしかして", subject: "お願いします", key: "Tab", keyAction: "修正"), theme: look.theme, appearance: appearance),
                       name: "note-suggestion-\(look.name)", to: output, appearance: appearance)
                render(modeView(theme: look.theme, appearance: appearance), name: "mode-\(look.name)", to: output, appearance: appearance)
                render(associationListView(theme: look.theme, appearance: appearance), name: "association-list-\(look.name)", to: output, appearance: appearance)
                render(associationBranchView(theme: look.theme, appearance: appearance), name: "association-branch-\(look.name)", to: output, appearance: appearance)
                render(homophoneListView(theme: look.theme, appearance: appearance), name: "homophone-list-\(look.name)", to: output, appearance: appearance)
                render(homophoneBranchView(theme: look.theme, appearance: appearance), name: "homophone-branch-\(look.name)", to: output, appearance: appearance)
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
                // 動きの途中のコマ(選択の枠とタブの印が滑る・種類を切り替えて中身を送る・肌の色の帯が浮かび上がる)
                for (step, sample) in SamplePalettes.motionSteps.enumerated() {
                    render(paletteMotionView(from: sample.from, to: sample.to, at: sample.time, theme: look.theme, appearance: appearance),
                           name: "palette-motion-\(step + 1)-\(look.name)",
                           to: output, appearance: appearance)
                }
                render(associationHintListView(theme: look.theme, appearance: appearance), name: "association-hint-list-\(look.name)", to: output, appearance: appearance)
                render(predictionView(theme: look.theme, appearance: appearance), name: "prediction-\(look.name)", to: output, appearance: appearance)
                render(associationHintBranchView(theme: look.theme, appearance: appearance), name: "association-hint-branch-\(look.name)", to: output, appearance: appearance)
            }
        }
        // 長い文: 窓は幅の上限に収め，一覧は末尾を省き，分岐図は注目している文節が見えるように幹をずらす
        for look in looks where ["glass-dark", "platinum"].contains(look.name) {
            let appearance = NSAppearance(named: look.appearance)
            (appearance ?? NSAppearance(named: .aqua)!).performAsCurrentDrawingAppearance {
                for focus in [0, 6, 13] {
                    render(longLatticeView(theme: look.theme, appearance: appearance, focus: focus), name: "branch-long-\(focus)-\(look.name)", to: output, appearance: appearance)
                }
                render(longListView(theme: look.theme, appearance: appearance), name: "list-long-\(look.name)", to: output, appearance: appearance)
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
        // 左の一覧は窓の中では写らない(地のぼかしの層を写せない)ので，一覧だけを別に描く
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

    /// glass の地のぼかしは画像に写らないので，書き出すときだけ面を塗り，影の代わりに余白を付けて地の上に置く
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
            selectedEntry: 0, focus: .candidate, position: 1, total: 3, note: Note(tone: .correction, title: "修正", key: "Space", keyAction: "入力のままに戻す")
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
            selectedEntry: 0, focus: .candidate, position: 1, total: 3, note: Note(tone: .correction, title: "修正", key: "Esc", keyAction: "入力のままに戻す")
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

    /// from から to へ動き始めてから time 秒たったところのパレット
    private static func paletteMotionView(from: PalettePanel, to: PalettePanel, at time: Double, theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = PaletteView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.forcesMotion = true
        view.clock = { 0 }
        view.panel = from
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: to))
        view.panel = to
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
        ], position: 1, total: 2, note: Note(tone: .correction, title: "修正", subject: "今日の天気は様ですね", key: "Esc", keyAction: "戻す"))
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 押した位置から対象を求める処理(候補をマウスで選ぶ)を確かめる．窓を細かく区切って押してみて，
    /// 見えている幹・枝・行・字種・コメントの札がどれも押せることと，上から下への並びが候補の順と合うことを確かめ，合わなければ知らせる．
    /// コメントの札は，札の中を押すとコメントに，札の外の行を押すと候補になることも確かめる
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

    /// 分岐図で押せるはずの対象．幹の文節と，注目している文節の上下の枝と，コメントの札
    private static func expectedTargets(_ panel: LatticePanel) -> Set<PointerTarget> {
        let focused = panel.columns.first(where: \.isFocused)
        let comments = focused.map { column in column.alternatives.indices.filter { column.comment(at: $0) != nil } } ?? []
        return Set(panel.columns.indices.map(PointerTarget.segment) + (focused?.alternatives.indices.map(PointerTarget.alternative) ?? [])
                   + (focused?.variants.indices.map(PointerTarget.variant) ?? []) + comments.map(PointerTarget.comment))
    }

    /// 一覧で押せるはずの対象．候補の行と，使える字種と，コメントの札
    private static func expectedTargets(_ panel: CandidatePanel) -> Set<PointerTarget> {
        Set(panel.entries.indices.map(PointerTarget.entry)
            + panel.variants.indices.filter { panel.variants[$0].isAvailable }.map(PointerTarget.listVariant)
            + panel.entries.indices.filter { panel.entries[$0].comment != nil }.map(PointerTarget.comment))
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
            view.panel = LatticePanel(columns: longSentence.enumerated().map { column, text in
                column == index ? .init(text: text, alternatives: [text, text + "候補", "ひらがなの" + text], selectedAlternative: 0, isFocused: true, isUncertain: false)
                    : .init(text: text, isFocused: false, isUncertain: false)
            }, position: 1, total: 3)
        }
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: view.panel!))
        return backdropped(view)
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

    private static func latticeView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = SamplePanels.lattice
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

    /// 同音異義語の使い分け(R-08)を一覧で出したところ．既定では候補の右のカードにし，選んでいる候補を三角で指す
    private static func homophoneListView(theme: ThemeChoice, appearance: NSAppearance?, placement: MeaningPlacement = .side) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        var panel = CandidatePanel(variants: [], selectedVariant: nil, entries: ["撮る", "取る", "採る", "執る"].map { .init(text: $0, annotation: nil) },
                                   selectedEntry: 0, focus: .candidate, position: 1, total: 6, note: nil)
        panel.homophone = SamplePanels.homophone
        panel.meaningPlacement = placement
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
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
        return backdropped(view)
    }

    /// 意味のある候補から意味の無い候補(ひらがな)に移ったところ．カードの場所は空けたままにし，窓の大きさを変えない
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

    /// 同音異義語の使い分けを分岐図で出したところ．既定では選んでいる候補の先に線を伸ばしてカードをつなぐ．
    /// 同音語の札には枝に出ていない語だけを出す．selected を意味の無い候補にすると，カードの場所を空けたままにする
    private static func homophoneBranchView(theme: ThemeChoice, appearance: NSAppearance?, placement: MeaningPlacement = .side, selected: Int = 1) -> NSView {
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
            panel.columns[1].homophone = nil
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

    /// ユーザー辞書の語のコメント(R-21)を札に出した一覧．選んでいる行の札は選択の地の上に描く
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

    /// 書き出した画像の地．入力先のアプリの画面の代わりに，薄い色の面を敷く
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
            drawNestedTables(of: view, into: rep)
        }
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Form の中の表(FormTableHost)は別の NSHostingView で描くので，外のビューの cacheDisplay では写らない(白く抜ける)．
    /// 表のすぐ左(Form の行の地)の色で塗り，表の入れ物と見えている行を 1 つずつ写して乗算で重ねる．
    /// cacheDisplay は透明なところを白で埋めるので，乗算で白を地の色に戻す．
    /// ダークの外観では白い文字が乗算で消えるので，表の中は写らない(地の色だけになる)
    static func drawNestedTables(of root: NSView, into rep: NSBitmapImageRep) {
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
            draw(view, at: flip(frame), into: context, clip: nil)
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
                draw(row, at: flip(row.convert(row.bounds, to: root)), into: context, clip: flip(clip.convert(visible, to: root)))
            }
        }
    }

    private static func draw(_ view: NSView, at rect: NSRect, into context: NSGraphicsContext, clip: NSRect?) {
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: image)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        if let clip { NSBezierPath(rect: clip).setClip() }
        image.draw(in: rect, from: .zero, operation: .multiply, fraction: 1, respectFlipped: false, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }
}
#endif
