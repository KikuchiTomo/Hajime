import Foundation

/// この Mac の設定と同期のファイルを突き合わせ，両方を同じ中身にする(R-15)．
///
/// - まとまり(SyncGroup)ごとに，最後に変えた時刻が新しい方を採る．範囲が「この Mac だけ」のまとまりは，
///   この Mac の値を変えず，同期のファイルにある値(ほかの Mac のもの)も消さない
/// - ユーザー辞書は語の和集合にする．消した語は墓標(消した時刻)で伝え，墓標より後に登録し直した語は残す
/// - 墓標は `tombstoneLifetime` を過ぎたら捨てる(ファイルが大きくなり続けないように)
public enum SyncMerge {
    public static let tombstoneLifetime: TimeInterval = 180 * 24 * 60 * 60

    public struct Result: Sendable, Equatable {
        /// 突き合わせたあとのこの Mac の設定(JSON のオブジェクト)
        public var settings: [String: JSONValue]
        public var ledger: SyncLedger
        /// 同期のファイルに書く中身
        public var document: SyncDocument
        /// この Mac の設定が変わったか(取り込んだか)
        public var changedLocal: Bool
        /// 同期のファイルを書き直す必要があるか
        public var changedRemote: Bool
    }

    /// localFields はまとまりを同期していても，この Mac の値を変えず，同期のファイルの値(ほかの Mac のもの)も変えない項目
    public static func merge(local: [String: JSONValue], ledger: SyncLedger, remote: SyncDocument?,
                             scopes: [SyncGroup: SyncScope], localFields: Set<String> = [], now: Date) -> Result {
        var settings = local
        var ledger = ledger
        var document = remote ?? SyncDocument()
        document.version = SyncDocument.currentVersion
        for group in SyncGroup.allCases where group != .dictionary && (scopes[group] ?? group.defaultScope) == .synced {
            let localTime = ledger.groupModifiedAt[group] ?? .distantPast
            var localValues = values(of: group, in: local)
            if let payload = remote?.groups[group], payload.modifiedAt > localTime {
                // 古いバージョンの Mac の値(legacyFieldNames)も取り込み，設定を作るときに新しい項目へ移し替える
                for name in group.fieldNames + group.legacyFieldNames where !localFields.contains(name) {
                    settings[name] = payload.values[name]
                }
                ledger.groupModifiedAt[group] = payload.modifiedAt
            } else {
                // この Mac だけの項目は，同期のファイルにある値(ほかの Mac のもの)を残す
                for name in localFields where group.fieldNames.contains(name) {
                    localValues[name] = remote?.groups[group]?.values[name]
                }
                document.groups[group] = .init(modifiedAt: localTime, values: localValues)
            }
        }
        if (scopes[.dictionary] ?? SyncGroup.dictionary.defaultScope) == .synced {
            mergeDictionary(settings: &settings, ledger: &ledger, document: &document, remote: remote, now: now)
        }
        ledger.lastSyncedAt = now
        return Result(settings: settings, ledger: ledger, document: document,
                      changedLocal: settings != local, changedRemote: remote.map { $0 != document } ?? true)
    }

    /// 語の和集合をとり，墓標より後に登録した語だけを残す
    private static func mergeDictionary(settings: inout [String: JSONValue], ledger: inout SyncLedger, document: inout SyncDocument,
                                        remote: SyncDocument?, now: Date) {
        var tombstones = ledger.dictionaryTombstones
        for (key, time) in remote?.tombstones ?? [:] { tombstones[key] = max(tombstones[key] ?? .distantPast, time) }
        tombstones = tombstones.filter { now.timeIntervalSince($0.value) < tombstoneLifetime }

        var order: [String] = []
        var entries: [String: SyncDocument.DictionaryEntry] = [:]
        func add(_ entry: SyncDocument.DictionaryEntry) {
            let key = Self.key(reading: entry.reading, word: entry.word)
            if let existing = entries[key] {
                entries[key]?.addedAt = max(existing.addedAt, entry.addedAt)
            } else {
                order.append(key)
                entries[key] = entry
            }
        }
        for entry in localDictionary(settings) {
            add(.init(reading: entry.reading, word: entry.word,
                      addedAt: ledger.dictionaryAddedAt[key(reading: entry.reading, word: entry.word)] ?? .distantPast))
        }
        remote?.dictionary.forEach(add)
        let kept = order.compactMap { key -> SyncDocument.DictionaryEntry? in
            guard let entry = entries[key] else { return nil }
            if let removed = tombstones[key], removed >= entry.addedAt { return nil }
            return entry
        }
        settings["userDictionary"] = .array(kept.map { .object(["reading": .string($0.reading), "word": .string($0.word)]) })
        ledger.dictionaryAddedAt = Dictionary(kept.map { (key(reading: $0.reading, word: $0.word), $0.addedAt) }, uniquingKeysWith: max)
        ledger.dictionaryTombstones = tombstones
        document.dictionary = kept
        document.tombstones = tombstones
    }

    /// まとまりに入る項目の値
    public static func values(of group: SyncGroup, in object: [String: JSONValue]) -> [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: group.fieldNames.compactMap { name in object[name].map { (name, $0) } })
    }

    /// ユーザー辞書の語を引く鍵
    public static func key(reading: String, word: String) -> String { "\(reading)\t\(word)" }

    private static func localDictionary(_ object: [String: JSONValue]) -> [(reading: String, word: String)] {
        guard case .array(let items)? = object["userDictionary"] else { return [] }
        return items.compactMap { item in
            guard case .object(let fields) = item, case .string(let reading)? = fields["reading"], case .string(let word)? = fields["word"] else { return nil }
            return (reading, word)
        }
    }

    /// この Mac で設定を変えたときに記録をつける．まとまりの値が変わったら時刻を記し，辞書の語の登録と削除を記す
    /// localFields(この Mac だけの項目)だけが変わったときは，まとまりを変えたことにしない(ほかの Mac に送らない)
    public static func noteChange(from old: [String: JSONValue], to new: [String: JSONValue], ledger: inout SyncLedger,
                                  localFields: Set<String> = [], now: Date) {
        for group in SyncGroup.allCases {
            let before = values(of: group, in: old).filter { !localFields.contains($0.key) }
            let after = values(of: group, in: new).filter { !localFields.contains($0.key) }
            if before != after { ledger.groupModifiedAt[group] = now }
        }
        let before = Set(localDictionary(old).map { key(reading: $0.reading, word: $0.word) })
        let after = Set(localDictionary(new).map { key(reading: $0.reading, word: $0.word) })
        for added in after.subtracting(before) {
            ledger.dictionaryAddedAt[added] = now
            ledger.dictionaryTombstones[added] = nil
        }
        for removed in before.subtracting(after) {
            ledger.dictionaryAddedAt[removed] = nil
            ledger.dictionaryTombstones[removed] = now
        }
    }
}
