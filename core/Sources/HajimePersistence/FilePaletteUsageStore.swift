import Foundation
import HajimeApplication
import HajimeDomain

/// パレットで選んだ文字の使い方を JSON のファイルに保存する．ファイルは本人だけが読み書きでき，端末の外には出さない．
/// 読めないファイル(壊れた・大きすぎる)は使わずに空の使い方で始め，次に選んだときに書き直す(パレットを開けなくしない)
@MainActor
public final class FilePaletteUsageStore: PaletteUsageStoring {
    private let fileURL: URL
    public private(set) var usage: PaletteUsage

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.usage = (try? Self.load(from: fileURL)) ?? PaletteUsage()
    }

    public func update(_ change: (inout PaletteUsage) -> Void) {
        let before = usage
        change(&usage)
        guard usage != before else { return }
        try? ProtectedFile.write(JSONEncoder().encode(usage), to: fileURL)
    }

    private static func load(from url: URL) throws -> PaletteUsage {
        try JSONDecoder().decode(PaletteUsage.self, from: ProtectedFile.read(from: url, maximumBytes: DefaultSettings.maximumPaletteUsageFileBytes))
    }
}
