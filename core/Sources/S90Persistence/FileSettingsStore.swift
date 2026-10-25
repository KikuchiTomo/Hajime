import Foundation
import S90Application
import S90Domain

/// 設定を JSON のファイルに保存する．ファイルは本人だけが読み書きできる権限で作る(docs/dev/SECURITY-MODEL.md)．
@MainActor
public final class FileSettingsStore: SettingsStoring, SettingsObserving {
    public enum StoreError: Error, Equatable {
        case fileTooLarge(bytes: Int)
    }

    private let fileURL: URL
    public private(set) var current: Settings
    private var observers: [(Settings) -> Void] = []

    /// 読めないファイル・壊れたファイルのときは既定値で始める．入力を止めないため．
    /// 読めなかったファイルは脇に置き，既定値で上書きして利用者の設定とユーザー辞書を消さないようにする
    public init(fileURL: URL) {
        self.fileURL = fileURL
        do {
            self.current = try JSONDecoder().decode(Settings.self, from: ProtectedFile.read(from: fileURL, maximumBytes: DefaultSettings.maximumSettingsFileBytes))
        } catch {
            if FileManager.default.fileExists(atPath: fileURL.path) { ProtectedFile.setAside(fileURL) }
            self.current = DefaultSettings.settings
        }
    }

    public func update(_ change: (inout Settings) -> Void) throws {
        var next = current
        change(&next)
        guard next != current else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(next)
        // 上限を超えるファイルは次に読めないので，書く前に断る
        guard data.count <= DefaultSettings.maximumSettingsFileBytes else { throw StoreError.fileTooLarge(bytes: data.count) }
        try ProtectedFile.write(data, to: fileURL)
        current = next
        observers.forEach { $0(next) }
    }

    /// 設定が変わるたびに呼ばれる処理を足す．エンジンや設定の画面を新しい設定に合わせるのに使う
    public func observe(_ handler: @escaping (Settings) -> Void) {
        observers.append(handler)
    }
}
