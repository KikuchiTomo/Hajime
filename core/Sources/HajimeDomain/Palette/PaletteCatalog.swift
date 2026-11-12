/// パレットに並べる文字の一覧．同梱の表(data/palette/palette.tsv)を読み，表の順に持つ．
///
/// 行は「種類<タブ>まとまり<タブ>文字<タブ>絵文字のバージョン<タブ>日本語の名前<タブ>名前の読み<タブ>英語の名前<タブ>読み<タブ>キーワード<タブ>ショートコード<タブ>肌の色の形<タブ>名前の出どころ」．
/// 名前の出どころの列は無くてもよい(前の形の表も読む)．
/// 読みから後ろの列は | で区切る．# で始まる行は注記．表は tools/palette/update.sh が作る
public struct PaletteCatalog: Sendable, Equatable {
    public private(set) var items: [PaletteItem]

    public init(items: [PaletteItem]) {
        self.items = items
    }

    /// 表の中身を読む．形の合わない行と，知らない種類・まとまりの行は飛ばす(新しいバージョンの表を古いアプリで読んでも動くように)
    public init(text: String) {
        var items: [PaletteItem] = []
        var seen = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count >= 11, let kind = PaletteItem.Kind(rawValue: String(fields[0])), let category = PaletteCategory(rawValue: String(fields[1])),
                  category.kind == kind, !fields[2].isEmpty, fields[2].count <= Self.maximumTextLength(of: kind) else { continue }
            let text = String(fields[2])
            guard seen.insert("\(kind.rawValue):\(text)").inserted else { continue }
            let skinTones = Self.list(fields[10])
            items.append(PaletteItem(
                kind: kind, category: category, text: text, version: EmojiVersion(fields[3]),
                japaneseName: String(fields[4]), nameReading: String(fields[5]), englishName: String(fields[6]),
                readings: Self.list(fields[7]), keywords: Self.list(fields[8]), shortcodes: Self.list(fields[9]),
                skinTones: skinTones.count == SkinTone.allTones.count ? skinTones : [],
                nameSource: fields.count > 11 ? PaletteItem.NameSource(rawValue: String(fields[11])) : nil))
        }
        self.items = items
    }

    /// 1 つの項目の文字の長さの上限．顔文字は何文字もあるので別に決める
    private static func maximumTextLength(of kind: PaletteItem.Kind) -> Int {
        kind == .kaomoji ? DefaultSettings.maximumKaomojiTextLength : DefaultSettings.maximumPaletteTextLength
    }

    private static func list(_ field: Substring) -> [String] {
        field.split(separator: "|").map(String.init)
    }

    /// まとまりの順に，項目のあるまとまり
    public var categories: [PaletteCategory] {
        let present = Set(items.map(\.category))
        return PaletteCategory.allCases.filter(present.contains)
    }

    public func items(in category: PaletteCategory) -> [PaletteItem] {
        items.filter { $0.category == category }
    }

    /// この文字の項目．肌の色を変えた形からも引く
    public func item(for text: String) -> PaletteItem? {
        items.first { $0.text == text || $0.skinTones.contains(text) }
    }

    /// このショートコード(「:bow:」のコロンを除いた「bow」)の項目．大文字と小文字は区別しない
    public func item(forShortcode name: String) -> PaletteItem? {
        let name = name.lowercased()
        return items.first { $0.shortcodes.contains(name) }
    }

    /// 記号に，読みから引く記号の辞書(SymbolDictionary)の読みを足したもの．変換で出る記号はパレットでも同じ読みで探せるようにする
    public func addingReadings(_ entries: [(reading: String, symbols: [String])]) -> PaletteCatalog {
        var readings: [String: [String]] = [:]
        for entry in entries {
            for symbol in entry.symbols {
                readings[symbol, default: []].append(entry.reading)
            }
        }
        var result = self
        for index in result.items.indices where result.items[index].kind == .symbol {
            guard let extra = readings[result.items[index].text] else { continue }
            let known = Set(result.items[index].readings)
            result.items[index].readings += extra.filter { !known.contains($0) }
        }
        return result
    }

    /// OS が描けない新しい絵文字を除いたもの．記号はそのまま
    public func limited(to version: EmojiVersion) -> PaletteCatalog {
        PaletteCatalog(items: items.filter { $0.version.map { $0 <= version } ?? true })
    }

    /// バージョンごとに，そのバージョンで入った絵文字を 1 つずつ(古い順)．OS がどのバージョンまで描けるかを確かめるのに使う．
    /// 組み合わせの少ない絵文字ほど描けるかどうかがはっきりするので，符号位置のいちばん少ないものを選ぶ
    public var versionSamples: [(version: EmojiVersion, text: String)] {
        var samples: [EmojiVersion: String] = [:]
        for item in items {
            guard let version = item.version else { continue }
            if let current = samples[version], current.unicodeScalars.count <= item.text.unicodeScalars.count { continue }
            samples[version] = item.text
        }
        return samples.keys.sorted().compactMap { version in samples[version].map { (version, $0) } }
    }
}
