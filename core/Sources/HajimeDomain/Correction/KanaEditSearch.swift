/// かなの単位の訂正．言い違い・聞き違い・書き違いのように，打ったキーは読みのとおりでも読みそのものが違う誤り
/// (「なんてゆったの」→ 言った，「そうゆう」→ そういう)を探す．
///
/// 言葉の一覧は持たない．変換で語にならずかなのまま残った部分(spans)のかなを 1 か所だけ変えた読みを全部作り，
/// 文全体の言語モデルの点数から変えた手間を引いた値で選ぶ(KeyEditSearch と同じ尺度．ReadingCorrectionRule がそのまま比べる)．
/// 手間は，かなの音の違い(KanaPhonetics．子音と母音の違い)で決める(ゆ → い は 1.5，ゆ → ま は 2 で置き換えない)．音が同じ書き分け(ず → づ)は小さくする．
/// 直した読みはキーの並び(KanaRomanizer)にして返すので，そのあとはキーの訂正と同じ道筋で直す・示す
public enum KanaEditSearch {
    public struct Edit: Sendable, Equatable {
        public var reading: String
        public var cost: Double
        /// 変えたところ(直した読みの中の位置)．直したあとにここが語になったかを確かめるのに使う
        public var changed: Range<Int>
    }

    public struct Costs: Sendable {
        /// 置き換えで，音の違い(KanaPhonetics.distance)1 つごとの手間
        public var substitutionPerDifference = DefaultSettings.kanaEditCosts.substitutionPerDifference
        /// 置き換えてよい音の違いの上限．これより遠い字には置き換えない
        public var maximumPhoneticDistance = DefaultSettings.kanaEditCosts.maximumPhoneticDistance
        public var insertion = DefaultSettings.kanaEditCosts.insertion
        public var deletion = DefaultSettings.kanaEditCosts.deletion
        public var transposition = DefaultSettings.kanaEditCosts.transposition
        /// 音が変わらない書き分けの誤り(ず → づ・お → を)
        public var samePronunciation = DefaultSettings.keyEditCosts.samePronunciation

        public init() {}
    }

    /// spans の中のかなを 1 か所変えた読み．spans は読みの中の位置(文字数)の範囲．元と同じ読みは除き，同じ読みは手間の小さい方を残す
    public static func edits(of reading: String, in spans: [Range<Int>], costs: Costs = Costs()) -> [Edit] {
        let characters = Array(reading)
        let originalSound = KeyEditSearch.pronunciation(of: reading)
        var best: [String: Edit] = [:]
        func record(_ edited: [Character], cost: Double, changed: Range<Int>) {
            let text = String(edited)
            guard text != reading, !edited.isEmpty else { return }
            let cost = KeyEditSearch.pronunciation(of: text) == originalSound ? min(cost, costs.samePronunciation) : cost
            if let existing = best[text], existing.cost <= cost { return }
            best[text] = Edit(reading: text, cost: cost, changed: changed)
        }
        for span in spans {
            let lower = max(0, span.lowerBound), upper = min(characters.count, span.upperBound)
            guard lower < upper else { continue }
            for index in lower..<upper {
                guard KanaRomanizer.spelling(of: characters[index]) != nil else { continue }
                // 置き換え: 音が近い字だけ(KanaPhonetics)
                for kana in KanaRomanizer.singleKana where kana != characters[index] {
                    guard let distance = KanaPhonetics.distance(characters[index], kana), distance <= costs.maximumPhoneticDistance else { continue }
                    var edited = characters
                    edited[index] = kana
                    record(edited, cost: distance * costs.substitutionPerDifference, changed: index..<(index + 1))
                }
                // 余分な字
                var removed = characters
                removed.remove(at: index)
                record(removed, cost: costs.deletion, changed: max(0, index - 1)..<min(removed.count, index + 1))
                // 隣と入れ替え(ふいんき → ふんいき)
                if index + 1 < upper {
                    var swapped = characters
                    swapped.swapAt(index, index + 1)
                    record(swapped, cost: costs.transposition, changed: index..<(index + 2))
                }
            }
            // 抜けた字(範囲の前後も含めて補う)．抜けやすいのは特殊拍(っ・ん・ー)と，隣の字と綴りが近い字(同じ音の繰り返し・伸ばす音)．
            // どの字も補うと候補が千を超えて遅くなる(1 回 1 秒)ので，音の作りで絞る
            for index in lower...upper {
                let neighbors = [index > 0 ? characters[index - 1] : nil, index < characters.count ? characters[index] : nil]
                    .compactMap { $0 }.compactMap(KanaRomanizer.spelling(of:))
                for kana in KanaRomanizer.singleKana {
                    guard let spelling = KanaRomanizer.spelling(of: kana),
                        specialMora.contains(kana) || neighbors.contains(where: { EditDistance.damerauLevenshtein($0, spelling) <= 1 }) else { continue }
                    var inserted = characters
                    inserted.insert(kana, at: index)
                    record(inserted, cost: costs.insertion, changed: index..<(index + 1))
                }
            }
        }
        return Array(best.values)
    }

    /// 特殊拍(促音・撥音・長音)．単独で拍になり，抜けやすい
    static let specialMora: Set<Character> = ["っ", "ん", "ー"]

    /// spans の中のかなを 1 か所変えた読みを，変わったところの前後のもっともらしさで limit 件に絞り，言語モデルで採点する．
    /// 点数は「言語モデルの点数 - 手間 × costScale」(KeyEditSearch.corrections と同じ)．キーの並びにできない読みは除く．
    /// 打ったままの読みは入れない(キーの訂正の候補に入っている)
    /// unconverted は読みを変換したときに語にならなかった部分．直した読みのうち，変えたところが語になったものだけを残す
    /// (語にならなかった部分を語にするための直しなので．「これゆうです」→「これです」のように語にならない直しは採らない)
    public static func corrections(
        of reading: String,
        in spans: [Range<Int>],
        limit: Int = DefaultSettings.kanaEditCandidateCount,
        costScale: Double = DefaultSettings.keyEditCostScale,
        plausibility: (String) -> Double,
        unconverted: (String) -> [Range<Int>],
        languageModel: ([String]) -> [Double?]
    ) -> [ReadingCorrection] {
        scoredCorrections(ranked: rankedEdits(of: reading, in: spans, limit: limit, plausibility: plausibility, unconverted: unconverted),
                          costScale: costScale, languageModel: languageModel)
    }

    /// 言語モデルにかける候補(直した読みとそのキーの並び)
    public struct RankedEdit: Sendable, Equatable {
        public var edit: Edit
        public var keys: String
    }

    /// corrections の 1 段目．かなを 1 か所変えた読みを，変わったところの前後のもっともらしさで limit 件に絞る．
    /// 言語モデルを使わないので，言語モデルで採点する処理と並べて動かせる
    public static func rankedEdits(
        of reading: String,
        in spans: [Range<Int>],
        limit: Int = DefaultSettings.kanaEditCandidateCount,
        plausibility: (String) -> Double,
        unconverted: (String) -> [Range<Int>]
    ) -> [RankedEdit] {
        guard !spans.isEmpty else { return [] }
        let scored: [(edit: Edit, local: Double)] = edits(of: reading, in: spans).map { edit in
            (edit: edit, local: KeyEditSearch.localGain(of: edit.reading, over: reading, plausibility: plausibility) - edit.cost)
        }
        let sorted = scored.sorted { $0.local != $1.local ? $0.local > $1.local : $0.edit.reading < $1.edit.reading }
        var ranked: [RankedEdit] = []
        for item in sorted where ranked.count < limit {
            guard let keys = KanaRomanizer.keys(for: item.edit.reading),
                !unconverted(item.edit.reading).contains(where: { $0.overlaps(item.edit.changed) }) else { continue }
            ranked.append(RankedEdit(edit: item.edit, keys: keys))
        }
        return ranked
    }

    /// corrections の 2 段目．絞った候補を言語モデルで採点する
    public static func scoredCorrections(
        ranked: [RankedEdit],
        costScale: Double = DefaultSettings.keyEditCostScale,
        languageModel: ([String]) -> [Double?]
    ) -> [ReadingCorrection] {
        guard !ranked.isEmpty else { return [] }
        let scores = languageModel(ranked.map(\.keys))
        return zip(ranked, scores).compactMap { item, score in
            score.map { ReadingCorrection(keys: item.keys, reading: KanaWidth.katakana(from: item.edit.reading),
                                          score: $0 - item.edit.cost * costScale, cost: item.edit.cost * costScale, isReadingEdit: true) }
        }
    }
}
