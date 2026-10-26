#if os(Windows)
import CWindowsSpellCheck
import S90Application
import S90Domain

/// Windows のスペルチェッカー(ISpellChecker)を英単語の辞書として使う(R-02．macOS の SpellCheckerLexicon と同じ役)．
/// 調べるのは端末の中だけで，外部には送らない．スペルチェッカーが使えなければ，どの語も英単語とは答えず，候補も出さない
@MainActor
public final class WindowsSpellCheckerLexicon: EnglishLexicon {
    /// スペルチェッカーを開けたか
    public let isAvailable: Bool
    /// 開けなかったときの理由の番号(s90_spell_open の戻り値．-3 は英語のスペルチェッカーが入っていない)
    public let openStatus: Int32

    public init() {
        let language = Array(DefaultSettings.englishSpellCheckLanguage.utf16) + [0]
        openStatus = s90_spell_open(language)
        isAvailable = openStatus == 0
    }

    public func isWord(_ text: String) -> Bool {
        guard isAvailable, !text.isEmpty else { return false }
        let units = Array(text.utf16)
        return s90_spell_is_word(units, Int32(units.count)) == 1
    }

    public func suggestions(for text: String) -> [String] {
        guard isAvailable, !text.isEmpty else { return [] }
        let units = Array(text.utf16)
        let count = DefaultSettings.maximumSpellingSuggestions
        // 候補ごとに綴りの長さの上限と区切りの改行が入る大きさ
        var buffer = [UInt16](repeating: 0, count: count * (DefaultSettings.maximumCorrectionLength + DefaultSettings.maximumCorrectionDistance + 1))
        let written = s90_spell_suggestions(units, Int32(units.count), &buffer, Int32(buffer.count), Int32(count))
        guard written > 0 else { return [] }
        return String(decoding: buffer[0..<Int(written)], as: UTF16.self).split(separator: "\n").map(String.init)
    }
}
#endif
