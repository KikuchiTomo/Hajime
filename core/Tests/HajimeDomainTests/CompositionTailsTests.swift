import HajimeDomain
import Testing

/// 打ったキーの末尾の部分(Composition.tails)を条件で絞って取り出しても，すべて取り出してから同じ条件で選ぶのと同じになること．
/// 長い読みで打鍵ごとに全部の部分を文字列にしないための絞り込みなので，結果を変えてはならない
@Suite("打ったキーの末尾の部分の絞り込み")
struct CompositionTailsTests {
    private static let samples = [
        "kyouhapthondesu", "gitwotukau", "jvascriptdekaku", "kyouhaqqqtenkidesu", "konopythonnobajonha", "reactwotukattearu",
        "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "watasihaasitatoukyoudekaigininisyussekisimasu", "xqzvkyouha", "minnnanoikennwohannneisuru",
    ]

    private static func isLowercaseLetter(_ character: Character) -> Bool {
        character.isASCII && character.isLowercase && character.isLetter
    }

    /// keys を 1 キーずつ打ち，打つたびに確かめる
    private func eachStep(_ keys: String, _ check: (Composition) -> Void) {
        var composition = Composition()
        for key in keys {
            if key.isUppercase || key.isNumber {
                composition.insertLiteral(String(key), rawKey: key)
            } else {
                composition.insertRomaji(key)
            }
            check(composition)
        }
    }

    @Test("読めない並びを含む部分とキーの数で絞っても，あとから選んだときと同じ", arguments: samples)
    func invalidRomajiAndLength(keys: String) {
        eachStep(keys) { composition in
            let all = composition.tails()
            for maximum in [4, 8, 24] {
                #expect(composition.tails(maximumKeyCount: maximum, requiresInvalidRomaji: true)
                    == all.filter { $0.containsInvalidRomaji && $0.keys.count <= maximum })
            }
            #expect(composition.tails(requiresInvalidRomaji: true) == all.filter(\.containsInvalidRomaji))
        }
    }

    @Test("英小文字だけの部分で絞っても，あとから選んだときと同じ", arguments: samples + ["konoAPIwotukau", "userNamewotukau", "v2nisuru"])
    func lowercaseLetters(keys: String) {
        eachStep(keys) { composition in
            let all = composition.tails()
            #expect(composition.tails(requiresLowercaseLetters: true) == all.filter { $0.keys.allSatisfy(Self.isLowercaseLetter) })
            #expect(composition.tails(requiresInvalidRomaji: true, requiresLowercaseLetters: true)
                == all.filter { $0.containsInvalidRomaji && $0.keys.allSatisfy(Self.isLowercaseLetter) })
        }
    }

    @Test("部分の印(読めない並びを含むか・読めない文字で始まるか)は，その部分のかなから決まる", arguments: samples)
    func flags(keys: String) {
        eachStep(keys) { composition in
            let kana = Array(composition.kana)
            for tail in composition.tails() {
                let tailKana = kana[tail.kanaStart...]
                #expect(tail.containsInvalidRomaji == tailKana.contains { $0.isASCII && $0.isLetter })
                #expect(tail.startsWithUnconvertible == (tailKana.first.map { $0.isASCII && $0.isLetter } ?? false))
                #expect(tail.keys == String(Array(composition.rawKeys ?? "")[tail.rawStart...]))
            }
        }
    }
}
