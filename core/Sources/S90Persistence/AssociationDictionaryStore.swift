import Foundation
import S90Application
import S90Domain

/// 取り込んだ連想の辞書を，辞書ごとに索引のファイルに置き，語で引く(R-18)．
///
/// 索引のファイルは「見出しの語<タブ>意味の説明<タブ>語<タブ>語…」の行を見出しのバイト順に並べた UTF-8 のテキスト(SortedTabFile)．
/// まとまりの語ごとに，その語を見出しにした行を書く．見出しが同じ行は取り込んだファイルの順(よく使う意味が先)のまま並べる．
/// 起動時には読まず，初めて引くときに開く．
///
/// 同梱の辞書(AssociationDictionary.isBundled)は，アプリに入れた取り込む形のファイル(bundledSource)を裏で読んでメモリに置く．
/// 読み終わるまでと，読めなかったときは何も返さない(連想変換だけが効かなくなり，入力は止めない)
@MainActor
public final class AssociationDictionaryStore: AssociationLookup {
    /// 置き場所(Application Support の associations/)
    public let directory: URL
    private var indexes: [String: SortedTabFile] = [:]
    /// 同梱の辞書のファイル．無ければ同梱の辞書は引けない
    private let bundledSource: URL?
    private var bundled: BundledIndex?
    private var bundledLoading: Task<Void, Never>?

    public init(directory: URL, bundledSource: URL? = nil) {
        self.directory = directory
        self.bundledSource = bundledSource
    }

    /// 同梱の辞書を裏で読み始める．起動時に呼んでおくと，初めて連想変換を使うときに待たない
    public func preloadBundled() {
        guard bundledLoading == nil, let source = bundledSource else { return }
        bundledLoading = Task.detached(priority: .utility) { [weak self] in
            let index = BundledIndex.load(source)
            await self?.finishLoading(index)
        }
    }

    /// 同梱の辞書を読み終わるまで待つ(試す道具とテストのため)
    public func waitForBundled() async {
        preloadBundled()
        await bundledLoading?.value
    }

    private func finishLoading(_ index: BundledIndex?) {
        bundled = index
    }

    public func url(for dictionary: AssociationDictionary) -> URL {
        directory.appendingPathComponent(dictionary.indexFileName)
    }

    /// まとまりを語ごとの行にして索引のファイルに書く
    public nonisolated static func write(_ groups: [AssociationGroup], to url: URL) throws {
        var lines: [String] = []
        for group in groups where group.isValid {
            for word in group.words {
                lines.append(([word, group.label] + group.words.filter { $0 != word }).joined(separator: "\t"))
            }
        }
        try SortedTabFile.write(lines, to: url)
    }

    /// 取り込み直したあとに呼ぶ．開いている索引を閉じ，次に引くときに開き直す
    public func reload(_ dictionary: AssociationDictionary) {
        indexes[dictionary.id] = nil
    }

    public func remove(_ dictionary: AssociationDictionary) {
        indexes[dictionary.id] = nil
        try? FileManager.default.removeItem(at: url(for: dictionary))
    }

    public func groups(for word: String, in dictionary: AssociationDictionary) -> [AssociationGroup] {
        if dictionary.isBundled {
            preloadBundled()
            return bundled?.groups(for: word) ?? []
        }
        guard dictionary.hasValidIdentity, let index = index(for: dictionary) else { return [] }
        return index.lines(withKey: word).compactMap(Self.parse)
    }

    private func index(for dictionary: AssociationDictionary) -> SortedTabFile? {
        if let index = indexes[dictionary.id] { return index }
        guard let index = SortedTabFile(url: url(for: dictionary)) else { return nil }
        indexes[dictionary.id] = index
        return index
    }

    /// 行をまとまりに読む．まとまりの語は見出しを除いたもの．
    /// 索引のファイルを書き換えられていても変な語を出さないよう，取り込むときと同じ確かめをする
    private static func parse(_ line: String) -> AssociationGroup? {
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 3 else { return nil }
        let others = Array(columns.dropFirst(2))
        guard AssociationGroup(label: columns[1], words: [columns[0]] + others).isValid else { return nil }
        return AssociationGroup(label: columns[1], words: others)
    }
}

/// 同梱の辞書をメモリに置いたもの．単語ごとに，その単語を含むまとまりの位置を持つ．作ったあとは変えない
final class BundledIndex: Sendable {
    private let groups: [AssociationGroup]
    private let positions: [String: [Int]]

    init(groups: [AssociationGroup]) {
        var positions: [String: [Int]] = [:]
        for (index, group) in groups.enumerated() {
            for word in group.words { positions[word, default: []].append(index) }
        }
        self.groups = groups
        self.positions = positions
    }

    /// 読めなければ nil．取り込むときと同じ大きさの上限と形の確かめをする(AssociationFileReader)
    static func load(_ url: URL) -> BundledIndex? {
        guard let groups = try? AssociationFileReader.read(from: url) else { return nil }
        return BundledIndex(groups: groups)
    }

    /// word を含むまとまり．まとまりの語は word を除いたもの
    func groups(for word: String) -> [AssociationGroup] {
        (positions[word] ?? []).map { AssociationGroup(label: groups[$0].label, words: groups[$0].words.filter { $0 != word }) }
    }
}
