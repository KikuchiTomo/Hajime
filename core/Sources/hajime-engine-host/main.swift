#if os(Windows) || os(Linux) || os(macOS)
import Dispatch
import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeIPC
import HajimePersistence

/// 変換のエンジンのプロセス．Windows は名前付きパイプ，Linux は Unix ドメインソケットで枠組みの口とつなぐ(ADR 0003・0012)．
/// macOS では入力メソッドが core を直接使うので，ここは Linux の口を macOS で試すときだけ使う
enum HostPaths {
    #if os(Windows)
    /// 設定(移動プロファイルで運ぶ)
    static var roaming: URL { directory(environment: "APPDATA", fallback: nil) }
    /// 学習データ・使い方の記録・取り込んだ辞書(この PC だけのもの)
    static var local: URL { directory(environment: "LOCALAPPDATA", fallback: nil) }
    static let versionString = "Hajime for Windows"
    #else
    /// 設定(XDG Base Directory の config)
    static var roaming: URL { directory(environment: "XDG_CONFIG_HOME", fallback: ".config") }
    /// 学習データ・使い方の記録・取り込んだ辞書(XDG Base Directory の data)
    static var local: URL { directory(environment: "XDG_DATA_HOME", fallback: ".local/share") }
    static let versionString = "Hajime for Linux"
    #endif

    /// name の環境変数の場所．無ければホームの fallback(Linux)か一時フォルダ
    private static func directory(environment name: String, fallback: String?) -> URL {
        // XDG の値は絶対パスのときだけ使う(XDG Base Directory の決まり)
        let value = ProcessInfo.processInfo.environment[name].flatMap { !$0.isEmpty && (fallback == nil || $0.hasPrefix("/")) ? $0 : nil }
        let base = value.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? fallback.map { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent($0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("haji.men", isDirectory: true).appendingPathComponent("IME", isDirectory: true)
    }

    /// 実行ファイルと一緒に置いたもの(Zenzai モデル・かな漢字変換の辞書・連想の辞書・郵便番号の表)
    static var installation: URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
    }
}

/// 英単語の辞書が無いときの代わり．英単語の綴りの補正だけを止め，入力は続ける(Linux の辞書はまだ用意していない)
final class UnavailableEnglishLexicon: EnglishLexicon {
    func isWord(_ text: String) -> Bool { false }
    func suggestions(for text: String) -> [String] { [] }
}

/// インストール先に置いた Zenzai モデルと Jinen モデル(Zenzai\・Jinen\)とかな漢字変換の辞書(Dictionary\)を，同時に確かめて読む．
/// 無いか，大きさとハッシュが合わないものは使わずに動く(モデルが無ければ Zenzai なし・合議なし，辞書が無ければ azooKey に同梱の辞書)
@MainActor
func loadStartupResources() -> (zenzai: ZenzaiModel?, fastZenzai: ZenzaiModel?, jinen: JinenModel?, fastJinen: JinenModel?, dictionary: BundledDictionary?) {
    let models = HostPaths.installation.appendingPathComponent("Zenzai", isDirectory: true)
    let jinen = HostPaths.installation.appendingPathComponent("Jinen", isDirectory: true)
    // 前回確かめて合ったファイルが変わっていなければ，ハッシュを求め直さない(ADR 0017)．記録はこの PC の本人だけの場所に置く．
    // エンジンはアプリのバージョンを持たないので，実行ファイル自身を見分ける値を使う(入れ直せば変わる)．読めなければ記録を使わない
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let version = StartupResources.executableIdentity(at: executable)
    let resources = StartupResources.verified(
        zenzai: models.appendingPathComponent(ZenzaiModel.Variant.small.fileName),
        fastZenzai: models.appendingPathComponent(ZenzaiModel.Variant.xsmall.fileName),
        jinen: jinen.appendingPathComponent(JinenModel.Variant.small.fileName),
        fastJinen: jinen.appendingPathComponent(JinenModel.Variant.xsmall.fileName),
        dictionary: HostPaths.installation.appendingPathComponent(BundledDictionary.directoryName, isDirectory: true),
        records: version.map { _ in FileVerificationRecordStore(fileURL: HostPaths.local.appendingPathComponent(DefaultSettings.verificationRecordFileName)) },
        appVersion: version ?? "")
    return (accepted(resources.zenzai, name: "Zenzai(small)"), accepted(resources.fastZenzai, name: "Zenzai(xsmall)"),
            accepted(resources.jinen, name: "jinen(small)"), accepted(resources.fastJinen, name: "jinen(xsmall)"),
            accepted(resources.dictionary, name: "同梱の辞書"))
}

/// 確かめた結果を使うものにする．合わなければ理由を書いて使わない(中身は書かない．ファイルの種類と理由だけ)
private func accepted<Value, Failure: Error>(_ result: Result<Value, Failure>?, name: String) -> Value? {
    switch result {
    case .success(let value):
        return value
    case .failure(let error):
        FileHandle.standardError.write(Data("\(name)を使いません: \(error)\n".utf8))
        return nil
    case nil:
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
    EngineProcess.requestFullExecutionSpeed()
    // 候補ウィンドウは，辞書とモデルを読み込むあいだに起動しておく(起動してすぐの候補を早く出すため)．
    // パイプはもうあるので候補ウィンドウはすぐにつなぎ，エンジンが受け付けて挨拶を送るまで待つ
    let candidateWindow = HostPaths.installation.appendingPathComponent("hajime-candidate-ui.exe")
    var candidateProcess: Process?
    if FileManager.default.fileExists(atPath: candidateWindow.path) {
        let process = Process()
        process.executableURL = candidateWindow
        if (try? process.run()) != nil { candidateProcess = process }
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
    let resources = loadStartupResources()
    let zenzai = resources.zenzai
    let engine: AzooKeyConverterEngine
    do {
        engine = try AzooKeyConverterEngine(memoryDirectory: memory, versionString: HostPaths.versionString, zenzai: zenzai,
                                            fastZenzai: resources.fastZenzai, jinen: resources.jinen, fastJinen: resources.fastJinen,
                                            dictionaryDirectory: resources.dictionary?.url)
    } catch {
        FileHandle.standardError.write(Data("変換エンジンを用意できません: \(error)\n".utf8))
        #if os(Windows)
        // 先に起動した候補ウィンドウは，つなぐ相手が無いまま残らないよう終える
        candidateProcess?.terminate()
        #endif
        return 1
    }
    engine.apply(settings.current)
    let usage = FileUsageStore(fileURL: HostPaths.local.appendingPathComponent("usage.json"), settings: settings)
    let calendar = SystemCalendar(clock: { Date() })
    let dictionaries = ImportedDictionaryStore(directory: HostPaths.local.appendingPathComponent("dictionaries", isDirectory: true))
    // 同梱の辞書の中の専門用語の辞書(R-29)．同梱の辞書が無いか古ければ使わない
    let terms = resources.dictionary?.termDictionaryURL.map { TermDictionaryStore(url: $0) }
    let associations = AssociationDictionaryStore(
        directory: HostPaths.local.appendingPathComponent("associations", isDirectory: true),
        bundledSource: HostPaths.installation.appendingPathComponent(DefaultSettings.bundledAssociationFileName), settings: settings)
    associations.preloadBundled()
    let postalTable = HostPaths.installation.appendingPathComponent("postal-codes.tsv")
    let postalCodes = FileManager.default.fileExists(atPath: postalTable.path) ? PostalCodeFile(url: postalTable) : nil
    let usageTables = ["usage_dict.txt", "usage_dict_extra.tsv", "usage_dict_words.tsv"].map { HostPaths.installation.appendingPathComponent($0) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
    let usageDictionary = usageTables.isEmpty ? nil : UsageDictionaryFile(urls: usageTables)
    // 語の意味の辞書は数 MB あるので，注釈を出す設定なら起動したら裏で読み始める
    if settings.current.homophoneNotes { usageDictionary?.preload() }
    // 英語の語の辞書(R-24)．インストール先の english-terms.txt と設定で足した語をまとめて引き，変換の候補と英単語の補正で共有する
    let englishTerms = EnglishTerms(bundled: EnglishTermFile(url: HostPaths.installation.appendingPathComponent(DefaultSettings.bundledEnglishTermFileName)),
                                    settings: settings)
    // 英単語の辞書は Windows のスペルチェッカー(macOS の NSSpellChecker と同じ役)
    #if os(Windows)
    let spellChecker = WindowsSpellCheckerLexicon()
    if !spellChecker.isAvailable {
        // 英単語の綴りの補正だけを止めて，入力は続ける(英語の語の辞書の語は補正する)
        FileHandle.standardError.write(Data("英語のスペルチェッカーを使えません(\(spellChecker.openStatus))．英単語の綴りの補正をしません\n".utf8))
    }
    #else
    let spellChecker = UnavailableEnglishLexicon()
    #endif
    let lexicon = EnglishTermLexicon(spellChecker, terms: englishTerms)
    // 打ち間違いの訂正は時間がかかるので，別の変換器で裏で求める(Zenzai があるときだけ．macOS の CompositionRoot と同じ)
    let typoService = zenzai.map { ZenzaiTypoService(zenzai: $0, memoryDirectory: memory, versionString: HostPaths.versionString) }
    // 候補の指示は，Windows は候補ウィンドウ(hajime-candidate-ui.exe)，Linux は Fcitx 5 のアドオンが受け取る
    let window = CandidateWindowLink()
    let sendToWindow: (WireUiCommand) -> Void = { window.send($0) }
    #if os(Windows)
    let settingsApp = HostPaths.installation.appendingPathComponent("hajime-settings.exe")
    #else
    // 設定の画面は Linux ではまだ作っていない(ADR 0012)
    let settingsApp = HostPaths.installation.appendingPathComponent("hajime-settings")
    #endif

    // 設定の同期(R-15)．同期の記録とフォルダはこの PC だけのもの(移動プロファイルで運ばない)なので Local に置く
    let synchronizer = SettingsSynchronizer(settings: settings,
                                            stateStore: FileSyncStateStore(fileURL: HostPaths.local.appendingPathComponent("sync-state.json")))
    let sync = PathSyncCoordinator(synchronizer: synchronizer,
                                   runner: FolderSyncRunner(synchronizer: synchronizer, settings: settings, dictionaries: dictionaries),
                                   settings: settings)
    let files = SettingsFiles(settings: settings, dictionaries: dictionaries, associations: associations)

    // 設定の画面の「試す」は，入力と同じ変換器と英単語の辞書で英語と日本語を見分ける(macOS と同じ)
    let preview = WordLanguagePreview(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar, englishTerms: englishTerms),
                                      lexicon: lexicon, settings: settings)
    // 変換マクロの「試す」は，入力と同じ日時と乱数で見本の語に当てる(macOS と同じ)
    let macroPreview = ConversionMacroPreview(settings: settings, calendar: calendar)
    // 戻した補正を設定の「直さない語句」に覚える(macOS の CompositionRoot と同じ)
    let rejections = SettingsCorrectionRejections(settings: settings)
    // 予測に出した語句を設定の「予測に表示しない語句」に入れる(macOS の CompositionRoot と同じ)
    let predictionHiding = SettingsPredictionHiding(settings: settings)
    // 絵文字と記号のパレット(R-26)．描くのは Windows の候補ウィンドウだけ(Linux のアドオンはパレットを描かないので渡さない)．
    // エンジンのプロセスは書体を確かめられないので，Windows のビルド番号から描ける絵文字のバージョンを決める
    #if os(Windows)
    let paletteCatalog = PaletteCatalogFile(
        url: HostPaths.installation.appendingPathComponent(DefaultSettings.bundledPaletteFileName),
        maximumVersion: .supportedOnWindows(build: ProcessInfo.processInfo.operatingSystemVersion.patchVersion))
    // 絵文字に変換するときも同じ表から引く(このビルドの書体が描ける絵文字だけを出すため)
    if settings.current.palette || settings.current.emojiConversion { paletteCatalog.preload() }
    let paletteUsage = FilePaletteUsageStore(fileURL: HostPaths.local.appendingPathComponent(DefaultSettings.paletteUsageFileName))
    let palette: PaletteServices? = PaletteServices(catalog: paletteCatalog, usage: paletteUsage, now: { Date() })
    let resetPaletteHistory: () -> Void = { paletteUsage.update { $0.clearHistory() } }
    let emoji = PaletteEmojiLookup(catalog: paletteCatalog, usage: paletteUsage, settings: settings, now: { Date() })
    #else
    let palette: PaletteServices? = nil
    // Linux はパレットの表を持たないので，azooKey の絵文字の辞書から引く
    let emoji = engine
    let resetPaletteHistory: () -> Void = {}
    #endif
    let service = EngineService(
        makeSession: {
            // エンジンのセッションは，候補を文脈で並べ替える採点(検証木)も受け持つ．合議はこのプロセスの中で行う(ADR 0016)
            let engineSession = engine.makeSession()
            return InputSession(converter: SupplementedConverter(engineSession, settings: settings, calendar: calendar, postalCodes: postalCodes, dictionaries: dictionaries,
                                                                 terms: terms, emoji: emoji, lexicon: lexicon, englishTerms: englishTerms),
                                lexicon: lexicon, settings: settings, usage: usage, typoService: typoService, associations: associations,
                                keyNames: .windows, rejections: rejections, predictionHiding: predictionHiding, usageDictionary: usageDictionary,
                                palette: palette, calendar: calendar, scorer: engineSession, fusing: engineSession)
        },
        settings: settings,
        ui: sendToWindow,
        openSettings: { arguments in
            guard FileManager.default.fileExists(atPath: settingsApp.path) else { return }
            let process = Process()
            process.executableURL = settingsApp
            // 開くページなどの指示だけを渡す．登録する語は引数に入れず，設定の画面が takeWordRegistration で受け取る
            process.arguments = arguments
            try? process.run()
        },
        hints: { FooterHints.make(for: $0, settings: $1) },
        listHints: { FooterHints.make(for: $0, settings: $1) },
        placedHints: { FooterHints.placed(for: $0, settings: $1) },
        typoService: typoService,
        sync: sync,
        files: files,
        services: SettingsServices(
            resetLearning: { [engine] in engine.resetLearning() },
            usage: usage,
            resetPaletteHistory: resetPaletteHistory,
            previewLanguage: { preview.preview($0, precedingText: $1) },
            previewMacros: { macroPreview.preview(text: $0, reading: $1, pattern: $2) },
            automaticJinenModel: { [engine] in engine.automaticJinenModel?.rawValue }
        ),
        runCommand: { command in
            // 読みで呼び出すコマンド(R-22)．Windows だけで動かす(Linux はまだ設定の画面が無く，コマンドを登録できない)
            #if os(Windows)
            WindowsCommandLauncher.run(command)
            #else
            _ = command
            #endif
        },
        flushLearning: { [engine] in engine.flushLearning() },
        log: { message in
            #if os(Windows)
            EngineProcess.debugLog(message)
            #endif
        }
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
    window.start(listener: windowListener, expectedImagePath: candidateWindow.path) {
        [.hello(protocolVersion: WireProtocol.version), .setPresentation(presentation: presentation)]
    }
    EnginePipeServer.start(listener: engineListener, service: service, candidateWindowPath: candidateWindow.path, settingsAppPath: settingsApp.path)
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

FileHandle.standardError.write(Data("hajime-engine-host は Windows・Linux・macOS で動きます\n".utf8))
exit(1)
#endif
