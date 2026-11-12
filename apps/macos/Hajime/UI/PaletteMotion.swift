import AppKit
import HajimeApplication

/// パレットの窓の動き(R-26)．core が添えた PalettePanel.Motion から，滑る印・送る中身・弾む部品の動きを作り，
/// 時刻ごとの途中の位置と濃さを返す．時刻は CACurrentMediaTime の秒．
///
/// 動いているあいだは PaletteView が画面のリフレッシュごとに，動いている部品の範囲だけを描き直す(窓全体は描き直さない)
struct PaletteMotionState {
    /// 印が from から今の位置へ滑る動き
    struct Slide {
        var from: NSRect
        var start: CFTimeInterval
        var duration: CFTimeInterval
    }

    /// 部品が弾む・浮かび上がる動き
    struct Pop {
        var start: CFTimeInterval
        var duration: CFTimeInterval
    }

    /// マス目の中身を送る動き．前の中身を出ていかせ，今の中身を入れる
    struct ContentSwap {
        var previous: PalettePanel
        var direction: PalettePanel.Motion.Content
        var start: CFTimeInterval
        var duration: CFTimeInterval
    }

    var selection: Slide?
    var mode: Slide?
    var tab: Slide?
    var content: ContentSwap?
    var picker: Pop?
    var pin: Pop?

    var isActive: Bool { selection != nil || mode != nil || tab != nil || content != nil || picker != nil || pin != nil }

    /// 終わった動きを除く
    mutating func prune(at time: CFTimeInterval) {
        if let slide = selection, Self.progress(slide.start, slide.duration, at: time) >= 1 { selection = nil }
        if let slide = mode, Self.progress(slide.start, slide.duration, at: time) >= 1 { mode = nil }
        if let slide = tab, Self.progress(slide.start, slide.duration, at: time) >= 1 { tab = nil }
        if let swap = content, Self.progress(swap.start, swap.duration, at: time) >= 1 { content = nil }
        if let pop = picker, Self.progress(pop.start, pop.duration, at: time) >= 1 { picker = nil }
        if let pop = pin, Self.progress(pop.start, pop.duration, at: time) >= 1 { pin = nil }
    }

    /// 0 から 1 までの進み具合．長さが 0 なら終わっている
    static func progress(_ start: CFTimeInterval, _ duration: CFTimeInterval, at time: CFTimeInterval) -> CGFloat {
        guard duration > 0 else { return 1 }
        return CGFloat(min(max((time - start) / duration, 0), 1))
    }

    /// 滑っている印の今の位置．滑っていなければ target
    static func rect(_ slide: Slide?, to target: NSRect, at time: CFTimeInterval, easing: (CGFloat) -> CGFloat) -> NSRect {
        guard let slide else { return target }
        let t = easing(progress(slide.start, slide.duration, at: time))
        return NSRect(x: slide.from.minX + (target.minX - slide.from.minX) * t, y: slide.from.minY + (target.minY - slide.from.minY) * t,
                      width: slide.from.width + (target.width - slide.from.width) * t, height: slide.from.height + (target.height - slide.from.height) * t)
    }
}

/// 動きの速さの変わり方．どれも 0 で 0，1 で 1 になる(bounce を除く)
enum PaletteEasing {
    /// 速く動き出して静かに止まる(選択の枠・中身を送る)
    static func easeOut(_ t: CGFloat) -> CGFloat {
        1 - pow(1 - t, 3)
    }

    /// 静かに動き出して静かに止まる(種類の切り替えとタブの印)
    static func easeInOut(_ t: CGFloat) -> CGFloat {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }

    /// 少し行き過ぎてから戻る(肌の色の帯が浮かび上がる)
    static func overshoot(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
    }

    /// 0 から 1 へ上がって 0 に戻る(ピンが弾む)
    static func bounce(_ t: CGFloat) -> CGFloat {
        sin(.pi * t)
    }
}
