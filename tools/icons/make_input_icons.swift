// 入力メニューに出すアイコン(テンプレート画像)を作る．プラチナ外観の札と同じく，枠の中に字を置く．
// 使い方: swift tools/icons/make_input_icons.swift <出力先のディレクトリ>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let font = NSFont(name: "BIZUDGothic-Regular", size: 12) ?? NSFont.systemFont(ofSize: 12, weight: .bold)

/// dashed が真なら点線の枠にする(開発版の印．本番のアイコンと見分けるため)
func representation(label: String, pixels: Int, dashed: Bool) -> NSBitmapImageRep {
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
    if dashed {
        frame.setLineDash([2, 1], count: 2, phase: 0)
    }
    frame.stroke()
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let size = label.size(withAttributes: attributes)
    label.draw(at: NSPoint(x: (16 - size.width) / 2, y: (16 - size.height) / 2), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, label) in [("main", "あ"), ("en", "A")] {
    for (suffix, dashed) in [("", false), ("-dev", true)] {
        let reps = [16, 32].map { representation(label: label, pixels: $0, dashed: dashed) }
        let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0)!
        try data.write(to: output.appendingPathComponent("\(name)\(suffix).tiff"))
        print("wrote \(name)\(suffix).tiff")
    }
}
