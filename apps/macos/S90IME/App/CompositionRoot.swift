import AppKit
import os
import S90Application
import S90Domain
import S90Engine
import S90Persistence

/// 具象を組み立てる唯一の場所(docs/dev/GUIDELINES.md)．
///
/// InputMethodKit は入力コントローラを Info.plist のクラス名から自分で作るので，
/// イニシャライザで依存を渡せない．そのため組み立てた結果を `installed` に一度だけ置き，
/// コントローラはそこから受け取る．これ以外の場所でこの値を読まない．
@MainActor
final class CompositionRoot {
    private(set) static var installed: CompositionRoot?

    let settings: FileSettingsStore
    let engine: AzooKeyConverterEngine
    let usage: FileUsageStore
    let lexicon: SpellCheckerLexicon
    let candidatePanel: CandidatePanelController
    let modeIndicator: ModeIndicatorController
    let contextProvider: InputContextProvider
    let calendar = SystemCalendar(clock: { Date() })

    private init(settings: FileSettingsStore, engine: AzooKeyConverterEngine, usage: FileUsageStore) {
        self.settings = settings
        self.engine = engine
        self.usage = usage
        self.lexicon = SpellCheckerLexicon()
        self.candidatePanel = CandidatePanelController()
        self.modeIndicator = ModeIndicatorController()
        self.contextProvider = InputContextProvider(settings: settings)
    }

    static func install() throws {
        precondition(installed == nil, "CompositionRoot は起動時に一度だけ組み立てる")
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
        let settings = FileSettingsStore(fileURL: support.appendingPathComponent("settings.json"))
        let engine = try AzooKeyConverterEngine(
            memoryDirectory: support.appendingPathComponent("memory", isDirectory: true),
            versionString: AppIdentity.versionString,
            zenzai: loadZenzaiModel()
        )
        engine.apply(settings.current)
        settings.observe { [weak engine] in engine?.apply($0) }
        // 最初の変換はモデルの準備で時間がかかるので，打ち始める前に一度変換しておく
        engine.warmUp()
        FontRegistry.registerBundledFonts()
        let usage = FileUsageStore(fileURL: support.appendingPathComponent("usage.json"), isEnabled: { settings.current.recordsUsage })
        installed = CompositionRoot(settings: settings, engine: engine, usage: usage)
    }

    /// アプリに入れた Zenzai のモデルを確かめて読む．無いか，ハッシュが合わなければ Zenzai なしで動く
    private static func loadZenzaiModel() -> ZenzaiModel? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("Zenzai", isDirectory: true)
            .appendingPathComponent(ZenzaiModel.fileName) else { return nil }
        do {
            return try ZenzaiModel.verified(at: url)
        } catch {
            Logger(subsystem: AppIdentity.bundleIdentifier, category: "zenzai")
                .notice("Zenzai を使いません: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    func makeSession() -> InputSession {
        InputSession(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar), lexicon: lexicon, settings: settings, usage: usage)
    }

    /// 設定の画面．開くたびに作らず使い回す
    private(set) lazy var settingsWindow = SettingsWindowController(settings: settings, usage: usage, resetLearning: { [engine] in engine.resetLearning() })

    func makePresenter() -> ClientActionPresenter {
        ClientActionPresenter(candidatePanel: candidatePanel, modeIndicator: modeIndicator, settings: settings)
    }
}

/// 本番と開発版(Debug)で変わる値．どちらも Info.plist から読む(apps/macos/project.yml の configs)
enum AppIdentity {
    static let bundleIdentifier = Bundle.main.bundleIdentifier ?? "tokyo.s90.inputmethod.S90IME"
    static let supportDirectoryName = Bundle.main.infoDictionary?["S90SupportDirectoryName"] as? String ?? "tokyo.s90.ime"
    static let japaneseModeID = bundleIdentifier + ".Japanese"
    static let directModeID = bundleIdentifier + ".Roman"
    /// Info.plist の ComponentInputModeDict のキー．OS は setValue でこの値を渡してくる
    static let japaneseModeKey = "com.apple.inputmethod.Japanese"
    static let directModeKey = "com.apple.inputmethod.Roman"

    static var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        return "s90.tokyo IME (\(version))"
    }
}
