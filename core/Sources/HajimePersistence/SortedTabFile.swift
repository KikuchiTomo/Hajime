import Foundation

/// 1 列目(タブまで)の UTF-8 のバイト順に並べた行のファイルを，メモリに写して(mmap)1 列目で引く．
/// 行の頭の位置の表を作って二分探索するので，数十万行のファイルでも 1 つの見出しを引くのは数十回の比較で済む．
/// 取り込んだ辞書(ImportedDictionaryStore)と連想の辞書(AssociationDictionaryStore)の索引に使う
final class SortedTabFile {
    private let data: Data
    private let lineStarts: [Int]

    init?(url: URL) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        self.data = data
        var starts: [Int] = []
        data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
            var start = 0
            for (offset, byte) in buffer.enumerated() where byte == 0x0A {
                if offset > start { starts.append(start) }
                start = offset + 1
            }
            if start < buffer.count { starts.append(start) }
        }
        lineStarts = starts
    }

    var count: Int { lineStarts.count }

    /// 1 列目がちょうど key の行(改行を除く)．ファイルの中の順
    func lines(withKey key: String) -> [String] {
        let key = Array(key.utf8)
        return data.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) -> [String] in
            // 1 列目(タブまで)を key と比べる．小さければ負，同じなら 0，大きければ正
            func compare(_ line: Int) -> Int {
                var position = lineStarts[line]
                for byte in key {
                    guard position < buffer.count else { return -1 }
                    let current = buffer[position]
                    if current == 0x09 { return -1 }
                    if current != byte { return current < byte ? -1 : 1 }
                    position += 1
                }
                return position < buffer.count && buffer[position] == 0x09 ? 0 : 1
            }
            var low = 0
            var high = lineStarts.count
            while low < high {
                let middle = (low + high) / 2
                if compare(middle) < 0 { low = middle + 1 } else { high = middle }
            }
            var result: [String] = []
            var line = low
            while line < lineStarts.count, compare(line) == 0 {
                let start = lineStarts[line]
                var end = start
                while end < buffer.count, buffer[end] != 0x0A { end += 1 }
                result.append(String(decoding: UnsafeRawBufferPointer(rebasing: buffer[start..<end]), as: UTF8.self))
                line += 1
            }
            return result
        }
    }

    /// 行を 1 列目のバイト順に並べて書く．1 列目が同じ行は渡した順のまま(よく使うものを先に書いた順を保つ)
    static func write(_ lines: [String], to url: URL) throws {
        let keyed = lines.enumerated().map { (key: Array(($0.element.split(separator: "\t", maxSplits: 1).first ?? "").utf8), index: $0.offset) }
        let order = keyed.sorted { $0.key == $1.key ? $0.index < $1.index : $0.key.lexicographicallyPrecedes($1.key) }
        var data = Data()
        data.reserveCapacity(lines.reduce(0) { $0 + $1.utf8.count + 1 })
        for item in order {
            data.append(contentsOf: lines[item.index].utf8)
            data.append(0x0A)
        }
        try ProtectedFile.write(data, to: url)
    }
}
