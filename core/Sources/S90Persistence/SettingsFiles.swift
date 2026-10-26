import Foundation
import S90Application
import S90Domain

/// 設定の画面から頼まれたファイルの読み書き(R-16，設定のバックアップ，除外設定の CSV，決まりの一覧)．
/// Windows の設定の画面は別のプロセスなので，エンジンがここを呼んで macOS の設定の画面と同じ読み書きをする．
///
/// 外から来るファイルは，それぞれの読み込みの決まり(大きさの上限・形の確かめ)で読む．
/// 読むのと書くのはメインスレッドの外で行い，入力の処理を止めない．設定に反映するのはメインスレッドで行う
@MainActor
public final class SettingsFiles: SettingsFileHandling {
    private let settings: any SettingsStoring
    private let dictionaries: ImportedDictionaryStore

    public init(settings: any SettingsStoring, dictionaries: ImportedDictionaryStore) {
        self.settings = settings
        self.dictionaries = dictionaries
    }

    // MARK: 取り込んだ辞書

    public func importDictionary(from path: String, replacing id: String?) async throws(SettingsFileFailure) -> ImportedDictionary {
        let source = try Self.url(path)
        let list = settings.current.importedDictionaries
        let existing = id.flatMap { id in list.first { $0.id == id } }
        if id != nil, existing == nil { throw .unknownDictionary }
        guard existing != nil || list.count < DefaultSettings.maximumImportedDictionaries else { throw .tooMany }
        let dictionary = existing ?? ImportedDictionary(id: UUID().uuidString, name: source.deletingPathExtension().lastPathComponent, wordCount: 0)
        let imported = try await Self.importFile(source, as: dictionary, into: dictionaries)
        dictionaries.reload(imported)
        do {
            try settings.update { _ = ImportedDictionary.record(imported, isNew: existing == nil, in: &$0.importedDictionaries) }
        } catch {
            // 設定に残せなかった新しい辞書の索引は，どこからも使われないので消す
            if existing == nil { dictionaries.remove(imported) }
            throw .writeFailed
        }
        return settings.current.importedDictionaries.first { $0.id == imported.id } ?? imported
    }

    public func removeDictionary(id: String) throws(SettingsFileFailure) {
        guard let dictionary = settings.current.importedDictionaries.first(where: { $0.id == id }) else { throw .unknownDictionary }
        do {
            try settings.update { $0.importedDictionaries.removeAll { $0.id == id } }
        } catch {
            throw .writeFailed
        }
        dictionaries.remove(dictionary)
    }

    // MARK: バックアップ

    public func exportSettings(to path: String) async throws(SettingsFileFailure) {
        let destination = try Self.url(path)
        let current = settings.current
        try await Self.write { try SettingsTransfer.write(current, to: destination) }
    }

    /// 読み込んだ設定ですべてを置き換える．読めない項目と範囲の外の値は既定値になる(SettingsTransfer)
    public func importSettings(from path: String) async throws(SettingsFileFailure) {
        let source = try Self.url(path)
        let imported = try await Self.read { try SettingsTransfer.read(from: source) }
        try apply { $0 = imported }
    }

    // MARK: 除外設定

    public func importProfileRules(from path: String) async throws(SettingsFileFailure) -> (added: Int, skipped: Int) {
        let source = try Self.url(path)
        let file = try await Self.read { try ProfileRuleFile.readCounting(from: source) }
        try apply { ProfileRuleCSV.merge(file.rules, into: &$0) }
        return (file.rules.count, file.skipped)
    }

    public func exportProfileRules(to path: String) async throws(SettingsFileFailure) {
        let destination = try Self.url(path)
        let rules = settings.current.profileRules
        try await Self.write { try ProfileRuleFile.write(rules, to: destination) }
    }

    // MARK: 決まりの一覧

    public func importRuleList(_ list: RuleList, from path: String) async throws(SettingsFileFailure) -> (added: Int, skipped: Int) {
        let source = try Self.url(path)
        let rows = try await Self.read { try RuleListFile.read(from: source) }
        var added = 0
        try apply { added = list.merge(rows, into: &$0) }
        return (added, rows.count - added)
    }

    public func exportRuleList(_ list: RuleList, to path: String) async throws(SettingsFileFailure) {
        let destination = try Self.url(path)
        let rows = list.rows(in: settings.current)
        try await Self.write { try RuleListFile.write(rows, to: destination) }
    }

    // MARK: -

    private func apply(_ change: (inout Settings) -> Void) throws(SettingsFileFailure) {
        do {
            try settings.update(change)
        } catch {
            throw .writeFailed
        }
    }

    private static func url(_ path: String) throws(SettingsFileFailure) -> URL {
        guard let url = LocalFilePath.url(path) else { throw .invalidPath }
        return url
    }

    @concurrent
    private static func importFile(_ source: URL, as dictionary: ImportedDictionary,
                                   into store: ImportedDictionaryStore) async throws(SettingsFileFailure) -> ImportedDictionary {
        do {
            return try store.importFile(from: source, as: dictionary)
        } catch {
            throw failure(reading: error)
        }
    }

    @concurrent
    private static func read<Value: Sendable>(_ body: @Sendable () throws -> Value) async throws(SettingsFileFailure) -> Value {
        do {
            return try body()
        } catch {
            throw failure(reading: error)
        }
    }

    @concurrent
    private static func write(_ body: @Sendable () throws -> Void) async throws(SettingsFileFailure) {
        do {
            try body()
        } catch {
            throw .writeFailed
        }
    }

    /// 読み込みのエラーを，設定の画面に出す理由に分ける(エラーの中身はファイルの中身を含みうるので，種類だけを使う)
    nonisolated static func failure(reading error: any Error) -> SettingsFileFailure {
        switch error {
        case is ProtectedFile.TooLarge,
             DictionaryFileReader.FileError.fileTooLarge, SettingsTransfer.TransferError.fileTooLarge,
             ProfileRuleFile.FileError.fileTooLarge, RuleListFile.FileError.fileTooLarge:
            return .tooLarge
        case DictionaryFileReader.FileError.empty:
            return .empty
        case SettingsTransfer.TransferError.notSettings:
            return .notSettings
        case let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile:
            return .notFound
        case let error as POSIXError where error.code == .ENOENT:
            return .notFound
        default:
            return .unreadable
        }
    }
}
