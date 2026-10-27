#if os(Linux) || os(macOS)
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

/// Unix ドメインソケットで待ち受けるエンジンのサーバー(Linux．macOS では試すときだけ使う)．
/// つないできたのが同じユーザーのプロセスのときだけ話す(Windows の「同じセッション」に当たる．docs/dev/SECURITY-MODEL.md)
public enum EngineSocketServer {
    /// candidateWindowPath は候補ウィンドウの実行ファイル．その接続からだけ手書きの窓で選んだ文字を受ける
    public static func start(listener: UnixSocketListener, service: EngineService, candidateWindowPath: String?) {
        let thread = Thread {
            while true {
                do {
                    let connection = try listener.accept()
                    Thread { serve(connection, service: service, candidateWindowPath: candidateWindowPath) }.start()
                } catch {
                    Thread.sleep(forTimeInterval: 0.1)
                }
            }
        }
        thread.start()
    }

    static func serve(_ connection: UnixSocketConnection, service: EngineService, candidateWindowPath: String?) {
        guard let user = try? connection.peerUserID(), user == getuid() else {
            connection.close()
            return
        }
        let isCandidateWindow = candidateWindowPath.map { expected in
            connection.peerProcessID().flatMap(UnixSocketPeer.executablePath(processID:)) == expected
        } ?? false
        EngineRequestLoop.serve(connection, service: service, isCandidateWindow: isCandidateWindow)
    }
}
extension CandidateWindowLink {
    /// Unix ドメインソケットで候補ウィンドウ(Linux は Fcitx 5 のアドオン)を待ち受ける．同じユーザーのプロセスだけを相手にする．
    /// アドオンは Fcitx 5 のプロセスの中で動くので，Windows のように実行ファイルでは確かめられない
    public func start(listener: UnixSocketListener, greeting: @escaping @Sendable () -> [WireUiCommand]) {
        let thread = Thread { [self] in
            while true {
                guard let connection = try? listener.accept() else {
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }
                guard let user = try? connection.peerUserID(), user == getuid() else {
                    connection.close()
                    continue
                }
                attach(connection, greeting: greeting())
            }
        }
        thread.start()
    }
}
#endif
