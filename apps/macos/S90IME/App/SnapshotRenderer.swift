#if DEBUG
import AppKit
import S90Application
import S90Domain
import S90Persistence
import SwiftUI

/// 候補ウィンドウの見た目を画像に書き出す(デバッグビルドだけ)．
/// 入力メソッドとして動かさずに描画を確かめ，PR に貼るスクリーンショットを作るため．
///
/// 使い方: Debug でビルドした "s90.tokyo IME Debug.app/Contents/MacOS/s90.tokyo IME Debug" --render-snapshots
/// サンドボックスの中で動くので，書き出し先はサンドボックスの一時ディレクトリになる．場所は標準出力に出す
@MainActor
enum SnapshotRenderer {
    static let argument = "--render-snapshots"

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.contains(argument) else { return }
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("s90-snapshots", isDirectory: true)
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

    /// 一時ディレクトリに置いた設定．利用者の設定に触れない
    private static func snapshotStore(_ name: String) -> FileSettingsStore {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("s90-snapshot-\(name).json")
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
            settings.userDictionary = [UserDictionaryEntry(reading: "えすきゅー", word: "s90"), UserDictionaryEntry(reading: "かいしゃ", word: "会社")]
            settings.symbolRules = [SymbolRule(kind: .sequence, input: "->", output: "⇢"), SymbolRule(kind: .sequence, input: "<<", output: "«"),
                                    SymbolRule(kind: .sequence, input: "=>", output: "⇒", isEnabled: false)]
            settings.profileRules = [ProfileRule(applicationPrefix: "com.apple.Terminal", profile: .terminal)]
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
        // 左の一覧は窓の中では写らない(地のぼかしの層を写せない)ので，一覧だけを別に描く
        let sidebar = NSHostingView(rootView: SettingsSidebar(query: "", selection: .constant(.correction)).listStyle(.inset))
        let sidebarWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DesignTokens.Size.Settings.sidebarWidth, height: SettingsView.size.height),
                                     styleMask: [.borderless], backing: .buffered, defer: false)
        sidebarWindow.contentView = sidebar
        sidebarWindow.orderFrontRegardless()
        SettingsFixture.settle(sidebarWindow)
        render(sidebar, name: "settings-sidebar", to: output, appearance: NSAppearance(named: .aqua))
        sidebarWindow.close()
        // 読みにくい色を選んだカスタムテーマの編集の画面(知らせが出るか)
        var theme = fixture.model.draftCustomTheme()
        theme.textMuted = HexColor("#B0B0B0")!
        theme.surface = HexColor("#FFFFFF")!
        let editor = NSHostingView(rootView: CustomThemeEditor(model: fixture.model, draft: ThemeDraft(theme: theme, isNew: true)))
        editor.frame = NSRect(x: 0, y: 0, width: DesignTokens.Size.Settings.themeEditorWidth, height: DesignTokens.Size.Settings.themeEditorHeight)
        editor.layoutSubtreeIfNeeded()
        render(editor, name: "settings-theme-editor", to: output, appearance: NSAppearance(named: .aqua))
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
    /// 見えている幹・枝・行・字種がどれも押せることと，上から下への並びが候補の順と合うことを確かめ，合わなければ知らせる
    private static func checkPointerTargets() {
        for (name, theme) in [("glass", ThemeChoice(.automatic)), ("platinum", ThemeChoice(.platinum))] {
            let branch = BranchView()
            branch.theme = ResolvedTheme.resolve(theme, appearance: NSAppearance(named: .aqua))
            branch.panel = SamplePanels.lattice
            branch.frame = NSRect(origin: .zero, size: branch.fittingSize(for: SamplePanels.lattice))
            let list = CandidateView()
            list.theme = branch.theme
            list.panel = SamplePanels.list
            list.frame = NSRect(origin: .zero, size: list.fittingSize(for: SamplePanels.list))
            for (view, find) in [(branch as NSView, branch.target(at:)), (list as NSView, list.target(at:))] {
                var found: [PointerTarget] = []
                for y in stride(from: 0, to: view.bounds.height, by: 2) {
                    for x in stride(from: 0, to: view.bounds.width, by: 4) {
                        if let target = find(NSPoint(x: x, y: y)), found.last != target, !found.contains(target) { found.append(target) }
                    }
                }
                let focused = SamplePanels.lattice.columns.first(where: \.isFocused)
                let expected: Set<PointerTarget> = view === branch
                    ? Set(SamplePanels.lattice.columns.indices.map(PointerTarget.segment) + (focused?.alternatives.indices.map(PointerTarget.alternative) ?? [])
                          + (focused?.variants.indices.map(PointerTarget.variant) ?? []))
                    : Set(SamplePanels.list.entries.indices.map(PointerTarget.entry)
                          + SamplePanels.list.variants.indices.filter { SamplePanels.list.variants[$0].isAvailable }.map(PointerTarget.listVariant))
                let rows = found.compactMap { if case .alternative(let index) = $0 { index } else if case .entry(let index) = $0 { index } else { nil } }
                let ok = Set(found) == expected && rows == rows.sorted()
                print("押した位置の確かめ(\(name)・\(view === branch ? "分岐図" : "一覧")): \(ok ? "ok" : "合わない \(found)")")
            }
        }
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
