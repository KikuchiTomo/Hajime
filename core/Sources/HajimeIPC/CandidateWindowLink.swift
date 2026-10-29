import Dispatch
import Foundation
import HajimeDomain

/// 候補ウィンドウ(Windows は別のプロセスの窓，Linux は Fcitx 5 のアドオン)への指示を送る口．送り方によらない部分．
/// つないできた相手を確かめて attach するのは，送り方ごとの待ち受け(EnginePipeServer・EngineSocketServer)の役．
/// 相手は 1 つだけ．新しい相手がつながれば前の相手は閉じる
public final class CandidateWindowLink: @unchecked Sendable {
    private let queue = DispatchQueue(label: "men.haji.inputmethod.candidate-window")
    private let lock = NSLock()
    private var connection: (any EngineByteStream)?
    private var pending = 0
    /// 送り終えていない指示の上限．相手が読まずに溜まったら，それより後の指示は捨てる(入力を止めない)
    private static let maximumPending = 256

    public init() {}

    /// 確かめ終えた相手を，指示を送る先にする．greeting(挨拶と今の見た目)を先に送る
    public func attach(_ connection: any EngineByteStream, greeting: [WireUiCommand]) {
        lock.lock()
        let previous = self.connection
        self.connection = connection
        lock.unlock()
        previous?.close()
        // 読み続けるスレッドは置かない．同期の I/O のハンドルでは，読みが止まっているあいだ同じハンドルへの
        // 書き込みも待たされるため．候補ウィンドウはこの接続に書かず，切れたことは書き込みの失敗で知る
        greeting.forEach(send)
    }

    private func drop(_ closed: any EngineByteStream) {
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
                try connection.writeBytes(frame)
            } catch {
                drop(connection)
            }
        }
    }
}
