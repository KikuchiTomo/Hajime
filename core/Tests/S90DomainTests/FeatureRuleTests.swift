import Foundation
import Testing
@testable import S90Domain

@Suite("計算")
struct CalculatorTests {
    @Test("四則・かっこ・べき乗・小数を計算し，読みの中の全角や長音の記号も読む", arguments: [
        ("1+2*3=", "1+2*3", "7"),
        ("(1+2)*3=", "(1+2)*3", "9"),
        ("2^10=", "2^10", "1024"),
        ("10/4=", "10/4", "2.5"),
        ("１＋２＝", "1+2", "3"),
        ("5ー3=", "5-3", "2"),
        ("6・3＝", "6/3", "2"),
        ("1。5*2＝", "1.5*2", "3"),
    ])
    func evaluates(reading: String, expression: String, result: String) {
        let value = Calculator.evaluate(reading: reading)
        #expect(value?.expression == expression)
        #expect(value?.result == result)
    }

    @Test("式でないもの，0 で割る式，= で終わらないものは計算しない", arguments: ["1+2", "12=", "1/0=", "a+b=", "1++=", "(((((((((((((((((1)))))))))))))))))+1="])
    func rejects(reading: String) {
        #expect(Calculator.evaluate(reading: reading) == nil)
    }
}

@Suite("送り仮名")
struct OkuriganaTests {
    @Test("本則を選べば許容の語を本則にし，許容を選べば本則の語を許容にする")
    func rewrites() {
        #expect(Okurigana.rewrite("会議を行なう", to: .standard) == "会議を行う")
        #expect(Okurigana.rewrite("会議を行う", to: .allowed) == "会議を行なう")
        #expect(Okurigana.rewrite("意見を表わした", to: .standard) == "意見を表した")
        #expect(Okurigana.rewrite("会議を行う", to: .engine) == nil)
    }

    @Test("熟語の中と「行った(いった)」は書き換えない")
    func keepsCompounds() {
        #expect(Okurigana.rewrite("代表した", to: .allowed) == nil)
        #expect(Okurigana.rewrite("学校に行った", to: .allowed) == nil)
    }

    @Test("選んだ付け方の候補を先に並べ，無ければ足す")
    func reorders() {
        let candidates = [Candidate(text: "行なう", readingCount: 4, origin: .engine(id: 0)), Candidate(text: "行う", readingCount: 4, origin: .engine(id: 1))]
        #expect(Okurigana.reorder(candidates, style: .standard).map(\.text) == ["行う", "行なう"])
        #expect(Okurigana.reorder([candidates[0]], style: .standard).map(\.text) == ["行う", "行なう"])
        #expect(Okurigana.reorder(candidates, style: .engine).map(\.text) == ["行なう", "行う"])
    }
}

@Suite("記号の決まり")
struct SymbolRuleTests {
    @Test("既定の決まりで「ー＞」を「→」に，「←＞」を「↔」にまとめる")
    func defaults() {
        let set = SymbolSequenceSet.standard
        #expect(set.match(suffixOf: "あー＞")?.symbol == "→")
        #expect(set.match(suffixOf: "←＞")?.symbol == "↔")
    }

    @Test("利用者の決まりで既定を書き換え，無効にし，足せる．長い決まりは短い決まりでまとめたあとの形で照らし合わせる")
    func overrides() {
        let set = SymbolSequenceSet(rules: [
            SymbolRule(kind: .sequence, input: "->", output: "⟶"),
            SymbolRule(kind: .sequence, input: "<-", output: "", isEnabled: false),
            SymbolRule(kind: .sequence, input: "!=", output: "≠"),
            SymbolRule(kind: .sequence, input: "-->", output: "⟹"),
        ])
        #expect(set.match(suffixOf: "ー＞")?.symbol == "⟶")
        #expect(set.match(suffixOf: "＜ー") == nil)
        #expect(set.match(suffixOf: "！＝")?.symbol == "≠")
        #expect(set.match(suffixOf: "ー⟶")?.symbol == "⟹")
    }

    @Test("読みの決まりで記号を書き換え，無効にできる")
    func readings() {
        #expect(SymbolDictionary.symbols(for: "やじるし", rules: [SymbolRule(kind: .reading, input: "やじるし", output: "→ ⇒")]) == ["→", "⇒"])
        #expect(SymbolDictionary.symbols(for: "こめ", rules: [SymbolRule(kind: .reading, input: "こめ", output: "", isEnabled: false)]).isEmpty)
        #expect(SymbolDictionary.symbols(for: "こめ").contains("※"))
    }

    @Test("組み立て中の読みで，利用者の決まりが効く")
    func composition() {
        var composition = Composition(symbolSequences: SymbolSequenceSet(rules: [SymbolRule(kind: .sequence, input: "->", output: "⟶")]))
        composition.insertRomaji("-")
        composition.insertLiteral("＞")
        #expect(composition.kana == "⟶")
    }
}

@Suite("項目の無い設定のファイル")
struct MissingFieldsTests {
    @Test("項目の無い設定は既定で読む")
    func decoding() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("{}".utf8))
        #expect(settings.keymap == KeymapPreset.standard.keymap)
        #expect(settings.keypadDirect)
        #expect(settings.okuriganaStyle == .standard)
    }
}

@Suite("読み違い")
struct MisreadingTests {
    @Test("よくある読み違いを引き，読みの末尾でも見つける")
    func lookup() {
        #expect(Misreadings.entry(for: "ふいんき")?.word == "雰囲気")
        #expect(Misreadings.suffixEntry(in: "いいふいんき")?.start == 2)
        #expect(Misreadings.entry(for: "ふんいき") == nil)
        #expect(Set(Misreadings.entries.map(\.reading)).count == Misreadings.entries.count)
    }

    @Test("文の途中の言い違いは，変換でかなのまま残った部分だけを言い直す(結った・勇気は言い直さない)")
    func fragments() {
        #expect(Misreadings.fragmentVariants(of: "なんてゆったの", converted: "なんてゆったの") == ["なんていったの"])
        #expect(Misreadings.fragmentVariants(of: "そうゆうこと", converted: "そうゆうこと") == ["そういうこと"])
        #expect(Misreadings.fragmentVariants(of: "かみをゆった", converted: "髪を結った").isEmpty)
        #expect(Misreadings.fragmentVariants(of: "ゆうきがある", converted: "勇気がある").isEmpty)
    }
}

@Suite("補正の決まり")
struct CorrectionCustomizationTests {
    @Test("直さない語は英字と読みのどちらに含まれても当たり，置き換えの決まりは大文字小文字を区別しない")
    func matching() {
        var customization = CorrectionCustomization()
        customization.exceptions = ["kubectl", "ようです"]
        customization.rules = [CorrectionRule(typed: "teh", word: "the")]
        #expect(customization.isException(keys: "runkubectlnow", reading: ""))
        #expect(customization.isException(keys: nil, reading: "そのようです"))
        #expect(!customization.isException(keys: "python", reading: "ぱいそん"))
        #expect(customization.rule(for: "TEH")?.word == "the")
    }

    @Test("崩れた決まりは捨て，残りを読む")
    func decoding() throws {
        let json = #"{"english":false,"rules":[{"typed":"teh","word":"the"},{"typed":"1","word":""},{"bad":true}]}"#
        let value = try JSONDecoder().decode(CorrectionCustomization.self, from: Data(json.utf8))
        #expect(!value.english)
        #expect(value.japanese)
        #expect(value.rules == [CorrectionRule(typed: "teh", word: "the")])
    }
}
