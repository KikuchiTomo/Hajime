import Foundation

/// 待つものに時間の上限を付ける．上限を過ぎたら待つのをやめて nil を返す．
///
/// 上限を過ぎたときと，呼んだ側が取り消されたときは，仕事にも取り消しを伝える．取り消しを見て途中でやめる仕事
/// (打ち間違いの訂正)は CPU を使い続けない．ファイルの読み書き(クラウドのフォルダの，まだ手元に無いファイルなど)のように
/// 止められない仕事は終わるまで動き続けるので，呼ぶ側は，前の仕事が終わるまで次を始めないようにする
public enum Deadline {
    public static func run<Value: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> Value) async -> Value? {
        let worker = Worker()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
                let once = Once()
                let work = Task {
                    let value = await operation()
                    if await once.claim() { continuation.resume(returning: value) }
                }
                worker.set(work)
                Task {
                    try? await Task.sleep(for: .seconds(seconds))
                    if await once.claim() {
                        work.cancel()
                        continuation.resume(returning: nil)
                    }
                }
            }
        } onCancel: {
            // 取り消しを仕事に伝える．仕事が途中でやめて返した値はそのまま返る(呼ぶ側は Task.isCancelled を見る)
            worker.cancel()
        }
    }

    /// 取り消しを伝える先の仕事(macOS 14 で動かすので Mutex の代わりに NSLock で守る)
    private final class Worker: @unchecked Sendable {
        private let lock = NSLock()
        private var task: Task<Void, Never>?
        private var cancelled = false

        func set(_ task: Task<Void, Never>) {
            let cancelled = lock.withLock {
                self.task = task
                return self.cancelled
            }
            // 仕事を作る前に取り消されていたら，すぐ伝える
            if cancelled { task.cancel() }
        }

        func cancel() {
            let task = lock.withLock {
                cancelled = true
                return self.task
            }
            task?.cancel()
        }
    }

    /// 先に終わったほうだけが答えを返すための印
    private actor Once {
        private var claimed = false

        func claim() -> Bool {
            guard !claimed else { return false }
            claimed = true
            return true
        }
    }
}
