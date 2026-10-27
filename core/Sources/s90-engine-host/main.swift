#if os(Windows) || os(Linux) || os(macOS)
import Dispatch
import Foundation
import S90Application
import S90Domain
import S90Engine
import S90IPC
import S90Persistence

/// 変換のエンジンのプロセス．Windows は名前付きパイプ，Linux は Unix ドメインソケットで枠組みの口とつなぐ(ADR 0003・0012)．
/// macOS では入力メソッドが core を直接使うので，ここは Linux の口を macOS で試すときだけ使う
enum HostPaths {
    #if os(Windows)
    /// 設定(移動プロファイルで運ぶ)
    static var roaming: URL { directory(environment: "APPDATA", fallback: nil) }
    /// 学習データ・使い方の記録・取り込んだ辞書(この PC だけのもの)
    static var local: URL { directory(environment: "LOCALAPPDATA", fallback: nil) }
    static let versionString = "s90.tokyo IME for Windows"
    #else
    /// 設定(XDG Base Directory の config)
    static var roaming: URL { directory(environment: "XDG_CONFIG_HOME", fallback: ".config") }
    /// 学習データ・使い方の記録・取り込んだ辞書(XDG Base Directory の data)
    static var local: URL { directory(environment: "XDG_DATA_HOME", fallback: ".local/share") }
    static let versionString = "s90.tokyo IME for Linux"
    #endif

    /// name の環境変数の場所．無ければホームの fallback(Linux)か一時フォルダ
    private static func directory(environment name: String, fallback: String?) -> URL {
        // XDG の値は絶対パスのときだけ使う(XDG Base Directory の決まり)
        let value = ProcessInfo.processInfo.environment[name].flatMap { !$0.isEmpty && (fallback == nil || $0.hasPrefix("/")) ? $0 : nil }
        let base = value.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fallback.map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("s90.tokyo", isDirectory: true).appendingPathComponent("IME", isDirectory: true)
    }

    /// 実行ファイルと一緒に置いたもの(Zenzai のモデル・連想の辞書・郵便番号の表)
    static var installation: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }
}

/// 英単語の辞書が無いときの代わり．英単語の綴りの補正だけを止め，入力は続ける(Linux の辞書はまだ用意していない)
final class UnavailableEnglishLexicon: EnglishLexicon {
    func isWord(_ text: String) -> Bool { false }
    func suggestions(for text: String) -> [String] { [] }
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
    private static let interval = DispatchTimeInterval.milliseconds(Int(DefaultSettings.settingsFileWatchInterval * 1000))
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
    #if os(Windows)
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
    #else
    let engineListener: UnixSocketListener
    let windowListener: UnixSocketListener
    do {
        engineListener = try UnixSocketListener(path: UnixSocketPath.engine())
        windowListener = try UnixSocketListener(path: UnixSocketPath.candidateWindow())
    } catch where error.isAlreadyRunning {
        return 0
    } catch {
        FileHandle.standardError.write(Data("ソケットを作れません: \(error)\n".utf8))
        return 1
    }
    #endif

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
    #if os(Windows)
    let lexicon = WindowsSpellCheckerLexicon()
    if !lexicon.isAvailable {
        // 英単語の綴りの補正だけを止めて，入力は続ける
        FileHandle.standardError.write(Data("英語のスペルチェッカーを使えません(\(lexicon.openStatus))．英単語の綴りの補正をしません\n".utf8))
    }
    #else
    let lexicon = UnavailableEnglishLexicon()
    #endif
    // 打ち間違いの訂正は時間がかかるので，別の変換器で裏で求める(Zenzai があるときだけ．macOS の CompositionRoot と同じ)
    let typoService = zenzai.map { ZenzaiTypoService(zenzai: $0, memoryDirectory: memory, versionString: HostPaths.versionString) }
    // 候補の指示は，Windows は候補ウィンドウ(s90-candidate-ui.exe)，Linux は Fcitx 5 のアドオンが受け取る
    let window = CandidateWindowLink()
    let sendToWindow: (WireUiCommand) -> Void = { window.send($0) }
    #if os(Windows)
    let settingsApp = HostPaths.installation.appendingPathComponent("s90-settings.exe")
    #else
    // 設定の画面は Linux ではまだ作っていない(ADR 0012)
    let settingsApp = HostPaths.installation.appendingPathComponent("s90-settings")
    #endif

    // 設定の同期(R-15)．同期の記録とフォルダはこの PC だけのもの(移動プロファイルで運ばない)なので Local に置く
    let synchronizer = SettingsSynchronizer(settings: settings,
                                            stateStore: FileSyncStateStore(fileURL: HostPaths.local.appendingPathComponent("sync-state.json")))
    let sync = PathSyncCoordinator(synchronizer: synchronizer,
                                   runner: FolderSyncRunner(synchronizer: synchronizer, settings: settings, dictionaries: dictionaries),
                                   settings: settings)
    let files = SettingsFiles(settings: settings, dictionaries: dictionaries, associations: associations)

    // 設定の画面の「試す」は，入力と同じ変換器と英単語の辞書で英語と日本語を見分ける(macOS と同じ)
    let preview = WordLanguagePreview(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar),
                                      lexicon: lexicon, settings: settings)
    let service = EngineService(
        makeSession: {
            InputSession(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar, postalCodes: postalCodes, dictionaries: dictionaries),
                         lexicon: lexicon, settings: settings, usage: usage, typoService: typoService, associations: associations,
                         keyNames: .windows)
        },
        settings: settings,
        ui: sendToWindow,
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
        sendToWindow(.setPresentation(presentation: service.presentation))
    }
    engine.warmUp()
    sync.start()
    let watcher = SettingsWatcher(settings: settings, url: HostPaths.roaming.appendingPathComponent("settings.json"))

    #if os(Windows)
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
    #else
    let presentation = service.presentation
    window.start(listener: windowListener) {
        [.hello(protocolVersion: WireProtocol.version), .setPresentation(presentation: presentation)]
    }
    EngineSocketServer.start(listener: engineListener, service: service, candidateWindowPath: nil)
    #endif
    withExtendedLifetime((watcher, engineListener, windowListener)) { dispatchMain() }
}

exit(MainActor.assumeIsolated { run() })
#else
import Foundation

FileHandle.standardError.write(Data("s90-engine-host は Windows・Linux・macOS で動きます\n".utf8))
exit(1)
#endif
