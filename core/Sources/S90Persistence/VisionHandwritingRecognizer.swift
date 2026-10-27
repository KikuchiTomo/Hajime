#if canImport(Vision)
import CoreGraphics
import Foundation
import S90Application
import S90Domain
import Vision

/// 手書きの線を Vision の文字認識で読む(R-14)．認識は端末の中だけで行い，通信しない．
///
/// Vision の文字認識は文書の中の文字列を読むためのもので，大きな枠に 1 字だけ書いた線はほとんど読めない
/// (書く場所の大きさのまま渡すと，十・山・日・木・田などの線を 1 割ほどしか読めなかった)．
/// 線の外接矩形で切り抜き，文書の文字に近い大きさと線の太さに描き直したものを何通りか読ませ，多くの描き方で読めた文字から並べる
public struct VisionHandwritingRecognizer: HandwritingRecognizing {
    /// 候補の数の上限
    static let maximumCandidates = 10
    /// 描き直す文字の高さ(ピクセル)と，高さに対する線の太さの割合．描き方によって読める字が違うので，すべて読ませて合わせる
    static let glyphHeights: [Double] = [32, 48, 64, 96]
    static let lineWidthRatios: [Double] = [0.08, 0.12]
    /// Vision が記号や英字として読みやすい形と，その形に見える漢字・かな．読めた記号のすぐ後ろに足す
    static let lookalikes: [String: [String]] = [
        "+": ["十"], "Y": ["人"], "-": ["一"], "ー": ["一"], "11": ["い"], "<": ["く"], ">": ["く"], "■": ["口"], "□": ["口"],
    ]

    public init() {}

    public func recognize(strokes: [[Point]], canvasSize: Size) async -> [String] {
        let strokes = strokes.filter { !$0.isEmpty }
        guard !strokes.isEmpty else { return [] }
        var images = [Self.render(strokes: strokes, canvasSize: canvasSize)].compactMap { $0 }
        for height in Self.glyphHeights {
            for ratio in Self.lineWidthRatios {
                if let image = Self.renderGlyph(strokes: strokes, height: height, lineWidthRatio: ratio) { images.append(image) }
            }
        }
        var readings: [[String]] = []
        for image in images { readings.append(await Self.recognize(image: image)) }
        return Self.rank(readings)
    }

    /// 描き方ごとに読めた文字を，読めた描き方の多い順(同じなら先に読めた順)に並べ，似た形の漢字・かなを足す
    static func rank(_ readings: [[String]]) -> [String] {
        var votes: [String: Int] = [:]
        var order: [String] = []
        for texts in readings {
            for text in Set(texts) {
                if votes[text] == nil { order.append(text) }
                votes[text, default: 0] += 1
            }
        }
        // Set で重なりを除いたので，同じ描き方の中の順はたどれない．先に読めた順は order が持つ
        let ranked = order.enumerated().sorted { lhs, rhs in
            let (left, right) = (votes[lhs.element, default: 0], votes[rhs.element, default: 0])
            return left != right ? left > right : lhs.offset < rhs.offset
        }.map(\.element)
        var seen = Set<String>()
        var result: [String] = []
        for text in ranked {
            for candidate in [text] + (lookalikes[text] ?? []) where seen.insert(candidate).inserted {
                result.append(candidate)
            }
        }
        return Array(result.prefix(maximumCandidates))
    }

    /// 線を書く場所の大きさのまま，白地に黒で描いた画像にする．横に長い線(一)はこの描き方でしか読めない
    static func render(strokes: [[Point]], canvasSize: Size, scale: Double = 2) -> CGImage? {
        let width = Int(canvasSize.width * scale), height = Int(canvasSize.height * scale)
        guard width > 0, height > 0, strokes.contains(where: { !$0.isEmpty }) else { return nil }
        return draw(strokes: strokes, width: width, height: height, lineWidth: 6 * scale) { point in
            CGPoint(x: point.x * scale, y: point.y * scale)
        }
    }

    /// 線の外接矩形で切り抜き，長い辺を height ピクセルにして，まわりに半分の高さの余白を付けて描く
    static func renderGlyph(strokes: [[Point]], height: Double, lineWidthRatio: Double) -> CGImage? {
        let points = strokes.flatMap { $0 }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
            let minY = points.map(\.y).min(), let maxY = points.map(\.y).max() else { return nil }
        let scale = height / max(maxX - minX, maxY - minY, 1)
        let margin = height / 2
        let width = Int(((maxX - minX) * scale + margin * 2).rounded(.up)), imageHeight = Int(((maxY - minY) * scale + margin * 2).rounded(.up))
        return draw(strokes: strokes, width: width, height: imageHeight, lineWidth: height * lineWidthRatio) { point in
            CGPoint(x: (point.x - minX) * scale + margin, y: (point.y - minY) * scale + margin)
        }
    }

    /// 白地に黒で線を描く．place は線の点(左上が原点)を画像の座標(左上が原点)に移す
    private static func draw(strokes: [[Point]], width: Int, height: Int, lineWidth: Double, place: (Point) -> CGPoint) -> CGImage? {
        guard width > 0, height > 0,
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes where !stroke.isEmpty {
            // CGContext は左下が原点なので，上下を返す
            let points = stroke.map(place).map { CGPoint(x: $0.x, y: Double(height) - $0.y) }
            context.move(to: points[0])
            if points.count == 1 { context.addLine(to: points[0]) }
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
        return context.makeImage()
    }

    /// Vision の認識を動かすキュー．認識は終わるまでスレッドを止めるので，Swift の並行処理のスレッドでは動かさない
    /// (スレッドの少ない環境では，止まったスレッドを Vision の中の仕事が待ち合い，認識が終わらなくなった)
    private static let queue = DispatchQueue(label: "tokyo.s90.handwriting.vision", qos: .userInitiated)

    /// 画像の文字を読む．よさそうな順に，重ねずに返す．
    /// 認識は専用のキューで動かし，DefaultSettings.handwritingRecognitionTimeout を過ぎたら候補なしで返す(入力を止めない)
    static func recognize(image: CGImage, timeout: Double = DefaultSettings.handwritingRecognitionTimeout) async -> [String] {
        let image = SendableImage(image)
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            queue.async { once.resume(recognizeSynchronously(image: image.value)) }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { once.resume([]) }
        }
    }

    static func recognizeSynchronously(image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["ja-JP"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        // 1 字だけでも読む(既定では画像の高さに対して小さすぎる文字を読まない)
        request.minimumTextHeight = 0
        // 端末の中だけで認識する(Vision は通信しない)
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        var seen = Set<String>()
        let texts = (request.results ?? []).flatMap { $0.topCandidates(maximumCandidates).map(\.string) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return Array(texts.prefix(maximumCandidates))
    }

    /// CGImage は作ったあと書き換えないので，キューへ渡してよい
    private struct SendableImage: @unchecked Sendable {
        let value: CGImage
        init(_ value: CGImage) { self.value = value }
    }

    /// 認識の結果と時間切れのうち，先に来た方だけで続きを再開する
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<[String], Never>?

        init(_ continuation: CheckedContinuation<[String], Never>) { self.continuation = continuation }

        func resume(_ texts: [String]) {
            lock.lock()
            let pending = continuation
            continuation = nil
            lock.unlock()
            pending?.resume(returning: texts)
        }
    }
}
#endif
