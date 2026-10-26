import Foundation
import S90Application
import S90Domain
import S90Engine
import Testing

/// 本物の辞書で変換できることを確かめる結合テスト．変換の質そのものは確かめない
@Suite("azooKey のエンジン")
@MainActor
struct AzooKeyConverterAdapterTests {
    private func makeEngine() throws -> AzooKeyConverterEngine {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-engine-\(UUID().uuidString)")
        return try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "s90.tokyo IME tests")
    }

    @Test("読み全体を変換した候補を返す")
    func converts() throws {
        let session = try makeEngine().makeSession()
        let candidates = session.candidates(for: "へんかん")
        #expect(candidates.contains { $0.text == "変換" && $0.readingCount == 4 })
    }

    @Test("文の先頭の文節だけの候補も返す")
    func firstClause() throws {
        let session = try makeEngine().makeSession()
        let candidates = session.candidates(for: "きょうはいいてんきです")
        #expect(candidates.contains { $0.readingCount < 11 })
        #expect(candidates.first?.readingCount == 11)
    }

    @Test("R-16: 取り込んだ辞書の語を渡すと，文の中の語として候補に出る")
    func auxiliaryWords() throws {
        let session = try makeEngine().makeSession()
        let word = AuxiliaryWord(word: DictionaryWord(reading: "でんあつ", word: "電圧ピヨ", wordClass: .noun), costOffset: 0)
        #expect(!session.candidates(for: "でんあつをはかる").contains { $0.text.hasPrefix("電圧ピヨ") })
        session.setAuxiliaryWords([word])
        #expect(session.candidates(for: "でんあつをはかる").contains { $0.text.hasPrefix("電圧ピヨ") })
        session.setAuxiliaryWords([])
        #expect(!session.candidates(for: "でんあつをはかる").contains { $0.text.hasPrefix("電圧ピヨ") })
    }

    @Test("R-16: 本体の辞書に無い読みの取り込んだ辞書の語も，文の途中で候補に出る")
    func auxiliaryWordsOutsideDefaultDictionary() throws {
        // 「ぴえぞでんき」は本体の辞書に 1 語としては無い読み．エンジンが本体の辞書の続きだけをたどると，読み全体と一致したときにしか出ない．
        // 「ピエゾ」と「電気」をつないだ候補と見分けるため，語は本体の辞書から作れない表記にする
        let session = try makeEngine().makeSession()
        let word = AuxiliaryWord(word: DictionaryWord(reading: "ぴえぞでんき", word: "ピヨ圧電", wordClass: .noun), costOffset: 0)
        #expect(!session.candidates(for: "ぴえぞでんきをつかう").contains { $0.text.contains("ピヨ圧電") })
        session.setAuxiliaryWords([word])
        #expect(session.candidates(for: "ぴえぞでんきをつかう").contains { $0.text.contains("ピヨ圧電") })
        #expect(session.candidates(for: "これはぴえぞでんきをつかう").contains { $0.text.contains("ピヨ圧電") })
    }

    @Test("空の読みには何も返さない")
    func empty() throws {
        #expect(try makeEngine().makeSession().candidates(for: "").isEmpty)
    }

    @Test("学習のディレクトリは本人だけが使える権限で作る")
    func permissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("s90-engine-\(UUID().uuidString)")
        _ = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "test")
        let permissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o700)
    }
}
