import AppKit
import HajimeApplication

/// 絵文字や記号を，書体の行の高さではなく実際の外形(ink)で箱の真ん中に置く．
/// 絵文字の書体(Apple Color Emoji)は小さい大きさほど字面が書体の大きさより大きく描かれ，行の高さの中でも下と右に寄るので，
/// 行の高さで真ん中に置くと箱の中の余白がそろわない．外形は一度だけ描いて測り，覚えておく(窓ごとに持つ)
@MainActor
final class GlyphFitting {
    private struct Key: Hashable {
        var text: String
        var fontName: String
        var size: CGFloat
    }

    private var inks: [Key: NSRect] = [:]
    /// 覚えておく数の上限(超えたら捨てて測り直す)．マス目の絵文字を描き直すたびに測り直さない数にする
    private let limit = 2048
    /// 外形に数える画素の濃さ(0〜255)．枠線のぼかしの薄い画素は数えず，目に見える形で真ん中に置く
    private static let inkAlpha: UInt8 = 96

    /// text を font で draw(at:) で描いたときの外形．描く原点(行の左上)からの位置
    func ink(_ text: String, font: NSFont) -> NSRect {
        let key = Key(text: text, fontName: font.fontName, size: font.pointSize)
        if let ink = inks[key] { return ink }
        let ink = Self.measure(text, font: font)
        if inks.count >= limit { inks.removeAll() }
        inks[key] = ink
        return ink
    }

    /// 外形の中心が box の中心に来るように描く原点
    func origin(_ text: String, font: NSFont, centeredIn box: NSRect) -> NSPoint {
        let ink = ink(text, font: font)
        let origin = PaletteWindowLayout.centeredOrigin(ink: .init(x: ink.minX, y: ink.minY, width: ink.width, height: ink.height),
                                                        in: .init(x: box.minX, y: box.minY, width: box.width, height: box.height))
        return NSPoint(x: origin.x, y: origin.y)
    }

    /// 外形が box から上下左右に padding を除いた中に収まる大きさの書体(fontName)．大きさは外形を測って詰める
    func font(_ text: String, named fontName: String, fitting box: NSRect, padding: CGFloat) -> NSFont {
        let target = min(box.width, box.height) - padding * 2
        var size = max(target, 1)
        for _ in 0..<3 {
            guard let font = NSFont(name: fontName, size: size) else { return .systemFont(ofSize: max(target, 1)) }
            let ink = ink(text, font: font)
            let extent = max(ink.width, ink.height)
            guard extent > target + 0.25, extent > 0 else { return font }
            size = max((size * target / extent * 2).rounded(.down) / 2, 1)
        }
        return NSFont(name: fontName, size: size) ?? .systemFont(ofSize: size)
    }

    /// 描いた画素から外形を測る(2 倍の解像度)．字が無ければ行の箱
    private static func measure(_ text: String, font: NSFont) -> NSRect {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let size = (text as NSString).size(withAttributes: attributes)
        let margin = font.pointSize
        let scale: CGFloat = 2
        let width = Int(((size.width + margin * 2) * scale).rounded(.up)), height = Int(((size.height + margin * 2) * scale).rounded(.up))
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
            return NSRect(origin: .zero, size: size)
        }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        // 下から margin の位置を行の下の端にして描く．画素の行は上から並ぶので，行の上の端は上から margin の位置
        (text as NSString).draw(at: NSPoint(x: margin, y: margin), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > inkAlpha {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return NSRect(origin: .zero, size: size) }
        return NSRect(x: CGFloat(minX) / scale - margin, y: CGFloat(minY) / scale - margin,
                      width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
    }
}
