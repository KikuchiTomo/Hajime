import AppKit
import HajimeApplication
import HajimeDomain

/// 分岐図を描く(ADR 0007)．文を 1 本の線(幹)に並べ，選んでいる文節から枝を出す．できることは，すべて線でつながった枝として見せる．
///
/// - 幹: 文節を横に並べ，その下の線に文節ごとの丸を置く．選んでいる文節の丸は選択の色で塗る．確信の低い文節は，下の線を点線にする
/// - 下の枝: 変換の候補．選んでいる文節の丸から縦の線を下ろし，候補ごとに丸・番号・文字を並べる．選んだ候補までの線は選択の色で太く描く
/// - 上の枝: 文字種(ひらがな・カタカナ・半角カタカナ)．文節の上から横へ伸ばす
/// - 先の枝: 選んでいる候補の行の先に小さな幹を伸ばし，語の意味(R-08)と連想(R-18)の丸を並べる．語の意味は，意味の丸から下へ出す
/// - キーの案内: 足元には並べず，操作する場所に置く(区切りは文節の境目の上，文字種は上の枝の先，再入力は候補の下，展開は先の枝の先)．
///   候補の中身と見分けられるよう，背景と反転した色の面で囲む
/// - 文節を区切っているとき(⇧↓)は，幹を意味のある切れ目(「問題｜が｜ある」)で分け，切れ目に番号を挟む．枝は出さない(core の PanelBuilder.splitting)
/// - 連想の一覧(R-18)では，いちばん上に見出しの行を出し，下の枝に連想の語を並べる
///
/// 幹の文節の位置は文字の幅だけで決め，選ぶ文節を移しても動かさない．窓の幅に上限があるので，枝が右に入らないときは枝を左右に反転して左へ出す．
/// 左右のどちらにも入らないときは，入る位置まで寄せて，角を曲げた線で文節とつなぐ．幹が窓より長いときは，選んでいる文節が見える位置まで幹を送り，
/// はみ出した側を端へ向けて透かす．
/// 角丸のテーマは丸と丸い角の線，platinum と desk は四角と 1 ドットの線で描く(BranchMapDrawing)
final class BranchView: NSView {
    private typealias Size = DesignTokens.Size.Candidate
    private typealias Branch = DesignTokens.Size.Branch
    private typealias Map = DesignTokens.Size.BranchMap
    private typealias Glass = DesignTokens.Size.Glass
    private typealias Meaning = DesignTokens.Size.Meaning
    private typealias Space = DesignTokens.Size.Space
    private typealias Part = DesignTokens.Size.Part
    private typealias Opacity = DesignTokens.Opacity.Candidate
    private typealias Stop = BranchMapDrawing.Stop
    private typealias Line = BranchMapDrawing.Line

    var panel: LatticePanel? {
        didSet {
            cache = nil
            updateTrunkOffset()
            needsDisplay = true
        }
    }
    /// 窓の幅の上限(CandidatePanelController が画面の幅から決める)．幹がこれより長い文では，幹を横に送って選んでいる文節を見せる
    var maximumWidth = DesignTokens.Size.Candidate.maxWidth {
        didSet {
            cache = nil
            updateTrunkOffset()
            needsDisplay = true
        }
    }
    /// 幹が窓に収まらないときに，幹を左へ送る量．選んでいる文節が窓から出るときだけ，出ない分だけ送る
    /// (文節を移るたびに幹が動かないよう，入る限り前の量を保つ)
    private var trunkOffset: CGFloat = 0 { didSet { cache = nil } }
    /// 案内に出すキーの割り当て
    var keys = KeymapPreset.standard.keymap { didSet { invalidate() } }
    /// キーの案内を出すか(設定の「キーの案内を表示」)
    var showsHints = true { didSet { invalidate() } }
    /// 押し続けている修飾キー(CandidatePanelController が入れる)．案内を押し続けているあいだだけ出す設定(LatticePanel.hintsOnHold)では，
    /// この修飾キーを使うキーの案内だけを出す．案内の場所はいつも空けてあるので，出しても候補は動かない
    var heldModifiers: NSEvent.ModifierFlags = [] { didSet { if heldModifiers != oldValue { needsDisplay = true } } }
    /// 押し続けて出す案内の濃さ(出し始めに 0 から 1 へ)
    var hintOpacity: CGFloat = 1 { didSet { if hintOpacity != oldValue { needsDisplay = true } } }
    var theme = ResolvedTheme.resolveStatic { didSet { invalidate() } }
    var fontSize: CGFloat = Size.fontSize { didSet { invalidate() } }
    var restOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    /// glass の面を自分で塗るか．ぼかしの背景(GlassBackdrop)の無いところ(画像への書き出し)で使う
    var fillsSurface = false { didSet { needsDisplay = true } }

    /// 今の panel の配置．描くとき・大きさを求めるとき・押した位置を調べるときで同じものを使う
    private var cache: Layout?

    private func invalidate() {
        cache = nil
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    // MARK: - 寸法

    /// テーマごとの寸法
    private struct Metrics {
        /// 窓の端から中身まで
        var inset: CGFloat
        var rowHeight: CGFloat
        /// 候補の行の背景の上下を縮める量(角丸のテーマ)
        var rowInset: CGFloat
        /// 注釈・知らせの行の高さ
        var noteHeight: CGFloat
        var lineWidth: CGFloat
        var lineWidthSelected: CGFloat
        /// 線の曲がり角の半径．直線の枝のテーマと platinum・desk は 0
        var turnRadius: CGFloat
    }

    private var metrics: Metrics {
        let scale = fontSize / Size.fontSize
        let note = max(Glass.keycapHeight, Glass.noteIconSize, (labelFont.ascender - labelFont.descender).rounded(.up))
        if theme.isRounded {
            return Metrics(inset: Size.frameWidth + Glass.windowPadding, rowHeight: (Glass.rowHeight * scale).rounded(), rowInset: Glass.selectionInsetY,
                           noteHeight: note, lineWidth: Glass.lineWidth, lineWidthSelected: Glass.lineWidthSelected,
                           turnRadius: theme.straightBranches ? 0 : Glass.branchTurnRadius)
        }
        return Metrics(inset: Size.frameWidth + Size.bevelWidth + Glass.windowPadding, rowHeight: (Size.rowHeight * scale).rounded(), rowInset: 0,
                       noteHeight: note, lineWidth: Branch.lineWidth, lineWidthSelected: Branch.lineWidthSelected, turnRadius: 0)
    }

    /// 候補の番号と，そのあとの空き
    private var lead: CGFloat { Glass.badgeSize + Glass.badgeGap }
    /// 縦の線から番号までの距離
    private var badgeOffset: CGFloat { Map.stopSizeSelected / 2 + Map.stemGap }
    /// 区切りの線の上と下，カードと枝のあいだの空き
    private var gap: CGFloat { Glass.separatorGap }
    /// 見出し・注釈・知らせの文字の左右の端
    private var textInset: CGFloat { metrics.inset + Part.rowPaddingX }

    private var candidateFont: NSFont { theme.candidateFont(size: fontSize) }
    private var trunkFont: NSFont { theme.trunkFont(size: fontSize) }
    private var labelFont: NSFont { theme.labelFont(size: theme.isRounded ? Glass.labelFontSize : Size.labelFontSize) }
    private var dropShadowOffset: CGFloat { theme.hasDropShadow ? Size.shadowOffset : 0 }

    private func textWidth(_ text: String, font: NSFont) -> CGFloat {
        text.size(withAttributes: [.font: font]).width.rounded(.up)
    }

    // MARK: - キーの案内

    /// 操作する場所ごとの案内
    private struct Hints {
        /// 選んでいる文節の境目の上(区切り・分割)．区切っているあいだは，区切る操作
        var boundary: [KeyHint] = []
        /// 文字種の枝の先
        var variant: KeyHint?
        /// 候補の下(再入力・表形式)．連想の一覧では，連想の操作
        var candidates: [KeyHint] = []
        /// 先の枝の先(展開)
        var expand: KeyHint?
        /// 先の枝の丸の中身の下(選択・意味の切り替え・戻る)
        var items: [KeyHint] = []
    }

    private func hints(for panel: LatticePanel) -> Hints {
        guard showsHints else { return Hints() }
        if panel.association != nil {
            // 先の枝の丸の中身として出しているときは，中身の下に置く
            let hints = UIStrings.Association.hints(for: keys)
            return panel.detail == nil ? Hints(candidates: hints) : Hints(items: hints)
        }
        if let split = panel.columns.first(where: \.isFocused)?.split {
            return Hints(boundary: UIStrings.Branch.splitHints(count: split.pieces.count - 1))
        }
        // 先の枝を畳んでいるとき(表示項目を減らす設定)は，開くキー(連想変換のキー)を案内する
        // 先の枝へ入るキー．候補にいるあいだ(と，先の枝を畳んでいるあいだ)だけ出す
        let expand: KeyHint? = if panel.collapsesDetail || (panel.detail != nil && panel.detail?.current == nil) {
            UIStrings.Branch.expandHint(for: keys)
        } else {
            panel.associationHint?.key.map(UIStrings.Branch.expandHint(key:))
        }
        return Hints(boundary: UIStrings.Branch.boundaryHints(for: keys), variant: UIStrings.Branch.variantHint(for: keys),
                     candidates: UIStrings.Branch.candidateHints(for: keys), expand: expand)
    }

    /// 今，この案内を出すか．常に出す設定ならすべて出し，押し続けて出す設定なら，押し続けている修飾キーを使うキーの案内だけを出す
    private func isShown(_ hint: KeyHint, in panel: LatticePanel) -> Bool {
        guard panel.hintsOnHold else { return true }
        let symbols: [(NSEvent.ModifierFlags, Character)] = [(.shift, "⇧"), (.option, "⌥"), (.control, "⌃"), (.command, "⌘")]
        return symbols.contains { heldModifiers.contains($0.0) && hint.key.contains($0.1) }
    }

    /// 案内を左から並べた位置に描く．出さない案内の場所は空けたままにする(出したり消したりしても，ほかの案内は動かない)
    private func drawHints(_ hints: [KeyHint], x: CGFloat, midY: CGFloat, in panel: LatticePanel) {
        var x = x
        for hint in hints {
            if isShown(hint, in: panel) { BranchMapDrawing.drawHint(hint, x: x, midY: midY, theme: theme) }
            x += BranchMapDrawing.hintWidth(hint, theme: theme) + Glass.hintGap
        }
    }

    /// 押し続けて出す案内を，出し始めの濃さ(hintOpacity)で描く
    private func withHintOpacity(in panel: LatticePanel, _ body: () -> Void) {
        guard panel.hintsOnHold, hintOpacity < 1, let context = NSGraphicsContext.current?.cgContext else {
            body()
            return
        }
        context.saveGState()
        context.setAlpha(hintOpacity)
        body()
        context.restoreGState()
    }

    // MARK: - 語の意味

    /// 枝として出す語の意味の文．意味と例を幅で折り返したもの
    private struct MeaningText {
        struct Sense {
            var meaning: [NSAttributedString]
            var example: [NSAttributedString]
        }

        /// 品詞
        var tag: String?
        var senses: [Sense]
        var width: CGFloat
        var height: CGFloat
    }

    private var partOfSpeechFont: NSFont { theme.labelFont(size: Meaning.partOfSpeechFontSize) }

    private func partOfSpeechWidth(_ text: String) -> CGFloat {
        textWidth(text, font: partOfSpeechFont) + Meaning.partOfSpeechPaddingX * 2
    }

    private func meaningText(_ note: HomophoneNote) -> MeaningText {
        let meaningAttributes: [NSAttributedString.Key: Any] = [.font: theme.bodyFont(size: Meaning.bodyFontSize), .foregroundColor: theme.text]
        let exampleAttributes: [NSAttributedString.Key: Any] = [.font: theme.bodyFont(size: Meaning.exampleFontSize), .foregroundColor: theme.textMuted]
        let tag = note.partOfSpeech?.name
        var width = tag.map(partOfSpeechWidth) ?? 0
        var height = tag == nil ? 0 : Meaning.partOfSpeechHeight + Space.stack
        var senses: [MeaningText.Sense] = []
        for (index, sense) in note.senses.enumerated() {
            let meaning = MeaningCardDrawing.wrap(NSAttributedString(string: sense.meaning, attributes: meaningAttributes), width: Map.meaningWidth,
                                                  maxLines: Int(Meaning.meaningLines))
            let example = sense.example.map {
                MeaningCardDrawing.wrap(NSAttributedString(string: $0, attributes: exampleAttributes), width: Map.meaningWidth, maxLines: Int(Meaning.exampleLines))
            } ?? []
            for line in meaning + example { width = max(width, line.size().width.rounded(.up)) }
            height += CGFloat(meaning.count) * Meaning.meaningPitch + CGFloat(example.count) * Meaning.examplePitch
            if index < note.senses.count - 1 { height += Meaning.senseGap }
            senses.append(MeaningText.Sense(meaning: meaning, example: example))
        }
        return MeaningText(tag: tag, senses: senses, width: width, height: height)
    }

    /// 候補の下に出す語の意味(設定の「意味の位置」が候補の下のとき)．窓の中身の幅いっぱいのカード
    private struct MeaningSlot {
        var layout: MeaningCardDrawing.Layout
        var size: NSSize
    }

    /// 同音語のタグに出す語．下の枝に出ていない語だけにする(枝に出ている語は見れば分かる)
    static func others(of note: HomophoneNote, in column: LatticePanel.Column) -> [String] {
        let shown = Set(column.alternatives)
        return note.others.filter { !shown.contains($0) }
    }

    private func meaningSlot(for panel: LatticePanel, width: CGFloat) -> MeaningSlot? {
        guard panel.meaningPlacement == .below, let column = panel.columns.first(where: \.isFocused), column.split == nil,
              let note = column.homophone else { return nil }
        let position = MeaningCardLayout.Placement(left: Part.rowPaddingX, headerMidY: MeaningCardDrawing.headerHeight(theme: theme) / 2)
        let layout = MeaningCardDrawing.layout(note, others: Self.others(of: note, in: column), width: width, placement: position, theme: theme)
        return MeaningSlot(layout: layout, size: layout.size)
    }

    // MARK: - 配置

    /// 文字種の 1 つ．線の上の丸と，文字の枠
    private struct Kind {
        var stop: NSPoint
        var label: NSRect
    }

    /// 先の枝の丸と見出し
    private struct Station {
        var title: String
        var stop: NSPoint
        var titleX: CGFloat
        var titleMidY: CGFloat
    }

    /// 枝として出す語の意味の位置
    private struct SideMeaning {
        var text: MeaningText
        /// 意味の丸から下ろす縦の線
        var lineX: CGFloat
        var top: CGFloat
        /// 文の，線に近い側の端
        var textX: CGFloat
    }

    private struct Layout {
        var size = NSSize.zero
        /// 幹の文節の枠(送ったあとの位置)
        var nodes: [NSRect] = []
        /// 幹の線の y と，左右の端
        var railY: CGFloat = 0
        var railStart: CGFloat = 0
        var railEnd: CGFloat = 0
        /// 幹が窓からはみ出している側
        var fadesLeft = false
        var fadesRight = false
        var focus: Int?
        /// 選んでいる文節の丸の x と，候補の枝の縦の線の x(枝を寄せていなければ同じ)
        var focusX: CGFloat = 0
        var stemX: CGFloat = 0
        /// 枝の向き．1 は右，-1 は左(左右に反転)
        var direction: CGFloat = 1
        /// 候補の行(選択の背景の枠)
        var rows: [NSRect] = []
        var kinds: [Kind] = []
        var twigDirection: CGFloat = 1
        var twigY: CGFloat = 0
        /// 文字種の線の，文節から遠い側の端
        var twigEndX: CGFloat = 0
        var variantHintX: CGFloat?
        /// 文節の境目の上の案内の行
        var boundaryMidY: CGFloat?
        var boundaryX: CGFloat = 0
        var stations: [Station] = []
        var expandX: CGFloat?
        var expandMidY: CGFloat = 0
        /// 候補のページの位置を示す点(候補の縦の線の下)．1 ページなら出さない
        var pageDots: PageDots?
        var itemPageDots: PageDots?
        /// 今いる丸の中身(連想の語・マクロの結果)の行と，その縦の線の x
        var itemRows: [NSRect] = []
        var itemStemX: CGFloat = 0
        /// 中身の説明(連想のまとまりの意味と位置)
        var itemLabel: (text: String, x: CGFloat, midY: CGFloat)?
        /// 中身の下の行(案内と位置)
        var itemBottomMidY: CGFloat?
        var itemHintsX: CGFloat = 0
        var itemPosition: (text: String, x: CGFloat)?
        /// 語の意味を下げる丸の位置
        var meaningStation: Int?
        /// 畳んでいる枝の，続きがある印の線(表示項目を減らす設定)．文字種は文節の上へ，先の枝は選んでいる候補の行の先へ
        var variantStub: (from: NSPoint, to: NSPoint)?
        var detailStub: (from: NSPoint, to: NSPoint)?
        var meaning: SideMeaning?
        /// 候補の下の行(案内・位置・辞書の名前)
        var bottomMidY: CGFloat?
        var bottomHintsX: CGFloat = 0
        var positionX: CGFloat = 0
        var sourceX: CGFloat = 0
        /// 候補の下に出す語の意味のカード
        var slot: MeaningSlot?
        var card: NSRect?
        /// 注釈・知らせの行を置き始める y
        var notesTop: CGFloat = 0
        var heading: NSRect?
        /// 幹の右端(送る前)と，選んでいる文節の左右の端(送る前)
        var trunkRight: CGFloat = 0
        var focusSpan: ClosedRange<CGFloat>?
        /// 幹が窓の幅の上限を超えているか
        var overflows = false
    }

    /// 上の枝の文字種ごとの，その文字種にするキー(variants と同じ数)．案内を出さない設定と，キーの無い文字種は nil
    private func variantKeys(of column: LatticePanel.Column?) -> [String?] {
        guard let column else { return [] }
        // 押し続けて出す設定では出さない(修飾キーの無いキーなので，押し続けて出す手がかりが無い．場所も空けない)
        let shows = showsHints && panel?.hintsOnHold == false
        return column.variants.indices.map { shows && column.variantKeys.indices.contains($0) ? column.variantKeys[$0] : nil }
    }

    /// 文節の左の端から，その文節の丸(と，そこから出る枝)までの距離．短い文節は真ん中，長い文節は左から決まった距離(1 字と余白)にする．
    /// 候補を移って文節の字の数が変わっても，丸と枝の位置が動かないようにするため(真ん中に置くと，字の数が変わるたびに枝が左右に動く)
    private func stopOffset(width: CGFloat) -> CGFloat {
        min(width / 2, fontSize + Part.rowPaddingX).rounded()
    }

    /// ページの位置を示す点の並び．縦の線の下に，ページの数だけ縦に並べる
    private struct PageDots {
        var x: CGFloat
        var top: CGFloat
        var count: Int
        var current: Int

        var height: CGFloat { CGFloat(count) * DesignTokens.Size.BranchMap.pageDotPitch }
    }

    /// ページの数と今のページ．1 ページか，1 ページの数が分からなければ nil
    private func pages(position: Int, total: Int, pageSize: Int) -> (count: Int, current: Int)? {
        guard pageSize > 0, total > pageSize else { return nil }
        return ((total + pageSize - 1) / pageSize, max(position - 1, 0) / pageSize)
    }

    /// ページが多すぎて点で示せないときの，数字の位置(「3 / 12」)
    private func pageText(_ pages: (count: Int, current: Int)?) -> String {
        guard let pages, pages.count > Int(Map.pageDotLimit) else { return "" }
        return UIStrings.Association.groupPosition(pages.current + 1, pages.count)
    }

    /// 幹の文節の幅(文字と左右の余白)
    private func trunkWidth(_ column: LatticePanel.Column) -> CGFloat {
        var text = trunkCommand(column).map { CommandDrawing.width + textWidth($0.title, font: trunkFont) } ?? textWidth(column.text, font: trunkFont)
        // 打ち直している文節は，読みのあとの入力位置の線の分を足し，読みが空でも場所が分かる幅を残す
        if column.isEditing { text = max(text + Glass.editingCaretWidth, Glass.editingMinWidth) }
        return (column.split.map { splitPieces($0).width } ?? text) + Part.rowPaddingX * 2 + (column.isCorrected ? correctedLabelWidth : 0)
    }

    /// 打ち間違いを直した文節の幹で，文字のあとに添える「修正」のタグの幅(前の空きを含む)
    private var correctedLabelWidth: CGFloat {
        NoteDrawing.tagWidth(UIStrings.Branch.corrected, theme: theme) + Space.inline
    }

    /// 候補の行の文字の幅(コマンドのアイコンと，文字のあとに添える説明を含む)
    private func lowerRowWidth(_ row: Row) -> CGFloat {
        let icon: CGFloat = row.command == nil ? 0 : CommandDrawing.width
        return textWidth(row.text, font: candidateFont) + icon + CandidateDetailDrawing.width(row.detail, font: labelFont)
    }

    private func layout(for panel: LatticePanel, offset: CGFloat? = nil) -> Layout {
        if offset == nil, panel == self.panel, let cache { return cache }
        let layout = makeLayout(for: panel, offset: offset)
        if offset == nil, panel == self.panel { cache = layout }
        return layout
    }

    // 配置を 1 か所で決める．幹・枝の向き・縦の並びの順に決めるので長い
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    private func makeLayout(for panel: LatticePanel, offset: CGFloat?) -> Layout {
        let metrics = metrics
        let hints = hints(for: panel)
        var result = Layout()

        // 幹(送る前)．文節のあいだには，境目のつまみの両側の空きを取る
        let nodeGap = Map.segmentGap * 2
        var x = metrics.inset
        var nodeX: [CGFloat] = []
        var nodeWidths: [CGFloat] = []
        for column in panel.columns {
            let width = trunkWidth(column)
            nodeX.append(x)
            nodeWidths.append(width)
            x += width + nodeGap
        }
        let trunkRight = panel.columns.isEmpty ? metrics.inset : x - nodeGap
        let focus = panel.columns.firstIndex(where: \.isFocused)
        let column = focus.map { panel.columns[$0] }
        let lower = column.map { candidateRows($0, in: panel) } ?? []
        let selectedRow = lower.firstIndex(where: \.isSelected)
        let detail = panel.detail
        let isInside = detail?.selectedItem != nil

        // 候補の枝．縦の線から外へ向かう距離で決める(枝を左右に反転しても同じ距離を使う)
        let textOffset = badgeOffset + lead
        let noteWidth = lower.compactMap { $0.note.map { NoteDrawing.tagWidth($0, theme: theme) } }.max() ?? 0
        let rowStart = badgeOffset - Part.rowPaddingX
        // 候補の下の行(案内・辞書の名前・位置)．候補の行の幅に収め，先の枝や語の意味と重ねない
        // ページの位置は，候補の縦の線の下に点で出す．ページが多すぎるときだけ数字にする．先の枝の丸の中身に入っているあいだは，中身の下に出す
        let candidatePages = lower.isEmpty || !showsPosition(panel) || isInside ? nil : pages(position: panel.position, total: panel.total, pageSize: panel.pageSize)
        let positionText = pageText(candidatePages)
        let positionWidth = positionText.isEmpty ? 0 : textWidth(positionText, font: labelFont)
        let sourceWidth = column?.sourceName.map { textWidth(UIStrings.Branch.dictionarySource($0), font: labelFont) + Size.paddingX } ?? 0
        let farWidth = positionWidth + sourceWidth
        let bottomHintsWidth = lower.isEmpty ? 0 : BranchMapDrawing.hintsWidth(hints.candidates, theme: theme)
        let hasBottom = bottomHintsWidth > 0 || farWidth > 0
        let bottomEnd = badgeOffset + bottomHintsWidth + (bottomHintsWidth > 0 && farWidth > 0 ? Space.group : 0) + farWidth
        let rowEnd = max(textOffset + (lower.map(lowerRowWidth).max() ?? 0) + (noteWidth > 0 ? Space.group + noteWidth : 0) + Part.rowPaddingX * 2,
                         hasBottom ? bottomEnd : 0)
        let farStart = rowEnd - farWidth
        var reach = lower.isEmpty ? 0 : rowEnd

        // 先の枝(意味・連想)．候補を選んでいるときだけ出す
        var titles: [String] = []
        var meaning: MeaningText?
        var meaningStation: Int?
        if let detail, let column, selectedRow != nil, !column.isEditing {
            // 丸は core が決める(語の意味・連想・変換マクロのうち，使える物)
            titles = detail.stations.map(\.title)
            if panel.meaningPlacement == .side, let note = column.homophone, let index = detail.stations.firstIndex(where: { $0.kind == .meaning }) {
                meaning = meaningText(note)
                meaningStation = index
            }
        } else if let column, selectedRow != nil, panel.association == nil, !column.isEditing {
            if panel.meaningPlacement == .side, let note = column.homophone {
                titles.append(UIStrings.Branch.meaningTitle)
                meaning = meaningText(note)
                meaningStation = 0
            }
            if let hint = panel.associationHint { titles.append(hint.label) }
        }
        var stationOffsets: [CGFloat] = []
        var cursor = rowEnd + Map.stationGap
        for title in titles {
            let width = textWidth(title, font: labelFont)
            stationOffsets.append(cursor + width / 2)
            cursor += width + Map.stationGap
        }
        var expandOffset: CGFloat?
        if !titles.isEmpty {
            reach = cursor - Map.stationGap
            if let expand = hints.expand, panel.associationHint != nil || detail != nil {
                expandOffset = reach + Space.group
                reach += Space.group + BranchMapDrawing.hintWidth(expand, theme: theme)
            }
        }
        if let meaning, let meaningStation, stationOffsets.indices.contains(meaningStation) {
            reach = max(reach, stationOffsets[meaningStation] + Map.meaningIndent + meaning.width)
        }
        // 今いる丸の中身(連想の語・マクロの結果)．丸から下へ，候補と同じ形で並べる
        let items = itemRows(of: panel)
        let itemStation = stationOffsets.indices.contains(detail?.current ?? -1) ? detail?.current : nil
        let itemLabelText = detail.map(itemLabel) ?? ""
        let itemPages = detail.flatMap { $0.current == nil || items.isEmpty ? nil : pages(position: $0.position, total: $0.total, pageSize: $0.pageSize) }
        let itemPositionText = pageText(itemPages)
        let itemHintsWidth = BranchMapDrawing.hintsWidth(hints.items, theme: theme)
        let itemPositionWidth = itemPositionText.isEmpty ? 0 : textWidth(itemPositionText, font: labelFont)
        let itemBottomWidth = itemHintsWidth + (itemHintsWidth > 0 && itemPositionWidth > 0 ? Space.group : 0) + itemPositionWidth
        let itemRowEnd = max(textOffset + (items.map { textWidth($0.text, font: candidateFont) }.max() ?? 0) + Part.rowPaddingX * 2,
                             badgeOffset + itemBottomWidth, badgeOffset + textWidth(itemLabelText, font: labelFont))
        if let itemStation, !items.isEmpty { reach = max(reach, stationOffsets[itemStation] + itemRowEnd) }
        // 先の枝を畳んでいるとき: 候補の行の先に，続きがある印の線と開くキーの案内
        let showsDetailStub = panel.collapsesDetail && selectedRow != nil && column?.isEditing == false
        if showsDetailStub {
            reach = rowEnd + Map.stubLength
            if let expand = hints.expand {
                expandOffset = reach + Space.inset
                reach += Space.inset + BranchMapDrawing.hintWidth(expand, theme: theme)
            }
        }

        // 文字種の枝．文節の上から横へ伸ばす．並びは反転しない
        // 文字種の文字の前に，その文字種にするキーを置く(案内を出す設定で，キーが割り当てられているとき)
        let kindKeys = variantKeys(of: column)
        let kindWidths = (column?.variants ?? []).enumerated().map { index, text in
            textWidth(text, font: labelFont) + Part.rowPaddingX * 2 + (kindKeys[index].map { BranchMapDrawing.keyWidth($0, theme: theme) + Space.inline } ?? 0)
        }
        // 文字種の文字・境目の案内・候補の番号・候補の下の案内の左の端を，縦の線から同じ距離にそろえる
        let kindStart = badgeOffset - Part.rowPaddingX
        let variantHintWidth = kindWidths.isEmpty ? 0 : hints.variant.map { BranchMapDrawing.hintWidth($0, theme: theme) } ?? 0
        var kindsReach: CGFloat = 0
        if !kindWidths.isEmpty {
            kindsReach = kindStart + kindWidths.reduce(0, +) + Map.stationGap * CGFloat(kindWidths.count - 1)
                + (variantHintWidth > 0 ? Space.group + variantHintWidth : 0)
        }

        // 窓の幅．上限を超える文は，幹を送る
        let focusCenter = focus.map { nodeX[$0] + stopOffset(width: nodeWidths[$0]) } ?? metrics.inset
        let boundaryWidth = BranchMapDrawing.hintsWidth(hints.boundary, theme: theme)
        let notesWidth = [column?.usageNote.map { textWidth($0, font: labelFont) }, panel.note.map { NoteDrawing.width($0, theme: theme) },
                          panel.meaningPlacement == .below && column?.homophone != nil ? Meaning.listWidth : nil]
            .compactMap { $0.map { $0 + Part.rowPaddingX * 2 } }.max() ?? 0
        let showsHeading = panel.association != nil && panel.detail == nil
        let headingWidth = showsHeading ? panel.association.map { AssociationHeadingDrawing.width($0, font: labelFont, emphasis: labelFont) + textInset * 2 } ?? 0 : 0
        // 境目の案内は，文節から上へ伸びる線の右に置く
        let boundaryStart = badgeOffset
        var width = max(Size.minWidth, trunkRight + metrics.inset, focusCenter + max(reach, kindsReach) + metrics.inset,
                        focusCenter + boundaryStart + boundaryWidth + metrics.inset, notesWidth + metrics.inset * 2, headingWidth)
        let limit = max(maximumWidth, Size.minWidth)
        var shift: CGFloat = 0
        if width > limit {
            width = limit
            // 最後の文節を選んだときに，その右の境目のつまみまで見えるよう，文節のあいだの分だけ余分に送れるようにする
            shift = min(max(offset ?? trunkOffset, 0), max(trunkRight + nodeGap + metrics.inset - limit, 0))
            result.overflows = true
        }
        width = width.rounded(.up)
        let left = metrics.inset
        let right = width - metrics.inset
        let focusX = (focusCenter - shift).rounded()

        // 枝の向き．右に入れば右，入らなければ左右に反転して左．どちらにも入らなければ，広い側へ出して入る位置まで寄せる
        var direction: CGFloat = 1
        if focusX + reach > right { direction = focusX - reach >= left || focusX > width / 2 ? -1 : 1 }
        let edge = Map.stopSizeSelected / 2
        let stemX = (direction > 0 ? max(min(focusX, right - reach), left + edge) : min(max(focusX, left + reach), right - edge)).rounded()
        let twigDirection: CGFloat = focusX + kindsReach <= right || focusX - kindsReach < left ? 1 : -1
        /// 縦の線から外へ start の距離に置く，幅 width の物の左の端
        func minX(_ start: CGFloat, _ width: CGFloat) -> CGFloat { direction > 0 ? stemX + start : stemX - start - width }

        // 縦の並び．上から，見出し(連想)・文字種・境目の案内・幹の文節・幹の線・候補・候補の下の行
        let tag = Glass.tagHeight
        var y = metrics.inset
        if showsHeading {
            result.heading = NSRect(x: textInset, y: y, width: width - textInset * 2, height: metrics.noteHeight)
            y += metrics.noteHeight + gap * 2 + Size.frameWidth
        }
        if !kindWidths.isEmpty {
            let labelY = y
            y += tag + Space.inset
            result.twigY = (y + Map.stopSize / 2).rounded()
            y += Map.stopSize + Space.inset
            var kindX = twigDirection > 0 ? focusX + kindStart : focusX - kindsReach + (variantHintWidth > 0 ? variantHintWidth + Space.group : 0)
            for kindWidth in kindWidths {
                let label = NSRect(x: kindX.rounded(), y: labelY, width: kindWidth, height: tag)
                result.kinds.append(Kind(stop: NSPoint(x: label.minX + Part.rowPaddingX + Map.stopSize / 2, y: result.twigY), label: label))
                kindX += kindWidth + Map.stationGap
            }
            let labelsEnd = kindX - Map.stationGap
            result.twigEndX = twigDirection > 0 ? labelsEnd : (result.kinds.first?.label.minX ?? focusX)
            if variantHintWidth > 0 { result.variantHintX = twigDirection > 0 ? labelsEnd + Space.group : focusX - kindsReach }
        }
        if focus != nil, !showsHeading {
            result.boundaryMidY = y + tag / 2
            y += tag + Space.inset
        }
        let nodeTop = y
        y += metrics.rowHeight
        result.railY = (y + Map.railHeight / 2).rounded()
        y += Map.railHeight
        if !lower.isEmpty {
            y += Map.rowGap
            for index in lower.indices {
                result.rows.append(NSRect(x: minX(rowStart, rowEnd - rowStart), y: y + CGFloat(index) * metrics.rowHeight, width: rowEnd - rowStart,
                                          height: metrics.rowHeight))
            }
            y += CGFloat(lower.count) * metrics.rowHeight
        }
        var bottom = y
        if let pages = candidatePages, pages.count <= Int(Map.pageDotLimit) {
            let dots = PageDots(x: stemX, top: y + Space.inset, count: pages.count, current: pages.current)
            result.pageDots = dots
            bottom = max(bottom, dots.top + dots.height)
        }
        if hasBottom {
            result.bottomMidY = y + Space.inset + tag / 2
            result.bottomHintsX = minX(badgeOffset, bottomHintsWidth)
            let farX = minX(farStart, farWidth)
            // 位置は枝の外の端に，辞書の名前はその内側に置く
            result.positionX = direction > 0 ? farX + sourceWidth : farX
            result.sourceX = direction > 0 ? farX : farX + positionWidth + Size.paddingX
            bottom = max(bottom, y + Space.inset + tag)
        }
        if let selectedRow, result.rows.indices.contains(selectedRow) {
            let midY = result.rows[selectedRow].midY.rounded()
            for (title, stationOffset) in zip(titles, stationOffsets) {
                let titleWidth = textWidth(title, font: labelFont)
                let stopX = (direction > 0 ? stemX + stationOffset : stemX - stationOffset).rounded()
                result.stations.append(Station(title: title, stop: NSPoint(x: stopX, y: midY), titleX: stopX - titleWidth / 2,
                                               titleMidY: midY - Map.stopSize / 2 - Space.inset - tag / 2))
            }
            if let expandOffset, let expand = hints.expand {
                result.expandX = minX(expandOffset, BranchMapDrawing.hintWidth(expand, theme: theme))
                result.expandMidY = midY
            }
            if showsDetailStub {
                let from = direction > 0 ? stemX + rowEnd : stemX - rowEnd
                result.detailStub = (NSPoint(x: from, y: midY), NSPoint(x: from + direction * Map.stubLength, y: midY))
            }
            if let meaning, let meaningStation, result.stations.indices.contains(meaningStation) {
                let station = result.stations[meaningStation]
                let top = midY + Map.stopSize / 2 + Space.inset
                result.meaning = SideMeaning(text: meaning, lineX: station.stop.x, top: top,
                                             textX: direction > 0 ? station.stop.x + Map.meaningIndent : station.stop.x - Map.meaningIndent)
                result.meaningStation = meaningStation
                bottom = max(bottom, top + meaning.height)
            }
            if let itemStation, !items.isEmpty {
                // 丸の縦の線を，候補の縦の線と同じように使う(線から外への距離は候補と同じ)
                let lineX = result.stations[itemStation].stop.x
                func itemMinX(_ start: CGFloat, _ width: CGFloat) -> CGFloat { direction > 0 ? lineX + start : lineX - start - width }
                var itemY = midY + Map.stopSize / 2 + Space.inset
                if !itemLabelText.isEmpty {
                    result.itemLabel = (itemLabelText, itemMinX(badgeOffset, textWidth(itemLabelText, font: labelFont)), itemY + tag / 2)
                    itemY += tag
                }
                for index in items.indices {
                    result.itemRows.append(NSRect(x: itemMinX(rowStart, itemRowEnd - rowStart), y: itemY + CGFloat(index) * metrics.rowHeight,
                                                  width: itemRowEnd - rowStart, height: metrics.rowHeight))
                }
                itemY += CGFloat(items.count) * metrics.rowHeight
                result.itemStemX = lineX
                if let pages = itemPages, pages.count <= Int(Map.pageDotLimit) {
                    let dots = PageDots(x: lineX, top: itemY + Space.inset, count: pages.count, current: pages.current)
                    result.itemPageDots = dots
                    bottom = max(bottom, dots.top + dots.height)
                }
                if itemBottomWidth > 0 {
                    result.itemBottomMidY = itemY + Space.inset + tag / 2
                    result.itemHintsX = itemMinX(badgeOffset, itemHintsWidth)
                    if !itemPositionText.isEmpty {
                        result.itemPosition = (itemPositionText, itemMinX(itemRowEnd - itemPositionWidth, itemPositionWidth))
                    }
                    itemY += Space.inset + tag
                }
                bottom = max(bottom, itemY)
            }
        }
        // 候補の下の語の意味: 窓の中身の幅いっぱい
        if focus != nil, let below = meaningSlot(for: panel, width: right - left) {
            let frame = NSRect(x: left, y: bottom + gap, width: below.size.width, height: below.size.height)
            result.slot = below
            result.card = frame
            bottom = frame.maxY
        }
        result.notesTop = bottom
        let notes = (column?.usageNote == nil ? 0 : 1) + (panel.note == nil ? 0 : 1)
        let height = bottom + (gap + metrics.noteHeight) * CGFloat(notes) + metrics.inset

        result.nodes = panel.columns.indices.map { NSRect(x: (nodeX[$0] - shift).rounded(), y: nodeTop, width: nodeWidths[$0], height: metrics.rowHeight) }
        result.fadesLeft = result.overflows && shift > 0
        result.fadesRight = result.overflows && trunkRight - shift > right
        result.railStart = result.fadesLeft ? 0 : (result.nodes.first.map { $0.minX + stopOffset(width: $0.width) } ?? left)
        result.railEnd = result.fadesRight ? width : (result.nodes.last.map { $0.minX + stopOffset(width: $0.width) } ?? left)
        result.focus = focus
        result.focusX = focusX
        result.stemX = stemX
        result.direction = direction
        result.twigDirection = twigDirection
        result.boundaryX = max(min(focusX + boundaryStart, right - boundaryWidth), left)
        // 文字種の枝を畳んでいるとき: 文節の上へ，続きがある印の線を境目の案内の行の高さだけ伸ばす
        if panel.collapsesVariants, let boundaryMidY = result.boundaryMidY, column?.split == nil {
            result.variantStub = (NSPoint(x: focusX, y: nodeTop + metrics.rowInset), NSPoint(x: focusX, y: boundaryMidY - tag / 2))
        }
        result.trunkRight = trunkRight
        result.focusSpan = focus.map { nodeX[$0]...(nodeX[$0] + nodeWidths[$0] + nodeGap) }
        result.size = NSSize(width: width, height: height.rounded(.up))
        return result
    }

    /// 選んでいる文節が窓の内側に入るよう，幹を送る量を決め直す．入っていれば前の量のまま
    private func updateTrunkOffset() {
        guard let panel else {
            trunkOffset = 0
            return
        }
        let natural = layout(for: panel, offset: 0)
        guard natural.overflows, let span = natural.focusSpan else {
            trunkOffset = 0
            return
        }
        let inset = metrics.inset
        let visible = max(maximumWidth, Size.minWidth) - inset * 2
        var offset = trunkOffset
        // 左に出たら左端に，右に出たら右端にそろえる．文節が窓より広いときは左端を優先する
        if span.upperBound - offset > inset + visible { offset = span.upperBound - inset - visible }
        if span.lowerBound - offset < inset { offset = span.lowerBound - inset }
        trunkOffset = max(offset, 0)
    }

    func fittingSize(for panel: LatticePanel) -> NSSize {
        let size = layout(for: panel).size
        return NSSize(width: size.width + dropShadowOffset, height: size.height + dropShadowOffset)
    }

    // MARK: - 押した位置

    /// 押した対象を知らせる先(候補の窓をマウスで押したとき)
    var onChoose: ((PointerTarget) -> Void)?

    /// point(この view の座標)にある押せる対象．幹の文節と，選んでいる文節の候補・文字種．無ければ nil
    func target(at point: NSPoint) -> PointerTarget? {
        guard let panel else { return nil }
        let layout = layout(for: panel)
        // 文節は，文字と，その下の線の上の丸を押せる
        for (index, node) in layout.nodes.enumerated() {
            let area = NSRect(x: node.minX, y: node.minY, width: node.width, height: node.height + Map.railHeight)
            if area.contains(point) { return .segment(index) }
        }
        // 区切っているあいだ(⇧↓)は番号キーで区切る位置を選ぶので，枝は押せない
        guard let focus = layout.focus, panel.columns[focus].split == nil else { return nil }
        let column = panel.columns[focus]
        if panel.detail?.selectedItem != nil {
            let index = layout.itemRows.indices.first { layout.itemRows[$0].contains(point) }
            return index.flatMap { column.alternatives.indices.contains($0) ? .alternative($0) : nil }
        }
        if let index = layout.rows.indices.first(where: { rowArea(layout.rows[$0], in: layout).contains(point) }), column.alternatives.indices.contains(index) {
            // コメントのタグは行の中にあるので，行より先に調べる(タグを押すと候補の代わりにコメントを入れる)
            if let comment = column.comment(at: index) {
                let row = layout.rows[index]
                if NoteDrawing.tagHitRect(comment, maxX: tagMaxX(comment, in: row, direction: layout.direction), row: row, theme: theme).contains(point) {
                    return .comment(index)
                }
            }
            return .alternative(index)
        }
        if let index = layout.kinds.indices.first(where: { kindArea(layout.kinds[$0]).contains(point) }) { return .variant(index) }
        return nil
    }

    /// 候補の行の押せる範囲．縦の線の上の丸から行の端まで
    private func rowArea(_ row: NSRect, in layout: Layout) -> NSRect {
        let edge = Map.stopSizeSelected / 2
        let minX = min(row.minX, layout.stemX - edge)
        return NSRect(x: minX, y: row.minY, width: max(row.maxX, layout.stemX + edge) - minX, height: row.height)
    }

    /// 文字種の押せる範囲．文字と，その下の線の上の丸
    private func kindArea(_ kind: Kind) -> NSRect {
        NSRect(x: kind.label.minX, y: kind.label.minY, width: kind.label.width, height: kind.stop.y + Map.stopSize / 2 - kind.label.minY)
    }

    override func mouseDown(with event: NSEvent) {
        guard let target = target(at: convert(event.locationInWindow, from: nil)) else { return }
        onChoose?(target)
    }

    // 窓が前に出ていなくても 1 回目の押下で選ぶ(入力先のアプリからフォーカスを移さない)
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 描画

    // 線・丸・文字・案内の順に重ねる．1 か所で順を決めるので長い
    // swiftlint:disable:next function_body_length cyclomatic_complexity
    override func draw(_ dirtyRect: NSRect) {
        guard let panel else { return }
        let layout = layout(for: panel)
        let metrics = metrics
        let hints = hints(for: panel)
        let body = NSRect(origin: .zero, size: layout.size)
        if theme.isRounded {
            GlassDrawing.drawFrame(in: body, theme: theme, fillsSurface: fillsSurface)
        } else {
            BevelDrawing.drawDropShadow(for: body, theme: theme)
            BevelDrawing.drawPanel(in: body, theme: theme)
        }
        if let heading = panel.association, let row = layout.heading {
            AssociationHeadingDrawing.draw(heading, in: row, theme: theme, font: labelFont, emphasis: labelFont)
            theme.line.setFill()
            NSRect(x: metrics.inset, y: row.maxY + gap, width: body.width - metrics.inset * 2, height: Size.frameWidth).fill()
        }
        let column = layout.focus.map { panel.columns[$0] }
        let rows = column.map { candidateRows($0, in: panel) } ?? []
        let selectedRow = rows.firstIndex(where: \.isSelected)
        let items = itemRows(of: panel)
        let selectedItem = items.firstIndex(where: \.isSelected)
        let currentStation = panel.detail?.current
        let stale: CGFloat = column?.isEditing == true ? Opacity.editingStale : 1

        // 丸．線は丸の内側を通さない
        let trunkStops = layout.nodes.enumerated().map { index, node in
            Stop(center: NSPoint(x: node.minX + stopOffset(width: node.width), y: layout.railY), state: index == layout.focus ? .selected : .plain)
        }
        var branchStops: [Stop] = []
        for (index, row) in layout.rows.enumerated() where rows.indices.contains(index) {
            let state: Stop.State = index == selectedRow ? .selected : selectedRow.map { index < $0 } == true ? .passed : .plain
            branchStops.append(Stop(center: NSPoint(x: layout.stemX, y: row.midY.rounded()), state: state, opacity: rows[index].opacity))
        }
        for (index, kind) in layout.kinds.enumerated() {
            // 文節に近い側の丸ほど，選んだ道すじの途中になる
            let passed = column?.selectedVariant.map { layout.twigDirection > 0 ? index < $0 : index > $0 } ?? false
            branchStops.append(Stop(center: kind.stop, state: index == column?.selectedVariant ? .selected : passed ? .passed : .plain, opacity: stale))
        }
        for (index, station) in layout.stations.enumerated() {
            // 今いる丸は塗り，そこまでに通る丸は選択の色の輪にする
            let state: Stop.State = index == currentStation ? .selected : currentStation.map { index < $0 } == true ? .passed : .plain
            branchStops.append(Stop(center: station.stop, state: state))
        }
        for (index, row) in layout.itemRows.enumerated() {
            let state: Stop.State = index == selectedItem ? .selected : selectedItem.map { index < $0 } == true ? .passed : .plain
            branchStops.append(Stop(center: NSPoint(x: layout.itemStemX, y: row.midY.rounded()), state: state))
        }
        var senseStops: [Stop] = []
        if let meaning = layout.meaning {
            var y = meaning.top + (meaning.text.tag == nil ? 0 : Meaning.partOfSpeechHeight + Space.stack)
            for sense in meaning.text.senses {
                senseStops.append(Stop(center: NSPoint(x: meaning.lineX, y: (y + Meaning.meaningPitch / 2).rounded())))
                y += CGFloat(sense.meaning.count) * Meaning.meaningPitch + CGFloat(sense.example.count) * Meaning.examplePitch + Meaning.senseGap
            }
        }
        let focusStops = layout.focus.map { [trunkStops[$0]] } ?? []
        let avoided = branchStops + senseStops + focusStops

        // 幹．窓からはみ出す側は，端へ向けて透かす
        BranchMapDrawing.fading(left: layout.fadesLeft, right: layout.fadesRight, in: body) {
            var solid: [Line] = []
            var dotted: [Line] = []
            var cursor = layout.railStart
            for (index, node) in layout.nodes.enumerated() where panel.columns[index].isUncertain {
                // 確信の低い文節の下は点線
                // 幹の線は最初と最後の丸で止めるので，点線もその内側に収める
                let from = max(node.minX + Part.rowPaddingX, layout.railStart)
                let to = min(node.maxX - Part.rowPaddingX, layout.railEnd)
                guard to > from else { continue }
                if from > cursor { solid.append(Line(points: [NSPoint(x: cursor, y: layout.railY), NSPoint(x: from, y: layout.railY)])) }
                dotted.append(Line(points: [NSPoint(x: from, y: layout.railY), NSPoint(x: to, y: layout.railY)], dotted: true))
                cursor = to
            }
            if layout.railEnd > cursor { solid.append(Line(points: [NSPoint(x: cursor, y: layout.railY), NSPoint(x: layout.railEnd, y: layout.railY)])) }
            BranchMapDrawing.stroke(solid, color: theme.line, width: metrics.lineWidth, avoiding: trunkStops, in: body, theme: theme)
            BranchMapDrawing.stroke(dotted, color: theme.textMuted, width: metrics.lineWidthSelected, avoiding: trunkStops, in: body, theme: theme)
            BranchMapDrawing.draw(trunkStops, lineWidth: metrics.lineWidth, theme: theme)
            for (index, column) in panel.columns.enumerated() where layout.nodes[index].maxX >= 0 && layout.nodes[index].minX <= body.maxX {
                drawTrunkNode(column, in: layout.nodes[index])
            }
            // 文節へ移るキーを，文節の丸の上に重ねる(区切っているあいだは，番号キーが別の意味になるので出さない)
            if showsHints, !panel.columns.contains(where: { $0.split != nil }) {
                withHintOpacity(in: panel) {
                    for (index, column) in panel.columns.enumerated() {
                        guard let key = column.jumpKey else { continue }
                        let hint = KeyHint(key: key, label: "")
                        guard isShown(hint, in: panel) else { continue }
                        let stop = trunkStops[index]
                        BranchMapDrawing.drawHint(hint, x: stop.center.x - BranchMapDrawing.hintWidth(hint, theme: theme) / 2, midY: stop.center.y,
                                                  theme: theme, selected: index == layout.focus)
                    }
                }
            }
        }

        // 枝の線．選んでいない線をまとめて描き，選んだ道すじを選択の色と太さで上に重ねる
        var lines: [Line] = []
        var route: [Line] = []
        if let focus = layout.focus {
            let node = layout.nodes[focus]
            if let last = layout.rows.last, let first = layout.rows.first {
                let stem = stemPoints(to: last.midY.rounded(), in: layout, firstRow: first)
                lines.append(Line(points: stem, radius: bendRadius(in: layout, firstRow: first)))
                if let selectedRow, layout.rows.indices.contains(selectedRow) {
                    route.append(Line(points: stemPoints(to: layout.rows[selectedRow].midY.rounded(), in: layout, firstRow: first),
                                      radius: bendRadius(in: layout, firstRow: first)))
                }
            }
            if !layout.kinds.isEmpty {
                let top = NSPoint(x: layout.focusX, y: node.minY + metrics.rowInset)
                let corner = NSPoint(x: layout.focusX, y: layout.twigY)
                lines.append(Line(points: [top, corner, NSPoint(x: layout.twigEndX, y: layout.twigY)], radius: metrics.turnRadius))
                if let selected = column?.selectedVariant, layout.kinds.indices.contains(selected) {
                    route.append(Line(points: [top, corner, NSPoint(x: layout.kinds[selected].stop.x, y: layout.twigY)], radius: metrics.turnRadius))
                }
            }
        }
        if let selectedRow, layout.rows.indices.contains(selectedRow), let last = layout.stations.last {
            let row = layout.rows[selectedRow]
            lines.append(Line(points: [NSPoint(x: layout.direction > 0 ? row.maxX : row.minX, y: last.stop.y), last.stop]))
        }
        if let meaning = layout.meaning, let last = senseStops.last, let index = layout.meaningStation, layout.stations.indices.contains(index) {
            lines.append(Line(points: [layout.stations[index].stop, NSPoint(x: meaning.lineX, y: last.center.y)]))
        }
        // 今いる丸とその中身: 選んだ候補から丸までと，丸から選んだ中身までを，選んだ道すじにする
        if let currentStation, layout.stations.indices.contains(currentStation), let selectedRow, layout.rows.indices.contains(selectedRow) {
            let row = layout.rows[selectedRow]
            let station = layout.stations[currentStation].stop
            route.append(Line(points: [NSPoint(x: layout.direction > 0 ? row.maxX : row.minX, y: station.y), station]))
            if let last = layout.itemRows.last {
                lines.append(Line(points: [station, NSPoint(x: layout.itemStemX, y: last.midY.rounded())]))
            }
            if let selectedItem, layout.itemRows.indices.contains(selectedItem) {
                route.append(Line(points: [station, NSPoint(x: layout.itemStemX, y: layout.itemRows[selectedItem].midY.rounded())]))
            }
        }
        BranchMapDrawing.stroke(lines, color: theme.line.withAlphaComponent(theme.line.alphaComponent * stale), width: metrics.lineWidth,
                                avoiding: avoided, in: body, theme: theme)
        BranchMapDrawing.stroke(route, color: theme.selection, width: metrics.lineWidthSelected, avoiding: avoided, in: body, theme: theme)
        BranchMapDrawing.draw(branchStops + senseStops, lineWidth: metrics.lineWidth, theme: theme)
        // ページの位置を示す点
        for dots in [layout.pageDots, layout.itemPageDots].compactMap({ $0 }) {
            BranchMapDrawing.drawPageDots(x: dots.x, top: dots.top, count: dots.count, current: dots.current, theme: theme)
        }
        // 畳んでいる枝の，続きがある印
        for stub in [layout.variantStub, layout.detailStub].compactMap({ $0 }) {
            // 線の色のままだと透かした先が見えないので，控えめな文字の色から透かす
            BranchMapDrawing.drawFadingLine(from: stub.from, to: stub.to, color: theme.textMuted.withAlphaComponent(theme.textMuted.alphaComponent * stale),
                                            width: metrics.lineWidth)
        }

        // 候補・文字種・先の枝の見出し・語の意味
        for (index, row) in layout.rows.enumerated() where rows.indices.contains(index) {
            drawRow(rows[index], in: row, direction: layout.direction)
        }
        if let column {
            let keys = variantKeys(of: column)
            for (index, kind) in layout.kinds.enumerated() where column.variants.indices.contains(index) {
                drawKind(column.variants[index], key: keys[index], in: kind.label, selected: index == column.selectedVariant, opacity: stale)
            }
        }
        for (index, station) in layout.stations.enumerated() {
            let color = index == currentStation ? theme.text : theme.textMuted
            TextFitting.draw(station.title, attributes: [.font: labelFont, .foregroundColor: color], x: station.titleX, midY: station.titleMidY)
        }
        for (index, row) in layout.itemRows.enumerated() where items.indices.contains(index) {
            drawRow(items[index], in: row, direction: layout.direction)
        }
        if let label = layout.itemLabel {
            TextFitting.draw(label.text, attributes: [.font: labelFont, .foregroundColor: theme.textMuted], x: label.x, midY: label.midY)
        }
        if let midY = layout.itemBottomMidY, let position = layout.itemPosition {
            TextFitting.draw(position.text, attributes: [.font: labelFont, .foregroundColor: theme.textMuted], x: position.x, midY: midY)
        }
        if let meaning = layout.meaning { drawMeaning(meaning, direction: layout.direction) }

        // キーの案内と，文節の境目のつまみ
        withHintOpacity(in: panel) {
            if let midY = layout.boundaryMidY, !hints.boundary.isEmpty {
                drawHints(hints.boundary, x: layout.boundaryX, midY: midY, in: panel)
                // 境目のつまみは，境目を動かすキーの案内と一緒に出す
                if let focus = layout.focus, column?.split == nil, column?.isEditing == false, hints.boundary.first.map({ isShown($0, in: panel) }) == true {
                    let node = layout.nodes[focus]
                    BranchMapDrawing.drawGrip(x: node.maxX + Map.segmentGap, midY: node.midY, height: (trunkFont.ascender - trunkFont.descender).rounded(),
                                              theme: theme)
                }
            }
            if let x = layout.variantHintX, let hint = hints.variant, let label = layout.kinds.first?.label, isShown(hint, in: panel) {
                BranchMapDrawing.drawHint(hint, x: x, midY: label.midY, theme: theme)
            }
            if let x = layout.expandX, let hint = hints.expand, isShown(hint, in: panel) {
                BranchMapDrawing.drawHint(hint, x: x, midY: layout.expandMidY, theme: theme)
            }
            if let midY = layout.bottomMidY { drawHints(hints.candidates, x: layout.bottomHintsX, midY: midY, in: panel) }
            if let midY = layout.itemBottomMidY { drawHints(hints.items, x: layout.itemHintsX, midY: midY, in: panel) }
        }
        if let midY = layout.bottomMidY {
            let text = pageText(showsPosition(panel) && panel.detail?.selectedItem == nil
                ? pages(position: panel.position, total: panel.total, pageSize: panel.pageSize) : nil)
            if !text.isEmpty, !rows.isEmpty {
                TextFitting.draw(text, attributes: [.font: labelFont, .foregroundColor: theme.textMuted], x: layout.positionX, midY: midY)
            }
            if let source = column?.sourceName {
                // 選んでいる候補が取り込んだ辞書の語なら，その辞書の名前を小さく出す(R-16)
                TextFitting.draw(UIStrings.Branch.dictionarySource(source), attributes: [.font: labelFont, .foregroundColor: theme.correction],
                                 x: layout.sourceX, midY: midY)
            }
        }

        // 候補の下の語の意味，注釈，知らせ
        if let slot = layout.slot, let card = layout.card { MeaningCardDrawing.drawContent(slot.layout, in: card, theme: theme) }
        var noteY = layout.notesTop
        if let note = column?.usageNote {
            let row = NSRect(x: textInset, y: noteY + gap, width: body.width - textInset * 2, height: metrics.noteHeight)
            TextFitting.draw(note, attributes: [.font: labelFont, .foregroundColor: theme.textMuted], x: row.minX, midY: row.midY)
            noteY = row.maxY
        }
        if let note = panel.note {
            // 打ち間違いを直したことなど，IME が変えたことを知らせる
            let row = NSRect(x: textInset, y: noteY + gap, width: body.width - textInset * 2, height: metrics.noteHeight)
            NoteDrawing.draw(note, x: row.minX, midY: row.midY, theme: theme)
        }
    }

    /// 選んでいる文節の丸から，候補の縦の線を y まで下ろす道すじ．枝を寄せているときは，幹の線と最初の候補のあいだで横へ曲げる
    private func stemPoints(to y: CGFloat, in layout: Layout, firstRow: NSRect) -> [NSPoint] {
        let start = NSPoint(x: layout.focusX, y: layout.railY)
        guard layout.stemX != layout.focusX else { return [start, NSPoint(x: layout.stemX, y: y)] }
        let bendY = ((layout.railY + Map.railHeight / 2 + firstRow.minY) / 2).rounded()
        return [start, NSPoint(x: layout.focusX, y: bendY), NSPoint(x: layout.stemX, y: bendY), NSPoint(x: layout.stemX, y: y)]
    }

    /// 寄せた枝の曲がり角の半径．横と縦の線の長さに収まるようにする
    private func bendRadius(in layout: Layout, firstRow: NSRect) -> CGFloat {
        let vertical = (firstRow.minY - layout.railY - Map.railHeight / 2) / 2
        return max(min(metrics.turnRadius, abs(layout.stemX - layout.focusX) / 2, vertical), 0)
    }

    // MARK: - 幹

    private func drawTrunkNode(_ column: LatticePanel.Column, in node: NSRect) {
        if column.isEditing {
            drawEditingNode(column, in: node)
            return
        }
        let color: NSColor
        // 矢印で木をたどっていて幹の上にいるときは，文節を候補と同じ強い選択で見せる(今いる場所)
        let onTrunk = column.isFocused && panel?.trunkFocused == true
        if theme.isRounded {
            if column.isFocused {
                GlassDrawing.fillCapsule(node.insetBy(dx: 0, dy: Glass.selectionInsetY), color: onTrunk ? theme.selection : theme.focusTint)
            }
            color = onTrunk ? theme.selectionText : theme.text
        } else {
            if column.isFocused {
                theme.selection.setFill()
                node.fill()
            }
            color = column.isFocused ? theme.selectionText : theme.text
        }
        if let split = column.split {
            drawSplit(split, in: node, color: color)
        } else if let command = trunkCommand(column) {
            // コマンドを選んでいれば，幹も枝と同じく種類のアイコンと名前で見せる(入力中の文字には印を付けた名前が出る)
            CommandDrawing.drawIcon(command.kind, x: node.minX + Part.rowPaddingX, midY: node.midY, theme: theme, selected: !theme.isRounded && column.isFocused)
            TextFitting.draw(command.title, attributes: [.font: trunkFont, .foregroundColor: color], x: node.minX + Part.rowPaddingX + CommandDrawing.width,
                             midY: node.midY)
        } else {
            TextFitting.draw(column.text, attributes: [.font: trunkFont, .foregroundColor: color], x: node.minX + Part.rowPaddingX, midY: node.midY)
        }
        if column.isCorrected {
            // 打ち間違いを直した文節には，文字のあとに補正の色で「修正」と添える．確信の低い文節の点線と見分けるため
            NoteDrawing.drawTag(UIStrings.Branch.corrected, maxX: node.maxX - Part.rowPaddingX, midY: node.midY, theme: theme,
                                selected: !theme.isRounded && column.isFocused)
        }
    }

    /// その場で打ち直している文節(⇧⌫)の幹．塗らずに選択の色の枠線で囲み，打っている読みのあとに入力位置の線を置く．
    /// 読みが空のあいだも枠を残し，どこを打ち直しているかを見せる
    private func drawEditingNode(_ column: LatticePanel.Column, in node: NSRect) {
        let stroke = DesignTokens.Size.Part.stroke
        theme.selection.setStroke()
        if theme.isRounded {
            let frame = node.insetBy(dx: stroke / 2, dy: Glass.selectionInsetY + stroke / 2)
            let path = NSBezierPath(roundedRect: frame, xRadius: Glass.selectionRadius, yRadius: Glass.selectionRadius)
            path.lineWidth = stroke
            path.stroke()
        } else {
            let path = NSBezierPath(rect: node.insetBy(dx: stroke / 2, dy: stroke / 2))
            path.lineWidth = stroke
            path.stroke()
        }
        let x = node.minX + Part.rowPaddingX
        TextFitting.draw(column.text, attributes: [.font: trunkFont, .foregroundColor: theme.text], x: x, midY: node.midY)
        let height = (trunkFont.ascender - trunkFont.descender).rounded()
        theme.selection.setFill()
        NSRect(x: (x + textWidth(column.text, font: trunkFont)).rounded(), y: (node.midY - height / 2).rounded(), width: Glass.editingCaretWidth,
               height: height).fill()
    }

    /// 幹の文節で選んでいるコマンドの種類と名前．コマンドを選んでいなければ nil
    private func trunkCommand(_ column: LatticePanel.Column) -> (kind: LauncherCommand.Kind, title: String)? {
        guard let index = column.selectedAlternative, column.alternativeCommands.indices.contains(index), column.alternatives.indices.contains(index),
              let kind = column.alternativeCommands[index] else { return nil }
        return (kind, column.alternatives[index])
    }

    // MARK: - 区切る位置

    /// 区切る位置の番号を挟んだ文節の並び．runs は番号のあいだの字と左端，badges は番号と丸の中心(幹の文字の左端から)
    private struct SplitPieces {
        var runs: [(text: String, x: CGFloat)] = []
        var badges: [(label: String, centerX: CGFloat)] = []
        var width: CGFloat = 0
    }

    private func splitPieces(_ split: LatticePanel.Column.Split) -> SplitPieces {
        let slot = Branch.splitBadgeSize + Branch.splitBadgeGap * 2
        var pieces = SplitPieces()
        var x: CGFloat = 0
        for (index, text) in split.pieces.enumerated() {
            if index > 0 {
                pieces.badges.append(("\(index)", x + slot / 2))
                x += slot
            }
            pieces.runs.append((text, x))
            x += textWidth(text, font: trunkFont)
        }
        pieces.width = x
        return pieces
    }

    /// 区切っている文節の幹．切れ目(「問題｜が｜ある」)に，小さな丸で番号を描く
    private func drawSplit(_ split: LatticePanel.Column.Split, in node: NSRect, color: NSColor) {
        let pieces = splitPieces(split)
        let left = node.minX + Part.rowPaddingX
        for run in pieces.runs {
            TextFitting.draw(run.text, attributes: [.font: trunkFont, .foregroundColor: color], x: left + run.x, midY: node.midY)
        }
        // platinum と desk は選んでいる文節を選択の色で塗るので，丸も選んでいる行の上の描き方にする
        for badge in pieces.badges {
            GlassDrawing.drawBadge(badge.label, center: NSPoint(x: (left + badge.centerX).rounded(), y: node.midY.rounded()), theme: theme,
                                   selected: !theme.isRounded, opacity: 1, size: Branch.splitBadgeSize, fontSize: Branch.splitBadgeFontSize)
        }
    }

    // MARK: - 枝

    private struct Row {
        var text: String
        var badge: String
        var isSelected: Bool
        var opacity: CGFloat
        /// 打ったまま・修正・コマンドの添え書きか，ユーザー辞書の語のコメント
        var note: String?
        /// コマンドの候補なら，その種類(文字の前にアイコンを置き，添え書きをアクセントの色のタグにする)
        var command: LauncherCommand.Kind?
        /// 文字のすぐあとに控えめに添える説明(絵文字の名前)
        var detail: String?
        /// 番号をキーキャップにしない(番号キーが，この行ではなく先の枝の中身を選ぶあいだ)
        var isPlain = false
        /// 選択の背景を薄くする(選んだままだが，今は先の枝の丸か中身にいる)
        var isSoft = false
    }

    /// 候補の列に出す行．先の枝の丸の中身に入っているあいだは，元の候補を控えめに出す(番号は中身に付く)
    private func candidateRows(_ column: LatticePanel.Column, in panel: LatticePanel) -> [Row] {
        guard let detail = panel.detail, !panel.trunkFocused else {
            // 幹の上にいるあいだは，選んでいる候補の背景を薄くする(今いる場所は文節)
            return lowerRows(column).map { row in
                var row = row
                row.isSoft = panel.trunkFocused
                return row
            }
        }
        guard detail.selectedItem != nil else {
            // 丸の上にいるあいだは，選んでいる候補の背景を薄くする(今いる場所は丸)
            return lowerRows(column).map { row in
                var row = row
                row.isSoft = detail.current != nil
                return row
            }
        }
        return detail.candidates.enumerated().map { index, text in
            Row(text: text, badge: "\(index + 1)", isSelected: index == detail.selectedCandidate, opacity: 1, isPlain: true, isSoft: true)
        }
    }

    /// 今いる丸の中身(連想の語・マクロの結果)の行
    private func itemRows(of panel: LatticePanel) -> [Row] {
        guard let detail = panel.detail, detail.current != nil else { return [] }
        return detail.items.enumerated().map { index, text in
            Row(text: text, badge: "\(index + 1)", isSelected: index == detail.selectedItem, opacity: 1, isPlain: detail.selectedItem == nil)
        }
    }

    /// 中身の説明．連想のまとまりの意味と，まとまりが 2 つ以上あればその位置
    private func itemLabel(_ detail: BranchDetail) -> String {
        guard detail.current != nil, !detail.items.isEmpty else { return "" }
        let group = detail.groupCount > 1 ? UIStrings.Association.groupPosition(detail.group, detail.groupCount) : ""
        return [detail.label, group].filter { !$0.isEmpty }.joined(separator: "  ")
    }

    /// 中身の位置．1 ページに入りきらないときだけ出す
    private func itemPosition(_ detail: BranchDetail, count: Int) -> String {
        guard detail.current != nil, detail.total > count, count > 0 else { return "" }
        return UIStrings.Branch.position(first: detail.position, last: detail.position + count - 1, total: detail.total)
    }

    /// 下の枝(変換の候補)．第 1 候補はすぐに濃く出す
    private func lowerRows(_ column: LatticePanel.Column) -> [Row] {
        column.alternatives.enumerated().map { index, text in
            Row(text: text, badge: "\(index + 1)", isSelected: index == column.selectedAlternative,
                opacity: column.isEditing ? Opacity.editingStale : index == 0 ? 1 : restOpacity,
                note: column.alternativeNotes.indices.contains(index) ? column.alternativeNotes[index] : nil,
                command: column.alternativeCommands.indices.contains(index) ? column.alternativeCommands[index] : nil,
                detail: column.alternativeDetails.indices.contains(index) ? column.alternativeDetails[index] : nil)
        }
    }

    /// 候補の行の添え書きのタグの右端．タグは，縦の線から遠い側の端に置く
    private func tagMaxX(_ note: String, in row: NSRect, direction: CGFloat) -> CGFloat {
        direction > 0 ? row.maxX - Part.rowPaddingX : row.minX + Part.rowPaddingX + NoteDrawing.tagWidth(note, theme: theme)
    }

    /// 候補の行．縦の線に近い側から，番号・文字・添え書きの順に並べる(枝を左右に反転したときは右から)
    private func drawRow(_ row: Row, in rect: NSRect, direction: CGFloat) {
        // 薄い選択(今は先の枝にいる)は，文節と同じ薄い背景にして，文字はふつうの色のままにする
        let solid = row.isSelected && !row.isSoft
        let textColor = (solid ? theme.selectionText : theme.text).withAlphaComponent(row.isSelected ? 1 : row.opacity)
        let mutedColor = (solid ? theme.selectionText : theme.textMuted).withAlphaComponent(row.isSelected ? 1 : row.opacity)
        if row.isSelected {
            let fill = solid ? theme.selection : theme.focusTint
            if theme.isRounded {
                GlassDrawing.fillCapsule(rect.insetBy(dx: 0, dy: Glass.selectionInsetY), color: fill)
            } else {
                fill.setFill()
                rect.fill()
            }
        }
        // 番号は番号キーで選べるので，キーキャップの形にする
        let badgeX = direction > 0 ? rect.minX + Part.rowPaddingX : rect.maxX - Part.rowPaddingX - Glass.badgeSize
        let badge = NSRect(x: badgeX.rounded(), y: (rect.midY - Glass.badgeSize / 2).rounded(), width: Glass.badgeSize, height: Glass.badgeSize)
        if theme.isRounded, !row.isPlain { BranchMapDrawing.drawBadgeBox(badge, theme: theme, selected: solid) }
        GlassDrawing.drawLabel(row.badge, color: mutedColor, in: badge, theme: theme)
        let line = CandidateDetailDrawing.line(row.text, attributes: [.font: candidateFont, .foregroundColor: textColor], detail: row.detail,
                                               detailAttributes: [.font: labelFont, .foregroundColor: mutedColor])
        let icon: CGFloat = row.command == nil ? 0 : CommandDrawing.width
        let contentWidth = icon + line.size().width.rounded(.up)
        let contentX = direction > 0 ? badge.maxX + Glass.badgeGap : badge.minX - Glass.badgeGap - contentWidth
        if let kind = row.command {
            // コマンドの候補は，文字の前に種類のアイコンを置く
            CommandDrawing.drawIcon(kind, x: contentX, midY: rect.midY, theme: theme, selected: solid, opacity: row.isSelected ? 1 : row.opacity)
        }
        CandidateDetailDrawing.draw(line, x: contentX + icon, in: rect)
        if let note = row.note {
            NoteDrawing.drawTag(note, maxX: tagMaxX(note, in: rect, direction: direction), midY: rect.midY, theme: theme, selected: solid,
                                command: row.command != nil)
        }
    }

    /// 文字種．選んでいるものは選択の背景で囲む
    private func drawKind(_ text: String, key: String?, in label: NSRect, selected: Bool, opacity: CGFloat) {
        if selected {
            if theme.isRounded {
                GlassDrawing.fillCapsule(label, color: theme.selection)
            } else {
                theme.selection.setFill()
                label.fill()
            }
        }
        let color = selected ? theme.selectionText : theme.text.withAlphaComponent(theme.text.alphaComponent * opacity)
        var textX = label.minX + Part.rowPaddingX
        if let key {
            BranchMapDrawing.drawKey(key, x: textX, midY: label.midY, theme: theme, selected: selected)
            textX += BranchMapDrawing.keyWidth(key, theme: theme) + Space.inline
        }
        TextFitting.draw(text, attributes: [.font: labelFont, .foregroundColor: color], x: textX, midY: label.midY)
    }

    /// 枝として出す語の意味．品詞のタグと，意味ごとの文と使い方の例．文は縦の線に近い側の端にそろえる
    private func drawMeaning(_ meaning: SideMeaning, direction: CGFloat) {
        func x(_ width: CGFloat) -> CGFloat { direction > 0 ? meaning.textX : meaning.textX - width }
        var y = meaning.top
        if let tag = meaning.text.tag {
            let width = partOfSpeechWidth(tag)
            let rect = NSRect(x: x(width).rounded(), y: y.rounded(), width: width, height: Meaning.partOfSpeechHeight)
            let stroke = Part.stroke
            let frame = rect.insetBy(dx: stroke / 2, dy: stroke / 2)
            let path = theme.isRounded ? NSBezierPath(roundedRect: frame, xRadius: Map.badgeRadius, yRadius: Map.badgeRadius) : NSBezierPath(rect: frame)
            path.lineWidth = stroke
            theme.line.setStroke()
            path.stroke()
            GlassDrawing.drawLineCentered(tag, attributes: [.font: partOfSpeechFont, .foregroundColor: theme.textMuted], in: rect)
            y += Meaning.partOfSpeechHeight + Space.stack
        }
        for sense in meaning.text.senses {
            for line in sense.meaning {
                TextFitting.draw(line, x: x(line.size().width.rounded(.up)), midY: y + Meaning.meaningPitch / 2)
                y += Meaning.meaningPitch
            }
            for line in sense.example {
                TextFitting.draw(line, x: x(line.size().width.rounded(.up)), midY: y + Meaning.examplePitch / 2)
                y += Meaning.examplePitch
            }
            y += Meaning.senseGap
        }
    }

    // MARK: - 位置

    /// 何番目の候補かを出すか．区切っているときは候補を出さないので出さない
    private func showsPosition(_ panel: LatticePanel) -> Bool {
        panel.columns.first(where: \.isFocused)?.split == nil
    }

    private func position(of panel: LatticePanel) -> String {
        let count = panel.columns.first(where: \.isFocused)?.alternatives.count ?? 0
        return UIStrings.Branch.position(first: panel.position, last: panel.position + max(count, 1) - 1, total: panel.total)
    }
}

extension LatticePanel.Column {
    /// 下の枝の index 番目の候補に添えたユーザー辞書の語のコメント(タグに出す文字．長ければ先頭だけ)．コメントでなければ nil
    func comment(at index: Int) -> String? {
        guard alternativeComments.indices.contains(index), alternativeComments[index], alternativeNotes.indices.contains(index) else { return nil }
        return alternativeNotes[index]
    }
}
