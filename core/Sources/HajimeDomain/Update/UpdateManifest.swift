import Foundation

/// リリースのバージョン(X.Y.Z)．比べるときは数として比べる(0.2.10 は 0.2.9 より新しい)
public struct ReleaseVersion: Sendable, Hashable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// 「0.2.7」の形だけを読む．前の「v」や後ろの印(-beta など)は受け付けない
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 9, part.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Int(part) else { return nil }
            numbers.append(number)
        }
        self.init(major: numbers[0], minor: numbers[1], patch: numbers[2])
    }

    public var description: String { "\(major).\(minor).\(patch)" }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// 配布物を選ぶ OS．latest.json の files・sha256 のキー
public enum UpdatePlatform: String, Sendable {
    case macos
    case windows
}

/// 取って入れる配布物．URL は決めた場所(DefaultSettings.updateDownloadBaseURL)の下だけ
public struct UpdatePackage: Sendable, Equatable {
    public var url: URL
    public var fileName: String
    /// 小文字の 16 進 64 桁
    public var sha256: String
}

/// 1 つのバージョンの変更点(CHANGELOG.md の節)
public struct ReleaseNote: Sendable, Equatable {
    public var version: ReleaseVersion
    public var date: String
    public var notes: String
}

public enum UpdateManifestError: Error, Equatable {
    /// 上限(DefaultSettings.maximumUpdateManifestBytes)より大きい
    case tooLarge
    /// JSON の形が違う
    case unreadable
}

/// 最新のバージョンの知らせ(https://haji.men/download/latest.json．tools/release/upload_downloads.sh が書く)．
///
///     { "version": "0.2.7",
///       "files": { "macos": "v0.2.7/Hajime-0.2.7.pkg", "windows": "v0.2.7/Hajime-0.2.7.msi" },
///       "sha256": { "macos": "…", "windows": "…" },
///       "releases": [{ "version": "0.2.7", "date": "2026-11-11", "notes": "### 追加\n\n- …" }] }
///
/// 外から取ったものなので，配布物の場所と SHA-256 は形を確かめてから使う(package(for:baseURL:))
public struct UpdateManifest: Sendable, Equatable {
    public var version: ReleaseVersion
    public var files: [String: String]
    public var sha256: [String: String]
    /// 新しい順
    public var releases: [ReleaseNote]

    public init(version: ReleaseVersion, files: [String: String], sha256: [String: String], releases: [ReleaseNote]) {
        self.version = version
        self.files = files
        self.sha256 = sha256
        self.releases = releases
    }

    public static func decode(_ data: Data) throws(UpdateManifestError) -> UpdateManifest {
        guard data.count <= DefaultSettings.maximumUpdateManifestBytes else { throw .tooLarge }
        let raw: Raw
        do {
            raw = try JSONDecoder().decode(Raw.self, from: data)
        } catch {
            throw .unreadable
        }
        guard let version = ReleaseVersion(raw.version) else { throw .unreadable }
        // 読めない節は飛ばす(変更点が出ないだけで，更新はできる)
        let releases = (raw.releases ?? []).compactMap { note in
            ReleaseVersion(note.version).map { ReleaseNote(version: $0, date: note.date, notes: note.notes) }
        }
        return UpdateManifest(version: version, files: raw.files, sha256: raw.sha256, releases: releases.sorted { $0.version > $1.version })
    }

    /// その OS の配布物．場所が「v<バージョン>/<ファイル名>」の形でないか，SHA-256 が 16 進 64 桁でなければ nil
    public func package(for platform: UpdatePlatform, baseURL: String) -> UpdatePackage? {
        guard let path = files[platform.rawValue], let digest = sha256[platform.rawValue]?.lowercased(),
              Self.isVersionedPath(path), Self.isHexDigest(digest),
              baseURL.hasPrefix("https://"), baseURL.hasSuffix("/"),
              let url = URL(string: baseURL + path) else { return nil }
        // isVersionedPath で「v<バージョン>/<ファイル名>」の 2 つに分かれることを確かめてある
        let fileName = String(path.split(separator: "/")[1])
        return UpdatePackage(url: url, fileName: fileName, sha256: digest)
    }

    /// 今のバージョンより新しく，知らせのバージョンまでの変更点(新しい順)
    public func notes(newerThan current: ReleaseVersion) -> [ReleaseNote] {
        releases.filter { $0.version > current && $0.version <= version }
    }

    /// サイトの Worker と同じ形(apps/docs-site/worker/downloads.js の VERSIONED)．「..」や「/」を含む名前を通さない
    static func isVersionedPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].first == "v", ReleaseVersion(String(parts[0].dropFirst())) != nil else { return false }
        let name = parts[1]
        guard let first = name.unicodeScalars.first, isAlphanumeric(first) else { return false }
        return name.unicodeScalars.allSatisfy { isAlphanumeric($0) || $0 == "." || $0 == "_" || $0 == "-" }
    }

    static func isHexDigest(_ text: String) -> Bool {
        text.utf8.count == 64 && text.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    private static func isAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        ("0"..."9").contains(scalar) || ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }

    private struct Raw: Decodable {
        var version: String
        var files: [String: String]
        var sha256: [String: String]
        var releases: [RawNote]?
    }

    private struct RawNote: Decodable {
        var version: String
        var date: String
        var notes: String
    }
}
