import Testing
@testable import HajimeDomain

@Suite("英語と日本語の混ざった並びを語に分ける")
struct MixedWordSplitTests {
    private let words: Set<String> = ["zoom", "om", "m", "github", "git", "hub", "push", "pus", "nip", "ush"]

    private func split(_ keys: String) -> [String]? {
        MixedWordSplit.split(keys) { words.contains($0) }?.map { $0.isEnglishWord ? "[\($0.keys)]" : $0.keys }
    }

    @Test("R-05: ローマ字として読めない英単語を切り出し，前と後ろをローマ字の語にする")
    func splitsAroundEnglishWord() {
        #expect(split("kyouhazoomdekaigi") == ["kyouha", "[zoom]", "dekaigi"])
        #expect(split("githubnipushsitekara") == ["[github]", "ni", "[push]", "sitekara"])
        #expect(split("zoomde") == ["[zoom]", "de"])
        // 短い英単語を並べる分け方(「nip」+「ush」)より，英単語の少ない分け方にする
        #expect(split("gitnipushsite") == ["[git]", "ni", "[push]", "site"])
    }

    @Test("R-05: 全体を読める並び・英単語だけの並び・辞書にない並びは分けない")
    func keepsWhole() {
        #expect(split("kyouhaiitenki") == nil)
        #expect(split("githubpush") == nil)
        #expect(split("kyouhaslackde") == nil)
        // 大文字はローマ字の語にしない
        #expect(split("kyouhaZoomDE") == nil)
    }
}
