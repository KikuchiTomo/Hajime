import Foundation
import HajimeApplication
import HajimeDomain

/// 起動のときに同梱のモデルと辞書を確かめた結果(ADR 0017)を JSON のファイルに保存する．ファイルは本人だけが読み書きでき，端末の外には出さない．
/// 読めない記録(無い・壊れた・大きすぎる・形が違う)は無かったものとし，呼ぶ側はすべて確かめ直す
public final class FileVerificationRecordStore: VerificationRecordStoring {
    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> VerificationRecord? {
        guard let data = try? ProtectedFile.read(from: fileURL, maximumBytes: DefaultSettings.maximumVerificationRecordBytes) else { return nil }
        return try? JSONDecoder().decode(VerificationRecord.self, from: data)
    }

    /// 書けなくても起動は続ける(次の起動で確かめ直すだけ)
    public func save(_ record: VerificationRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(record) else { return }
        try? ProtectedFile.write(data, to: fileURL)
    }
}
