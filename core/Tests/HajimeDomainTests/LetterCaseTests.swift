import Testing
@testable import HajimeDomain

@Suite("英字の大文字と小文字(R-03)")
struct LetterCaseTests {
    @Test("段ごとの見た目", arguments: [
        (LetterCase.asTyped, "pyThon", "pyThon"), (.uppercase, "pyThon", "PYTHON"), (.lowercase, "pyThon", "python"),
        (.capitalized, "pyThon", "Python"), (.uppercase, "ｐｙ", "ＰＹ"), (.capitalized, "", ""),
    ])
    func apply(letterCase: LetterCase, text: String, expected: String) {
        #expect(letterCase.apply(to: text) == expected)
    }

    @Test("見た目が前の段と同じになる段は飛ばして，順に回る", arguments: [
        ("python", [LetterCase.uppercase, .capitalized, .asTyped]),
        ("Python", [.uppercase, .lowercase, .asTyped]),
        ("PYTHON", [.lowercase, .capitalized, .asTyped]),
        ("pyThon", [.uppercase, .lowercase, .capitalized, .asTyped]),
    ])
    func next(text: String, expected: [LetterCase]) {
        var current = LetterCase.asTyped
        var visited: [LetterCase] = []
        for _ in expected {
            current = current.next(for: text)
            visited.append(current)
        }
        #expect(visited == expected)
    }

    @Test("英字が無ければ入力どおりのまま")
    func noLetters() {
        #expect(LetterCase.asTyped.next(for: "123-4") == .asTyped)
    }
}
