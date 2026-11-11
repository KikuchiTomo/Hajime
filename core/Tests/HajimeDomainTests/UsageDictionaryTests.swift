import Testing
@testable import HajimeDomain

@Suite("語の意味と同音異義語の使い分けの辞書")
struct UsageDictionaryTests {
    private let dictionary = UsageDictionary(text: """
        とる\t撮る\t五段・ラ行\t写真を写す。「写真を撮る」
        とる\t取る\t五段・ラ行\t〈採るも参照〉\\n1. 手に持つ。「本を取る」\\n2. 得る。
        とる\t採る\t五段・ラ行\t〈「取る」とも〉選び出す。「「意見」を採る」
        あし\t足\t*\t1. 人間・動物などが移動のために使う部分の総称。\\n2. 足首から下の部分。
        あし\t脚\t*\t足の付け根から足首までを指すときに使う。
        あいず\t合図\t*\t知らせ。
        うごく\t動く\t五段・カ行イ音便\t位置が変わる。「車が動く」
        うごかす\t動かす\t五段・サ行\t位置を変える。「机を動かす」
        よぶ\t呼ぶ\t五段・バ行\t1. 声をかける。「名前を呼ぶ」\\n2. 来させる。\\n3. 名付ける。\\n4. 集める。\\n5. 招く。\\n6. 引き起こす。\t動詞
        しずか\t静か\t*\t音がしないさま。\t形容動詞
        けっこう\t結構\t*\t十分なさま。\t知らない品詞
        壊れた行
        """)

    @Test("活用した形にも当て，意味と例とほかの語を示す", arguments: [
        ("撮った", "とった", HomophoneNote(word: "撮る", meaning: "写真を写す", example: "写真を撮る", others: ["取る", "採る"])),
        ("取る", "とる", HomophoneNote(word: "取る", senses: [.init(meaning: "手に持つ", example: "本を取る"), .init(meaning: "得る")], others: ["撮る", "採る"])),
        ("採る", "とる", HomophoneNote(word: "採る", meaning: "選び出す", example: "「意見」を採る", others: ["撮る", "取る"])),
        ("足が", "あしが", HomophoneNote(word: "足", senses: [.init(meaning: "人間・動物などが移動のために使う部分の総称"), .init(meaning: "足首から下の部分")], others: ["脚"])),
    ])
    func note(text: String, reading: String, expected: HomophoneNote) {
        #expect(dictionary.note(for: text, reading: reading) == expected)
    }

    @Test("意味の頭の注記と番号と補足の行を除き，句点のあとのかぎ括弧だけを例にする", arguments: [
        ("〈「取る」とも〉\\n※補足。\\n1. 手でつかむ。「ボールを取る」", [HomophoneNote.Sense(meaning: "手でつかむ", example: "ボールを取る")]),
        ("「調整する」などの意味で使う。", [HomophoneNote.Sense(meaning: "「調整する」などの意味で使う")]),
        ("知らせ。", [HomophoneNote.Sense(meaning: "知らせ")]),
        ("1. 声をかける。「名前を呼ぶ」\\n2. 来させる。", [.init(meaning: "声をかける", example: "名前を呼ぶ"), .init(meaning: "来させる")]),
    ])
    func senses(description: String, expected: [HomophoneNote.Sense]) {
        #expect(UsageDictionary.senses(of: Substring(description)) == expected)
    }

    @Test("意味は辞書の順に，設定で選べる数の上限まで読む")
    func limitsSenses() throws {
        let note = try #require(dictionary.note(for: "呼ぶ", reading: "よぶ"))
        #expect(note.senses.count == DefaultSettings.meaningSenseLimitRange.upperBound)
        #expect(note.senses.first?.meaning == "声をかける")
    }

    @Test("5 列目の品詞を読む．列が無いか知らない名前なら品詞を付けない", arguments: [
        ("呼ぶ", "よぶ", PartOfSpeech?.some(.verb)),
        ("静か", "しずか", .adjectivalNoun),
        ("結構", "けっこう", nil),
        ("合図", "あいず", nil),
    ])
    func partOfSpeech(text: String, reading: String, expected: PartOfSpeech?) {
        #expect(dictionary.note(for: text, reading: reading)?.partOfSpeech == expected)
    }

    @Test("品詞の名前を読み戻せる")
    func partOfSpeechNames() {
        for partOfSpeech in PartOfSpeech.allCases { #expect(PartOfSpeech(name: partOfSpeech.name) == partOfSpeech) }
        #expect(PartOfSpeech(name: "") == nil)
    }

    @Test("設定に合わせて絞る．意味は 1 つは残す")
    func limited() {
        let note = HomophoneNote(word: "撮る", partOfSpeech: .verb, senses: [.init(meaning: "写す", example: "写真を撮る"), .init(meaning: "撮影する")],
                                 others: ["取る"])
        #expect(note.limited(senseLimit: 5, partOfSpeech: true, examples: true, homophones: true) == note)
        #expect(note.limited(senseLimit: 0, partOfSpeech: false, examples: false, homophones: false)
            == HomophoneNote(word: "撮る", meaning: "写す", others: []))
        #expect(note.limited(senseLimit: 2, partOfSpeech: true, examples: false, homophones: true).senses.map(\.example) == [nil, nil])
    }

    @Test("読み上げの文に品詞を括弧で添える")
    func text() {
        let note = HomophoneNote(word: "撮る", partOfSpeech: .verb, meaning: "写す", example: "写真を撮る", others: ["取る"])
        #expect(note.text == "撮る(動詞): 写す。例「写真を撮る」　ほかに 取る")
    }

    @Test("同じ読みの語が 1 つだけの語(動く)にも，意味だけを示す")
    func meaningWithoutHomophones() {
        #expect(dictionary.note(for: "合図", reading: "あいず") == HomophoneNote(word: "合図", meaning: "知らせ", others: []))
        #expect(dictionary.note(for: "動いた", reading: "うごいた") == HomophoneNote(word: "動く", meaning: "位置が変わる", example: "車が動く", others: []))
    }

    @Test("漢字の部分が同じ語は，送り仮名が長く合う語にする", arguments: [
        ("動かした", "うごかした", "動かす"),
        ("動く", "うごく", "動く"),
        ("動かない", "うごかない", "動く"),
    ])
    func prefersLongerOkurigana(text: String, reading: String, word: String) {
        #expect(dictionary.note(for: text, reading: reading)?.word == word)
    }

    @Test("語の後ろが読みの後ろと合わないもの(足跡・取引)には出さない")
    func noNote() {
        #expect(dictionary.note(for: "足跡", reading: "あしあと") == nil)
        #expect(dictionary.note(for: "取引", reading: "とりひき") == nil)
    }

    @Test("辞書に無い語は，このリポジトリで書いた組で補う")
    func fallsBackToBuiltIn() {
        #expect(UsageGuide.homophoneNote(for: "講演", reading: "こうえん", dictionary: dictionary)?.word == "講演")
        #expect(UsageGuide.homophoneNote(for: "撮った", reading: "とった", dictionary: dictionary)?.senses.first?.meaning == "写真を写す")
    }
}
