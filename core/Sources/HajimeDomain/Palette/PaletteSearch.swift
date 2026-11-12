import Foundation

/// パレットの項目を，読み・名前・キーワード・ショートコードで探す(FuzzyMatch)．
///
/// 当たりを強さで段に分け，段の順に並べる．あいまいな当たりが打ったとおりの当たりを追い越さないようにするため．
/// 1. 名前・読み・キーワード・ショートコードと同じ．同じ語で前に何度も選んだ項目もここに入れる
/// 2. 名前・読み・ショートコードの頭から当たる
/// 3. キーワードの頭か，語の頭(空白や区切りの記号のあと)から当たる
/// 4. 途中に当たる
/// 5. 飛び飛びに当たる(英数字を 3 文字以上打ったときだけ)
///
/// 同じ段の中は，当たりのよさ(余った文字が少ないほど・名前で当たったほど高い)に，よく使う度合いとピン留めの加点を足した点で並べる．
/// 点が同じなら今見ているパレットの種類を先にし，最後は表の順
public struct PaletteSearch: Sendable {
    /// 探す語．打ったままの英数字と，それをかなにした読みの両方で探す(「neko」でも「ねこ」でも猫が出る)
    public struct Query: Sendable, Equatable, Hashable {
        /// 打った英数字と記号．「:」で始めるとショートコードだけを探す
        public var typed: String
        /// 打った読み(ひらがな)．かなにならなかった部分は含めない
        public var kana: String

        public init(typed: String, kana: String = "") {
            self.typed = typed
            self.kana = kana
        }

        public var isEmpty: Bool { shortcodePattern?.isEmpty ?? (typed.isEmpty && kana.isEmpty) }

        /// 「:」で始めたときの，コロンを除いたショートコード(「:bow:」→「bow」)．「:」で始めていなければ nil
        public var shortcodePattern: String? {
            guard typed.hasPrefix(":") else { return nil }
            var pattern = typed.dropFirst()
            if pattern.hasSuffix(":") { pattern = pattern.dropLast() }
            return String(pattern)
        }
    }

    /// 並べるときに使う，利用者ごとの手がかり
    public struct Ranking: Sendable, Equatable {
        /// 項目の文字ごとのよく使う度合い(PaletteUsage の点)
        public var usage: [String: Double]
        /// この語で前に何度も選んだ項目(PaletteUsage.learnedChoices)
        public var learned: Set<String>
        /// 利用者がピン留めした項目
        public var pinned: Set<String>
        /// 今見ているパレットの種類．点が同じなら先に出す
        public var preferredKind: PaletteItem.Kind?

        public init(usage: [String: Double] = [:], learned: Set<String> = [], pinned: Set<String> = [], preferredKind: PaletteItem.Kind? = nil) {
            self.usage = usage
            self.learned = learned
            self.pinned = pinned
            self.preferredKind = preferredKind
        }
    }

    /// どの欄で当たったか
    enum Field: Sendable {
        /// 名前・名前の読み・ショートコード
        case name
        /// 名前のほかの読み
        case reading
        case keyword
    }

    /// 当たりの段．後ろほど強い
    enum Tier: Int, Comparable {
        case scattered
        case substring
        case keywordPrefix
        case prefix
        case exact

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private struct Key: Sendable {
        var scalars: [Unicode.Scalar]
        var field: Field
    }

    private struct Entry: Sendable {
        var item: PaletteItem
        /// 打った英数字と照らし合わせる欄
        var typedKeys: [Key]
        /// 読みと照らし合わせる欄
        var kanaKeys: [Key]
        var shortcodes: [Key]
    }

    private let entries: [Entry]

    public init(catalog: PaletteCatalog) {
        entries = catalog.items.map { item in
            func keys(_ texts: [String], _ field: Field) -> [Key] {
                texts.filter { !$0.isEmpty }.map { Key(scalars: FuzzyMatch.normalized($0), field: field) }
            }
            let isASCII: (String) -> Bool = { $0.unicodeScalars.allSatisfy(\.isASCII) }
            let shortcodes = keys(item.shortcodes, .name)
            return Entry(
                item: item,
                typedKeys: shortcodes + keys([item.text, item.englishName, item.japaneseName], .name) + keys(item.keywords.filter(isASCII), .keyword),
                kanaKeys: keys([item.nameReading, item.japaneseName], .name) + keys(item.readings, .reading) + keys(item.keywords.filter { !isASCII($0) }, .keyword),
                shortcodes: shortcodes)
        }
    }

    /// query に当たる項目を並べて返す．shape を渡すと，そのマスの形の種類だけを探す(顔文字と絵文字・記号を同じ結果に混ぜない)
    public func search(_ query: Query, ranking: Ranking = Ranking(), shape: PaletteCellShape? = nil,
                       limit: Int = DefaultSettings.maximumPaletteSearchResults) -> [PaletteItem] {
        guard !query.isEmpty, limit > 0 else { return [] }
        let shortcode = query.shortcodePattern.map(FuzzyMatch.normalized)
        let typed = shortcode == nil ? FuzzyMatch.normalized(query.typed) : []
        let kana = shortcode == nil ? FuzzyMatch.normalized(query.kana) : []

        struct Ranked {
            var index: Int
            var tier: Tier
            var points: Double
            var preferred: Bool
        }
        var ranked: [Ranked] = []
        for (index, entry) in entries.enumerated() where shape.map({ entry.item.kind.cellShape == $0 }) ?? true {
            var best: (tier: Tier, quality: Int)?
            func consider(_ pattern: [Unicode.Scalar], _ keys: [Key], allowsScattered: Bool) {
                guard !pattern.isEmpty else { return }
                for key in keys {
                    guard let match = FuzzyMatch.match(pattern, in: key.scalars),
                          let candidate = Self.rank(match, field: key.field, pattern: pattern, key: key.scalars, allowsScattered: allowsScattered) else { continue }
                    if best.map({ ($0.tier, $0.quality) < (candidate.tier, candidate.quality) }) ?? true { best = candidate }
                }
            }
            if let shortcode {
                consider(shortcode, entry.shortcodes, allowsScattered: true)
            } else {
                // 飛び飛びの当たりは英数字を 3 文字以上打ったときだけ(短い語やかなでは，関係の薄い項目にまで当たってしまう)
                consider(typed, entry.typedKeys, allowsScattered: typed.count >= DefaultSettings.minimumScatteredPaletteQueryLength)
                consider(kana, entry.kanaKeys, allowsScattered: false)
            }
            let text = entry.item.text
            if ranking.learned.contains(text) {
                best = (.exact, max(best?.quality ?? 0, 0))
            }
            guard let best else { continue }
            let points = Double(best.quality) + Self.usageBonus(ranking.usage[text] ?? 0)
                + (ranking.pinned.contains(text) ? DefaultSettings.palettePinnedBonus : 0)
            ranked.append(Ranked(index: index, tier: best.tier, points: points, preferred: entry.item.kind == ranking.preferredKind))
        }
        ranked.sort { lhs, rhs in
            if lhs.tier != rhs.tier { return lhs.tier > rhs.tier }
            if lhs.points != rhs.points { return lhs.points > rhs.points }
            if lhs.preferred != rhs.preferred { return lhs.preferred }
            return lhs.index < rhs.index
        }
        return ranked.prefix(limit).map { entries[$0.index].item }
    }

    /// 当たりを段と当たりのよさにする．出さない当たりなら nil
    private static func rank(_ match: FuzzyMatch.Match, field: Field, pattern: [Unicode.Scalar], key: [Unicode.Scalar],
                             allowsScattered: Bool) -> (tier: Tier, quality: Int)? {
        let tier: Tier
        switch match.kind {
        case .exact: tier = .exact
        case .prefix: tier = field == .keyword ? .keywordPrefix : .prefix
        case .wordPrefix: tier = .keywordPrefix
        case .substring: tier = .substring
        case .scattered:
            guard allowsScattered, match.score >= DefaultSettings.minimumScatteredMatchScorePerCharacter * pattern.count else { return nil }
            return (.scattered, match.score)
        }
        // 余った文字が少ないほど，探した語そのものに近い
        let quality = pattern.count - key.count + (field == .name ? DefaultSettings.paletteNameMatchBonus : 0)
        return (tier, quality)
    }

    /// よく使う度合いの加点．使う回数が増えても加点は対数でゆっくり増やし，上限で止める(当たりのよさを覆さない)
    static func usageBonus(_ usage: Double) -> Double {
        guard usage > 0 else { return 0 }
        let bonus = DefaultSettings.paletteUsageBonus
        return min(bonus.maximum, bonus.scale * log2(1 + usage))
    }
}

extension PaletteSearch.Query: CustomStringConvertible, CustomDebugStringConvertible {
    // 探した語は入力の中身なので，ログには長さだけを出す
    public var description: String { "Query(typed: \(typed.count), kana: \(kana.count))" }
    public var debugDescription: String { description }
}
