import Dispatch
import Foundation
import HajimeDomain

/// エンジンのプロセスがつないできた相手と話すための，送り方(Windows の名前付きパイプ・Unix ドメインソケット)の口
public protocol EngineByteStream: AnyObject, Sendable {
    /// 届いたバイト．相手が閉じたら空
    func readBytes() throws -> [UInt8]
    func writeBytes(_ bytes: [UInt8]) throws
    func close()
}

/// 1 つの接続で，要求を読んでサービスに渡し，応答を書き返す．送り方によらない部分(Windows と Linux で共通)．
/// 接続ごとのスレッドで呼ぶ．サービスはメインアクターで動かす
public enum EngineRequestLoop {
    public static func serve(_ stream: some EngineByteStream, service: EngineService, isCandidateWindow: Bool, isSettingsApp: Bool = false) {
        let id = onMain { service.connect(isCandidateWindow: isCandidateWindow, isSettingsApp: isSettingsApp) }
        defer {
            onMain { service.disconnect(id) }
            stream.close()
        }
        var reader = MessageFraming.Reader()
        do {
            while true {
                let bytes = try stream.readBytes()
                guard !bytes.isEmpty else { return }
                reader.append(bytes)
                while let body = try reader.nextBody() {
                    let request = try MessageFraming.decode(WireRequest.self, from: body)
                    let response: WireResponse
                    switch onMain({ service.reply(to: request, from: id) }) {
                    case .now(let immediate):
                        response = immediate
                    case .later(let work):
                        // ファイルの読み書きを終えるまで，この接続のスレッドで待つ(メインスレッドは止めない)．
                        // 同期のフォルダが応えないときも待ち続けないよう，設定の画面が待つ時間で打ち切る
                        response = wait(for: work, id: request.id)
                    }
                    try stream.writeBytes(MessageFraming.encode(response))
                }
            }
        } catch {
            return
        }
    }

    /// メインアクターで動かす非同期の仕事を，呼んだスレッド(接続のスレッド)で終わるまで待つ
    private static func wait(for work: @escaping @MainActor @Sendable () async -> WireResponse, id: UInt32) -> WireResponse {
        let result = ResultBox()
        let done = DispatchSemaphore(value: 0)
        Task { @MainActor in
            let response = await work()
            result.set(response)
            done.signal()
        }
        guard done.wait(timeout: .now() + DefaultSettings.settingsAppFileTimeout) == .success else {
            // 仕事は続けさせ(終われば結果は捨てる)，頼んだ側には今は手が離せないと答える
            return WireResponse(id: id, body: .fileFailed(reason: .busy))
        }
        // signal の前に必ず入れているので nil にはならない．念のため malformed で答える
        return result.get() ?? WireResponse(id: id, body: .error(code: .malformed))
    }

    static func onMain<Value: Sendable>(_ body: @MainActor () -> Value) -> Value {
        DispatchQueue.main.sync { MainActor.assumeIsolated(body) }
    }

    /// スレッドをまたいで応答を受け渡す入れ物(macOS 14 でも使えるよう NSLock で守る)
    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: WireResponse?

        func set(_ response: WireResponse) {
            lock.lock()
            value = response
            lock.unlock()
        }

        func get() -> WireResponse? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
    }
}
