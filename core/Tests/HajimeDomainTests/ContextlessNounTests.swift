import HajimeDomain
import Testing

@Suite("左の文脈が無い 1 語の名詞の第 1 候補")
struct ContextlessNounTests {
    private static func candidate(_ text: String, readingCount: Int = 2, commonNoun: Bool = false, id: Int = 0) -> Candidate {
        Candidate(text: text, readingCount: readingCount, origin: .engine(id: id),
                  words: [Candidate.Word(text: text, readingCount: readingCount, startsWithNoun: commonNoun, isCommonNoun: commonNoun)])
    }

    @Test("第 1 候補が読みのかなのままなら，Zenzai を使わない変換の一般名詞を先頭に移し，かなをすぐ後ろに置く")
    func movesNounToFront() {
        let candidates = [Self.candidate("いえ"), Self.candidate("家", commonNoun: true, id: 1), Self.candidate("言え")]
        let result = ContextlessNoun.reordered(candidates, reading: "いえ") { Self.candidate("家", commonNoun: true, id: 9) }
        #expect(result.map(\.text) == ["家", "いえ", "言え"])
        // 候補にあればその候補を動かす(確定したときに Zenzai の候補として学ぶ)
        #expect(result.first?.origin == .engine(id: 1))
    }

    @Test("候補に無い名詞は先頭に足す")
    func insertsMissingNoun() {
        let result = ContextlessNoun.reordered([Self.candidate("はし"), Self.candidate("走")], reading: "はし") {
            Self.candidate("橋", commonNoun: true)
        }
        #expect(result.map(\.text) == ["橋", "はし", "走"])
    }

    @Test("名詞でない語・かなの語・語が 2 つ以上の候補・第 1 候補がかなでないときは変えない", arguments: [
        ("たぶん", "多分", false, 1), ("ありがとう", "ありがとう", false, 1), ("いえ", "いえ", true, 1), ("いえ", "家", true, 2),
    ])
    func keeps(reading: String, plain: String, commonNoun: Bool, words: Int) {
        let candidates = [Self.candidate(reading, readingCount: reading.count), Self.candidate(plain, readingCount: reading.count)]
        var noun = Self.candidate(plain, readingCount: reading.count, commonNoun: commonNoun)
        if words == 2 {
            noun.words = [Candidate.Word(text: "家", readingCount: 1, isCommonNoun: true), Candidate.Word(text: "", readingCount: 1)]
        }
        #expect(ContextlessNoun.reordered(candidates, reading: reading) { noun } == candidates)
        let kanjiFirst = [Self.candidate("家", commonNoun: true), Self.candidate("いえ")]
        #expect(ContextlessNoun.reordered(kanjiFirst, reading: "いえ") { noun } == kanjiFirst)
    }
}
