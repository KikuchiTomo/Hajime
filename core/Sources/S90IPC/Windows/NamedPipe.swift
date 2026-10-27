#if os(Windows)
import Foundation
import WinSDK

public struct NamedPipeError: Error, Equatable, CustomStringConvertible {
    public enum Operation: String, Sendable {
        case currentUser, securityDescriptor, create, connect, read, write, clientProcess, open
    }

    public var operation: Operation
    public var code: UInt32

    init(_ operation: Operation, code: UInt32 = GetLastError()) {
        self.operation = operation
        self.code = code
    }

    public var description: String { "NamedPipeError(\(operation.rawValue), \(code))" }

    public var isAlreadyRunning: Bool { operation == .create && (code == DWORD(ERROR_ACCESS_DENIED) || code == DWORD(ERROR_PIPE_BUSY)) }
    public var isClosed: Bool { code == DWORD(ERROR_BROKEN_PIPE) || code == DWORD(ERROR_PIPE_NOT_CONNECTED) || code == DWORD(ERROR_NO_DATA) }
}

public enum NamedPipeName {
    public static func engine() throws(NamedPipeError) -> String {
        try name(role: "engine")
    }

    public static func candidateWindow() throws(NamedPipeError) -> String {
        try name(role: "ui")
    }

    static func name(role: String) throws(NamedPipeError) -> String {
        #"\\.\pipe\s90.tokyo-ime.\#(try WindowsAccount.currentUserSID()).\#(WindowsAccount.currentSessionID()).\#(role)"#
    }
}

enum WindowsAccount {
    static func currentSessionID() -> UInt32 {
        var session: DWORD = 0
        guard ProcessIdToSessionId(GetCurrentProcessId(), &session) else { return 0 }
        return session
    }

    static func currentUserSID() throws(NamedPipeError) -> String {
        var token: HANDLE?
        guard OpenProcessToken(GetCurrentProcess(), DWORD(TOKEN_QUERY), &token), let token else { throw NamedPipeError(.currentUser) }
        defer { CloseHandle(token) }
        var needed: DWORD = 0
        _ = GetTokenInformation(token, TokenUser, nil, 0, &needed)
        guard needed > 0 else { throw NamedPipeError(.currentUser) }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(needed), alignment: MemoryLayout<TOKEN_USER>.alignment)
        defer { buffer.deallocate() }
        guard GetTokenInformation(token, TokenUser, buffer, needed, &needed) else { throw NamedPipeError(.currentUser) }
        let user = buffer.assumingMemoryBound(to: TOKEN_USER.self).pointee
        var text: LPWSTR?
        guard ConvertSidToStringSidW(user.User.Sid, &text), let text else { throw NamedPipeError(.currentUser) }
        defer { LocalFree(text) }
        return String(decodingCString: text, as: UTF16.self)
    }
}

public final class NamedPipeConnection: @unchecked Sendable {
    private var handle: HANDLE?
    private let isServer: Bool
    private let lock = NSLock()

    init(handle: HANDLE, isServer: Bool) {
        self.handle = handle
        self.isServer = isServer
    }

    deinit {
        close()
    }

    public func read(maximumBytes: Int = 64 * 1024) throws(NamedPipeError) -> [UInt8] {
        guard let handle = lock.locked({ self.handle }) else { return [] }
        var buffer = [UInt8](repeating: 0, count: maximumBytes)
        var count: DWORD = 0
        let succeeded = buffer.withUnsafeMutableBytes { ReadFile(handle, $0.baseAddress, DWORD($0.count), &count, nil) }
        guard succeeded else {
            let error = NamedPipeError(.read)
            if error.isClosed { return [] }
            throw error
        }
        return Array(buffer.prefix(Int(count)))
    }

    public func write(_ bytes: [UInt8]) throws(NamedPipeError) {
        guard let handle = lock.locked({ self.handle }) else { throw NamedPipeError(.write, code: DWORD(ERROR_PIPE_NOT_CONNECTED)) }
        var offset = 0
        while offset < bytes.count {
            var written: DWORD = 0
            let succeeded = bytes.withUnsafeBytes { raw in
                WriteFile(handle, raw.baseAddress?.advanced(by: offset), DWORD(bytes.count - offset), &written, nil)
            }
            guard succeeded else { throw NamedPipeError(.write) }
            offset += Int(written)
        }
    }

    public func clientProcessID() throws(NamedPipeError) -> UInt32 {
        guard let handle = lock.locked({ self.handle }) else { throw NamedPipeError(.clientProcess, code: DWORD(ERROR_PIPE_NOT_CONNECTED)) }
        var process: ULONG = 0
        guard GetNamedPipeClientProcessId(handle, &process) else { throw NamedPipeError(.clientProcess) }
        return process
    }

    public func close() {
        let closing: HANDLE? = lock.locked {
            let current = self.handle
            self.handle = nil
            return current
        }
        guard let closing else { return }
        if isServer { DisconnectNamedPipe(closing) }
        CloseHandle(closing)
    }
}

public final class NamedPipeListener: @unchecked Sendable {
    public let name: String
    private let securityDescriptor: PSECURITY_DESCRIPTOR
    private var pending: HANDLE?

    public init(name: String) throws(NamedPipeError) {
        self.name = name
        let sid = try WindowsAccount.currentUserSID()
        let sddl = "D:P(A;;GA;;;\(sid))(A;;GRGW;;;AC)S:(ML;;NW;;;LW)"
        var descriptor: PSECURITY_DESCRIPTOR?
        let converted = sddl.withCString(encodedAs: UTF16.self) {
            ConvertStringSecurityDescriptorToSecurityDescriptorW($0, DWORD(SDDL_REVISION_1), &descriptor, nil)
        }
        guard converted, let descriptor else { throw NamedPipeError(.securityDescriptor) }
        self.securityDescriptor = descriptor
        pending = try makeInstance(first: true)
    }

    deinit {
        if let pending { CloseHandle(pending) }
        LocalFree(securityDescriptor)
    }

    private func makeInstance(first: Bool) throws(NamedPipeError) -> HANDLE {
        var attributes = SECURITY_ATTRIBUTES(nLength: DWORD(MemoryLayout<SECURITY_ATTRIBUTES>.size), lpSecurityDescriptor: securityDescriptor, bInheritHandle: false)
        let openMode = DWORD(PIPE_ACCESS_DUPLEX) | (first ? DWORD(FILE_FLAG_FIRST_PIPE_INSTANCE) : 0)
        let pipeMode = DWORD(PIPE_TYPE_BYTE) | DWORD(PIPE_READMODE_BYTE) | DWORD(PIPE_WAIT) | DWORD(PIPE_REJECT_REMOTE_CLIENTS)
        let bufferSize = DWORD(64 * 1024)
        let handle = name.withCString(encodedAs: UTF16.self) {
            CreateNamedPipeW($0, openMode, pipeMode, DWORD(PIPE_UNLIMITED_INSTANCES), bufferSize, bufferSize, 0, &attributes)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw NamedPipeError(.create) }
        return handle
    }

    public func accept() throws(NamedPipeError) -> NamedPipeConnection {
        let handle: HANDLE
        if let pending {
            handle = pending
            self.pending = nil
        } else {
            handle = try makeInstance(first: false)
        }
        if !ConnectNamedPipe(handle, nil) {
            let error = NamedPipeError(.connect)
            guard error.code == DWORD(ERROR_PIPE_CONNECTED) else {
                CloseHandle(handle)
                throw error
            }
        }
        return NamedPipeConnection(handle: handle, isServer: true)
    }
}

public enum NamedPipeClient {
    private static let securityQualityOfService: DWORD = 0x0010_0000 | 0x0001_0000

    public static func connect(name: String, timeoutMilliseconds: UInt32 = 1000) throws(NamedPipeError) -> NamedPipeConnection {
        let handle = name.withCString(encodedAs: UTF16.self) { wide -> HANDLE? in
            _ = WaitNamedPipeW(wide, timeoutMilliseconds)
            return CreateFileW(wide, DWORD(GENERIC_READ) | DWORD(GENERIC_WRITE), 0, nil, DWORD(OPEN_EXISTING), securityQualityOfService, nil)
        }
        guard let handle, handle != INVALID_HANDLE_VALUE else { throw NamedPipeError(.open) }
        return NamedPipeConnection(handle: handle, isServer: false)
    }
}

public enum NamedPipePeer {
    public static func isInCurrentSession(processID: UInt32) -> Bool {
        var session: DWORD = 0
        guard ProcessIdToSessionId(processID, &session) else { return false }
        return session == WindowsAccount.currentSessionID()
    }

    public static func imagePath(processID: UInt32) -> String? {
        guard let process = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, processID) else { return nil }
        defer { CloseHandle(process) }
        var buffer = [WCHAR](repeating: 0, count: Int(MAX_PATH) * 4)
        var size = DWORD(buffer.count)
        guard QueryFullProcessImageNameW(process, 0, &buffer, &size) else { return nil }
        return String(decoding: buffer.prefix(Int(size)), as: UTF16.self)
    }

    /// 実行ファイルの場所が同じか．imagePath は \ で区切るが，URL.path は Windows でも / で区切り，
    /// 先頭に / が付くこともあるので，形をそろえてから大文字と小文字を区別せずに比べる
    public static func isSameImage(_ path: String, as expected: String) -> Bool {
        normalizedImagePath(path).caseInsensitiveCompare(normalizedImagePath(expected)) == .orderedSame
    }

    static func normalizedImagePath(_ path: String) -> String {
        var normalized = path.replacingOccurrences(of: "/", with: "\\")
        // "\C:\..." の先頭の区切りを外す(UNC の "\\server\..." はそのまま)
        if normalized.hasPrefix("\\"), normalized.dropFirst(2).first == ":" {
            normalized.removeFirst()
        }
        return normalized
    }
}

extension NSLock {
    fileprivate func locked<Value>(_ body: () -> Value) -> Value {
        lock()
        defer { unlock() }
        return body()
    }
}
#endif
