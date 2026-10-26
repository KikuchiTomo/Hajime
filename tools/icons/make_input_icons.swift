// 入力メニューに出すアイコン(テンプレート画像)を作る．
// 使い方: swift tools/icons/make_input_icons.swift <アイコンの出力先> [見本の画像の出力先]
//
// テンプレート画像は黒とアルファだけで描き，色は OS がメニューバーのライト・ダークに合わせて付ける．
// 本番は角丸の面を塗り，字を抜く(「あ」と「A」)．右下の角だけ丸めず，分岐図の幹から枝が出る角に見立てる．
// 開発版は面を塗らずに枠だけにし，字を塗る．本番と並べたときに見分けられるようにする．
// 1x(16px)と 2x(32px)を 1 つの tiff に入れる．
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("使い方: swift tools/icons/make_input_icons.swift <出力先> [見本の出力先]\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1], isDirectory: true)
let previewOutput = arguments.count >= 3 ? URL(fileURLWithPath: arguments[2], isDirectory: true) : nil

/// 1 ドット = 1pt の 16pt 四方で描く
let canvas: CGFloat = 16
let body = NSRect(x: 1, y: 2, width: 14, height: 12)
let radius: CGFloat = 3

enum Glyph {
    case hiragana
    case latin

    var text: String { self == .hiragana ? "あ" : "A" }

    /// 字の大きさと太さ．抜いた字が 16px でも潰れない太さにする
    func font(filled: Bool) -> NSFont {
        switch self {
        case .hiragana:
            return NSFont(name: filled ? "HiraginoSans-W7" : "HiraginoSans-W6", size: 11) ?? .systemFont(ofSize: 11, weight: .bold)
        case .latin:
            let base = NSFont.systemFont(ofSize: 11.5, weight: filled ? .heavy : .bold)
            return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 11.5) } ?? base
        }
    }
}

/// 右下の角だけ丸めない角丸の長方形
func plate(in rect: NSRect) -> NSBezierPath {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: rect.minX + radius, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.minY))
    path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - radius))
    path.appendArc(withCenter: NSPoint(x: rect.maxX - radius, y: rect.maxY - radius), radius: radius, startAngle: 0, endAngle: 90)
    path.line(to: NSPoint(x: rect.minX + radius, y: rect.maxY))
    path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.maxY - radius), radius: radius, startAngle: 90, endAngle: 180)
    path.line(to: NSPoint(x: rect.minX, y: rect.minY + radius))
    path.appendArc(withCenter: NSPoint(x: rect.minX + radius, y: rect.minY + radius), radius: radius, startAngle: 180, endAngle: 270)
    path.close()
    return path
}

/// 字を面の中央に置く．字の見た目の範囲(字面)でそろえる
func drawGlyph(_ glyph: Glyph, filled: Bool, color: NSColor) {
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let attributes: [NSAttributedString.Key: Any] = [.font: glyph.font(filled: filled), .foregroundColor: color]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph.text, attributes: attributes))
    let bounds = CTLineGetImageBounds(line, context)
    context.textPosition = CGPoint(x: body.midX - bounds.width / 2 - bounds.minX, y: body.midY - bounds.height / 2 - bounds.minY)
    CTLineDraw(line, context)
}

/// filled なら面を塗って字を抜く(本番)．そうでなければ枠だけを描いて字を塗る(開発版)
func drawIcon(_ glyph: Glyph, filled: Bool, ink: NSColor) {
    let path = plate(in: filled ? body : body.insetBy(dx: 0.5, dy: 0.5))
    if filled {
        ink.setFill()
        path.fill()
        NSGraphicsContext.current?.compositingOperation = .destinationOut
        drawGlyph(glyph, filled: true, color: .black)
        NSGraphicsContext.current?.compositingOperation = .sourceOver
    } else {
        ink.setStroke()
        path.lineWidth = 1
        path.stroke()
        drawGlyph(glyph, filled: false, color: ink)
    }
}

func bitmap(pixels: Int, points: CGFloat, draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: points, height: points)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let icons: [(name: String, glyph: Glyph, filled: Bool)] = [
    ("main", .hiragana, true), ("en", .latin, true), ("main-dev", .hiragana, false), ("en-dev", .latin, false),
]

for icon in icons {
    let reps = [16, 32].map { pixels in bitmap(pixels: pixels, points: canvas) { drawIcon(icon.glyph, filled: icon.filled, ink: .black) } }
    let data = NSBitmapImageRep.tiffRepresentationOfImageReps(in: reps, using: .lzw, factor: 0)!
    try data.write(to: output.appendingPathComponent("\(icon.name).tiff"))
    print("wrote \(icon.name).tiff")
}

// 見本: メニューバーのライトとダークの色で，実寸(2x)と 8 倍の拡大を並べる
if let previewOutput {
    let scale: CGFloat = 8
    let cell = canvas * scale
    let width = cell * CGFloat(icons.count) + 16 * CGFloat(icons.count + 1)
    let height = (cell + 16 + canvas * 2 + 16) * 2
    let image = NSImage(size: NSSize(width: width, height: height), flipped: true) { _ in
        let rows: [(background: NSColor, ink: NSColor)] = [
            (NSColor(white: 0.93, alpha: 1), NSColor(white: 0, alpha: 0.85)),
            (NSColor(white: 0.16, alpha: 1), NSColor(white: 1, alpha: 0.9)),
        ]
        for (rowIndex, row) in rows.enumerated() {
            let top = CGFloat(rowIndex) * height / 2
            row.background.setFill()
            NSRect(x: 0, y: top, width: width, height: height / 2).fill()
            for (index, icon) in icons.enumerated() {
                let x = 16 + CGFloat(index) * (cell + 16)
                for (size, y) in [(cell, top + 16), (canvas * 2, top + 16 + cell + 8)] {
                    // 16px のビットマップを拡大して，実際のピクセルの粗さを見せる
                    let pixels = size == cell ? 16 : 32
                    let rep = bitmap(pixels: pixels, points: canvas) { drawIcon(icon.glyph, filled: icon.filled, ink: row.ink) }
                    NSGraphicsContext.current?.imageInterpolation = .none
                    rep.draw(in: NSRect(x: x, y: y, width: size, height: size), from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
                }
            }
        }
        return true
    }
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try rep.representation(using: .png, properties: [:])!.write(to: previewOutput.appendingPathComponent("input-icons.png"))
    print("wrote input-icons.png")
}
