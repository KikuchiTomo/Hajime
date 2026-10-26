#if DEBUG
import AppKit
import QuartzCore
import S90Application
import S90Domain
import S90Persistence

/// 設定の画面でページを切り替えたときにかかる時間を測る(デバッグビルドだけ)．
/// 実際の窓(ツールバー付き)を出し，ページを切り替えて，描き終わるまでの時間をページごとに出す．
///
/// 使い方: Debug でビルドした "s90.tokyo IME Debug.app/Contents/MacOS/s90.tokyo IME Debug" --measure-settings
/// 設定はサンドボックスの一時ディレクトリに置き，利用者の設定に触れない．
/// 環境変数 S90_MEASURE_PAGES・S90_MEASURE_ROUNDS・S90_MEASURE_CHANGES で，測るページ・回数・設定を変える回数を選べる(docs/dev/DESIGN-SYSTEM.md)
@MainActor
enum SettingsBenchmark {
    static let argument = "--measure-settings"
    /// 1 ページを何回ずつ測るか．1 回目は初めて組み立てる分が重いので別に出す
    private static var rounds: Int {
        Int(ProcessInfo.processInfo.environment["S90_MEASURE_ROUNDS"] ?? "") ?? 6
    }

    /// 測るページ．環境変数 S90_MEASURE_PAGES にページの名前をカンマで区切って渡すと，そのページだけを測る(プロファイラで見るとき)
    private static var pages: [SettingsView.Page] {
        guard let names = ProcessInfo.processInfo.environment["S90_MEASURE_PAGES"]?.split(separator: ",").map(String.init) else {
            return SettingsView.Page.allCases
        }
        return SettingsView.Page.allCases.filter { names.contains($0.title) }
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
                let start = CACurrentMediaTime()
                navigation.page = page
                SettingsFixture.settle(window)
                let elapsed = (CACurrentMediaTime() - start) * 1000
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
        let changeCount = Int(ProcessInfo.processInfo.environment["S90_MEASURE_CHANGES"] ?? "") ?? 10
        for _ in 0..<changeCount {
            let start = CACurrentMediaTime()
            fixture.model.update { $0.liveConversion.toggle() }
            SettingsFixture.settle(window)
            changes.append((CACurrentMediaTime() - start) * 1000)
        }
        changes.sort()
        print(String(format: "設定を 1 つ変える\t-\t%.1f\t%.1f", changes[changes.count / 2], changes.last ?? 0))
        exit(0)
    }
}

/// 計測と書き出しに使う設定の画面の部品．設定と同期の状態は一時ディレクトリに置く
@MainActor
struct SettingsFixture {
    let model: SettingsModel
    let sync: SyncCoordinator

    static func make(name: String) -> SettingsFixture {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-\(name)", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = FileSettingsStore(fileURL: directory.appendingPathComponent("settings.json"))
        let synchronizer = SettingsSynchronizer(settings: store, stateStore: FileSyncStateStore(fileURL: directory.appendingPathComponent("sync-state.json")))
        let dictionaries = ImportedDictionaryStore(directory: directory.appendingPathComponent("dictionaries", isDirectory: true))
        let sync = SyncCoordinator(synchronizer: synchronizer, runner: FolderSyncRunner(synchronizer: synchronizer, settings: store, dictionaries: dictionaries), settings: store)
        let model = SettingsModel(store: store, usage: nil, files: SettingsFiles(settings: store, dictionaries: dictionaries), resetLearning: {})
        return SettingsFixture(model: model, sync: sync)
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
