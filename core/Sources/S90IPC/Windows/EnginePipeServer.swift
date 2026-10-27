#if os(Windows)
import Dispatch
import Foundation
import S90Domain

public enum EnginePipeServer {
    /// candidateWindowPath は候補ウィンドウの実行ファイル．その接続からだけ手書きの窓で選んだ文字を受ける
    public static func start(listener: NamedPipeListener, service: EngineService, candidateWindowPath: String) {
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

    static func serve(_ connection: NamedPipeConnection, service: EngineService, candidateWindowPath: String) {
        guard let process = try? connection.clientProcessID(), NamedPipePeer.isInCurrentSession(processID: process) else {
            connection.close()
            return
        }
        let isCandidateWindow = NamedPipePeer.imagePath(processID: process)
            .map { NamedPipePeer.isSameImage($0, as: candidateWindowPath) } ?? false
        EngineRequestLoop.serve(connection, service: service, isCandidateWindow: isCandidateWindow)
    }
}

extension NamedPipeConnection: EngineByteStream {
    public func readBytes() throws -> [UInt8] { try read() }
    public func writeBytes(_ bytes: [UInt8]) throws { try write(bytes) }
}

extension CandidateWindowLink {
    /// 名前付きパイプで候補ウィンドウを待ち受ける．同じセッションの，決まった実行ファイルのプロセスだけを相手にする
    public func start(listener: NamedPipeListener, expectedImagePath: String, greeting: @escaping @Sendable () -> [WireUiCommand]) {
        let thread = Thread { [self] in
            while true {
                guard let connection = try? listener.accept() else {
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }
                guard let process = try? connection.clientProcessID(), NamedPipePeer.isInCurrentSession(processID: process),
                      let path = NamedPipePeer.imagePath(processID: process),
                      NamedPipePeer.isSameImage(path, as: expectedImagePath) else {
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
