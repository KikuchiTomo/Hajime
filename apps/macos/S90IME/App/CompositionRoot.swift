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
    let note: NoteController
    let contextProvider: InputContextProvider
    let calendar = SystemCalendar(clock: { Date() })
    let sync: SyncCoordinator
    /// 取り込んだ辞書の索引(Application Support の dictionaries/)．入力欄ごとの変換と設定の画面で共有する
    let dictionaries: ImportedDictionaryStore
    /// 連想の辞書の索引(Application Support の associations/．R-18)．入力欄ごとの変換と設定の画面で共有する
    let associations: AssociationDictionaryStore

    /// 打ち間違いの訂正を別に求めるもの．Zenzai が無ければ nil
    let typoService: ZenzaiTypoService?
    /// 再変換で確定済みの文字の読みを求める(OS の日本語の解析)
    let transcriber = SystemReadingTranscriber()

    private init(settings: FileSettingsStore, engine: AzooKeyConverterEngine, usage: FileUsageStore, typoService: ZenzaiTypoService?, sync: SyncCoordinator,
                 dictionaries: ImportedDictionaryStore, associations: AssociationDictionaryStore) {
        self.typoService = typoService
        self.settings = settings
        self.engine = engine
        self.usage = usage
        self.sync = sync
        self.dictionaries = dictionaries
        self.associations = associations
        self.lexicon = SpellCheckerLexicon()
        self.candidatePanel = CandidatePanelController()
        self.modeIndicator = ModeIndicatorController()
        self.note = NoteController()
        self.contextProvider = InputContextProvider(settings: settings)
    }

    static func install() throws {
        precondition(installed == nil, "CompositionRoot は起動時に一度だけ組み立てる")
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true)
        let settings = FileSettingsStore(fileURL: support.appendingPathComponent("settings.json"))
        let zenzai = loadZenzaiModel()
        let memory = support.appendingPathComponent("memory", isDirectory: true)
        let engine = try AzooKeyConverterEngine(memoryDirectory: memory, versionString: AppIdentity.versionString, zenzai: zenzai)
        // 打ち間違いの訂正は時間がかかるので，別の変換器でメインスレッドの外で求める(Zenzai があるときだけ)
        let typoService = zenzai.map { ZenzaiTypoService(zenzai: $0, memoryDirectory: memory, versionString: AppIdentity.versionString) }
        engine.apply(settings.current)
        settings.observe { [weak engine] in engine?.apply($0) }
        // 最初の変換はモデルの準備で時間がかかるので，打ち始める前に一度変換しておく
        engine.warmUp()
        let usage = FileUsageStore(fileURL: support.appendingPathComponent("usage.json"), isEnabled: { settings.current.recordsUsage })
        // 同期(R-15)．この Mac の同期の設定は settings.json と別のファイルに置く
        let synchronizer = SettingsSynchronizer(settings: settings, stateStore: FileSyncStateStore(fileURL: support.appendingPathComponent("sync-state.json")))
        let dictionaries = ImportedDictionaryStore(directory: support.appendingPathComponent("dictionaries", isDirectory: true))
        let sync = SyncCoordinator(synchronizer: synchronizer, runner: FolderSyncRunner(synchronizer: synchronizer, settings: settings, dictionaries: dictionaries),
                                   settings: settings)
        sync.start()
        // 同梱の連想の辞書(日本語 WordNet)は，起動したら裏で読み始め，初めて連想変換を使うときに待たせない
        let associations = AssociationDictionaryStore(
            directory: support.appendingPathComponent("associations", isDirectory: true),
            bundledSource: Bundle.main.resourceURL?.appendingPathComponent(DefaultSettings.bundledAssociationFileName))
        associations.preloadBundled()
        installed = CompositionRoot(settings: settings, engine: engine, usage: usage, typoService: typoService, sync: sync, dictionaries: dictionaries,
                                    associations: associations)
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
        InputSession(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar, postalCodes: postalCodes, dictionaries: dictionaries),
                     lexicon: lexicon, settings: settings, usage: usage, typoService: typoService, associations: associations)
    }

    /// 設定の画面．開くたびに作らず使い回す
    private(set) lazy var settingsWindow: SettingsWindowController = {
        // 設定の画面の「試す」は，入力と同じ変換器と英単語の辞書で英語と日本語を見分ける
        let preview = WordLanguagePreview(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar),
                                          lexicon: lexicon, settings: settings)
        let controller = SettingsWindowController(settings: settings, usage: usage, sync: sync, files: SettingsFiles(settings: settings, dictionaries: dictionaries, associations: associations), associations: associations,
                                                  resetLearning: { [engine] in engine.resetLearning() },
                                                  previewLanguage: { preview.preview($0, precedingText: $1) })
        controller.noteSetAsideFile(settings.setAsideFile)
        return controller
    }()

    func makePresenter(session: InputSession) -> ClientActionPresenter {
        ClientActionPresenter(session: session, candidatePanel: candidatePanel, modeIndicator: modeIndicator, note: note, settings: settings,
                              openSettings: { [unowned self] in self.settingsWindow.show() }, handwriting: handwriting)
    }

    /// 郵便番号の表(R-13)．入力欄ごとのセッションで共有し，初めて引くときに読み込む
    private(set) lazy var postalCodes: PostalCodeFile? = Bundle.main.url(forResource: "postal-codes", withExtension: "tsv").map(PostalCodeFile.init(url:))

    /// 手書きの窓(R-14)．開くたびに作らず使い回す
    private(set) lazy var handwriting = HandwritingController(recognizer: VisionHandwritingRecognizer(), settings: settings)
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
