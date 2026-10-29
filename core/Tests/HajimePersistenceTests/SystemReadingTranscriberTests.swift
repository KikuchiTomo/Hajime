#if canImport(Darwin)
import HajimePersistence
import Testing

@Suite("確定済みの文字の読み(再変換)")
@MainActor
struct SystemReadingTranscriberTests {
    @Test("漢字・かなの混ざった文字をひらがなの読みにする", arguments: [
        ("変換", "へんかん"), ("今日は", "きょうは"), ("カタカナ", "かたかな"),
    ])
    func reading(text: String, expected: String) {
        #expect(SystemReadingTranscriber().reading(of: text) == expected)
    }

    @Test("空の文字は読めない")
    func empty() {
        #expect(SystemReadingTranscriber().reading(of: "") == nil)
    }
}
#endif
