import Foundation

/// 互いに関係しない仕事を CPU のコアの数だけ並べて進め，すべて終わるのを待って，渡した順に結果を返す．
///
/// 起動の途中で一度だけ待つ確認(同梱の辞書のファイルごとのハッシュ，Zenzai モデル)に使う．
/// 呼ぶ側(composition root)を同期のまま保つため，async にせず DispatchQueue.concurrentPerform で並べる．
/// 渡す仕事は @Sendable にし，ほかの状態を書き換えない(結果は戻り値で返す)
enum ConcurrentWork {
    static func map<Element: Sendable, Output: Sendable>(_ elements: [Element], _ transform: @Sendable (Element) -> Output) -> [Output] {
        let results = Results<Output>(count: elements.count)
        DispatchQueue.concurrentPerform(iterations: elements.count) { index in
            results.store(transform(elements[index]), at: index)
        }
        return results.values()
    }

    /// 並べた仕事の結果を受け取る入れ物．macOS 14 で動かすので Mutex の代わりに NSLock で守る(Deadline.Worker と同じ)
    private final class Results<Output: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [Output?]

        init(count: Int) {
            storage = Array(repeating: nil, count: count)
        }

        func store(_ value: Output, at index: Int) {
            lock.lock()
            defer { lock.unlock() }
            storage[index] = value
        }

        /// すべての仕事が終わったあとに呼ぶ．concurrentPerform はすべて終わるまで戻らないので，どの場所にも値が入っている
        func values() -> [Output] {
            lock.lock()
            defer { lock.unlock() }
            return storage.map { value in
                guard let value else { preconditionFailure("並べた仕事の結果が欠けている(concurrentPerform の前提が崩れた)") }
                return value
            }
        }
    }
}
