import AppKit
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
    let lexicon: SpellCheckerLexicon
    let candidatePanel: CandidatePanelController
    let modeIndicator: ModeIndicatorController
    let contextProvider: InputContextProvider

    private init(settings: FileSettingsStore, engine: AzooKeyConverterEngine) {
        self.settings = settings
        self.engine = engine
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
            versionString: AppIdentity.versionString
        )
        FontRegistry.registerBundledFonts()
        installed = CompositionRoot(settings: settings, engine: engine)
    }

    func makeSession() -> InputSession {
        InputSession(converter: engine.makeSession(), lexicon: lexicon, settings: settings)
    }

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
