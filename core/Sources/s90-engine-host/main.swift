#if os(Windows)
import Dispatch
import Foundation
import S90Application
import S90Domain
import S90Engine
import S90IPC
import S90Persistence

enum HostPaths {
    static var roaming: URL { directory(environment: "APPDATA") }
    static var local: URL { directory(environment: "LOCALAPPDATA") }

    private static func directory(environment name: String) -> URL {
        let base = ProcessInfo.processInfo.environment[name].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("s90.tokyo", isDirectory: true).appendingPathComponent("IME", isDirectory: true)
    }

    static var installation: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }

    static let versionString = "s90.tokyo IME for Windows"
}

/// インストール先の Zenzai\ に置いたモデルを確かめて読む．無いか，大きさとハッシュが合わなければ Zenzai なしで動く
@MainActor
func loadZenzaiModel() -> ZenzaiModel? {
    let url = HostPaths.installation.appendingPathComponent("Zenzai", isDirectory: true).appendingPathComponent(ZenzaiModel.fileName)
    do {
        return try ZenzaiModel.verified(at: url)
    } catch {
        // 中身は書かない(ファイルの場所と理由だけ)
        FileHandle.standardError.write(Data("Zenzai を使いません: \(error)\n".utf8))
        return nil
    }
}

@MainActor
final class SettingsWatcher {
    private static let interval = DispatchTimeInterval.seconds(2)
    private let settings: FileSettingsStore
    private let url: URL
    private var last: Date?
    private let timer = DispatchSource.makeTimerSource(queue: .main)

    init(settings: FileSettingsStore, url: URL) {
        self.settings = settings
        self.url = url
        self.last = Self.modificationDate(of: url)
        timer.schedule(deadline: .now() + Self.interval, repeating: Self.interval)
        timer.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.resume()
    }

    private func check() {
        let date = Self.modificationDate(of: url)
        guard date != last else { return }
        last = date
        settings.reload()
    }

    private static func modificationDate(of url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}

@MainActor
func run() -> Int32 {
    let engineListener: NamedPipeListener
    let windowListener: NamedPipeListener
    do {
        engineListener = try NamedPipeListener(name: NamedPipeName.engine())
        windowListener = try NamedPipeListener(name: NamedPipeName.candidateWindow())
    } catch where error.isAlreadyRunning {
        return 0
    } catch {
        FileHandle.standardError.write(Data("名前付きパイプを作れません: \(error)\n".utf8))
        return 1
    }

    let settings = FileSettingsStore(fileURL: HostPaths.roaming.appendingPathComponent("settings.json"))
    let memory = HostPaths.local.appendingPathComponent("memory", isDirectory: true)
    let zenzai = loadZenzaiModel()
    let engine: AzooKeyConverterEngine
    do {
        engine = try AzooKeyConverterEngine(memoryDirectory: memory, versionString: HostPaths.versionString, zenzai: zenzai)
    } catch {
        FileHandle.standardError.write(Data("変換エンジンを用意できません: \(error)\n".utf8))
        return 1
    }
    engine.apply(settings.current)
    let usage = FileUsageStore(fileURL: HostPaths.local.appendingPathComponent("usage.json"), isEnabled: { settings.current.recordsUsage })
    let calendar = SystemCalendar(clock: { Date() })
    let dictionaries = ImportedDictionaryStore(directory: HostPaths.local.appendingPathComponent("dictionaries", isDirectory: true))
    let associations = AssociationDictionaryStore(
        directory: HostPaths.local.appendingPathComponent("associations", isDirectory: true),
        bundledSource: HostPaths.installation.appendingPathComponent(DefaultSettings.bundledAssociationFileName))
    associations.preloadBundled()
    let postalTable = HostPaths.installation.appendingPathComponent("postal-codes.tsv")
    let postalCodes = FileManager.default.fileExists(atPath: postalTable.path) ? PostalCodeFile(url: postalTable) : nil
    // 英単語の辞書は Windows のスペルチェッカー(macOS の NSSpellChecker と同じ役)
    let lexicon = WindowsSpellCheckerLexicon()
    // 打ち間違いの訂正は時間がかかるので，別の変換器で裏で求める(Zenzai があるときだけ．macOS の CompositionRoot と同じ)
    let typoService = zenzai.map { ZenzaiTypoService(zenzai: $0, memoryDirectory: memory, versionString: HostPaths.versionString) }
    let window = CandidateWindowLink()
    let settingsApp = HostPaths.installation.appendingPathComponent("s90-settings.exe")

    // 設定の同期(R-15)．同期の記録とフォルダはこの PC だけのもの(移動プロファイルで運ばない)なので Local に置く
    let synchronizer = SettingsSynchronizer(settings: settings,
                                            stateStore: FileSyncStateStore(fileURL: HostPaths.local.appendingPathComponent("sync-state.json")))
    let sync = PathSyncCoordinator(synchronizer: synchronizer,
                                   runner: FolderSyncRunner(synchronizer: synchronizer, settings: settings, dictionaries: dictionaries),
                                   settings: settings)
    let files = SettingsFiles(settings: settings, dictionaries: dictionaries)

    // 設定の画面の「試す」は，入力と同じ変換器と英単語の辞書で英語と日本語を見分ける(macOS と同じ)
    let preview = WordLanguagePreview(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar),
                                      lexicon: lexicon, settings: settings)
    let service = EngineService(
        makeSession: {
            InputSession(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar, postalCodes: postalCodes, dictionaries: dictionaries),
                         lexicon: lexicon, settings: settings, usage: usage, typoService: typoService, associations: associations)
        },
        settings: settings,
        ui: { window.send($0) },
        openSettings: {
            guard FileManager.default.fileExists(atPath: settingsApp.path) else { return }
            let process = Process()
            process.executableURL = settingsApp
            try? process.run()
        },
        hints: { BranchHints.make(for: $0, settings: $1) },
        typoService: typoService,
        sync: sync,
        files: files,
        services: SettingsServices(
            resetLearning: { [engine] in engine.resetLearning() },
            usage: usage,
            previewLanguage: { preview.preview($0, precedingText: $1) }
        )
    )
    settings.observe { [weak engine] in
        engine?.apply($0)
        window.send(.setPresentation(presentation: service.presentation))
    }
    engine.warmUp()
    sync.start()
    let watcher = SettingsWatcher(settings: settings, url: HostPaths.roaming.appendingPathComponent("settings.json"))

    let presentation = service.presentation
    let candidateWindow = HostPaths.installation.appendingPathComponent("s90-candidate-ui.exe")
    window.start(listener: windowListener, expectedImagePath: candidateWindow.path) {
        [.hello(protocolVersion: WireProtocol.version), .setPresentation(presentation: presentation)]
    }
    EnginePipeServer.start(listener: engineListener, service: service, candidateWindowPath: candidateWindow.path)
    if FileManager.default.fileExists(atPath: candidateWindow.path) {
        let process = Process()
        process.executableURL = candidateWindow
        try? process.run()
    }
    withExtendedLifetime(watcher) { dispatchMain() }
}

exit(MainActor.assumeIsolated { run() })
#else
import Foundation

FileHandle.standardError.write(Data("s90-engine-host は Windows だけで動きます(macOS では core を入力メソッドに直接つなぐ)\n".utf8))
exit(1)
#endif
