import Foundation

/// 設定の画面から受け取ったファイルやフォルダのパスを確かめて URL にする(docs/dev/SECURITY-MODEL.md)．
///
/// パスは利用者がファイルを選ぶ画面で選んだもの．エンジンはパスを組み立てずにそのまま使い，
/// ローカルのドライブの絶対パスだけを受け付ける．Windows では「C:\」の形だけにし，
/// ネットワークの共有(\\server\share)・デバイスや名前付きパイプ(\\.\，\\?\)・代替データストリームは断る
enum LocalFilePath {
    static func url(_ path: String, isDirectory: Bool = false) -> URL? {
        guard !path.isEmpty, path.utf16.count <= maximumLength, !path.contains("\0"), isLocalAbsolute(path) else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: isDirectory)
        // 「..」で別の場所を指すパスは，選ぶ画面からは来ないので断る
        guard !url.pathComponents.contains("..") else { return nil }
        return url
    }

    /// 今あるフォルダのパスか
    static func existingDirectory(_ path: String) -> URL? {
        guard let url = url(path, isDirectory: true) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return url
    }

    /// Windows の長いパスの上限(32767 文字)
    private static let maximumLength = 32_767

    private static func isLocalAbsolute(_ path: String) -> Bool {
        #if os(Windows)
        let characters = Array(path.unicodeScalars.prefix(3))
        guard characters.count == 3 else { return false }
        // 3 文字目より後ろの「:」は代替データストリーム(file.txt:stream)なので断る
        return characters[0].isASCII && characters[0].properties.isAlphabetic && characters[1] == ":" && (characters[2] == "\\" || characters[2] == "/")
            && !path.unicodeScalars.dropFirst(2).contains(":")
        #else
        return path.hasPrefix("/")
        #endif
    }
}
