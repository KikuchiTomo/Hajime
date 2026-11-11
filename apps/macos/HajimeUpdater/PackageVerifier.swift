import CryptoKit
import Foundation
import HajimeDomain
import os
import Security

/// 取った配布物が，latest.json の SHA-256 と一致し，このアプリと同じチームの Developer ID で署名され，
/// Apple の公証を通ったものかを確かめる．どれか 1 つでも確かめられなければ入れない
@MainActor
struct PackageVerifier {
    private let logger = Logger(subsystem: UpdaterIdentity.subsystem, category: "update")

    /// このアプリの署名のチーム．アドホック署名(開発版)なら nil
    func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any] else { return nil }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    func verify(_ file: URL, sha256: String, team: String) async throws(UpdateFailure) {
        guard try await Self.digest(of: file) == sha256 else { throw .digestMismatch }
        // spctl はインストーラーとしての Gatekeeper の判定を出す．公証を通った Developer ID の配布物だけが accepted になる
        guard let outcome = await ProcessRunner.run("/usr/sbin/spctl", ["--assess", "--type", "install", "-vv", file.path],
                                                    timeout: DefaultSettings.updateVerificationTimeout) else { throw .signature }
        guard outcome.status == 0, !outcome.timedOut, Self.isTrusted(spctlOutput: outcome.output, team: team) else {
            logger.notice("配布物の署名を確かめられませんでした: status=\(outcome.status, privacy: .public) timedOut=\(outcome.timedOut, privacy: .public)")
            throw .signature
        }
    }

    /// 「source=Notarized Developer ID」と「origin=Developer ID Installer: 名前 (チーム)」の両方があるか
    static func isTrusted(spctlOutput output: String, team: String) -> Bool {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let notarized = lines.contains("source=Notarized Developer ID")
        let origin = lines.contains { $0.hasPrefix("origin=Developer ID Installer: ") && $0.hasSuffix("(\(team))") }
        return notarized && origin
    }

    /// 大きなファイルなので少しずつ読んで求める．画面を止めないよう，メインスレッドの外で求める
    @concurrent
    private nonisolated static func digest(of file: URL) async throws(UpdateFailure) -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: file)
        } catch {
            throw .digestMismatch
        }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk: Data?
            do {
                chunk = try handle.read(upToCount: 1 << 20)
            } catch {
                throw .digestMismatch
            }
            guard let chunk, !chunk.isEmpty else { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
