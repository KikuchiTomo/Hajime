#if DEBUG
import AppKit
import QuartzCore
import HajimeApplication
import HajimeDomain
import HajimePersistence

/// 設定の画面でページを切り替えたときにかかる時間を測る(デバッグビルドだけ)．
/// 実際の窓(ツールバー付き)を出し，ページを切り替えて，描き終わるまでの時間をページごとに出す．
///
/// 使い方: Debug でビルドした "Hajime Debug.app/Contents/MacOS/Hajime Debug" --measure-settings
/// 設定はサンドボックスの一時ディレクトリに置き，利用者の設定に触れない．
/// 環境変数 HAJIME_MEASURE_PAGES・HAJIME_MEASURE_ROUNDS・HAJIME_MEASURE_CHANGES で，測るページ・回数・設定を変える回数を選べる(docs/dev/DESIGN-SYSTEM.md)．
/// HAJIME_MEASURE_INTERACTIONS=1 を付けると，ページの中の操作(スクロール・設定の変更・文字の入力・表の行の選択)の時間もページごとに出す．
/// HAJIME_MEASURE_OPENS に回数を渡すと，ページを初めて開く時間を新しい窓でその回数ずつ測る．
/// HAJIME_MEASURE_CLOCK=cpu を付けると，経った時間の代わりにメインスレッドが使った CPU の時間を出す(ほかの処理で混んでいても比べられる)
@MainActor
enum SettingsBenchmark {
    static let argument = "--measure-settings"
    /// 1 ページを何回ずつ測るか．1 回目は初めて組み立てる分が重いので別に出す
    private static var rounds: Int {
        Int(ProcessInfo.processInfo.environment["HAJIME_MEASURE_ROUNDS"] ?? "") ?? 6
    }

    /// 測るページ．環境変数 HAJIME_MEASURE_PAGES にページの名前をカンマで区切って渡すと，そのページだけを測る(プロファイラで見るとき)
    private static var pages: [SettingsView.Page] {
        guard let names = ProcessInfo.processInfo.environment["HAJIME_MEASURE_PAGES"]?.split(separator: ",").map(String.init) else {
            return SettingsView.Page.allCases
        }
        return SettingsView.Page.allCases.filter { names.contains($0.title) }
    }

    /// 今の時刻(秒)．HAJIME_MEASURE_CLOCK=cpu ならメインスレッドが使った CPU の時間
    static func now() -> Double {
        guard ProcessInfo.processInfo.environment["HAJIME_MEASURE_CLOCK"] == "cpu" else { return CACurrentMediaTime() }
        return Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1_000_000_000
    }

    static func runIfRequested() {
        guard CommandLine.arguments.contains(argument) else { return }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let fixture = SettingsFixture.make(name: "benchmark")
        let navigation = SettingsNavigation(page: .input)
        let window = SettingsWindowController.makeWindow(model: fixture.model, sync: fixture.sync, navigation: navigation)
        window.orderFrontRegardless()
        SettingsFixture.settle(window)

        var first: [SettingsView.Page: Double] = [:]
        var later: [SettingsView.Page: [Double]] = [:]
        for round in 0..<rounds {
            for page in pages {
                // 前のページから切り替える時間を測るため，毎回ちがうページから来るようにする
                let start = now()
                navigation.page = page
                SettingsFixture.settle(window)
                let elapsed = (now() - start) * 1000
                if round == 0 { first[page] = elapsed } else { later[page, default: []].append(elapsed) }
            }
        }
        print("ページ\t初回(ms)\t2回目から中央値(ms)\t最大(ms)")
        var total = 0.0
        for page in pages {
            let samples = (later[page] ?? []).sorted()
            let median = samples.isEmpty ? 0 : samples[samples.count / 2]
            total += median
            print(String(format: "%@\t%.1f\t%.1f\t%.1f", page.title, first[page] ?? 0, median, samples.last ?? 0))
        }
        print(String(format: "合計\t%.1f\t%.1f", first.values.reduce(0, +), total))
        // 設定を 1 つ変えたときに画面を描き直す時間．開いたことのあるページがすべて残っている状態で測る
        var changes: [Double] = []
        let changeCount = Int(ProcessInfo.processInfo.environment["HAJIME_MEASURE_CHANGES"] ?? "") ?? 10
        for _ in 0..<changeCount {
            let start = now()
            fixture.model.update { $0.liveConversion.toggle() }
            SettingsFixture.settle(window)
            changes.append((now() - start) * 1000)
        }
        changes.sort()
        print(String(format: "設定を 1 つ変える\t-\t%.1f\t%.1f", changes[changes.count / 2], changes.last ?? 0))
        // 何も変えずに画面を映し終わるまで回す時間．どの数字にもこの分が入っている
        let idle = (0..<10).map { _ in
            let start = now()
            SettingsFixture.settle(window)
            return (now() - start) * 1000
        }.sorted()
        print(String(format: "何もしない\t-\t%.1f\t%.1f", idle[idle.count / 2], idle.last ?? 0))
        if let opens = Int(ProcessInfo.processInfo.environment["HAJIME_MEASURE_OPENS"] ?? "") {
            window.close()
            measureFirstOpens(pages: pages, count: opens)
        }
        if ProcessInfo.processInfo.environment["HAJIME_MEASURE_INTERACTIONS"] != nil {
            window.close()
            measureInteractions(pages: pages)
        }
        exit(0)
    }
}

// MARK: ページの中の操作

extension SettingsBenchmark {
    /// ページの中の操作(スクロール・設定の変更・文字の入力・表の行の選択)にかかる時間を，ページごとに出す．
    /// 1 回の操作を画面に映し終わるまでの時間で，16.7 ms を超えると 1 こま(60 Hz)に収まらない
    static func measureInteractions(pages: [SettingsView.Page]) {
        print("ページ\tスクロール中央値(ms)\tスクロール最大(ms)\tページの設定の変更(ms)\tほかの設定の変更(ms)\t入力中央値(ms)\t入力最大(ms)\t行を選ぶ(ms)")
        for page in pages {
            // そのページだけを開いた窓で測る(ほかのページの描き直しを混ぜない)
            let fixture = SettingsFixture.make(name: "benchmark-page")
            let window = SettingsWindowController.makeWindow(model: fixture.model, sync: fixture.sync, navigation: SettingsNavigation(page: page))
            window.isReleasedWhenClosed = false
            window.orderFrontRegardless()
            SettingsFixture.settle(window)
            SettingsFixture.settle(window)
            let scroll = scrollTimes(window)
            // そのページに出している設定と，ほかのページの設定(統計の記録．統計のページではライブ変換)
            let own = ownChange(on: page).map { change in median((0..<10).map { _ in timed(window) { fixture.model.update(change) } }) }
            let other = median((0..<10).map { _ in
                timed(window) { fixture.model.update { page == .usage ? $0.liveConversion.toggle() : $0.recordsUsage.toggle() } }
            })
            let typing = typingTimes(window)
            let selecting = selectionTimes(window)
            print(String(format: "%@\t%.1f\t%.1f\t%@\t%.1f\t%.1f\t%.1f\t%@", page.title, median(scroll), scroll.max() ?? 0,
                         own.map { String(format: "%.1f", $0) } ?? "-", other, median(typing), typing.max() ?? 0,
                         selecting.isEmpty ? "-" : String(format: "%.1f", median(selecting))))
            window.close()
        }
    }

    /// ページを初めて開く時間を，新しい窓で count 回ずつ測る(1 つの窓では 1 回しか測れないため)
    static func measureFirstOpens(pages: [SettingsView.Page], count: Int) {
        print("ページ\t初めて開く中央値(ms)\t最大(ms)")
        for page in pages {
            let times = (0..<count).map { _ in
                // いちばん軽いページを開いた窓から切り替える
                let fixture = SettingsFixture.make(name: "benchmark-open")
                let navigation = SettingsNavigation(page: page == .backup ? .usage : .backup)
                let window = SettingsWindowController.makeWindow(model: fixture.model, sync: fixture.sync, navigation: navigation)
                window.isReleasedWhenClosed = false
                window.orderFrontRegardless()
                SettingsFixture.settle(window)
                SettingsFixture.settle(window)
                let time = timed(window) { navigation.page = page }
                window.close()
                return time
            }
            print(String(format: "%@\t%.1f\t%.1f", page.title, median(times), times.max() ?? 0))
        }
    }

    /// そのページに出している設定を 1 つ変える操作(ほかの行の使える・使えないも変わる項目を選ぶ)．設定の項目の無いページは nil
    private static func ownChange(on page: SettingsView.Page) -> ((inout HajimeDomain.Settings) -> Void)? {
        switch page {
        case .input: { $0.showsModeIndicator.toggle() }
        case .conversion: { $0.liveConversion.toggle() }
        case .correction: { $0.correction.japanese.toggle() }
        case .language: { $0.englishTermCandidates.toggle() }
        case .apps: { $0.terminalCommands.toggle() }
        case .dictionary: { $0.dynamicDictionary.toggle() }
        case .palette: { $0.paletteShowsPreview.toggle() }
        case .commands: { $0.conversionMacros.toggle() }
        case .appearance: { $0.theme = $0.theme == .platinum ? .desk : .platinum }
        case .usage: { $0.recordsUsage.toggle() }
        case .romaji, .keys, .symbols, .sync, .backup, .about: nil
        }
    }

    /// ページの最初の表の行を上から 1 つずつ選び，1 行ごとの時間を返す．表の無いページは空
    private static func selectionTimes(_ window: NSWindow) -> [Double] {
        guard let table = pageViews(window).compactMap({ $0 as? NSTableView }).first(where: { $0.numberOfRows > 1 }) else { return [] }
        let times = (0..<min(table.numberOfRows, 8)).map { row in
            timed(window) { table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        }
        table.deselectAll(nil)
        SettingsFixture.settle(window)
        return times
    }

    private static func median(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.sorted()[values.count / 2]
    }

    /// work を行い，画面に映し終わるまでの時間(ms)
    private static func timed(_ window: NSWindow, _ work: () -> Void) -> Double {
        let start = now()
        work()
        SettingsFixture.settle(window)
        return (now() - start) * 1000
    }

    /// 開いているページの中の部品(見せていないページと左の一覧は除く)
    private static func pageViews(_ window: NSWindow) -> [NSView] {
        guard let content = window.contentView else { return [] }
        var stack: [NSView] = [content]
        var root: NSView?
        while let view = stack.popLast(), root == nil {
            if view is SettingsPageStack.PageStackView { root = view }
            stack.append(contentsOf: view.subviews)
        }
        var found: [NSView] = []
        stack = root.map { [$0] } ?? []
        while let view = stack.popLast() {
            if view.isHidden { continue }
            found.append(view)
            stack.append(contentsOf: view.subviews)
        }
        return found
    }

    /// ページを上から下まで少しずつ送り，1 段ごとの時間を返す．送れないページは空
    private static func scrollTimes(_ window: NSWindow) -> [Double] {
        let scrolls = pageViews(window).compactMap { $0 as? NSScrollView }
        // ページ全体を送るスクロールビュー(いちばん長く送れるもの)
        guard let scroll = scrolls.max(by: { range($0) < range($1) }), range(scroll) > 0 else { return [] }
        let clip = scroll.contentView
        let step: CGFloat = 40
        var times: [Double] = []
        var y: CGFloat = 0
        while y < range(scroll) {
            y = min(y + step, range(scroll))
            times.append(timed(window) {
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
                scroll.reflectScrolledClipView(clip)
            })
        }
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: 0))
        scroll.reflectScrolledClipView(clip)
        SettingsFixture.settle(window)
        return times
    }

    private static func range(_ scroll: NSScrollView) -> CGFloat {
        max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
    }

    /// ページの最初の入力欄に 1 字ずつ打ち，1 字ごとの時間を返す．入力欄の無いページは空
    private static func typingTimes(_ window: NSWindow) -> [Double] {
        let fields = pageViews(window).compactMap { $0 as? NSTextField }.filter { $0.isEditable && $0.isEnabled }
        // 画面の上にある欄から使う
        guard let field = fields.min(by: { $0.convert(NSPoint.zero, to: nil).y > $1.convert(NSPoint.zero, to: nil).y }),
              window.makeFirstResponder(field), let editor = window.firstResponder as? NSTextView else { return [] }
        let end = NSRange(location: NSNotFound, length: 0)
        let times = (0..<12).map { _ in timed(window) { editor.insertText("a", replacementRange: end) } }
        editor.selectAll(nil)
        editor.insertText("", replacementRange: editor.selectedRange())
        SettingsFixture.settle(window)
        return times
    }
}

/// 計測と書き出しに使う設定の画面の部品．設定と同期の状態は一時ディレクトリに置く
@MainActor
struct SettingsFixture {
    let model: SettingsModel
    let sync: SyncCoordinator
    let store: FileSettingsStore

    static func make(name: String) -> SettingsFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FileSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let synchronizer = SettingsSynchronizer(settings: store, stateStore: FileSyncStateStore(fileURL: directory.appendingPathComponent("sync-state.json")))
        let dictionaries = ImportedDictionaryStore(directory: directory.appendingPathComponent("dictionaries", isDirectory: true))
        let sync = SyncCoordinator(synchronizer: synchronizer, runner: FolderSyncRunner(synchronizer: synchronizer, settings: store, dictionaries: dictionaries), settings: store)
        // 変換マクロの「試す」は本番と同じものを付ける(コマンドのページを描くたびに呼ばれる)
        let macroPreview = ConversionMacroPreview(settings: store, calendar: SystemCalendar(clock: Date.init))
        let model = SettingsModel(store: store, usage: nil, files: SettingsFiles(settings: store, dictionaries: dictionaries), resetLearning: {},
                                  previewMacros: { macroPreview.preview(text: $0, reading: $1, pattern: $2) })
        return SettingsFixture(model: model, sync: sync, store: store)
    }

    /// 切り替えを画面に映し終わるまで回す．SwiftUI は実行ループの区切りで描き直すので，実行ループを回してから描く．
    /// 初めて開くページは「読み込み中」を出した次の区切りで組み立てるので，何度か回す
    static func settle(_ window: NSWindow) {
        for _ in 0..<8 {
            RunLoop.main.run(mode: .default, before: Date())
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
        }
    }
}
#endif
