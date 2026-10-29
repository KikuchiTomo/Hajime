import AppKit

/// SF Symbols の記号を，名前・大きさ・太さ・色ごとに一度だけビットマップにして使い回す．
///
/// 記号の画像は描くたびに字形から書き出す(NSImage の bestRepresentation)ので重い．分岐図の足元のキーの案内は，
/// 候補をふわっと出すあいだ 1 秒に 60 回描き直すので，描くたびに作ると Space から分岐図が出るまでが延びた
@MainActor
enum SymbolImageCache {
    private struct Key: Hashable {
        var name: String
        var pointSize: CGFloat
        var weight: CGFloat
        var color: [CGFloat]
        var scale: CGFloat
    }

    private static var images: [Key: NSImage] = [:]
    /// 覚えておく数の上限(色や大きさの組み合わせは限られるので，超えたら捨てて作り直す)
    private static let limit = 256

    static func image(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let rgb = color.usingColorSpace(.deviceRGB)
        let components = rgb.map { [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent] } ?? []
        let key = Key(name: name, pointSize: pointSize, weight: weight.rawValue, color: components, scale: scale)
        if let cached = images[key] { return cached }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight).applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration) else { return nil }
        let size = symbol.size
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((size.width * scale).rounded(.up)), pixelsHigh: Int((size.height * scale).rounded(.up)),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                            bytesPerRow: 0, bitsPerPixel: 0) else { return symbol }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        symbol.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        if images.count >= limit { images.removeAll() }
        images[key] = image
        return image
    }
}
