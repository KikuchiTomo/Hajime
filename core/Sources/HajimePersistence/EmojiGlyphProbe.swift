#if canImport(CoreText)
import CoreText
import Foundation

/// OS の絵文字の書体がその絵文字を 1 つの字として描けるか(R-26．macOS)．新しいバージョンの絵文字は，OS が古いと
/// 部品に分かれて描かれるか別の書体で代わりに描かれるので，パレットとかな漢字変換の候補に出さない．
/// アプリ(パレットの表を読むとき)と hajime-playground が同じ確かめ方をする．CoreText はどのスレッドからでも使える
public enum EmojiGlyphProbe {
    /// macOS の絵文字の書体
    public static let fontName = "AppleColorEmoji"

    public static func canRender(_ text: String, size: Double) -> Bool {
        let font = CTFontCreateWithName(fontName as CFString, CGFloat(size), nil)
        let string = NSAttributedString(string: text, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(string)
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun], runs.count == 1, CTRunGetGlyphCount(runs[0]) == 1 else { return false }
        var glyph = CGGlyph()
        CTRunGetGlyphs(runs[0], CFRange(location: 0, length: 1), &glyph)
        guard glyph != 0 else { return false }
        // 絵文字の書体に無い字は，OS が別の書体で代わりに描く．代わりの書体で描いた字は描けないものとする
        let attributes = CTRunGetAttributes(runs[0]) as NSDictionary
        guard let value = attributes[kCTFontAttributeName as String], CFGetTypeID(value as CFTypeRef) == CTFontGetTypeID() else { return false }
        // 型を CTFontGetTypeID で確かめたので，必ず CTFont になる
        let used = CTFontCopyPostScriptName(value as! CTFont) as String
        return used == fontName
    }
}
#endif
