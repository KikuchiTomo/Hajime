/// 単語と変換マクロに書ける書き方(TextTemplate)のチップ(R-21・R-22)．まとまりごとに，書き方・意味・今の値を求める書き方を並べる．
/// 文言は各 OS の画面の側(UIStrings・strings.rs)に置き，ここには押した書き方を欄の語に足す決まりだけを置く
public struct TemplateReference: Sendable, Equatable {
    /// まとまりの種類．押したときの足し方が変わる
    public enum Kind: Sendable, Equatable {
        /// `{date}` のような書き方．押すと語の末尾に足す
        case syntax
        /// `|upper` のような値の変え方．語の最後の書き方の中に足す
        case filter
        /// `YYYY` のような日時の書式の記号．語の最後の日時の書き方の書式に足す
        case formatSymbol
    }

    public struct Item: Sendable, Hashable, Identifiable {
        /// チップに出す書き方(`{date}`・`|upper`・`YYYY`)
        public var code: String
        public var meaning: String
        /// チップに添える今の値を求める書き方．語の最後に足せる書き方が無いときは，これを末尾に足す
        public var sample: String
        /// 値がコード(UUID・16 進数・Base64 など)で，等幅の書体で出す
        public var isCodeValue: Bool

        public var id: String { code }

        /// sample を省くと code と同じにする(`{date}` のような書き方)
        public init(_ code: String, _ meaning: String, sample: String? = nil, codeValue: Bool = false) {
            self.code = code
            self.meaning = meaning
            self.sample = sample ?? code
            self.isCodeValue = codeValue
        }
    }

    public struct Group: Sendable, Equatable {
        public var title: String
        public var kind: Kind
        public var items: [Item]

        public init(title: String, kind: Kind, items: [Item]) {
            self.title = title
            self.kind = kind
            self.items = items
        }
    }

    public var groups: [Group]

    public init(_ groups: [Group]) {
        self.groups = groups
    }

    /// item を押したときの語．text は欄の入力位置より前の文字．
    /// 打ちかけの書き方(`{da`・`{reading|ka`・`{date:YY`)があれば，その打ちかけの部分を置き換える．
    /// 無ければ，書き方は末尾に足し，値の変え方と書式の記号は語の最後の書き方に足せれば足し，足せなければ sample を末尾に足す
    public static func inserting(_ item: Item, kind: Kind, into text: String) -> String {
        let typing = TextTemplate.typing(before: text)
        switch kind {
        case .syntax:
            guard case .name(let name) = typing else { return text + item.code }
            return String(text.dropLast(name.count + 1)) + item.code
        case .filter:
            let filter = item.code.drop { $0 == "|" }
            switch typing {
            case .filter(let typed): return String(text.dropLast(typed.count + 1)) + "|" + filter
            case .some: return text + "|" + filter
            case nil: return TextTemplate.addingFilter(String(filter), to: text) ?? text + item.sample
            }
        case .formatSymbol:
            switch typing {
            case .format(let typed): return String(text.dropLast(typed.count)) + item.code
            case .name(let name) where TextTemplate.acceptsFormat(name): return text + ":" + item.code
            case .some: return text + item.code
            case nil: return TextTemplate.addingFormatSymbol(item.code, to: text) ?? text + item.sample
            }
        }
    }

    /// 欄の文字の書き換え．range(UTF-16 の位置)を replacement に置き換える
    public struct Edit: Sendable, Equatable {
        public var range: Range<Int>
        public var replacement: String

        public init(range: Range<Int>, replacement: String) {
            self.range = range
            self.replacement = replacement
        }
    }

    /// 欄で selection(UTF-16 の位置．入力位置なら空の範囲)を選んでいるときに item を押した書き換え．
    /// 選んでいる部分を消し，入力位置より前の文字に inserting をかける．書き換える範囲は変わる部分だけにする(取り消しで戻せるように)
    public static func insertion(of item: Item, kind: Kind, in text: String, selection: Range<Int>) -> Edit {
        let utf16 = Array(text.utf16)
        let lower = min(max(selection.lowerBound, 0), utf16.count)
        let upper = min(max(selection.upperBound, lower), utf16.count)
        let prefix = String(decoding: utf16[..<lower], as: UTF16.self)
        let inserted = inserting(item, kind: kind, into: prefix)
        let common = zip(prefix, inserted).prefix { $0 == $1 }.count
        let start = prefix.prefix(common).utf16.count
        return Edit(range: start..<upper, replacement: String(inserted.dropFirst(common)))
    }

    /// 打ちかけの書き方に当たるチップ(まとまりの順)．絞り込まないとき(打ちかけでない・名前をまだ打っていない・
    /// 日時でない引数を打っている)は nil．
    /// 名前を打ちかけているあいだ(`{da`)は，当たる名前ごとに最初のチップを 1 つずつ並べる(date・datetime・days)．
    /// 名前を打ち終えたら(`{date`)，ずらす量や引数を付けたものも並べる
    public func matches(for typing: TextTemplate.Typing?) -> [Match]? {
        let accepts: (Kind, String) -> Bool
        var onePerName = false
        switch typing {
        case .name(let typed) where !typed.isEmpty:
            let lowered = typed.lowercased()
            let names = Set(groups.filter { $0.kind == .syntax }.flatMap(\.items).map { TextTemplate.name(of: String($0.code.dropFirst().dropLast())) })
            onePerName = !names.contains(lowered) && !lowered.contains { "+-@:".contains($0) }
            accepts = { kind, code in kind == .syntax && code.dropFirst().lowercased().hasPrefix(lowered) }
        case .filter(let typed):
            accepts = { kind, code in kind == .filter && code.dropFirst().lowercased().hasPrefix(typed.lowercased()) }
        case .format(let typed):
            // 書式の記号は大文字と小文字で意味が違う(M は月，m は分)
            accepts = { kind, code in kind == .formatSymbol && code.hasPrefix(typed) }
        default:
            return nil
        }
        var seen: Set<String> = []
        return groups.flatMap { group in
            group.items.compactMap { item in
                guard accepts(group.kind, item.code) else { return nil }
                let key = onePerName ? TextTemplate.name(of: String(item.code.dropFirst().dropLast())) : item.code
                guard seen.insert(key).inserted else { return nil }
                return Match(item: item, kind: group.kind)
            }
        }
    }

    /// 絞り込みで当たったチップと，その押したときの足し方
    public struct Match: Sendable, Equatable, Identifiable {
        public var item: Item
        public var kind: Kind

        public var id: String { item.code }

        public init(item: Item, kind: Kind) {
            self.item = item
            self.kind = kind
        }
    }
}
