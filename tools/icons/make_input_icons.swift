// 入力メニューに出すアイコン(テンプレート画像)を作る．プラチナ外観の札と同じく，枠の中に字を置く．
// 使い方: swift tools/icons/make_input_icons.swift <出力先のディレクトリ>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let font = NSFont(name: "BIZUDGothic-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .bold)

func representation(label: String, pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: 16, height: 16)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: 16, height: 16).fill()
    NSColor.black.set()
    // 1 ドットの枠．角は丸めない
    let frame = NSBezierPath(rect: NSRect(x: 1.5, y: 1.5, width: 13, height: 13))
    frame.lineWidth = 1
    frame.stroke()
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let size = label.size(withAttributes: attributes)
    label.draw(at: NSPoint(x: (16 - size.width) / 2, y: (16 - size.height) / 2), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, label) in [("main", "あ"), ("en", "A")] {
    let reps = [representation(label: label, pixels: 16), representation(label: label, pixels: 32)]
    let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0)!
    try data.write(to: output.appendingPathComponent("\(name).tiff"))
    print("wrote \(name).tiff")
}
