#if os(Linux) || os(macOS)
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Foundation

/// Unix ドメインソケットの失敗．operation は何をしていたか，code は errno
public struct UnixSocketError: Error, Equatable, CustomStringConvertible {
    public enum Operation: String, Sendable {
        case directory, path, create, bind, listen, accept, connect, read, write, peer
    }

    public let operation: Operation
    public let code: Int32

    public init(_ operation: Operation, code: Int32 = errno) {
        self.operation = operation
        self.code = code
    }

    /// 同じ場所でほかのエンジンが動いている
    public var isAlreadyRunning: Bool { operation == .bind && code == EADDRINUSE }

    public var description: String { "\(operation.rawValue) に失敗しました(errno \(code))" }
}

/// ソケットの置き場所(docs/dev/adr/0012-linux.md)．$XDG_RUNTIME_DIR/s90.tokyo/ に置く．
/// $XDG_RUNTIME_DIR が無いとき(macOS で試すとき)は一時フォルダの s90.tokyo-<ユーザー ID>/ に置く．
/// フォルダは本人だけが読み書きできるようにし，ほかのユーザーのフォルダなら使わない
public enum UnixSocketPath {
    public static func engine() throws(UnixSocketError) -> String { try path(role: "engine") }
    public static func candidateWindow() throws(UnixSocketError) -> String { try path(role: "candidate-window") }

    static func path(role: String) throws(UnixSocketError) -> String {
        let directory = try preparedDirectory()
        return directory + "/" + role + ".sock"
    }

    static func preparedDirectory() throws(UnixSocketError) -> String {
        let environment = ProcessInfo.processInfo.environment
        let directory: String
        if let runtime = environment["XDG_RUNTIME_DIR"], runtime.hasPrefix("/") {
            directory = runtime + "/s90.tokyo"
        } else {
            directory = NSTemporaryDirectory().trimmingSuffix("/") + "/s90.tokyo-\(getuid())"
        }
        if mkdir(directory, 0o700) != 0, errno != EEXIST { throw UnixSocketError(.directory) }
        var status = stat()
        guard lstat(directory, &status) == 0 else { throw UnixSocketError(.directory) }
        // 本人のフォルダで，ほかの人が読み書きできないこと(先に作られたフォルダやリンクを使わない)
        guard status.st_mode & S_IFMT == S_IFDIR, status.st_uid == getuid(), status.st_mode & 0o077 == 0 else {
            throw UnixSocketError(.directory, code: EACCES)
        }
        return directory
    }
}

/// つながった 1 本．読み書きは接続のスレッドで行う
public final class UnixSocketConnection: EngineByteStream, @unchecked Sendable {
    private var descriptor: Int32
    private let lock = NSLock()

    init(descriptor: Int32) {
        self.descriptor = descriptor
        #if canImport(Darwin)
        // 相手が閉じたあとに書いてもプロセスを止めない(Linux は送るときの MSG_NOSIGNAL で同じことをする)
        var on: Int32 = 1
        setsockopt(descriptor, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        #endif
    }

    deinit {
        close()
    }

    private var current: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return descriptor
    }

    public func read(maximumBytes: Int = 64 * 1024) throws(UnixSocketError) -> [UInt8] {
        let descriptor = current
        guard descriptor >= 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: maximumBytes)
        while true {
            let count = buffer.withUnsafeMutableBytes { recv(descriptor, $0.baseAddress, $0.count, 0) }
            if count >= 0 { return Array(buffer.prefix(count)) }
            if errno == EINTR { continue }
            if errno == ECONNRESET || errno == EBADF { return [] }
            throw UnixSocketError(.read)
        }
    }

    public func write(_ bytes: [UInt8]) throws(UnixSocketError) {
        let descriptor = current
        guard descriptor >= 0 else { throw UnixSocketError(.write, code: EBADF) }
        #if canImport(Glibc)
        let flags = Int32(MSG_NOSIGNAL)
        #else
        let flags: Int32 = 0
        #endif
        var offset = 0
        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes { send(descriptor, $0.baseAddress?.advanced(by: offset), bytes.count - offset, flags) }
            if sent < 0 {
                if errno == EINTR { continue }
                throw UnixSocketError(.write)
            }
            offset += sent
        }
    }

    /// 相手のユーザー ID
    public func peerUserID() throws(UnixSocketError) -> uid_t {
        let descriptor = current
        #if canImport(Glibc)
        var credentials = ucred()
        var length = socklen_t(MemoryLayout<ucred>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_PEERCRED, &credentials, &length) == 0 else { throw UnixSocketError(.peer) }
        return credentials.uid
        #else
        var user: uid_t = 0
        var group: gid_t = 0
        guard getpeereid(descriptor, &user, &group) == 0 else { throw UnixSocketError(.peer) }
        return user
        #endif
    }

    /// 相手のプロセスの ID．分からなければ nil
    public func peerProcessID() -> pid_t? {
        let descriptor = current
        #if canImport(Glibc)
        var credentials = ucred()
        var length = socklen_t(MemoryLayout<ucred>.size)
        guard getsockopt(descriptor, SOL_SOCKET, SO_PEERCRED, &credentials, &length) == 0 else { return nil }
        return credentials.pid
        #else
        var process: pid_t = 0
        var length = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(descriptor, SOL_LOCAL, LOCAL_PEERPID, &process, &length) == 0 else { return nil }
        return process
        #endif
    }

    public func close() {
        lock.lock()
        let closing = descriptor
        descriptor = -1
        lock.unlock()
        guard closing >= 0 else { return }
        shutdown(closing, Int32(SHUT_RDWR))
        _ = systemClose(closing)
    }

    public func readBytes() throws -> [UInt8] { try read() }
    public func writeBytes(_ bytes: [UInt8]) throws { try write(bytes) }

    /// 待ち受けているソケットにつなぐ(枠組みの口・候補ウィンドウ・テストが使う)
    public static func connect(path: String) throws(UnixSocketError) -> UnixSocketConnection {
        let descriptor = try makeSocket()
        var address = try socketAddress(path)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { systemConnect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard result == 0 else {
            let error = UnixSocketError(.connect)
            _ = systemClose(descriptor)
            throw error
        }
        return UnixSocketConnection(descriptor: descriptor)
    }
}

/// 決まった場所で待ち受ける．前のエンジンが残したソケットのファイルは，つなげなければ消して作り直す
public final class UnixSocketListener: @unchecked Sendable {
    public let path: String
    private let descriptor: Int32

    public init(path: String) throws(UnixSocketError) {
        self.path = path
        if (try? UnixSocketConnection.connect(path: path)) != nil {
            // ほかのエンジンが待ち受けている
            throw UnixSocketError(.bind, code: EADDRINUSE)
        }
        unlink(path)
        let descriptor = try makeSocket()
        var address = try socketAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else {
            let error = UnixSocketError(.bind)
            _ = systemClose(descriptor)
            throw error
        }
        // フォルダが本人だけのものなので，ファイルも本人だけにする
        chmod(path, 0o600)
        guard listen(descriptor, SOMAXCONN) == 0 else {
            let error = UnixSocketError(.listen)
            _ = systemClose(descriptor)
            throw error
        }
        self.descriptor = descriptor
    }

    deinit {
        _ = systemClose(descriptor)
        unlink(path)
    }

    /// 次の接続を待つ．同じユーザーのプロセスかは呼んだ側が peerUserID で確かめる
    public func accept() throws(UnixSocketError) -> UnixSocketConnection {
        while true {
            let client = systemAccept(descriptor, nil, nil)
            if client >= 0 { return UnixSocketConnection(descriptor: client) }
            if errno == EINTR { continue }
            throw UnixSocketError(.accept)
        }
    }
}

public enum UnixSocketPeer {
    /// 相手のプロセスの実行ファイルの場所(Linux の /proc/<ID>/exe)．分からなければ nil
    public static func executablePath(processID: pid_t) -> String? {
        #if os(Linux)
        try? FileManager.default.destinationOfSymbolicLink(atPath: "/proc/\(processID)/exe")
        #else
        nil
        #endif
    }
}

private func makeSocket() throws(UnixSocketError) -> Int32 {
    #if canImport(Glibc)
    let descriptor = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
    #else
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    if descriptor >= 0 { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
    #endif
    guard descriptor >= 0 else { throw UnixSocketError(.create) }
    return descriptor
}

private func socketAddress(_ path: String) throws(UnixSocketError) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    // 終わりの 0 を入れる分を残す
    guard !bytes.isEmpty, bytes.count < capacity else { throw UnixSocketError(.path, code: ENAMETOOLONG) }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
        raw.copyBytes(from: bytes)
        raw[bytes.count] = 0
    }
    return address
}

// 同じ名前のメソッド(close・connect・accept)と取り違えないよう，システムの関数に別の名前を付ける
private func systemClose(_ descriptor: Int32) -> Int32 {
    #if canImport(Glibc)
    Glibc.close(descriptor)
    #else
    Darwin.close(descriptor)
    #endif
}

private func systemConnect(_ descriptor: Int32, _ address: UnsafePointer<sockaddr>, _ length: socklen_t) -> Int32 {
    #if canImport(Glibc)
    Glibc.connect(descriptor, address, length)
    #else
    Darwin.connect(descriptor, address, length)
    #endif
}

private func systemAccept(_ descriptor: Int32, _ address: UnsafeMutablePointer<sockaddr>?, _ length: UnsafeMutablePointer<socklen_t>?) -> Int32 {
    #if canImport(Glibc)
    Glibc.accept(descriptor, address, length)
    #else
    Darwin.accept(descriptor, address, length)
    #endif
}

private extension String {
    func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
#endif
