import AppKit
import HajimeApplication

extension NSRect {
    /// core の配置(MeaningCardLayout・CandidateListLayout)の長方形．どちらも上が y の小さい側で，isFlipped のビューと同じ向き
    init(_ box: MeaningCardLayout.Box) {
        self.init(x: box.x, y: box.y, width: box.width, height: box.height)
    }
}
