import CoreGraphics
import Foundation
import S90Application
import S90Domain
import Vision

/// 手書きの線を Vision の文字認識で読む(R-14)．認識は端末の中だけで行い，通信しない
public struct VisionHandwritingRecognizer: HandwritingRecognizing {
    /// 候補の数の上限
    static let maximumCandidates = 10

    public init() {}

    public func recognize(strokes: [[Point]], canvasSize: Size) async -> [String] {
        guard let image = Self.render(strokes: strokes, canvasSize: canvasSize) else { return [] }
        return await Self.recognize(image: image)
    }

    /// 線を白地に黒で描いた画像にする．認識しやすいよう，線を太めにして余白を付ける
    static func render(strokes: [[Point]], canvasSize: Size, scale: Double = 2) -> CGImage? {
        let width = Int(canvasSize.width * scale), height = Int(canvasSize.height * scale)
        guard width > 0, height > 0, strokes.contains(where: { !$0.isEmpty }),
            let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setStrokeColor(gray: 0, alpha: 1)
        context.setLineWidth(6 * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        for stroke in strokes where !stroke.isEmpty {
            // CGContext は左下が原点なので，上下を返す
            let points = stroke.map { CGPoint(x: $0.x * scale, y: Double(height) - $0.y * scale) }
            context.move(to: points[0])
            if points.count == 1 { context.addLine(to: points[0]) }
            for point in points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        }
        return context.makeImage()
    }

    /// 画像の文字を読む．よさそうな順に，重ねずに返す．Vision は呼んだスレッドで処理するので，メインスレッドの外で行う
    static func recognize(image: CGImage) async -> [String] {
        await Task.detached(priority: .userInitiated) { recognizeSynchronously(image: image) }.value
    }

    static func recognizeSynchronously(image: CGImage) -> [String] {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["ja-JP"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        // 端末の中だけで認識する(Vision は通信しない)
        guard (try? VNImageRequestHandler(cgImage: image).perform([request])) != nil else { return [] }
        var seen = Set<String>()
        let texts = (request.results ?? []).flatMap { $0.topCandidates(maximumCandidates).map(\.string) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return Array(texts.prefix(maximumCandidates))
    }
}
