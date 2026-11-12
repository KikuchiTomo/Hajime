import HajimeApplication
import HajimeDomain

// 絵文字と記号のパレット(R-26)を，エンジンと候補ウィンドウのあいだで送る形にする．
// 候補ウィンドウは PalettePanel をそのまま描き，マウスで押した対象(WirePaletteTarget)をエンジンに返す

extension PaletteSection.Kind {
    /// 送るときの名前．表のまとまりは PaletteCategory の値
    public var wireName: String {
        switch self {
        case .pinned: "pinned"
        case .frequent: "frequent"
        case .results: "results"
        case .category(let category): category.rawValue
        }
    }

    public init?(wireName: String) {
        switch wireName {
        case "pinned": self = .pinned
        case "frequent": self = .frequent
        case "results": self = .results
        default:
            guard let category = PaletteCategory(rawValue: wireName) else { return nil }
            self = .category(category)
        }
    }
}

extension WirePaletteKind {
    public init(_ kind: PaletteItem.Kind) {
        switch kind {
        case .emoji: self = .emoji
        case .symbol: self = .symbol
        case .kaomoji: self = .kaomoji
        }
    }
}

extension PaletteItem.Kind {
    public init(_ wire: WirePaletteKind) {
        switch wire {
        case .emoji: self = .emoji
        case .symbol: self = .symbol
        case .kaomoji: self = .kaomoji
        }
    }
}

extension WireSkinTone {
    public init(_ tone: SkinTone) {
        switch tone {
        case .none: self = .none
        case .light: self = .light
        case .mediumLight: self = .mediumLight
        case .medium: self = .medium
        case .mediumDark: self = .mediumDark
        case .dark: self = .dark
        }
    }
}

extension SkinTone {
    public init(_ wire: WireSkinTone) {
        switch wire {
        case .none: self = .none
        case .light: self = .light
        case .mediumLight: self = .mediumLight
        case .medium: self = .medium
        case .mediumDark: self = .mediumDark
        case .dark: self = .dark
        }
    }
}

extension WirePalettePanel {
    /// cellSize は設定のパレットのマスの大きさ(macOS は窓が設定を読むが，Windows の候補ウィンドウは設定を読まないので添える)
    public init(_ panel: PalettePanel, cellSize: Double) {
        self.init(
            modes: panel.modes.map { WirePaletteMode(kind: WirePaletteKind($0.kind), title: $0.title, isSelected: $0.isSelected) },
            query: panel.query,
            placeholder: panel.placeholder,
            tabs: panel.tabs.map { WirePaletteTab(section: $0.section.wireName, title: $0.title, symbol: $0.symbol, isSelected: $0.isSelected) },
            heading: panel.heading,
            rows: panel.rows.map { row in
                WirePaletteRow(index: UInt32(clamping: row.index),
                               cells: row.cells.map { WirePaletteCell(text: $0.text, name: $0.name, isPinned: $0.isPinned) },
                               startsSection: row.startsSection, sectionTitle: row.sectionTitle)
            },
            rowCount: UInt32(clamping: panel.rowCount),
            firstRow: UInt32(clamping: panel.firstRow),
            columns: UInt32(clamping: panel.columns),
            visibleRows: UInt32(clamping: panel.visibleRows),
            selection: panel.selection.map { WirePalettePosition(row: UInt32(clamping: $0.row), column: UInt32(clamping: $0.column)) },
            // 見出しの名前は japaneseName に，Unicode の名前(並びは CLDR の英語の名前)は englishName に入れる．
            // 名前を定めたところは後から足した項目なので，知らない候補ウィンドウは読み飛ばす
            preview: panel.preview.map {
                WirePalettePreview(text: $0.text, japaneseName: $0.name, englishName: $0.unicodeName, shortcodes: $0.shortcodes,
                                   readings: $0.readings, codePoints: $0.codePoints.joined(separator: " "), isPinned: $0.isPinned,
                                   nameSource: $0.nameSource, englishNameSource: $0.unicodeNameSource)
            },
            showsPreview: panel.showsPreview,
            skinTone: WireSkinTone(panel.skinTone),
            skinTonePicker: panel.skinTonePicker.map { WirePaletteSkinTonePicker(options: $0.options, selected: UInt32(clamping: $0.selected)) },
            message: panel.message,
            hints: panel.hints.map { WireKeyHint(keys: $0.key, label: $0.action) },
            cellSize: cellSize,
            // 四角いマスだけなら省く(顔文字を知らない候補ウィンドウにも同じ形で送る)
            cellsPerRow: panel.cellsPerRow == panel.columns ? nil : UInt32(clamping: panel.cellsPerRow),
            previewFields: WirePalettePreviewFields(unicodeName: panel.previewFields.unicodeName, readings: panel.previewFields.readings,
                                                    shortcodes: panel.previewFields.shortcodes, codePoints: panel.previewFields.codePoints)
        )
    }
}

extension PaletteTarget {
    /// 候補ウィンドウから届いた対象．知らないまとまりは nil(新しいバージョンの候補ウィンドウとつながっても落とさない)
    public init?(_ wire: WirePaletteTarget) {
        func position(_ row: UInt32, _ column: UInt32) -> PalettePanel.Position {
            PalettePanel.Position(row: Int(row), column: Int(column))
        }
        switch wire {
        case .cell(let row, let column): self = .cell(position(row, column))
        case .hover(let row, let column): self = .hover(position(row, column))
        case .tab(let section):
            guard let kind = PaletteSection.Kind(wireName: section) else { return nil }
            self = .tab(kind)
        case .mode(let kind): self = .mode(PaletteItem.Kind(kind))
        case .scroll(let rows): self = .scroll(Int(rows))
        case .skinTone(let tone): self = .skinTone(SkinTone(tone))
        case .skinToneButton: self = .skinToneButton
        case .pin: self = .pin
        case .close: self = .close
        }
    }
}
