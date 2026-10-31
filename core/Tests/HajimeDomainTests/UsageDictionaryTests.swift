import Testing
@testable import HajimeDomain

@Suite("同音異義語の使い分けの辞書")
struct UsageDictionaryTests {
    private let dictionary = UsageDictionary(text: """
        とる\t撮る\t五段・ラ行\t写真を写す。「写真を撮る」
        とる\t取る\t五段・ラ行\t1. 手に持つ。「本を取る」\\n2. 得る。
        あし\t足\t*\t1. 人間・動物などが移動のために使う部分の総称。\\n2. 足首から下の部分。
        あし\t脚\t*\t足の付け根から足首までを指すときに使う。
        あいず\t合図\t*\t知らせ。
        壊れた行
        """)

    @Test("活用した形にも当て，最初の意味とほかの語を示す", arguments: [
        ("撮った", "とった", "撮る: 写真を写す。「写真を撮る」　ほかに 取る"),
        ("取る", "とる", "取る: 手に持つ。「本を取る」　ほかに 撮る"),
        ("足が", "あしが", "足: 人間・動物などが移動のために使う部分の総称。　ほかに 脚"),
    ])
    func note(text: String, reading: String, expected: String) {
        #expect(dictionary.note(for: text, reading: reading) == expected)
    }

    @Test("語の後ろが読みの後ろと合わないもの(足跡)と，同じ読みの語が 1 つだけのもの(合図)には出さない")
    func noNote() {
        #expect(dictionary.note(for: "足跡", reading: "あしあと") == nil)
        #expect(dictionary.note(for: "取引", reading: "とりひき") == nil)
        #expect(dictionary.note(for: "合図", reading: "あいず") == nil)
    }

    @Test("辞書に無い語は，このリポジトリで書いた組で補う")
    func fallsBackToBuiltIn() {
        #expect(UsageGuide.homophoneNote(for: "講演", reading: "こうえん", dictionary: dictionary)?.hasPrefix("講演:") == true)
        #expect(UsageGuide.homophoneNote(for: "撮った", reading: "とった", dictionary: dictionary)?.hasPrefix("撮る: 写真を写す") == true)
    }
}
