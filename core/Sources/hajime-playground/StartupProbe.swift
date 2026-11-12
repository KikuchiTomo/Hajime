import Foundation
import HajimeDomain
import HajimeEngine

/// 起動から最初の変換ができるまでの時間を，アプリの組み立て(macOS の CompositionRoot・hajime-engine-host)と同じ順で測る．
/// Zenzai のモデルと同梱の辞書を確かめ，エンジンを作り，warmUp してから最初の変換をする．
/// アプリを入れずに，確かめる処理を変えたときの前後を比べるため(CPU 時間は /usr/bin/time などで外から測る)
@MainActor
enum StartupProbe {
    static func run(zenzaiPath: String?, fastZenzaiPath: String?, dictionaryPath: String) throws {
        let clock = ContinuousClock()
        let start = clock.now
        let resources = StartupResources.verified(
            zenzai: zenzaiPath.map { URL(fileURLWithPath: $0) },
            fastZenzai: fastZenzaiPath.map { URL(fileURLWithPath: $0) },
            dictionary: URL(fileURLWithPath: dictionaryPath, isDirectory: true))
        let verified = clock.now
        guard let dictionary = try? resources.dictionary?.get() else {
            print("同梱の辞書を確かめられませんでした")
            exit(1)
        }
        let memory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-startup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: memory) }
        let engine = try AzooKeyConverterEngine(memoryDirectory: memory, versionString: "hajime-playground", zenzai: try? resources.zenzai?.get(),
                                                fastZenzai: try? resources.fastZenzai?.get(), dictionaryDirectory: dictionary.url)
        let created = clock.now
        engine.warmUp()
        let warmed = clock.now
        let session = engine.makeSession()
        _ = session.candidates(for: "とうきょうとちじにきく")
        session.endComposition()
        let converted = clock.now
        print("確認 \(verified - start)  エンジン \(created - verified)  warmUp \(warmed - created)  最初の変換 \(converted - warmed)  合計 \(converted - start)")
    }
}
