import Foundation

/// 連想の辞書の 1 つの意味のまとまり(R-18)．同じ意味の語・関わりの深い語を並べる
public struct AssociationGroup: Sendable, Equatable, Hashable {
    /// 意味の説明(語義)．空なら説明を出さない
    public var label: String
    /// よく使う順の語
    public var words: [String]

    public init(label: String, words: [String]) {
        self.label = label
        self.words = words
    }

    /// 説明と語の長さが上限以内で，タブと改行を含まない(索引のファイルの区切りのため)．語は 2 つ以上
    public var isValid: Bool {
        words.count >= 2 && words.count <= DefaultSettings.maximumAssociationGroupWords
            && label.count <= DefaultSettings.maximumAssociationLabelLength && !Self.containsSeparator(label)
            && words.allSatisfy { !$0.isEmpty && $0.count <= DefaultSettings.maximumAssociationWordLength && !Self.containsSeparator($0) }
    }

    private static func containsSeparator(_ text: String) -> Bool {
        text.contains { $0 == "\t" || $0.isNewline }
    }
}

extension AssociationGroup: CustomStringConvertible, CustomDebugStringConvertible {
    // 語は入力内容と同じに扱うので，ログには数だけを出す
    public var description: String { "AssociationGroup(words: \(words.count))" }
    public var debugDescription: String { description }
}

/// 変換中の語から引いた連想．元の語(見出し)と，意味ごとのまとまり
public struct Associations: Sendable, Equatable {
    public var headword: String
    public var groups: [AssociationGroup]

    public init(headword: String, groups: [AssociationGroup]) {
        self.headword = headword
        self.groups = groups
    }

    /// まとまりを辞書から引いた順に並べ，見出しと同じ語と，前のまとまりに出た語を除き，全部で limit 語までにする．
    /// 語の残らないまとまりは捨てる．何も残らなければ nil
    public static func make(headword: String, groups: [AssociationGroup], limit: Int) -> Associations? {
        var seen: Set<String> = [headword]
        var remaining = max(limit, 0)
        var result: [AssociationGroup] = []
        for group in groups where remaining > 0 {
            let words = group.words.filter { seen.insert($0).inserted }.prefix(remaining)
            guard !words.isEmpty else { continue }
            remaining -= words.count
            result.append(AssociationGroup(label: group.label, words: Array(words)))
        }
        return result.isEmpty ? nil : Associations(headword: headword, groups: result)
    }
}

extension Associations: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "Associations(groups: \(groups.count))" }
    public var debugDescription: String { description }
}

/// 連想の一覧で選んでいる位置．語は意味のまとまりの順につないで 1 列に並べ，
/// 上下で 1 語ずつ(まとまりをまたぐ)，左右でまとまりを移る．1 ページにはひとつのまとまりの語だけを出す
public struct AssociationList: Sendable, Equatable {
    public let associations: Associations
    /// 全体の中で選んでいる語の位置
    public private(set) var index = 0
    /// まとまりごとの，全体の中での先頭の位置
    private let starts: [Int]
    private let count: Int

    public init(_ associations: Associations) {
        self.associations = associations
        var starts: [Int] = []
        var total = 0
        for group in associations.groups {
            starts.append(total)
            total += group.words.count
        }
        self.starts = starts
        self.count = total
    }

    /// 選んでいる語のまとまりの位置
    public var groupIndex: Int { starts.lastIndex { $0 <= index } ?? 0 }
    public var group: AssociationGroup { associations.groups[groupIndex] }
    /// まとまりの中で選んでいる位置
    public var indexInGroup: Int { index - starts[groupIndex] }
    public var selectedWord: String { group.words[indexInGroup] }

    /// 1 語ずつ送る．端では反対の端に戻る
    public mutating func move(by offset: Int) {
        guard count > 0 else { return }
        index = ((index + offset) % count + count) % count
    }

    /// まとまりを移り，その先頭を選ぶ．端では反対の端に戻る
    public mutating func moveGroup(by offset: Int) {
        let groups = starts.count
        guard groups > 0 else { return }
        index = starts[((groupIndex + offset) % groups + groups) % groups]
    }

    /// まとまりの中を perPage 語ずつのページで送る．まとまりの端を越えたら隣のまとまりに移る
    /// (次へは先頭のページ，前へは最後のページ)
    public mutating func movePage(by offset: Int, perPage: Int) {
        guard perPage > 0, count > 0 else { return }
        let page = indexInGroup / perPage + offset
        let pages = (group.words.count + perPage - 1) / perPage
        if (0..<pages).contains(page) {
            index = starts[groupIndex] + page * perPage
        } else if offset > 0 {
            moveGroup(by: 1)
        } else {
            moveGroup(by: -1)
            index = starts[groupIndex] + (group.words.count - 1) / perPage * perPage
        }
    }

    public mutating func selectFirst() { index = 0 }
    public mutating func selectLast() { index = max(count - 1, 0) }

    /// 今のページの語と，その中で選んでいる位置
    public func page(perPage: Int) -> (words: [String], selected: Int) {
        let perPage = max(perPage, 1)
        let start = indexInGroup / perPage * perPage
        let words = Array(group.words[start..<min(start + perPage, group.words.count)])
        return (words, indexInGroup - start)
    }

    /// 今のページの number 番目(1 から)を選ぶ．範囲の外なら false
    public mutating func select(number: Int, perPage: Int) -> Bool {
        let perPage = max(perPage, 1)
        let target = indexInGroup / perPage * perPage + number - 1
        guard number >= 1, number <= perPage, group.words.indices.contains(target) else { return false }
        index = starts[groupIndex] + target
        return true
    }
}

extension AssociationList: CustomStringConvertible, CustomDebugStringConvertible {
    public var description: String { "AssociationList(index: \(index), words: \(count))" }
    public var debugDescription: String { description }
}

/// 連想の辞書 1 つの設定(R-18)．アプリに同梱した辞書と，利用者が取り込んだ辞書がある．
/// 語そのものは別のファイル(同梱のファイルか取り込んだ索引)に置き，設定には入れない．一覧の並び順が優先度(上ほど先に出す)
public struct AssociationDictionary: Sendable, Equatable, Codable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var isEnabled: Bool
    /// 取り込んだまとまり(意味)の数．同梱の辞書は 0
    public var groupCount: Int
    /// アプリに同梱した辞書か．同梱の辞書は消せない(オフにはできる)
    public var isBundled: Bool

    public init(id: String, name: String, isEnabled: Bool = true, groupCount: Int, isBundled: Bool = false) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.groupCount = groupCount
        self.isBundled = isBundled
    }

    private enum CodingKeys: String, CodingKey { case id, name, isEnabled, groupCount, isBundled }

    /// 項目を足しても前に保存した設定を読めるよう，無い項目は既定にする
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        groupCount = try container.decodeIfPresent(Int.self, forKey: .groupCount) ?? 0
        isBundled = try container.decodeIfPresent(Bool.self, forKey: .isBundled) ?? false
    }

    /// 索引のファイルの名前．id は取り込むときに作る UUID．設定のファイルを手で書き換えて
    /// UUID の形でない id(「../」などでパスを差し込むもの)にしたものは，設定を読むときに捨てる(hasValidIdentity)
    public var indexFileName: String { "\(id).tsv" }

    public var hasValidIdentity: Bool { UUID(uuidString: id) != nil && id.count == 36 }
}
