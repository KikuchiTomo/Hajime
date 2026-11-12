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

        /// ショートコードに使う文字か(英小文字・数字・「_」「+」「-」)
        public static func isShortcodeCharacter(_ character: Character) -> Bool {
            character.isASCII && (character.isLowercase || character.isNumber || "_+-".contains(character))
        }

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
    /// 絵文字の名前の読みと読み(normalized の形)ごとの，項目の位置と名前の読みで当たったか(emoji(reading:) が引く)
    private let emojiByReading: [String: [(index: Int, isName: Bool)]]
    /// 絵文字の文字ごとの項目の位置と，同じ意味の語の一覧(emoji(reading:word:) が名前の照らし合わせを通さずに出す)
    private let emojiByText: [String: Int]
    private let synonyms: EmojiSynonyms

    public init(catalog: PaletteCatalog, synonyms: EmojiSynonyms = EmojiSynonyms()) {
        var emojiByReading: [String: [(index: Int, isName: Bool)]] = [:]
        var emojiByText: [String: Int] = [:]
        for (index, item) in catalog.items.enumerated() where item.kind == .emoji {
            if emojiByText[item.text] == nil { emojiByText[item.text] = index }
            var seen = Set<String>()
            for (reading, isName) in [(item.nameReading, true)] + item.readings.map({ ($0, false) }) where !reading.isEmpty {
                let key = String(String.UnicodeScalarView(FuzzyMatch.normalized(reading)))
                if seen.insert(key).inserted { emojiByReading[key, default: []].append((index, isName)) }
            }
        }
        self.emojiByReading = emojiByReading
        self.emojiByText = emojiByText
        self.synonyms = synonyms
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

    /// 読みと同じ読み(名前の読みか読み)を持つ絵文字．かな漢字変換の候補に足すのに使う．前方一致では出さない(関係の薄い絵文字を出さないため)．
    /// word を渡すと，その語が絵文字の名前の語と合うものに限る(EmojiRelevance．翼の「空」のような連想の読みで出さないため)．
    /// 同じ意味の語の一覧(EmojiSynonyms)にある絵文字は，名前の照らし合わせを通さずに出す(コーヒー → ☕)．
    /// 並びは，この読みで何度も選んだもの(ranking.learned)を先にし，次に一覧の絵文字を一覧の順に，そのあとは search と同じく，
    /// 名前の読みで当たったか・よく使う度合い・ピン留めの点の順．点が同じなら表の順
    public func emoji(reading: String, word: EmojiWord? = nil, ranking: Ranking = Ranking(), limit: Int) -> [PaletteItem] {
        guard limit > 0 else { return [] }
        let hits = emojiByReading[String(String.UnicodeScalarView(FuzzyMatch.normalized(reading)))] ?? []
        var listed: [Int] = []
        for text in word.map({ synonyms.emoji(reading: reading, word: $0) }) ?? [] {
            if let index = emojiByText[text], !listed.contains(index) { listed.append(index) }
        }
        let relevant = word.map { word in
            hits.filter { !listed.contains($0.index) && EmojiRelevance.matches(entries[$0.index].item, reading: reading, word: word) }
        } ?? hits
        let candidates = listed.map { (index: $0, isName: false) } + relevant
        let ranked = candidates.map { hit -> (index: Int, learned: Bool, order: Int, points: Double) in
            let text = entries[hit.index].item.text
            let points = (hit.isName ? Double(DefaultSettings.paletteNameMatchBonus) : 0) + Self.usageBonus(ranking.usage[text] ?? 0)
                + (ranking.pinned.contains(text) ? DefaultSettings.palettePinnedBonus : 0)
            return (hit.index, ranking.learned.contains(text), listed.firstIndex(of: hit.index) ?? listed.count, points)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.learned != rhs.learned { return lhs.learned }
            if lhs.order != rhs.order { return lhs.order < rhs.order }
            if lhs.points != rhs.points { return lhs.points > rhs.points }
            return lhs.index < rhs.index
        }.prefix(limit).map { entries[$0.index].item }
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
