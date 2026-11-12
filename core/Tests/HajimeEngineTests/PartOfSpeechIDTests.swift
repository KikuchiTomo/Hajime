import Foundation
import HajimeDomain
import HajimeEngine
import KanaKanjiConverterModuleWithDefaultDictionary
import Testing

/// 登録した語の品詞から決めるエンジンの品詞の ID が，本体の辞書の同じ品詞の語と同じかを確かめる．
/// 名前の無い ID(サ変名詞など)は数で書いているので，辞書を替えたときにずれていないか見張る
@Suite("品詞の ID")
struct PartOfSpeechIDTests {
    @Test("登録した語の品詞の ID は，本体の辞書の同じ品詞の語の ID と同じ", arguments: [
        (WordClass.suruNoun, "べんきょう", "勉強"), (.adjectivalNoun, "きれい", "綺麗"), (.adverb, "とても", "迚も"),
        (.interjection, "ああ", "嗚呼"), (.noun, "かいしゃ", "会社"), (.surname, "やまだ", "山田"), (.givenName, "たろう", "太郎"),
        (.place, "とうきょう", "東京"),
    ])
    func matchesDictionary(wordClass: WordClass, reading: String, word: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-pos-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let converter = KanaKanjiConverter.withDefaultDictionary()
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        let options = ConvertRequestOptions(N_best: 10, requireJapanesePrediction: .disabled, requireEnglishPrediction: .disabled,
                                            keyboardLanguage: .ja_JP, englishCandidateInRoman2KanaInput: false, fullWidthRomanCandidate: false,
                                            halfWidthKanaCandidate: false, learningType: .nothing, maxMemoryCount: 0, shouldResetMemory: false,
                                            memoryDirectoryURL: directory, sharedContainerURL: directory, textReplacer: .empty,
                                            specialCandidateProviders: nil, metadata: nil)
        let candidates = converter.requestCandidates(composing, options: options).mainResults
        let element = try #require(candidates.first { $0.text == word && $0.data.count == 1 }?.data.first)
        #expect(element.lcid == AzooKeyConverterEngine.partOfSpeechID(for: wordClass))
    }
}
