import Foundation
import HajimeApplication
import HajimeDomain

/// 同梱の辞書の中の専門用語の辞書(terms.tsv)を読みで引く(R-29)．
///
/// ファイルは「読み<タブ>語<タブ>品詞<タブ>分野<タブ>同音」の行を読みのバイト順に並べた UTF-8 のテキスト(SortedTabFile)．
/// 同音は，通常の辞書に同じ読みの語があれば 1．無い列は 1 とみなす(点数を下げる方に倒す)．
/// 同梱の辞書を確かめたあと(BundledDictionary)の場所を渡す．起動時には読まず，初めて引くときに開く．
/// ファイルが無い(古い辞書)か読めなければ，語を返さない
@MainActor
public final class TermDictionaryStore: TermDictionaryLookup {
    private let url: URL
    private var file: SortedTabFile?
    private var opened = false

    public init(url: URL) {
        self.url = url
    }

    public func words(reading: String) -> [TermWord] {
        if !opened {
            opened = true
            file = SortedTabFile(url: url)
        }
        return file?.lines(withKey: reading).compactMap(Self.parse) ?? []
    }

    /// 1 行を語にする．知らない分野(この版より新しい辞書の分野)と，取り込んだ辞書と同じ確かめに通らない語は使わない
    static func parse(_ line: String) -> TermWord? {
        let columns = line.split(separator: "\t", omittingEmptySubsequences: false)
        guard columns.count >= 4, let field = TermField(rawValue: String(columns[3])) else { return nil }
        let word = DictionaryWord(reading: String(columns[0]), word: String(columns[1]), wordClass: WordClass(rawValue: String(columns[2])) ?? .noun)
        let hasHomophones = columns.count < 5 || columns[4] != "0"
        return word.isValid ? TermWord(word: word, field: field, hasHomophones: hasHomophones) : nil
    }
}
