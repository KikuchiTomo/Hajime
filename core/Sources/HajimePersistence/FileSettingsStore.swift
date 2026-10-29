import Foundation
#if canImport(os)
import os
#endif
import HajimeApplication
import HajimeDomain

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
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            self.current = DefaultSettings.settings
            return
        }
        do {
            let data = try ProtectedFile.read(from: fileURL, maximumBytes: DefaultSettings.maximumSettingsFileBytes)
            self.current = try SettingsCoding.decode(data)
        } catch {
            // ファイルはあるが読めない．脇に置いたことを記録し，設定の画面で一度知らせる(ファイルの中身はログに出さない)
            self.setAsideFile = ProtectedFile.setAside(fileURL)
            #if canImport(os)
            Logger(subsystem: "men.haji.inputmethod", category: "settings")
                .notice("読めなかった設定のファイルを脇に置きました: \(self.setAsideFile?.lastPathComponent ?? "-", privacy: .public)")
            #endif
            self.current = DefaultSettings.settings
        }
    }

    /// 起動したときに読めず，脇に置いた設定のファイル．無ければ nil
    public private(set) var setAsideFile: URL?

    public func reload() {
        guard let data = try? ProtectedFile.read(from: fileURL, maximumBytes: DefaultSettings.maximumSettingsFileBytes),
              let next = try? SettingsCoding.decode(data), next != current else { return }
        current = next
        observers.forEach { $0(next) }
    }

    public func update(_ change: (inout Settings) -> Void) throws {
        var next = current
        change(&next)
        guard next != current else { return }
        let data = try SettingsCoding.encode(next)
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
