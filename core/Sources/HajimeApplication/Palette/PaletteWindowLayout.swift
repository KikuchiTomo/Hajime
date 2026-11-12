import HajimeDomain

/// パレットの窓の部品の位置(R-26)．余白は間隔の段階(design/tokens の size.space)だけで決める．
///
/// - 窓の内側の余白は上下左右とも metrics.padding(窓の枠線の内側から．角丸のテーマは枠線，platinum と desk はベベル)
/// - 区画(探す欄 → タブ → マス目 → 区切り → 説明 → 区切り → 足元)のあいだは metrics.sectionGap．区切りの線の上と下も同じ
/// - まとまりのあいだ(探す欄と種類の切り替え，タブとマスの見出し，マス目とスクロールの位置の線)は metrics.groupGap，
///   まとまりの中(マスの見出しとマス目)は metrics.itemGap
/// - 中身の右の端は 1 か所(探す欄・種類の切り替え・区切りの線・スクロールの位置の線・肌の色のボタンの右の端)
///
/// 窓の大きさは列数・行数・マスの大きさ・説明に出す項目の設定と種類で決め，選んでいる文字では変えない．
/// 説明の欄は種類ごとに出る行の分の高さにし(PalettePreviewLayout.height)，いちばん高い種類(絵文字)との差は，
/// マスの行に回せる分をマス目の行に回す(extraRows．core の PaletteSession が visibleRows に足す)．
/// 回しきれない端の高さは余白に回さず，窓をその分だけ低くする(種類を替えると窓の下の端が動く)．区切りの線の上と下はどの種類でも同じ．
/// macOS の PaletteView が使い，Windows の候補ウィンドウ(palette::layout)は同じ決め方を Rust で持つ
public struct PaletteWindowLayout: Sendable, Equatable {
    public typealias Box = PalettePreviewLayout.Box

    /// 寸法(デザイントークン)．border と shadow はテーマで決まる
    public struct Metrics: Sendable {
        public var padding: Double
        public var sectionGap: Double
        public var groupGap: Double
        public var itemGap: Double
        public var controlHeight: Double
        public var textRowHeight: Double
        public var scrollbarWidth: Double
        /// 区切りの線の太さ
        public var lineWidth: Double
        /// 足元の行の高さ(キーキャップの高さ)．肌の色のボタンもこの高さの正方形
        public var footerHeight: Double
        /// 窓の枠線の太さ(角丸のテーマは枠線，platinum と desk は外枠とベベル)
        public var border: Double
        /// 窓の右と下に付ける影(desk)
        public var shadow: Double

        public init(padding: Double, sectionGap: Double, groupGap: Double, itemGap: Double, controlHeight: Double, textRowHeight: Double,
                    scrollbarWidth: Double, lineWidth: Double, footerHeight: Double, border: Double, shadow: Double) {
            self.padding = padding
            self.sectionGap = sectionGap
            self.groupGap = groupGap
            self.itemGap = itemGap
            self.controlHeight = controlHeight
            self.textRowHeight = textRowHeight
            self.scrollbarWidth = scrollbarWidth
            self.lineWidth = lineWidth
            self.footerHeight = footerHeight
            self.border = border
            self.shadow = shadow
        }

        /// デザイントークンの値．border と shadow はテーマごとに描く側が渡す
        public static func tokens(border: Double, shadow: Double) -> Metrics {
            Metrics(padding: LayoutTokens.Palette.padding, sectionGap: LayoutTokens.Palette.sectionGap, groupGap: LayoutTokens.Palette.groupGap,
                    itemGap: LayoutTokens.Palette.itemGap, controlHeight: LayoutTokens.Palette.controlHeight,
                    textRowHeight: LayoutTokens.Palette.textRowHeight, scrollbarWidth: LayoutTokens.Palette.scrollbarWidth,
                    lineWidth: LayoutTokens.Candidate.frameWidth, footerHeight: LayoutTokens.Glass.keycapHeight, border: border, shadow: shadow)
        }
    }

    /// 窓の大きさ(desk の影を含む)
    public var width: Double
    public var height: Double
    /// 窓の本体(影を除く)と，内側の余白の内側
    public var body: Box
    public var content: Box
    public var search: Box
    public var modes: [Box]
    public var tabs: [Box]
    /// マス目の上の見出し
    public var heading: Box
    public var grid: Box
    public var scrollbar: Box
    /// 区切りの線(上の端の y)．説明を出すときは 2 本，出さないときは 1 本
    public var separators: [Double]
    public var preview: Box?
    /// 足元の行(キーの案内と肌の色のボタン)
    public var footer: Box
    public var skinToneButton: Box

    /// - Parameters:
    ///   - visibleRows: 今の種類で見せるマス目の行の数(extraRows を足したもの)
    ///   - modeWidths: 種類の切り替えのそれぞれの幅
    ///   - previewHeight: 今の種類の説明の欄の高さ．出さない設定なら nil
    public init(columns: Int, visibleRows: Int, cellSize: Double, tabCount: Int, modeWidths: [Double], previewHeight: Double?, metrics: Metrics) {
        let inset = metrics.border + metrics.padding
        let gridWidth = Double(columns) * cellSize
        let contentWidth = gridWidth + metrics.groupGap + metrics.scrollbarWidth
        var bodyHeight = inset * 2 + metrics.controlHeight + metrics.sectionGap + metrics.controlHeight + metrics.groupGap + metrics.textRowHeight
            + metrics.itemGap + Double(visibleRows) * cellSize + metrics.sectionGap + metrics.lineWidth + metrics.sectionGap + metrics.footerHeight
        if let previewHeight { bodyHeight += previewHeight + metrics.sectionGap + metrics.lineWidth + metrics.sectionGap }
        width = inset * 2 + contentWidth + metrics.shadow
        height = bodyHeight + metrics.shadow
        body = Box(x: 0, y: 0, width: inset * 2 + contentWidth, height: bodyHeight)
        let content = Box(x: inset, y: inset, width: contentWidth, height: bodyHeight - inset * 2)
        self.content = content
        var y = content.y
        // 探す欄の右に種類の切り替えを置き，右の端を中身の右の端にそろえる
        var x = content.maxX - modeWidths.reduce(0, +)
        modes = modeWidths.map { width in
            defer { x += width }
            return Box(x: x, y: y, width: width, height: metrics.controlHeight)
        }
        search = Box(x: content.x, y: y, width: content.width - modeWidths.reduce(0, +) - metrics.groupGap, height: metrics.controlHeight)
        y += metrics.controlHeight + metrics.sectionGap
        // タブは探す欄と同じ高さの正方形にまとまりのあいだの間隔を足した幅で並べ，窓の幅に収まらなければ詰める
        let tabWidth = tabCount == 0 ? 0 : min(metrics.controlHeight + metrics.groupGap, content.width / Double(tabCount)).rounded(.down)
        let tabTop = y
        tabs = (0..<tabCount).map { Box(x: content.x + Double($0) * tabWidth, y: tabTop, width: tabWidth, height: metrics.controlHeight) }
        y += metrics.controlHeight + metrics.groupGap
        heading = Box(x: content.x, y: y, width: content.width, height: metrics.textRowHeight)
        y += metrics.textRowHeight + metrics.itemGap
        let grid = Box(x: content.x, y: y, width: gridWidth, height: Double(visibleRows) * cellSize)
        self.grid = grid
        scrollbar = Box(x: content.maxX - metrics.scrollbarWidth, y: grid.y, width: metrics.scrollbarWidth, height: grid.height)
        y = grid.maxY + metrics.sectionGap
        separators = [y]
        y += metrics.lineWidth + metrics.sectionGap
        if let height = previewHeight {
            self.preview = Box(x: content.x, y: y, width: content.width, height: height)
            y += height + metrics.sectionGap
            separators.append(y)
            y += metrics.lineWidth + metrics.sectionGap
        } else {
            self.preview = nil
        }
        footer = Box(x: content.x, y: y, width: content.width, height: metrics.footerHeight)
        skinToneButton = Box(x: content.maxX - metrics.footerHeight, y: y, width: metrics.footerHeight, height: metrics.footerHeight)
    }

    /// 今の種類のマス目に回す行の数．説明の欄がいちばん高い種類(絵文字)より低い分を，マスの一辺で割って切り捨てる
    public static func extraRows(previewHeight: Double?, windowPreviewHeight: Double?, cellSize: Double) -> Int {
        guard let previewHeight, let windowPreviewHeight, cellSize > 0 else { return 0 }
        return max(Int(((windowPreviewHeight - previewHeight) / cellSize).rounded(.down)), 0)
    }

    /// 文字の実際の外形(ink．描く原点からの相対の位置)の中心が，box の中心に来るように描く原点
    public static func centeredOrigin(ink: Box, in box: Box) -> (x: Double, y: Double) {
        (box.x + box.width / 2 - (ink.x + ink.width / 2), box.y + box.height / 2 - (ink.y + ink.height / 2))
    }
}
