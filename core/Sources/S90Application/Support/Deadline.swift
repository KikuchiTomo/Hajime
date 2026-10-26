/// 待つものに時間の上限を付ける．上限を過ぎたら待つのをやめて nil を返す．
///
/// ファイルの読み書き(クラウドのフォルダの，まだ手元に無いファイルなど)は止められないので，
/// 仕事そのものは終わるまで動き続ける．呼ぶ側は，前の仕事が終わるまで次を始めないようにする
public enum Deadline {
    public static func run<Value: Sendable>(seconds: Double, _ operation: @escaping @Sendable () async -> Value) async -> Value? {
        await withCheckedContinuation { (continuation: CheckedContinuation<Value?, Never>) in
            let once = Once()
            Task {
                let value = await operation()
                if await once.claim() { continuation.resume(returning: value) }
            }
            Task {
                try? await Task.sleep(for: .seconds(seconds))
                if await once.claim() { continuation.resume(returning: nil) }
            }
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
