#if os(Windows)
import Dispatch
import Foundation

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
            .map { $0.caseInsensitiveCompare(candidateWindowPath) == .orderedSame } ?? false
        let id = onMain { service.connect(isCandidateWindow: isCandidateWindow) }
        defer {
            onMain { service.disconnect(id) }
            connection.close()
        }
        var reader = MessageFraming.Reader()
        do {
            while true {
                let bytes = try connection.read()
                guard !bytes.isEmpty else { return }
                reader.append(bytes)
                while let body = try reader.nextBody() {
                    let request = try MessageFraming.decode(WireRequest.self, from: body)
                    let response = onMain { service.handle(request, from: id) }
                    try connection.write(MessageFraming.encode(response))
                }
            }
        } catch {
            return
        }
    }

    private static func onMain<Value: Sendable>(_ body: @MainActor () -> Value) -> Value {
        DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }
}

public final class CandidateWindowLink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "tokyo.s90.ime.candidate-window")
    private let lock = NSLock()
    private var connection: NamedPipeConnection?
    private var pending = 0
    private static let maximumPending = 256

    public init() {}

    public func start(listener: NamedPipeListener, expectedImagePath: String, greeting: @escaping @Sendable () -> [WireUiCommand]) {
        let thread = Thread { [self] in
            while true {
                guard let connection = try? listener.accept() else {
                    Thread.sleep(forTimeInterval: 0.1)
                    continue
                }
                guard let process = try? connection.clientProcessID(), NamedPipePeer.isInCurrentSession(processID: process),
                      let path = NamedPipePeer.imagePath(processID: process),
                      path.caseInsensitiveCompare(expectedImagePath) == .orderedSame else {
                    connection.close()
                    continue
                }
                lock.lock()
                let previous = self.connection
                self.connection = connection
                lock.unlock()
                previous?.close()
                // 読み続けるスレッドは置かない．同期の I/O のハンドルでは，読みが止まっているあいだ同じハンドルへの
                // 書き込みも待たされるため．候補ウィンドウはこのパイプに書かず，切れたことは書き込みの失敗で知る
                greeting().forEach(send)
            }
        }
        thread.start()
    }

    private func drop(_ closed: NamedPipeConnection) {
        lock.lock()
        if connection === closed { connection = nil }
        lock.unlock()
        closed.close()
    }

    public func send(_ command: WireUiCommand) {
        lock.lock()
        guard let connection, pending < Self.maximumPending else {
            lock.unlock()
            return
        }
        pending += 1
        lock.unlock()
        queue.async { [self] in
            defer {
                lock.lock()
                pending -= 1
                lock.unlock()
            }
            guard let frame = try? MessageFraming.encode(command) else { return }
            do {
                try connection.write(frame)
            } catch {
                drop(connection)
            }
        }
    }
}
#endif
