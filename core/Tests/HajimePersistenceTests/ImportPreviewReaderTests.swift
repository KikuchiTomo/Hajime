import Foundation
import HajimeDomain
import HajimePersistence
import Testing

/// 取り込む前に見せる中身の読み方(R-16・R-18・R-21)．取り込める行は，実際に取り込むときの読み方と同じになる
@Suite("取り込む前に見せる中身")
struct ImportPreviewReaderTests {
    private func preview(_ kind: ImportPreview.Kind, _ text: String) throws -> ImportPreview {
        try ImportPreviewReader.preview(kind, data: Data(text.utf8))
    }

    @Test("R-21: 登録した単語は読み・単語・品詞・コメントの 4 列で読み，品詞の無い行と知らない品詞の行は名詞にする．列の足りない行は読めない")
    func userDictionary() throws {
        let text = """
        !Microsoft IME Dictionary Tool
        やまだ\t山田\t姓\tコメント
        かいしゃ\t会社
        はしる\t走る\t動詞
        じゅうしょ\t住所\t名詞
        # コメントの行は見せない
        ひとつだけ
        漢字\t読みがひらがなでない
        """
        let shown = try preview(.userDictionary, text)
        #expect(shown.format == .tabSeparated)
        #expect(shown.columns == [.reading, .word, .wordClass, .comment])
        #expect(shown.rows == [
            .init(line: 2, cells: ["やまだ", "山田", WordClass.surname.rawValue, "コメント"], status: .ok),
            .init(line: 3, cells: ["かいしゃ", "会社", WordClass.noun.rawValue, ""], status: .defaultedWordClass),
            .init(line: 4, cells: ["はしる", "走る", WordClass.noun.rawValue, ""], status: .defaultedWordClass),
            .init(line: 5, cells: ["じゅうしょ", "住所", WordClass.noun.rawValue, ""], status: .ok),
            .init(line: 7, cells: ["ひとつだけ"], status: .unreadable),
            .init(line: 8, cells: ["漢字", "読みがひらがなでない"], status: .unreadable),
        ])
        #expect((shown.importable, shown.defaulted, shown.unreadable) == (4, 2, 2))
        // 取り込める行は，実際に取り込むときと同じ
        #expect(UserDictionaryFile.parse(text).map(\.word) == shown.rows.filter { $0.status != .unreadable }.map { $0.cells[1] })
    }

    @Test("R-16: 取り込む辞書は読みをひらがなにそろえ，同じ語は 1 つにする．取り込める語は実際に取り込むときと同じ")
    func dictionary() throws {
        let text = """
        トウキョウ\t東京\t地名
        とうきょう\t東京\t地名
        かいしゃ\t会社
        ひとつだけ
        """
        let shown = try preview(.dictionary, text)
        #expect(shown.columns == [.reading, .word, .wordClass])
        #expect(shown.rows.map(\.status) == [.ok, .defaultedWordClass, .unreadable])
        #expect(shown.rows.first?.cells == ["とうきょう", "東京", WordClass.place.rawValue])
        #expect(try DictionaryFileReader.parse(Data(text.utf8)).count == shown.importable)
    }

    @Test("R-16: SKK の辞書は 1 行に並ぶ語を 1 つずつ見せ，送り仮名のある読みの行は読めない")
    func skk() throws {
        let text = """
        ;; okuri-ari entries.
        はしr /走/
        ;; okuri-nasi entries.
        かんじ /漢字/幹事;注釈/
        """
        let shown = try preview(.dictionary, text)
        #expect(shown.format == .skk)
        #expect(shown.columns == [.reading, .word])
        #expect(shown.rows == [
            .init(line: 2, cells: ["はしr /走/"], status: .unreadable),
            .init(line: 4, cells: ["かんじ", "漢字"], status: .ok),
            .init(line: 4, cells: ["かんじ", "幹事"], status: .ok),
        ])
        #expect(try DictionaryFileReader.parse(Data(text.utf8)).count == shown.importable)
    }

    @Test("R-18: 連想の辞書はタブの行の先頭を意味の説明，「,」の行を語として読み，語が 1 つの行は読めない")
    func association() throws {
        let text = """
        明るい\t明るい\t朗らか\t陽気
        嬉しい,楽しい
        ひとつ
        """
        let shown = try preview(.association, text)
        #expect(shown.format == .tabSeparated)
        #expect(shown.columns == [.meaning, .words])
        #expect(shown.rows == [
            .init(line: 1, cells: ["明るい", "明るい、朗らか、陽気"], status: .ok),
            .init(line: 2, cells: ["", "嬉しい、楽しい"], status: .ok),
            .init(line: 3, cells: ["", "ひとつ"], status: .unreadable),
        ])
        #expect(try AssociationFileReader.parse(Data(text.utf8)).count == shown.importable)
    }

    @Test("見せる行は上限までにし，読めない行と名詞にする行を先に残す．数はファイル全体で数える")
    func truncated() throws {
        let limit = DefaultSettings.maximumImportPreviewRows
        let lines = (0..<limit + 10).map { "かいしゃ\t会社\($0)\t名詞" } + ["ひとつだけ"]
        let shown = try preview(.userDictionary, lines.joined(separator: "\n"))
        #expect(shown.rows.count == limit)
        #expect(shown.isTruncated)
        #expect(shown.rows.last?.status == .unreadable)
        #expect((shown.importable, shown.unreadable) == (limit + 10, 1))
    }
}
