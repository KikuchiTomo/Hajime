#if canImport(Vision)
import CoreGraphics
import CoreText
import Foundation
import S90Domain
import Testing
@testable import S90Persistence

@Suite("手書きの認識(R-14)")
struct HandwritingRecognizerTests {
    /// 既知の文字を書体で描いた画像を Vision に渡し，その文字が候補に入ることを確かめる
    @Test("書いた文字を候補に出す")
    func recognizeKnownCharacters() async {
        let image = Self.image(of: "東京", size: 96)
        let texts = await VisionHandwritingRecognizer.recognize(image: image)
        #expect(texts.contains { $0.contains("東京") })
    }

    @Test("線を白地に黒で描いた画像にする．線が無ければ画像にしない")
    func renderStrokes() {
        let strokes = [[Point(x: 10, y: 10), Point(x: 90, y: 10)], [Point(x: 50, y: 10), Point(x: 50, y: 90)]]
        let image = VisionHandwritingRecognizer.render(strokes: strokes, canvasSize: Size(width: 100, height: 100))
        #expect(image?.width == 200)
        #expect(VisionHandwritingRecognizer.render(strokes: [], canvasSize: Size(width: 100, height: 100)) == nil)
    }

    private static func image(of text: String, size: CGFloat) -> CGImage {
        let width = Int(size) * (text.count + 1), height = Int(size * 1.6)
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("HiraginoSans-W3" as CFString, size, nil)
        let attributed = NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: font])
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: size / 2, y: size / 2)
        CTLineDraw(line, context)
        return context.makeImage()!
    }
}
#endif
