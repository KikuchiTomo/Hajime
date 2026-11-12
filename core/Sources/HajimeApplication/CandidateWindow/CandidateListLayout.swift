/// 候補の一覧の窓の区画の配置．上から，文字種の行(連想の一覧では見出しの行)・候補・語の意味のカード・足元．
///
/// 角丸のテーマ(rounded)
/// - 縁の線の内側に，上下左右とも metrics.padding の余白を空ける．候補の行の地・区切りの線・カードの左右の端は余白の内側の端にそろう
/// - 区切りの線の上と下は metrics.separatorGap．候補の下のカードと候補のあいだも同じ
/// - 候補の右の語の意味と一覧のあいだは metrics.cardGap(選んでいる候補と語の意味をつなぐ線をここに引く)．語の意味は箱を描かない
/// - 候補の右のカードは，上の端を候補の 1 行目の地の上の端に，右の端を足元の区切りの線の右の端にそろえる
///
/// platinum と desk(bevel)
/// - 候補の行は立体の縁の内側いっぱいに置く(余白を空けない)．区画と区画は 1 ドットの線で区切る
/// - 候補の右の語の意味は角丸のテーマと同じく箱を描かずに置く．候補の下は区画にし，一覧とのあいだに横の線を引く
///
/// 座標は窓の左上が原点で，下が y の正．macOS の CandidateView がこの配置を描き，
/// Windows の候補ウィンドウ(scene::list)は同じ決め方を Rust で持つ
public struct CandidateListLayout: Sendable, Equatable {
    public typealias Box = MeaningCardLayout.Box

    public enum Style: Sendable, Equatable {
        /// 角丸のテーマ(標準・glass・和紙など)
        case rounded
        /// platinum と desk
        case bevel
    }

    /// 語の意味のカード
    public enum Card: Sendable, Equatable {
        /// 候補の右．width・height は語の意味の場所の大きさ
        case side(width: Double, height: Double)
        /// 候補の下．width は窓の中身の幅の下限(belowCardWidth)で，カードは窓の中身の幅いっぱいに置く
        case below(width: Double, height: Double)
    }

    /// 寸法．テーマの種類ごとの値は rounded・bevel
    public struct Metrics: Sendable, Equatable {
        /// 縁の線(角丸)，外枠と立体の縁(platinum と desk)の太さ
        public var edge: Double
        /// 縁の内側の余白
        public var padding: Double
        /// 区切りの線の上と下の空き
        public var separatorGap: Double
        /// 候補の右の語の意味と一覧のあいだ
        public var cardGap: Double
        public var separatorWidth: Double
        /// 候補の行の間隔(行の地の高さと，行と行のあいだの和)
        public var rowPitch: Double
        /// 候補の行の地の上下を縮める量．行と行のあいだはこの 2 倍
        public var rowInset: Double
        /// 文字種の行・連想の見出しの行の高さ
        public var headerHeight: Double
        /// 足元の行の高さ
        public var footerHeight: Double
        /// desk の影の幅(右と下)
        public var shadow: Double

        public init(edge: Double, padding: Double, separatorGap: Double, cardGap: Double, separatorWidth: Double, rowPitch: Double, rowInset: Double,
                    headerHeight: Double, footerHeight: Double, shadow: Double) {
            self.edge = edge
            self.padding = padding
            self.separatorGap = separatorGap
            self.cardGap = cardGap
            self.separatorWidth = separatorWidth
            self.rowPitch = rowPitch
            self.rowInset = rowInset
            self.headerHeight = headerHeight
            self.footerHeight = footerHeight
            self.shadow = shadow
        }

        /// 角丸のテーマ．行の間隔と行の高さは文字の大きさで変わるので描く側が渡す
        public static func rounded(rowPitch: Double, headerHeight: Double, footerHeight: Double) -> Metrics {
            Metrics(edge: LayoutTokens.Candidate.frameWidth, padding: LayoutTokens.Glass.windowPadding, separatorGap: LayoutTokens.Glass.separatorGap,
                    cardGap: LayoutTokens.Meaning.cardGap, separatorWidth: LayoutTokens.Candidate.frameWidth, rowPitch: rowPitch, rowInset: LayoutTokens.Glass.selectionInsetY,
                    headerHeight: headerHeight, footerHeight: footerHeight, shadow: 0)
        }

        /// platinum と desk．文字種の行と足元の行は同じ高さ(sectionHeight)
        public static func bevel(rowPitch: Double, sectionHeight: Double, hasShadow: Bool) -> Metrics {
            Metrics(edge: LayoutTokens.Candidate.frameWidth + LayoutTokens.Candidate.bevelWidth, padding: 0, separatorGap: 0, cardGap: LayoutTokens.Meaning.cardGap,
                    separatorWidth: LayoutTokens.Candidate.frameWidth, rowPitch: rowPitch, rowInset: 0, headerHeight: sectionHeight,
                    footerHeight: sectionHeight, shadow: hasShadow ? LayoutTokens.Candidate.shadowOffset : 0)
        }
    }

    /// 窓の大きさ(desk の影を含む)
    public var width: Double
    public var height: Double
    /// 窓の枠(影を除く)
    public var body: Box
    /// 縁と余白の内側
    public var content: Box
    /// 文字種の行(連想の一覧では見出しの行)と，その下の区切りの線
    public var header: Box?
    public var headerSeparator: Box?
    /// 候補の行の地(角丸のテーマは選んだ行の地そのもの)
    public var rows: [Box]
    /// 候補の行を押せる範囲(行と行のあいだを含む)
    public var hitRows: [Box]
    /// 語の意味のカード．platinum と desk は枠の無い区画で，cardSeparator で一覧と区切る
    public var card: Box?
    public var cardSeparator: Box?
    /// 足元の行と，その上の区切りの線．足元を出さないとき(設定の画面の見本)は候補の列の下の端の高さ 0 の区画
    public var footerSeparator: Box
    public var footer: Box

    /// 候補の下のカードの幅(窓の中身の幅)．listWidth は候補の列，footerWidth は足元の中身，minimum はカードの幅の下限
    public static func belowCardWidth(listWidth: Double, footerWidth: Double, minimum: Double) -> Double {
        max(listWidth, footerWidth, minimum)
    }

    /// - Parameters:
    ///   - listWidth: 候補の列(行の地)の幅
    ///   - footerWidth: 足元の中身の幅
    ///   - maximumWidth: 窓の幅の上限．超えるときは候補の列を狭める(長い候補は描く側が末尾を省く)
    ///   - size: 窓の大きさ(影を含む)を外から決めるとき(窓の大きさを変える動きの途中)．幅は候補の列で吸収し，区画は上から積む
    ///   - hasFooter: 足元の行(案内と位置)を出すか．設定の画面の見本では出さない
    public init(style: Style, listWidth: Double, footerWidth: Double, hasHeader: Bool, rowCount: Int, card: Card?, maximumWidth: Double,
                metrics: Metrics, size: (width: Double, height: Double)? = nil, hasFooter: Bool = true) {
        let outer = metrics.edge + metrics.padding
        let gap = metrics.separatorGap
        let line = metrics.separatorWidth
        // 候補の右の語の意味と一覧のあいだ(つなぐ線を引く幅)
        let sideGap = metrics.cardGap

        var contentWidth = max(listWidth, footerWidth)
        switch card {
        case .side(let cardWidth, _)?: contentWidth = max(listWidth + sideGap + cardWidth, footerWidth)
        case .below(let cardWidth, _)?: contentWidth = max(contentWidth, cardWidth)
        case nil: break
        }
        let bodyWidth = size.map { $0.width - metrics.shadow } ?? min(contentWidth + outer * 2, max(maximumWidth - metrics.shadow, 0)).rounded(.up)
        contentWidth = bodyWidth - outer * 2

        var y = outer
        var headerBox: Box?
        var headerLine: Box?
        if hasHeader {
            headerBox = Box(x: outer, y: y, width: 0, height: metrics.headerHeight)
            y += metrics.headerHeight + gap
            headerLine = Box(x: outer, y: y, width: 0, height: line)
            y += line + gap
        }
        let rowsTop = y
        let rowHeight = metrics.rowPitch - metrics.rowInset * 2
        let rowsHeight = rowCount > 0 ? metrics.rowPitch * Double(rowCount) - metrics.rowInset * 2 : 0
        var listBottom = rowsTop + rowsHeight
        var listColumn = contentWidth
        var cardBox: Box?
        var cardLine: Box?
        switch card {
        case .side(let cardWidth, let cardHeight)?:
            listColumn = max(contentWidth - sideGap - cardWidth, 0)
            let regionHeight = max(rowsHeight, cardHeight)
            cardBox = Box(x: outer + listColumn + sideGap, y: rowsTop, width: cardWidth, height: regionHeight)
            listBottom = rowsTop + regionHeight
        case .below(_, let cardHeight)?:
            let top = listBottom + (style == .rounded ? gap : line)
            if style == .bevel { cardLine = Box(x: outer, y: listBottom, width: contentWidth, height: line) }
            cardBox = Box(x: outer, y: top, width: contentWidth, height: cardHeight)
            listBottom = top + cardHeight
        case nil:
            break
        }
        rows = (0..<rowCount).map { index in
            Box(x: outer, y: rowsTop + metrics.rowPitch * Double(index), width: listColumn, height: rowHeight)
        }
        hitRows = rows.map { Box(x: $0.x, y: $0.y - metrics.rowInset, width: $0.width, height: metrics.rowPitch) }
        self.card = cardBox
        cardSeparator = cardLine
        // 文字種の行と，その下の区切りの線は候補の列の幅
        header = headerBox.map { Box(x: $0.x, y: $0.y, width: listColumn, height: $0.height) }
        headerSeparator = headerLine.map { Box(x: $0.x, y: $0.y, width: listColumn, height: $0.height) }
        if hasFooter {
            y = listBottom + gap
            footerSeparator = Box(x: outer, y: y, width: contentWidth, height: line)
            y += line + gap
            footer = Box(x: outer, y: y, width: contentWidth, height: metrics.footerHeight)
            y = footer.maxY + outer
        } else {
            footerSeparator = Box(x: outer, y: listBottom, width: contentWidth, height: 0)
            footer = Box(x: outer, y: listBottom, width: contentWidth, height: 0)
            y = listBottom + outer
        }
        body = Box(x: 0, y: 0, width: bodyWidth, height: size.map { $0.height - metrics.shadow } ?? y.rounded(.up))
        content = Box(x: outer, y: outer, width: contentWidth, height: body.height - outer * 2)
        width = body.width + metrics.shadow
        height = body.height + metrics.shadow
    }

    /// 区切りの線と区画(行の地・カード・足元)．重なりを確かめるのに使う
    public var parts: [Box] {
        [header, headerSeparator, card, cardSeparator, footerSeparator, footer].compactMap { $0 } + rows
    }
}
