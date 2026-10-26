#if os(Windows)
import Dispatch
import Foundation
import S90Application
import S90Domain
import S90Engine
import S90IPC
import S90Persistence

@MainActor
final class EmptyLexicon: EnglishLexicon {
    func isWord(_ text: String) -> Bool { true }
    func suggestions(for text: String) -> [String] { [] }
}

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
    let engine: AzooKeyConverterEngine
    do {
        engine = try AzooKeyConverterEngine(memoryDirectory: HostPaths.local.appendingPathComponent("memory", isDirectory: true),
                                            versionString: "s90.tokyo IME for Windows")
    } catch {
        FileHandle.standardError.write(Data("変換エンジンを用意できません: \(error)\n".utf8))
        return 1
    }
    engine.apply(settings.current)
    let usage = FileUsageStore(fileURL: HostPaths.local.appendingPathComponent("usage.json"), isEnabled: { settings.current.recordsUsage })
    let calendar = SystemCalendar(clock: { Date() })
    let dictionaries = ImportedDictionaryStore(directory: HostPaths.local.appendingPathComponent("dictionaries", isDirectory: true))
    let postalTable = HostPaths.installation.appendingPathComponent("postal-codes.tsv")
    let postalCodes = FileManager.default.fileExists(atPath: postalTable.path) ? PostalCodeFile(url: postalTable) : nil
    let lexicon = EmptyLexicon()
    let window = CandidateWindowLink()
    let settingsApp = HostPaths.installation.appendingPathComponent("s90-settings.exe")

    let service = EngineService(
        makeSession: {
            InputSession(converter: SupplementedConverter(engine.makeSession(), settings: settings, calendar: calendar, postalCodes: postalCodes, dictionaries: dictionaries),
                         lexicon: lexicon, settings: settings, usage: usage)
        },
        settings: settings,
        ui: { window.send($0) },
        openSettings: {
            guard FileManager.default.fileExists(atPath: settingsApp.path) else { return }
            let process = Process()
            process.executableURL = settingsApp
            try? process.run()
        },
        hints: { BranchHints.make(for: $0, settings: $1) }
    )
    settings.observe { [weak engine] in
        engine?.apply($0)
        window.send(.setPresentation(presentation: service.presentation))
    }
    engine.warmUp()

    let presentation = service.presentation
    let candidateWindow = HostPaths.installation.appendingPathComponent("s90-candidate-ui.exe")
    window.start(listener: windowListener, expectedImagePath: candidateWindow.path) {
        [.hello(protocolVersion: WireProtocol.version), .setPresentation(presentation: presentation)]
    }
    EnginePipeServer.start(listener: engineListener, service: service)
    if FileManager.default.fileExists(atPath: candidateWindow.path) {
        let process = Process()
        process.executableURL = candidateWindow
        try? process.run()
    }
    return -1
}

let status = MainActor.assumeIsolated { run() }
if status >= 0 { exit(status) }
dispatchMain()
#else
import Foundation

FileHandle.standardError.write(Data("s90-engine-host は Windows だけで動きます(macOS では core を入力メソッドに直接つなぐ)\n".utf8))
exit(1)
#endif
