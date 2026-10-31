#if os(Windows)
import Foundation
import HajimeDomain
import WinSDK

/// 読みで呼び出すコマンド(LauncherCommand)を Windows で動かす(R-22．macOS の CommandLauncher と同じ役)．
///
/// エンジンのプロセス(hajime-engine-host)で動かす．入力先のアプリに読み込まれた DLL では動かさない(EngineService)．
/// ShellExecuteW に行き先だけを渡し，引数は渡さない(打った文字や候補を差し込まない)．cmd.exe などのシェルは通さない
public enum WindowsCommandLauncher {
    public static func run(_ command: LauncherCommand) {
        guard command.isValid else { return }
        switch command.kind {
        case .openApplication:
            // 実行ファイル(.exe)だけを開く．バッチファイルやショートカットを「アプリ」として動かさない
            guard command.target.lowercased().hasSuffix(".exe"), FileManager.default.fileExists(atPath: command.target) else { return }
            open(command.target)
        case .openFile:
            guard FileManager.default.fileExists(atPath: command.target) else { return }
            open(command.target)
        case .openURL:
            open(command.target)
        case .runShortcut:
            // ショートカット App は macOS だけ
            break
        }
    }

    private static func open(_ target: String) {
        _ = "open".withCString(encodedAs: UTF16.self) { verb in
            target.withCString(encodedAs: UTF16.self) { file in
                ShellExecuteW(nil, verb, file, nil, nil, INT(SW_SHOWNORMAL))
            }
        }
    }
}
#endif
