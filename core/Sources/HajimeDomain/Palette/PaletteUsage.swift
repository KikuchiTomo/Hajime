import Foundation

/// パレットで選んだ文字の使い方．よく使う行と，探したときの並びに使う．端末の中にだけ保存する．
///
/// - 使った度合いは，使うたびに 1 を足し，時間がたつほど半減期(DefaultSettings.paletteUsageHalfLife)で減らす．
///   よく使う文字と最近使った文字の両方が高くなる
/// - 探した語ごとに選んだ文字を数え，同じ語で何度も選んだ文字は次から先頭に出す(learnedChoices)
/// - よく使う行は，開いたときだけ作り直し，前に出していた文字は同じ位置に残す(refreshFrequentRow)．
///   位置が変わると，覚えた場所で選べなくなるため．行はマスの形(顔文字と，絵文字・記号)ごとに持つ
/// - 肌の色は基本の形で数える．肌の色を変えても使った度合いは同じ文字に積む
public struct PaletteUsage: Sendable, Equatable {
    struct Record: Sendable, Equatable, Codable {
        /// updatedAt の時点の度合い
        var weight: Double
        /// 1970 年からの秒
        var updatedAt: Double
    }

    private(set) var records: [String: Record] = [:]
    /// 探した語(Query.learningKey)ごとに，選んだ文字と回数
    private(set) var choices: [String: [String: Int]] = [:]
    /// 利用者がピン留めした文字．並びは留めた順
    public private(set) var pinned: [String] = []
    /// 絵文字ごとに選んだ肌の色．選んでいない絵文字は既定の肌の色にする
    private(set) var skinTones: [String: SkinTone] = [:]
    /// 前に開いたときの，マスの形ごとのよく使う行．空の行は持たない
    public private(set) var frequentRows: [PaletteCellShape: [String]] = [:]
    /// 前に見ていたパレットの種類．次に開くときはこの種類で開く
    public var lastKind: PaletteItem.Kind?
    /// 肌の色を変えられる絵文字の既定の肌の色．絵文字ごとに選んだ肌の色があればそちらを使う
    public var defaultSkinTone = SkinTone.none

    public init() {}

    /// 文字を選んだ．text は肌の色を変えていない形．query は探して選んだときの語(探さずに選んだなら nil)
    public mutating func record(_ text: String, query: PaletteSearch.Query? = nil, at date: Date) {
        guard !text.isEmpty else { return }
        let now = date.timeIntervalSince1970
        records[text] = Record(weight: weight(of: text, at: now) + 1, updatedAt: now)
        if let key = query?.learningKey, !key.isEmpty {
            choices[key, default: [:]][text, default: 0] += 1
        }
        prune(at: now)
    }

    /// 今の使った度合い
    public func score(of text: String, at date: Date) -> Double {
        weight(of: text, at: date.timeIntervalSince1970)
    }

    /// すべての文字の今の使った度合い(PaletteSearch.Ranking.usage)
    public func scores(at date: Date) -> [String: Double] {
        let now = date.timeIntervalSince1970
        return records.mapValues { Self.decayed($0, at: now) }
    }

    /// この語で何度も(DefaultSettings.paletteLearnedChoiceCount 回以上)選んだ文字
    public func learnedChoices(for query: PaletteSearch.Query) -> Set<String> {
        Set((choices[query.learningKey] ?? [:]).filter { $0.value >= DefaultSettings.paletteLearnedChoiceCount }.keys)
    }

    // MARK: よく使う行

    /// よく使う行を作り直す．使った度合いの高い順に count 個を選ぶが，前に出していた文字のうち残るものは同じ位置に置き，
    /// 外れた文字の位置に新しい文字を入れる．新しい文字は，外れる文字の度合いを DefaultSettings.paletteFrequentReplacementRatio 倍より
    /// 上回るときだけ入れ替える(少しの差で並びが変わらないようにする)．excluding(ピン留めした文字など)は行に入れない．
    /// 行は shape ごとに持ち，accepting(その形の種類の文字か)に当たる文字だけを入れる
    public mutating func refreshFrequentRow(count: Int, at date: Date, excluding: Set<String> = [], shape: PaletteCellShape = .square,
                                            accepting: (String) -> Bool = { _ in true }) -> [String] {
        let now = date.timeIntervalSince1970
        let scores = records.mapValues { Self.decayed($0, at: now) }.filter { accepting($0.key) }
        let ranked = scores.filter { !excluding.contains($0.key) && $0.value > 0 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map(\.key)
        let top = Array(ranked.prefix(max(count, 0)))
        let topSet = Set(top)
        var row = Array((frequentRows[shape] ?? []).filter { !excluding.contains($0) && scores[$0] != nil }.prefix(max(count, 0)))
        var newcomers = top.filter { !row.contains($0) }
        // 外れた位置に，度合いの高い新しい文字から入れる
        for index in row.indices where !topSet.contains(row[index]) {
            guard let newcomer = newcomers.first else { break }
            let outgoing = scores[row[index]] ?? 0
            if scores[newcomer] ?? 0 > outgoing * DefaultSettings.paletteFrequentReplacementRatio {
                row[index] = newcomer
                newcomers.removeFirst()
            }
        }
        // 空いている枠は後ろに足す
        for newcomer in newcomers where row.count < count {
            row.append(newcomer)
        }
        frequentRows[shape] = row.isEmpty ? nil : row
        return row
    }

    // MARK: ピン留め

    public func isPinned(_ text: String) -> Bool { pinned.contains(text) }

    /// ピン留めする．上限(DefaultSettings.maximumPalettePins)を超えるなら留めない
    @discardableResult
    public mutating func pin(_ text: String) -> Bool {
        guard !text.isEmpty, !pinned.contains(text), pinned.count < DefaultSettings.maximumPalettePins else { return pinned.contains(text) }
        pinned.append(text)
        removeFromFrequentRows(text)
        return true
    }

    public mutating func unpin(_ text: String) {
        pinned.removeAll { $0 == text }
    }

    // MARK: 肌の色

    /// この絵文字に選んだ肌の色．選んでいなければ nil(既定の肌の色を使う)
    public func skinTone(for text: String) -> SkinTone? { skinTones[text] }

    /// この絵文字に使う肌の色．絵文字ごとに選んだ肌の色が無ければ既定の肌の色
    public func effectiveSkinTone(for text: String) -> SkinTone { skinTones[text] ?? defaultSkinTone }

    public mutating func setSkinTone(_ tone: SkinTone?, for text: String) {
        skinTones[text] = tone
    }

    // MARK: 消す

    /// 1 つの文字の履歴を消す(よく使う行からも外す)．ピン留めはそのまま
    public mutating func forget(_ text: String) {
        records[text] = nil
        removeFromFrequentRows(text)
        for key in choices.keys {
            choices[key]?[text] = nil
            if choices[key]?.isEmpty == true { choices[key] = nil }
        }
    }

    /// 履歴をすべて消す．ピン留めと肌の色は利用者が決めたものなので残す
    public mutating func clearHistory() {
        records = [:]
        choices = [:]
        frequentRows = [:]
    }

    private mutating func removeFromFrequentRows(_ text: String) {
        for shape in frequentRows.keys {
            frequentRows[shape]?.removeAll { $0 == text }
            if frequentRows[shape]?.isEmpty == true { frequentRows[shape] = nil }
        }
    }

    // MARK: 計算

    private func weight(of text: String, at now: Double) -> Double {
        records[text].map { Self.decayed($0, at: now) } ?? 0
    }

    /// now の時点まで減らした度合い．時計が戻っていたら減らさない
    private static func decayed(_ record: Record, at now: Double) -> Double {
        let elapsed = max(now - record.updatedAt, 0)
        return record.weight * pow(2, -elapsed / DefaultSettings.paletteUsageHalfLife)
    }

    /// 記録の数を上限に収める．度合いの低いものと，選んだ回数の少ない語から捨てる
    private mutating func prune(at now: Double) {
        if records.count > DefaultSettings.maximumPaletteUsageRecords {
            let kept = records.sorted { Self.decayed($0.value, at: now) > Self.decayed($1.value, at: now) }.prefix(DefaultSettings.maximumPaletteUsageRecords)
            records = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        if choices.count > DefaultSettings.maximumPaletteLearnedQueries {
            let kept = choices.sorted { $0.value.values.reduce(0, +) > $1.value.values.reduce(0, +) }.prefix(DefaultSettings.maximumPaletteLearnedQueries)
            choices = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
    }
}

extension PaletteUsage: Codable {
    private enum CodingKeys: String, CodingKey {
        // frequentRow は四角いマスの行(顔文字を足す前の名前のまま)，wideFrequentRow は顔文字の行
        case records, choices, pinned, skinTones, frequentRow, wideFrequentRow, lastKind, defaultSkinTone
    }

    /// 項目が欠けていても，読めない項目があっても，読める項目だけで始める(壊れた履歴でパレットを開けなくしない)
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = (try? container.decodeIfPresent([String: Record].self, forKey: .records)) ?? [:]
        records = records.filter { $0.value.weight.isFinite && $0.value.updatedAt.isFinite && $0.value.weight >= 0 }
        choices = (try? container.decodeIfPresent([String: [String: Int]].self, forKey: .choices)) ?? [:]
        pinned = Array(((try? container.decodeIfPresent([String].self, forKey: .pinned)) ?? []).prefix(DefaultSettings.maximumPalettePins))
        skinTones = (try? container.decodeIfPresent([String: SkinTone].self, forKey: .skinTones)) ?? [:]
        for (shape, key) in [(PaletteCellShape.square, CodingKeys.frequentRow), (.wide, .wideFrequentRow)] {
            if let row = try? container.decodeIfPresent([String].self, forKey: key), !row.isEmpty { frequentRows[shape] = row }
        }
        lastKind = (try? container.decodeIfPresent(String.self, forKey: .lastKind)).flatMap { $0.flatMap(PaletteItem.Kind.init(rawValue:)) }
        defaultSkinTone = (try? container.decodeIfPresent(SkinTone.self, forKey: .defaultSkinTone)) ?? .none
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(records, forKey: .records)
        try container.encode(choices, forKey: .choices)
        try container.encode(pinned, forKey: .pinned)
        try container.encode(skinTones, forKey: .skinTones)
        try container.encodeIfPresent(frequentRows[.square], forKey: .frequentRow)
        try container.encodeIfPresent(frequentRows[.wide], forKey: .wideFrequentRow)
        try container.encodeIfPresent(lastKind?.rawValue, forKey: .lastKind)
        try container.encode(defaultSkinTone, forKey: .defaultSkinTone)
    }
}

extension PaletteUsage: CustomStringConvertible, CustomDebugStringConvertible {
    // 選んだ文字と探した語は入力の中身なので，ログには数だけを出す
    public var description: String { "PaletteUsage(records: \(records.count), queries: \(choices.count), pinned: \(pinned.count))" }
    public var debugDescription: String { description }
}

extension PaletteSearch.Query {
    /// 同じ語で選んだ文字を覚えるときの鍵．打ったままの英数字があればそれを，無ければ読みを使う
    public var learningKey: String {
        let typed = String(KanaWidth.hiragana(from: typed.lowercased()))
        return typed.isEmpty ? kana : typed
    }
}
