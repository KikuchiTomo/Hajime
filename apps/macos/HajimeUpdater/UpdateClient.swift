import Foundation
import HajimeDomain
import os

/// 更新できなかった理由．画面には UIStrings.detail で出す
enum UpdateFailure: Error, Equatable {
    case network
    case unreadable
    case noPackage
    case tooLarge
    case digestMismatch
    case signature
    /// このアプリに署名のチームが無く(開発版)，配布物の署名と比べられない
    case unsignedApp
    case installFailed
    case cancelled
}

/// 最新のバージョンの知らせと配布物を取る．送るのは GET の要求だけで，入力の中身や設定は送らない．
/// 取る場所は DefaultSettings の updateManifestURL と updateDownloadBaseURL の下だけ
final class UpdateClient: Sendable {
    private let userAgent: String
    private let logger = Logger(subsystem: UpdaterIdentity.subsystem, category: "update")

    init(version: String) {
        userAgent = "Hajime/\(version) (macOS)"
    }

    /// 最新のバージョンの知らせ(latest.json)．上限より大きければ読むのをやめる
    func manifest() async throws(UpdateFailure) -> UpdateManifest {
        guard let url = URL(string: DefaultSettings.updateManifestURL) else { throw .unreadable }
        let session = URLSession(configuration: configuration(timeout: DefaultSettings.updateManifestTimeout))
        defer { session.finishTasksAndInvalidate() }
        var data = Data()
        do {
            let (bytes, response) = try await session.bytes(for: request(url))
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateFailure.unreadable }
            for try await byte in bytes {
                data.append(byte)
                if data.count > DefaultSettings.maximumUpdateManifestBytes { throw UpdateFailure.tooLarge }
            }
        } catch let failure as UpdateFailure {
            throw failure
        } catch {
            logger.notice("最新のバージョンの知らせを取れませんでした: \(String(describing: error), privacy: .public)")
            throw .network
        }
        do {
            return try UpdateManifest.decode(data)
        } catch {
            throw .unreadable
        }
    }

    /// 配布物を folder に取る．progress には 0〜1 の進み具合を渡す
    func download(_ package: UpdatePackage, to folder: URL, progress: @escaping @Sendable (Double) -> Void,
                  started: @escaping @Sendable (PackageDownload) -> Void) async throws(UpdateFailure) -> URL {
        let destination = folder.appendingPathComponent(package.fileName)
        let download = PackageDownload(destination: destination, maximumBytes: Int64(DefaultSettings.maximumUpdatePackageBytes), progress: progress)
        started(download)
        try await download.run(request(package.url), configuration: configuration(timeout: DefaultSettings.updateDownloadTimeout))
        return destination
    }

    private func configuration(timeout: TimeInterval) -> URLSessionConfiguration {
        // Cookie もキャッシュも残さない
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForResource = timeout
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return configuration
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }
}

/// 配布物の 1 回のダウンロード．大きさが上限を超えたら止める．キャンセルできる
final class PackageDownload: NSObject, URLSessionDownloadDelegate, Sendable {
    private struct State {
        var continuation: CheckedContinuation<Void, any Error>?
        var task: URLSessionDownloadTask?
        var failure: UpdateFailure?
    }

    private let destination: URL
    private let maximumBytes: Int64
    private let progress: @Sendable (Double) -> Void
    private let state = OSAllocatedUnfairLock(initialState: State())

    init(destination: URL, maximumBytes: Int64, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.maximumBytes = maximumBytes
        self.progress = progress
    }

    func run(_ request: URLRequest, configuration: URLSessionConfiguration) async throws(UpdateFailure) {
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let task = session.downloadTask(with: request)
                let cancelled = state.withLock { state in
                    state.continuation = continuation
                    state.task = task
                    return state.failure == .cancelled
                }
                if cancelled { task.cancel() }
                task.resume()
            }
        } catch {
            throw state.withLock { $0.failure } ?? .network
        }
    }

    func cancel() {
        let task = state.withLock { state in
            state.failure = .cancelled
            return state.task
        }
        task?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > maximumBytes || totalBytesExpectedToWrite > maximumBytes {
            fail(.tooLarge, task: downloadTask)
            return
        }
        if totalBytesExpectedToWrite > 0 {
            progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
        }
    }

    /// 一時ファイルはこの中でしか読めないので，ここで置き場所に移す
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
            fail(.noPackage, task: nil)
            return
        }
        do {
            let size = try FileManager.default.attributesOfItem(atPath: location.path)[.size] as? Int64 ?? .max
            guard size <= maximumBytes else {
                fail(.tooLarge, task: nil)
                return
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            fail(.network, task: nil)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, failure) = state.withLock { state in
            defer { state.continuation = nil }
            return (state.continuation, state.failure)
        }
        if let failure {
            continuation?.resume(throwing: failure)
        } else if let error {
            continuation?.resume(throwing: error)
        } else {
            continuation?.resume()
        }
    }

    private func fail(_ failure: UpdateFailure, task: URLSessionTask?) {
        state.withLock { state in
            if state.failure == nil { state.failure = failure }
        }
        task?.cancel()
    }
}
