import Testing
@testable import HajimeDomain

@Suite("同音異義語の使い分けの辞書")
struct UsageDictionaryTests {
    private let dictionary = UsageDictionary(text: """
        とる\t撮る\t五段・ラ行\t写真を写す。「写真を撮る」
        とる\t取る\t五段・ラ行\t〈採るも参照〉\\n1. 手に持つ。「本を取る」\\n2. 得る。
        とる\t採る\t五段・ラ行\t〈「取る」とも〉選び出す。「「意見」を採る」
        あし\t足\t*\t1. 人間・動物などが移動のために使う部分の総称。\\n2. 足首から下の部分。
        あし\t脚\t*\t足の付け根から足首までを指すときに使う。
        あいず\t合図\t*\t知らせ。
        壊れた行
        """)

    @Test("活用した形にも当て，最初の意味と例とほかの語を示す", arguments: [
        ("撮った", "とった", HomophoneNote(word: "撮る", meaning: "写真を写す", example: "写真を撮る", others: ["取る", "採る"])),
        ("取る", "とる", HomophoneNote(word: "取る", meaning: "手に持つ", example: "本を取る", others: ["撮る", "採る"])),
        ("採る", "とる", HomophoneNote(word: "採る", meaning: "選び出す", example: "「意見」を採る", others: ["撮る", "取る"])),
        ("足が", "あしが", HomophoneNote(word: "足", meaning: "人間・動物などが移動のために使う部分の総称", others: ["脚"])),
    ])
    func note(text: String, reading: String, expected: HomophoneNote) {
        #expect(dictionary.note(for: text, reading: reading) == expected)
    }

    @Test("意味の頭の注記と番号と補足の行を除き，句点のあとのかぎ括弧だけを例にする", arguments: [
        ("〈「取る」とも〉\\n※補足。\\n1. 手でつかむ。「ボールを取る」", "手でつかむ", Optional("ボールを取る")),
        ("「調整する」などの意味で使う。", "「調整する」などの意味で使う", nil),
        ("知らせ。", "知らせ", nil),
    ])
    func firstMeaning(description: String, meaning: String, example: String?) {
        let result = UsageDictionary.firstMeaning(of: Substring(description))
        #expect(result.meaning == meaning)
        #expect(result.example == example)
    }

    @Test("語の後ろが読みの後ろと合わないもの(足跡)と，同じ読みの語が 1 つだけのもの(合図)には出さない")
    func noNote() {
        #expect(dictionary.note(for: "足跡", reading: "あしあと") == nil)
        #expect(dictionary.note(for: "取引", reading: "とりひき") == nil)
        #expect(dictionary.note(for: "合図", reading: "あいず") == nil)
    }

    @Test("辞書に無い語は，このリポジトリで書いた組で補う")
    func fallsBackToBuiltIn() {
        #expect(UsageGuide.homophoneNote(for: "講演", reading: "こうえん", dictionary: dictionary)?.word == "講演")
        #expect(UsageGuide.homophoneNote(for: "撮った", reading: "とった", dictionary: dictionary)?.meaning == "写真を写す")
    }
}
