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

    /// 書く場所(360×260)に大きく 1 字だけ書いた線．書く場所の大きさのまま読ませていたときは，どれも読めなかった
    @Test("大きく 1 字だけ書いた線を読む", arguments: ["木", "田", "し"])
    func recognizeHandwrittenCharacter(expected: String) async throws {
        let strokes = try #require(Self.handwritten[expected])
        let texts = await VisionHandwritingRecognizer().recognize(strokes: strokes, canvasSize: Size(width: 360, height: 260))
        #expect(texts.contains(expected))
    }

    @Test("多くの描き方で読めた文字から並べ，記号に見える形には漢字・かなを添える")
    func rankReadings() {
        let ranked = VisionHandwritingRecognizer.rank([["+"], ["木", "+"], ["木"], ["木"]])
        #expect(ranked == ["木", "+", "十"])
    }

    @Test("線を白地に黒で描いた画像にする．線が無ければ画像にしない")
    func renderStrokes() {
        let strokes = [[Point(x: 10, y: 10), Point(x: 90, y: 10)], [Point(x: 50, y: 10), Point(x: 50, y: 90)]]
        let image = VisionHandwritingRecognizer.render(strokes: strokes, canvasSize: Size(width: 100, height: 100))
        #expect(image?.width == 200)
        #expect(VisionHandwritingRecognizer.render(strokes: [], canvasSize: Size(width: 100, height: 100)) == nil)
        // 切り抜いて描き直すと，長い辺が指定の高さになり，まわりに半分の高さの余白が付く
        let glyph = VisionHandwritingRecognizer.renderGlyph(strokes: strokes, height: 48, lineWidthRatio: 0.1)
        #expect(glyph?.width == 96)
        #expect(glyph?.height == 96)
    }

    /// 指で書いたように，細かい点で少しゆらした線
    private static func segment(_ start: Point, _ end: Point) -> [Point] {
        (0...20).map { step in
            let t = Double(step) / 20
            let wobble = sin(t * 7) * 1.5
            return Point(x: start.x + (end.x - start.x) * t + wobble, y: start.y + (end.y - start.y) * t - wobble)
        }
    }

    /// 点を順に結んだ 1 画
    private static func line(_ points: Point...) -> [Point] {
        zip(points, points.dropFirst()).flatMap { pair in segment(pair.0, pair.1) }
    }

    private static let handwritten: [String: [[Point]]] = [
        "木": [
            line(Point(x: 110, y: 100), Point(x: 250, y: 100)), line(Point(x: 180, y: 50), Point(x: 180, y: 230)),
            line(Point(x: 178, y: 105), Point(x: 110, y: 200)), line(Point(x: 182, y: 105), Point(x: 250, y: 200)),
        ],
        "田": [
            line(Point(x: 120, y: 60), Point(x: 120, y: 210)), line(Point(x: 120, y: 60), Point(x: 240, y: 60), Point(x: 240, y: 210)),
            line(Point(x: 180, y: 60), Point(x: 180, y: 210)), line(Point(x: 120, y: 135), Point(x: 240, y: 135)),
            line(Point(x: 120, y: 208), Point(x: 240, y: 208)),
        ],
        "し": [line(Point(x: 150, y: 50), Point(x: 150, y: 170), Point(x: 175, y: 205), Point(x: 250, y: 170))],
    ]

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
