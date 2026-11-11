import Foundation

/// OS のコマンド(spctl・osascript)を動かし，終わるのを待つ．時間の上限を過ぎたら止める
@MainActor
enum ProcessRunner {
    struct Outcome: Sendable {
        var status: Int32
        /// 標準出力と標準エラーを合わせたもの
        var output: String
        var timedOut: Bool
    }

    /// 起動できなければ nil
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) async -> Outcome? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        let waiter = Waiter()
        return await withCheckedContinuation { continuation in
            waiter.continuation = continuation
            process.terminationHandler = { finished in
                let status = finished.terminationStatus
                // 出力は小さい(数百バイト)ので，終わってからまとめて読む
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                Task { @MainActor in
                    waiter.resume(Outcome(status: status, output: String(decoding: data, as: UTF8.self), timedOut: waiter.timedOut))
                }
            }
            do {
                try process.run()
            } catch {
                waiter.resume(nil)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                MainActor.assumeIsolated {
                    guard process.isRunning else { return }
                    waiter.timedOut = true
                    process.terminate()
                }
            }
        }
    }

    /// 待っている呼び出しに 1 回だけ結果を返す
    @MainActor
    private final class Waiter {
        var continuation: CheckedContinuation<Outcome?, Never>?
        var timedOut = false

        func resume(_ outcome: Outcome?) {
            continuation?.resume(returning: outcome)
            continuation = nil
        }
    }
}
