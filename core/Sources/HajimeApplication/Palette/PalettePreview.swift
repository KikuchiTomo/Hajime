import HajimeDomain

extension PalettePanel.Preview {
    /// 選んでいる文字の説明．名前は同梱の表の値(CLDR の名前)と Unicode の文字の名前から決め，どこで定めた名前かを添える．
    /// text は入れる文字(肌の色を当てたもの)．出さない設定の項目は空にする
    public init(item: PaletteItem, text: String, fields: PalettePanel.PreviewFields, isPinned: Bool) {
        let name = item.japaneseName.isEmpty ? item.englishName : item.japaneseName
        // 見出しが英語の名前のとき，同じ名前を 2 度出さない
        let unicodeName = (fields.unicodeName ? Self.unicodeName(of: item) : nil).flatMap { $0.name == name ? nil : $0 }
        self.init(
            text: text, name: name, nameSource: Self.nameSource(of: item),
            unicodeName: unicodeName?.name ?? "", unicodeNameSource: unicodeName?.source,
            readings: fields.readings ? Self.readings(of: item, name: name) : [],
            shortcodes: fields.shortcodes ? item.shortcodes.map { ":\($0):" } : [],
            // 顔文字は符号位置を並べても長いだけで役に立たないので出さない
            codePoints: fields.codePoints && item.kind != .kaomoji ? text.unicodeScalars.map { "U+" + String($0.value, radix: 16, uppercase: true) } : [],
            isPinned: isPinned)
    }

    /// 見出しの名前を定めたところ．絵文字の名前は CLDR の短い名前(tools/palette/build.py)．
    /// 記号は CLDR の名前と Hajime IME で付けた名前が混ざっていて見分けられず，顔文字の名前は読みなので，どちらも示さない
    private static func nameSource(of item: PaletteItem) -> String? {
        switch item.kind {
        case .emoji: item.japaneseName.isEmpty && item.englishName.isEmpty ? nil : PaletteStrings.cldrSource
        case .symbol, .kaomoji: nil
        }
    }

    /// Unicode の名前．異体字セレクタを除いて 1 つの符号位置なら UCD の名前(Swift の Unicode のデータ．Windows のエンジンでも同じ)．
    /// 並びと，Swift の Unicode のデータより新しい絵文字は，表の英語の名前(CLDR の英語の短い名前)．顔文字には名前が無い
    private static func unicodeName(of item: PaletteItem) -> (name: String, source: String)? {
        guard item.kind != .kaomoji else { return nil }
        let scalars = item.text.unicodeScalars.filter { !$0.properties.isVariationSelector }
        if scalars.count == 1, let name = scalars.first?.properties.name {
            return (name, PaletteStrings.unicodeSource)
        }
        // 記号の英語の名前は CLDR の名前と UCD の名前を小文字にしたものが混ざっているので，絵文字だけ使う
        guard item.kind == .emoji, !item.englishName.isEmpty else { return nil }
        return (item.englishName, PaletteStrings.cldrSource)
    }

    /// 説明に出す読み．名前の読みを先にし，見出しの名前と同じもの(かなの名前とそのひらがな)は除く
    private static func readings(of item: PaletteItem, name: String) -> [String] {
        let spelledName = KanaWidth.hiragana(from: name)
        var unique: [String] = []
        for reading in [item.nameReading] + item.readings where !reading.isEmpty && reading != name && reading != spelledName && !unique.contains(reading) {
            unique.append(reading)
        }
        return Array(unique.prefix(DefaultSettings.palettePreviewReadings))
    }
}
