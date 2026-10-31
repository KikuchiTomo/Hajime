import HajimeDomain

/// 変換中の語の連想を，取り込んだ連想の辞書から引く(R-18)．
/// 有効な辞書を一覧の順に引き，どの辞書にも無ければ読みでも引く(ひらがなで書いた語や，読みで書いた辞書のため)．
/// 変換マクロ(ConversionMacro)を使う設定なら，選んでいる語を整えた形を「整形」のまとまりとして最後に足す
@MainActor
struct AssociationFinder {
    private let lookup: (any AssociationLookup)?
    private let settings: any SettingsReading

    init(lookup: (any AssociationLookup)?, settings: any SettingsReading) {
        self.lookup = lookup
        self.settings = settings
    }

    /// 連想変換か変換マクロを使う設定か(どちらも連想変換のキーで一覧を出す)
    var isEnabled: Bool { settings.current.association || settings.current.conversionMacros }

    /// 引ける辞書があるか
    var hasDictionaries: Bool { lookup != nil && settings.current.associationDictionaries.contains(where: \.isEnabled) }

    /// text(読みは reading)の連想と変換マクロ．使わない設定のときと，見つからないときは nil．
    /// includesMacros が false なら連想の辞書だけを引く(連想があることの知らせに使う．マクロはいつでもあるため)
    func find(text: String, reading: String, includesMacros: Bool = true) -> Associations? {
        guard isEnabled, !text.isEmpty else { return nil }
        let current = settings.current
        var groups = current.association
            ? Associations.make(headword: text, groups: dictionaryGroups(text: text, reading: reading), limit: current.associationLimit)?.groups ?? []
            : []
        // マクロのまとまりは連想の数の上限に数えない(連想の語でまとまりが切られて，マクロが出なくなるのを避ける)
        if includesMacros, current.conversionMacros {
            let results = ConversionMacros.results(text: text, reading: KanaWidth.hiragana(from: reading), macros: current.macros)
            if !results.isEmpty { groups.append(AssociationGroup(label: DefaultSettings.macroGroupLabel, words: results)) }
        }
        return groups.isEmpty ? nil : Associations(headword: text, groups: groups)
    }

    private func dictionaryGroups(text: String, reading: String) -> [AssociationGroup] {
        guard let lookup else { return [] }
        let dictionaries = settings.current.associationDictionaries.filter(\.isEnabled)
        var groups = dictionaries.flatMap { dictionary in
            lookup.groups(for: text, in: dictionary).map { Self.labeled($0, dictionary: dictionary, among: dictionaries) }
        }
        if groups.isEmpty, !reading.isEmpty, reading != text {
            groups = dictionaries.flatMap { dictionary in
                lookup.groups(for: reading, in: dictionary).map { Self.labeled($0, dictionary: dictionary, among: dictionaries) }
            }
        }
        return groups
    }

    /// 説明の無いまとまりは，辞書が 2 つ以上あれば辞書の名前を説明にする(どの辞書の語かを見分けられるように)
    private static func labeled(_ group: AssociationGroup, dictionary: AssociationDictionary, among dictionaries: [AssociationDictionary]) -> AssociationGroup {
        guard group.label.isEmpty, dictionaries.count > 1 else { return group }
        return AssociationGroup(label: dictionary.name, words: group.words)
    }
}
