#if canImport(Darwin)
import Foundation
import HajimeApplication

/// 確定済みの文字の読みを，OS の日本語の解析(CFStringTokenizer のローマ字の読み)で求める(再変換)．
/// 語ごとにローマ字の読みを取り，ひらがなにする．読みの無い記号などはそのまま残す(かなでない読みは InputSession が断る)
@MainActor
public final class SystemReadingTranscriber: ReadingTranscribing {
    public init() {}

    public func reading(of text: String) -> String? {
        guard !text.isEmpty else { return nil }
        let string = text as NSString
        guard let tokenizer = CFStringTokenizerCreate(nil, string, CFRange(location: 0, length: string.length),
                                                      kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja_JP") as CFLocale) else { return nil }
        var reading = ""
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            let token = string.substring(with: NSRange(location: range.location, length: range.length))
            guard let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String else {
                reading += token
                continue
            }
            let kana = NSMutableString(string: latin)
            CFStringTransform(kana, nil, kCFStringTransformLatinHiragana, false)
            reading += kana as String
        }
        return reading.isEmpty ? nil : reading
    }
}
#endif
