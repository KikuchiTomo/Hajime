// 漢字を含む日本語の語の読みを，macOS の日本語の解析(CFStringTokenizer のローマ字の読み)でひらがなにする．
// tools/palette/update.sh がパレットの表を作るときに動かす(アプリの中では動かさない)．
//
// 使い方: swift tools/palette/readings.swift < 語の一覧 > 語<タブ>読み
// 1 行に 1 語を読み，読みがひらがなと長音だけになった語だけを書く(記号や英字が残る語は書かない)．
// 英字を含む語(「AB型」)は英字をローマ字として読んでしまうので，読みを求めない
import Foundation

func reading(of text: String) -> String? {
    let string = text as NSString
    guard let tokenizer = CFStringTokenizerCreate(nil, string, CFRange(location: 0, length: string.length),
                                                  kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja_JP") as CFLocale) else { return nil }
    var result = ""
    while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
        let range = CFStringTokenizerGetCurrentTokenRange(tokenizer)
        let token = string.substring(with: NSRange(location: range.location, length: range.length))
        if token.unicodeScalars.allSatisfy({ (0x3041...0x30FA).contains($0.value) || $0 == "ー" }) {
            // かなの語はそのままひらがなにする(ローマ字を通すと「マーク」が「まあく」になり，長音が消える)
            result += String(String.UnicodeScalarView(token.unicodeScalars.map { (0x30A1...0x30F6).contains($0.value) ? Unicode.Scalar($0.value - 0x60)! : $0 }))
            continue
        }
        guard let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String else {
            result += token
            continue
        }
        let kana = NSMutableString(string: latin)
        CFStringTransform(kana, nil, kCFStringTransformLatinHiragana, false)
        result += kana as String
    }
    let hiragana = result.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || $0 == "ー" }
    return hiragana && !result.isEmpty ? result : nil
}

while let line = readLine() {
    let word = line.trimmingCharacters(in: .whitespaces)
    if !word.isEmpty, !word.contains(where: { $0.isASCII && $0.isLetter }), let kana = reading(of: word) {
        print("\(word)\t\(kana)")
    }
}
