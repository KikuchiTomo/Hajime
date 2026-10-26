import S90Domain

/// 変換中の語の連想を，取り込んだ連想の辞書から引く(R-18)．
/// 有効な辞書を一覧の順に引き，どの辞書にも無ければ読みでも引く(ひらがなで書いた語や，読みで書いた辞書のため)
@MainActor
struct AssociationFinder {
    private let lookup: (any AssociationLookup)?
    private let settings: any SettingsReading

    init(lookup: (any AssociationLookup)?, settings: any SettingsReading) {
        self.lookup = lookup
        self.settings = settings
    }

    /// 連想変換を使う設定か
    var isEnabled: Bool { settings.current.association }

    /// 引ける辞書があるか
    var hasDictionaries: Bool { lookup != nil && settings.current.associationDictionaries.contains(where: \.isEnabled) }

    /// text(読みは reading)の連想．連想変換を使わない設定のときと，見つからないときは nil
    func find(text: String, reading: String) -> Associations? {
        guard isEnabled, let lookup, !text.isEmpty else { return nil }
        let dictionaries = settings.current.associationDictionaries.filter(\.isEnabled)
        var groups = dictionaries.flatMap { dictionary in
            lookup.groups(for: text, in: dictionary).map { Self.labeled($0, dictionary: dictionary, among: dictionaries) }
        }
        if groups.isEmpty, !reading.isEmpty, reading != text {
            groups = dictionaries.flatMap { dictionary in
                lookup.groups(for: reading, in: dictionary).map { Self.labeled($0, dictionary: dictionary, among: dictionaries) }
            }
        }
        return Associations.make(headword: text, groups: groups, limit: settings.current.associationLimit)
    }

    /// 説明の無いまとまりは，辞書が 2 つ以上あれば辞書の名前を説明にする(どの辞書の語かを見分けられるように)
    private static func labeled(_ group: AssociationGroup, dictionary: AssociationDictionary, among dictionaries: [AssociationDictionary]) -> AssociationGroup {
        guard group.label.isEmpty, dictionaries.count > 1 else { return group }
        return AssociationGroup(label: dictionary.name, words: group.words)
    }
}
