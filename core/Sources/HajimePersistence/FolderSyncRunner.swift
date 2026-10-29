import Foundation
import HajimeApplication
import HajimeDomain

/// 利用者が選んだフォルダで同期する 1 回分の手順(R-15・R-16)．macOS と Windows の同期の時機を決める側から呼ぶ．
///
/// 1. 設定とユーザー辞書を同期のファイル(hajime-sync.json)と突き合わせ，ほかの PC で消した辞書の索引をこの PC からも消す(syncSettings)
/// 2. 取り込んだ辞書の索引のファイルを hajime-dictionaries/ と運ぶ(dictionaryFiles で仕事を作り，メインスレッドの外で run する)
/// 3. 運んだ結果を設定と索引に反映する(finish)
///
/// フォルダの開き方(macOS のセキュリティスコープ付きのブックマーク，Windows のパス)は呼ぶ側が受け持つ
@MainActor
public final class FolderSyncRunner {
    /// 取り込んだ辞書の索引を運ぶ仕事．メインスレッドの外で動かせる
    public struct DictionaryFiles: Sendable {
        let localDirectory: URL
        let dictionaries: [ImportedDictionary]

        public func run(in folder: URL) throws -> DictionaryFileSync.Outcome {
            try DictionaryFileSync(localDirectory: localDirectory, syncFolder: folder).sync(dictionaries)
        }
    }

    private let synchronizer: SettingsSynchronizer
    private let settings: any SettingsStoring
    private let dictionaries: ImportedDictionaryStore

    public init(synchronizer: SettingsSynchronizer, settings: any SettingsStoring, dictionaries: ImportedDictionaryStore) {
        self.synchronizer = synchronizer
        self.settings = settings
        self.dictionaries = dictionaries
    }

    public var state: SyncState { synchronizer.state }

    /// 設定とユーザー辞書を同期のファイルと突き合わせる．ほかの PC で消した辞書は，この PC の索引も消す．
    /// 同期のファイルの読み書きはメインスレッドの外で行い，時間の上限(DefaultSettings.syncFileTimeout)を過ぎたら待つのをやめる
    /// (クラウドのフォルダがファイルをまだ手元に置いていないときなど)．うまくいけば nil，できなければ理由を返す
    public func syncSettings(in folder: URL) async -> SyncProblem? {
        let backend = FolderSyncBackend(folder: folder)
        guard let read = await Deadline.run(seconds: DefaultSettings.syncFileTimeout, { await Self.perform { try backend.read() } }) else {
            return .folderUnavailable
        }
        do {
            let merged = try merge(remote: try read.get())
            if let written = merged.written {
                let wrote = await Deadline.run(seconds: DefaultSettings.syncFileTimeout, { await Self.perform { try backend.write(written) } })
                guard let wrote else { return .folderUnavailable }
                try wrote.get()
            }
            try synchronizer.commit(merged)
            return nil
        } catch {
            return error as? SettingsSynchronizer.SyncError == .unreadableDocument ? .unreadable : .failed
        }
    }

    @concurrent
    private static func perform<Value: Sendable>(_ body: @Sendable () throws -> Value) async -> Result<Value, any Error> {
        Result { try body() }
    }

    /// 読んでおいた同期のファイルの中身と突き合わせる．ファイルの読み書きをメインスレッドの外で行うときに使う．
    /// 書く中身があれば同期のファイルに書き，書けたら synchronizer の commit で記録を進める
    public func merge(remote data: Data?) throws -> SettingsSynchronizer.Merged {
        let before = settings.current.importedDictionaries
        let merged = try synchronizer.merge(remote: data)
        let remaining = Set(settings.current.importedDictionaries.map(\.id))
        for dictionary in before where !remaining.contains(dictionary.id) { dictionaries.remove(dictionary) }
        return merged
    }

    public func commit(_ merged: SettingsSynchronizer.Merged) throws {
        try synchronizer.commit(merged)
    }

    /// 索引を運ぶ仕事．取り込んだ辞書のまとまりを同期しないときと，辞書が無いときは nil
    public func dictionaryFiles() -> DictionaryFiles? {
        guard synchronizer.state.scope(of: .importedDictionaries) == .synced else { return nil }
        let list = settings.current.importedDictionaries
        guard !list.isEmpty else { return nil }
        return DictionaryFiles(localDirectory: dictionaries.directory, dictionaries: list)
    }

    /// 運んだ索引を開き直し，同期を入れる前に取り込んだ辞書にバージョンを書き戻す(設定が変わるので，次の同期で索引を書き出す)
    public func finish(_ outcome: DictionaryFileSync.Outcome) {
        for dictionary in settings.current.importedDictionaries where outcome.installed.contains(dictionary.id) {
            dictionaries.reload(dictionary)
        }
        guard !outcome.computedRevisions.isEmpty else { return }
        try? settings.update { current in
            for index in current.importedDictionaries.indices where current.importedDictionaries[index].revision == nil {
                current.importedDictionaries[index].revision = outcome.computedRevisions[current.importedDictionaries[index].id]
            }
        }
    }
}
