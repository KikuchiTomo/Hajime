import Foundation
import S90Domain

/// 設定とユーザー辞書を同期のファイルと突き合わせる(TODO 43・49)．
///
/// この Mac で設定を変えたら記録をつけ(SyncMerge.noteChange)，`sync` で同期のファイルと突き合わせて両方を同じ中身にする．
/// 同期のファイルから取り込んだ変更は，この Mac で変えたことにしない(取り込んだ値で時刻を上書きしないため)
@MainActor
public final class SettingsSynchronizer {
    public enum SyncError: Error, Equatable {
        /// 同期のファイルが壊れている．上書きせずに止める(ほかの Mac の設定を消さないため)
        case unreadableDocument
    }

    private let settings: any SettingsStoring & SettingsObserving
    private let stateStore: any SyncStateStoring
    private let clock: () -> Date
    /// 同期のファイルは時刻を秒の単位で書くので，記録も秒にそろえる(書き戻すたびに違うと見なさないように)
    private var now: Date { Date(timeIntervalSince1970: clock().timeIntervalSince1970.rounded(.down)) }
    private var applyingRemote = false
    private var previous: [String: JSONValue]?

    public init(settings: any SettingsStoring & SettingsObserving, stateStore: any SyncStateStoring, clock: @escaping () -> Date = Date.init) {
        self.settings = settings
        self.stateStore = stateStore
        self.clock = clock
        previous = try? SettingsCoding.object(of: settings.current)
        settings.observe { [weak self] in self?.settingsDidChange($0) }
    }

    public var state: SyncState { stateStore.state }

    /// 同期のファイルと突き合わせる．取り込んだか，書き出したかを返す
    @discardableResult
    public func sync(with backend: any SyncBackend) throws -> SyncMerge.Result {
        var state = stateStore.state
        let remote: SyncDocument?
        if let data = try backend.read() {
            guard let document = try? SyncCoding.decoder.decode(SyncDocument.self, from: data) else { throw SyncError.unreadableDocument }
            remote = document
        } else {
            remote = nil
        }
        let local = try SettingsCoding.object(of: settings.current)
        let result = SyncMerge.merge(local: local, ledger: state.ledger, remote: remote, scopes: state.scopes, now: now)
        if result.changedLocal {
            let merged = try SettingsCoding.settings(from: result.settings)
            applyingRemote = true
            defer { applyingRemote = false }
            try settings.update { $0 = merged }
            previous = try? SettingsCoding.object(of: settings.current)
        }
        if result.changedRemote {
            try backend.write(SyncCoding.encoder.encode(result.document))
        }
        state.ledger = result.ledger
        try stateStore.save(state)
        return result
    }

    /// まとまりの範囲を変える
    public func setScope(_ scope: SyncScope, for group: SyncGroup) throws {
        var state = stateStore.state
        state.scopes[group] = scope
        try stateStore.save(state)
    }

    public func setEnabled(_ enabled: Bool, folderBookmark: Data?, folderName: String?) throws {
        var state = stateStore.state
        state.isEnabled = enabled
        state.folderBookmark = folderBookmark
        state.folderName = folderName
        try stateStore.save(state)
    }

    private func settingsDidChange(_ new: Settings) {
        guard let object = try? SettingsCoding.object(of: new) else { return }
        defer { previous = object }
        guard !applyingRemote, let old = previous else { return }
        var state = stateStore.state
        SyncMerge.noteChange(from: old, to: object, ledger: &state.ledger, now: now)
        try? stateStore.save(state)
    }
}

/// 同期のファイルと同期の状態の JSON の形(時刻は ISO 8601)
public enum SyncCoding {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
