// このファイルは tools/tokens/generate_swift.py が design/tokens/tokens.json から作る．手で編集しない．

import CoreGraphics

struct RGB: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
}

struct ThemePalette: Equatable, Sendable {
    let bevelLight: RGB
    let bevelShadow: RGB
    let correction: RGB
    let frame: RGB
    let prediction: RGB
    let selection: RGB
    let selectionText: RGB
    let surface: RGB
    let text: RGB
    let textMuted: RGB
}

enum DesignTokens {
    enum Palette {
        static let standard = ThemePalette(
            bevelLight: RGB(red: 0x1E, green: 0x1E, blue: 0x1E),
            bevelShadow: RGB(red: 0x1E, green: 0x1E, blue: 0x1E),
            correction: RGB(red: 0xFF, green: 0x37, blue: 0x5F),
            frame: RGB(red: 0xA9, green: 0xA8, blue: 0xB6),
            prediction: RGB(red: 0xA9, green: 0xA8, blue: 0xB6),
            selection: RGB(red: 0x01, green: 0x69, blue: 0xFF),
            selectionText: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            surface: RGB(red: 0x1E, green: 0x1E, blue: 0x1E),
            text: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            textMuted: RGB(red: 0xFF, green: 0xFF, blue: 0xFF)
        )
        static let platinum = ThemePalette(
            bevelLight: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            bevelShadow: RGB(red: 0x99, green: 0x99, blue: 0x99),
            correction: RGB(red: 0xCC, green: 0x33, blue: 0x66),
            frame: RGB(red: 0x00, green: 0x00, blue: 0x00),
            prediction: RGB(red: 0x66, green: 0x66, blue: 0x66),
            selection: RGB(red: 0x33, green: 0x66, blue: 0x99),
            selectionText: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            surface: RGB(red: 0xDD, green: 0xDD, blue: 0xDD),
            text: RGB(red: 0x00, green: 0x00, blue: 0x00),
            textMuted: RGB(red: 0x55, green: 0x55, blue: 0x55)
        )
        static let desk = ThemePalette(
            bevelLight: RGB(red: 0x44, green: 0x22, blue: 0x77),
            bevelShadow: RGB(red: 0x11, green: 0x00, blue: 0x22),
            correction: RGB(red: 0x33, green: 0xFF, blue: 0xCC),
            frame: RGB(red: 0x00, green: 0x00, blue: 0x00),
            prediction: RGB(red: 0x99, green: 0x77, blue: 0xBB),
            selection: RGB(red: 0xFF, green: 0x33, blue: 0x99),
            selectionText: RGB(red: 0x22, green: 0x00, blue: 0x44),
            surface: RGB(red: 0x22, green: 0x00, blue: 0x44),
            text: RGB(red: 0xFF, green: 0xCC, blue: 0x66),
            textMuted: RGB(red: 0x99, green: 0x77, blue: 0xBB)
        )
        static let washi = ThemePalette(
            bevelLight: RGB(red: 0xFF, green: 0xFB, blue: 0xF2),
            bevelShadow: RGB(red: 0xD8, green: 0xCD, blue: 0xB8),
            correction: RGB(red: 0x1D, green: 0x4E, blue: 0x89),
            frame: RGB(red: 0xC9, green: 0xBC, blue: 0xA3),
            prediction: RGB(red: 0x6B, green: 0x5F, blue: 0x53),
            selection: RGB(red: 0xB3, green: 0x26, blue: 0x2D),
            selectionText: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            surface: RGB(red: 0xF5, green: 0xEF, blue: 0xE3),
            text: RGB(red: 0x2A, green: 0x24, blue: 0x20),
            textMuted: RGB(red: 0x6B, green: 0x5F, blue: 0x53)
        )
        static let neon = ThemePalette(
            bevelLight: RGB(red: 0x2B, green: 0x24, blue: 0x59),
            bevelShadow: RGB(red: 0x1C, green: 0x17, blue: 0x40),
            correction: RGB(red: 0x2E, green: 0xE6, blue: 0xFF),
            frame: RGB(red: 0x3D, green: 0x34, blue: 0x80),
            prediction: RGB(red: 0xA6, green: 0x9E, blue: 0xDB),
            selection: RGB(red: 0xFF, green: 0x2E, blue: 0x93),
            selectionText: RGB(red: 0x14, green: 0x00, blue: 0x1F),
            surface: RGB(red: 0x0E, green: 0x0B, blue: 0x22),
            text: RGB(red: 0xF1, green: 0xEE, blue: 0xFF),
            textMuted: RGB(red: 0xA6, green: 0x9E, blue: 0xDB)
        )
        static let terminal = ThemePalette(
            bevelLight: RGB(red: 0x1E, green: 0x35, blue: 0x22),
            bevelShadow: RGB(red: 0x15, green: 0x26, blue: 0x1A),
            correction: RGB(red: 0xFF, green: 0xD4, blue: 0x4D),
            frame: RGB(red: 0x2E, green: 0x55, blue: 0x34),
            prediction: RGB(red: 0x5D, green: 0xB8, blue: 0x6C),
            selection: RGB(red: 0x86, green: 0xF5, blue: 0x9A),
            selectionText: RGB(red: 0x0A, green: 0x11, blue: 0x0B),
            surface: RGB(red: 0x0A, green: 0x11, blue: 0x0B),
            text: RGB(red: 0x86, green: 0xF5, blue: 0x9A),
            textMuted: RGB(red: 0x5D, green: 0xB8, blue: 0x6C)
        )
        static let nordic = ThemePalette(
            bevelLight: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            bevelShadow: RGB(red: 0xD7, green: 0xDE, blue: 0xE1),
            correction: RGB(red: 0xB5, green: 0x57, blue: 0x3A),
            frame: RGB(red: 0xC5, green: 0xCF, blue: 0xD4),
            prediction: RGB(red: 0x5D, green: 0x6C, blue: 0x77),
            selection: RGB(red: 0x41, green: 0x70, blue: 0x9C),
            selectionText: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            surface: RGB(red: 0xF4, green: 0xF6, blue: 0xF6),
            text: RGB(red: 0x24, green: 0x30, blue: 0x3A),
            textMuted: RGB(red: 0x5D, green: 0x6C, blue: 0x77)
        )
        static let contrast = ThemePalette(
            bevelLight: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            bevelShadow: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            correction: RGB(red: 0x00, green: 0xE5, blue: 0xFF),
            frame: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            prediction: RGB(red: 0xE6, green: 0xE6, blue: 0xE6),
            selection: RGB(red: 0xFF, green: 0xE6, blue: 0x00),
            selectionText: RGB(red: 0x00, green: 0x00, blue: 0x00),
            surface: RGB(red: 0x00, green: 0x00, blue: 0x00),
            text: RGB(red: 0xFF, green: 0xFF, blue: 0xFF),
            textMuted: RGB(red: 0xE6, green: 0xE6, blue: 0xE6)
        )
    }
    enum Size {
        enum Space {
            static let xxs: CGFloat = 2
            static let xs: CGFloat = 4
            static let sm: CGFloat = 8
            static let md: CGFloat = 12
            static let lg: CGFloat = 16
            static let xl: CGFloat = 24
            static let fine: CGFloat = 2
            static let inset: CGFloat = 4
            static let inline: CGFloat = 4
            static let stack: CGFloat = 4
            static let group: CGFloat = 8
            static let section: CGFloat = 12
            static let window: CGFloat = 12
            static let page: CGFloat = 24
        }
        enum Text {
            static let candidate: CGFloat = 15
            static let candidateLine: CGFloat = 20
            static let body: CGFloat = 13
            static let bodyLine: CGFloat = 20
            static let small: CGFloat = 11
            static let smallLine: CGFloat = 16
            static let tag: CGFloat = 10
            static let tagLine: CGFloat = 12
        }
        enum Part {
            static let windowRadius: CGFloat = 12
            static let cardRadius: CGFloat = 12
            static let rowHeight: CGFloat = 28
            static let rowPaddingX: CGFloat = 4
            static let rowRadius: CGFloat = 8
            static let fieldHeight: CGFloat = 28
            static let fieldPaddingX: CGFloat = 8
            static let fieldPaddingY: CGFloat = 4
            static let fieldRadius: CGFloat = 8
            static let tagHeight: CGFloat = 16
            static let tagPaddingX: CGFloat = 4
            static let tagPaddingY: CGFloat = 2
            static let tagGlyphGap: CGFloat = 2
            static let tagRadius: CGFloat = 4
            static let badgeSize: CGFloat = 16
            static let badgeGap: CGFloat = 8
            static let iconSize: CGFloat = 16
            static let iconPadding: CGFloat = 3
            static let iconRadius: CGFloat = 4
            static let stroke: CGFloat = 1
        }
        enum Candidate {
            static let rowHeight: CGFloat = 28
            static let fontSize: CGFloat = 15
            static let fontSizeMin: CGFloat = 12
            static let fontSizeMax: CGFloat = 24
            static let indexWidth: CGFloat = 18
            static let paddingX: CGFloat = 8
            static let frameWidth: CGFloat = 1
            static let bevelWidth: CGFloat = 1
            static let maxVisible: CGFloat = 9
            static let shadowOffset: CGFloat = 2
            static let labelFontSize: CGFloat = 11
            static let variantPaddingX: CGFloat = 4
            static let sectionPaddingY: CGFloat = 4
            static let minWidth: CGFloat = 180
            static let maxWidth: CGFloat = 720
            static let gridMaxWidth: CGFloat = 960
            static let screenMargin: CGFloat = 16
            static let truncationContext: CGFloat = 4
            static let detailGap: CGFloat = 8
            static let columnGap: CGFloat = 8
        }
        enum ModeIndicator {
            static let fontSize: CGFloat = 14
            static let paddingX: CGFloat = 8
            static let paddingY: CGFloat = 4
        }
        enum Branch {
            static let trunkGap: CGFloat = 12
            static let branchIndent: CGFloat = 16
            static let branchStemX: CGFloat = 4
            static let lineWidth: CGFloat = 1
            static let lineWidthSelected: CGFloat = 2
            static let underlineOffset: CGFloat = 2
            static let splitBadgeSize: CGFloat = 13
            static let splitBadgeFontSize: CGFloat = 9
            static let splitBadgeGap: CGFloat = 2
        }
        enum Settings {
            static let windowWidth: CGFloat = 820
            static let windowHeight: CGFloat = 580
            static let sidebarWidth: CGFloat = 190
            static let keymapStateWidth: CGFloat = 120
            static let keymapKeyWidth: CGFloat = 150
            static let keymapMarkWidth: CGFloat = 22
            static let keymapCaptureHeight: CGFloat = 22
            static let ruleTableHeight: CGFloat = 220
            static let commandEditorWidth: CGFloat = 460
            static let ruleSearchWidth: CGFloat = 160
            static let previewChipPaddingX: CGFloat = 8
            static let previewChipPaddingY: CGFloat = 4
            static let previewChipRadius: CGFloat = 6
            static let previewChipGap: CGFloat = 6
            static let ruleCheckColumnWidth: CGFloat = 40
            static let ruleKeyColumnWidth: CGFloat = 160
            static let ruleValueColumnWidth: CGFloat = 150
            static let ruleNoteFieldGap: CGFloat = 8
            static let ruleKindColumnWidth: CGFloat = 120
            static let commandReadingColumnWidth: CGFloat = 110
            static let commandTitleColumnWidth: CGFloat = 120
            static let commandKindColumnWidth: CGFloat = 130
            static let ruleProfileColumnWidth: CGFloat = 210
            static let tableHeaderInset: CGFloat = 10
            static let tableColumnSpacing: CGFloat = 17
            static let tablePopupTextInset: CGFloat = 21
            static let themeEditorWidth: CGFloat = 640
            static let themeEditorHeight: CGFloat = 720
            static let userDictionaryTableHeight: CGFloat = 280
            static let previewPadding: CGFloat = 24
            static let keyFilterRadius: CGFloat = 5
            static let fontSliderWidth: CGFloat = 220
            static let secondsSliderWidth: CGFloat = 180
            static let secondsLabelWidth: CGFloat = 52
            static let themeSwatchWidth: CGFloat = 40
            static let aboutIcon: CGFloat = 64
            static let themeSwatchHeight: CGFloat = 20
            static let themeSwatchGap: CGFloat = 3
            static let themeSwatchFontSize: CGFloat = 11
            static let themeSwatchSelectionWidth: CGFloat = 12
            static let themeSwatchSelectionHeight: CGFloat = 10
            static let themeSwatchRadius: CGFloat = 6
        }
        enum Glass {
            static let cornerRadius: CGFloat = 12
            static let windowPadding: CGFloat = 12
            static let compactPaddingX: CGFloat = 8
            static let compactPaddingY: CGFloat = 4
            static let separatorGap: CGFloat = 12
            static let rowPaddingX: CGFloat = 4
            static let headerHeight: CGFloat = 20
            static let rowHeight: CGFloat = 28
            static let labelFontSize: CGFloat = 11.5
            static let keyFontSize: CGFloat = 10.5
            static let badgeSize: CGFloat = 16
            static let badgeGap: CGFloat = 8
            static let selectionRadius: CGFloat = 7
            static let keycapRadius: CGFloat = 4
            static let keycapPaddingX: CGFloat = 4
            static let keycapPaddingY: CGFloat = 3
            static let keycapHeight: CGFloat = 16
            static let hintGap: CGFloat = 8
            static let footerHeight: CGFloat = 28
            static let trunkGap: CGFloat = 8
            static let branchIndent: CGFloat = 28
            static let branchStemX: CGFloat = 12
            static let lineWidth: CGFloat = 1.5
            static let lineWidthSelected: CGFloat = 2
            static let underlineOffset: CGFloat = 4
            static let modeIndicatorSize: CGFloat = 32
            static let modeIndicatorFontSize: CGFloat = 17
            static let selectionInsetY: CGFloat = 2
            static let branchTurnRadius: CGFloat = 8
            static let dotPitch: CGFloat = 5
            static let keycapPartGap: CGFloat = 2
            static let keycapGap: CGFloat = 4
            static let shadowRadius: CGFloat = 12
            static let shadowOffsetY: CGFloat = 3
            static let tagHeight: CGFloat = 16
            static let tagPaddingX: CGFloat = 4
            static let tagRadius: CGFloat = 4
            static let noteIconSize: CGFloat = 16
            static let commandIconSize: CGFloat = 18
            static let commandIconRadius: CGFloat = 5
            static let noteGap: CGFloat = 8
        }
        enum Meaning {
            static let markerWidth: CGFloat = 16
            static let markerGap: CGFloat = 4
            static let headerGap: CGFloat = 8
            static let senseGap: CGFloat = 8
            static let exampleGap: CGFloat = 4
            static let exampleIndent: CGFloat = 12
            static let exampleBarWidth: CGFloat = 2
            static let meaningPitch: CGFloat = 20
            static let examplePitch: CGFloat = 16
            static let othersGap: CGFloat = 12
            static let partOfSpeechGap: CGFloat = 4
            static let partOfSpeechHeight: CGFloat = 16
            static let partOfSpeechPaddingX: CGFloat = 4
            static let tagGap: CGFloat = 4
            static let headwordFontSize: CGFloat = 15
            static let bodyFontSize: CGFloat = 13
            static let exampleFontSize: CGFloat = 11
            static let partOfSpeechFontSize: CGFloat = 10
            static let numberFontSize: CGFloat = 10
            static let iconSize: CGFloat = 13
            static let listWidth: CGFloat = 288
            static let meaningLines: CGFloat = 3
            static let exampleLines: CGFloat = 2
        }
        enum Handwriting {
            static let width: CGFloat = 284
            static let height: CGFloat = 332
            static let canvasSize: CGFloat = 260
            static let canvasPadding: CGFloat = 12
            static let strokeWidth: CGFloat = 5
            static let frameWidth: CGFloat = 1
            static let guideDash: CGFloat = 4
            static let anchorGap: CGFloat = 4
            static let candidateGap: CGFloat = 8
            static let candidateFontSize: CGFloat = 18
            static let titleHeight: CGFloat = 32
            static let captionButtonWidth: CGFloat = 46
            static let captionFontSize: CGFloat = 12
            static let captionIconSize: CGFloat = 10
            static let controlHeight: CGFloat = 32
            static let controlRadius: CGFloat = 4
            static let controlPaddingX: CGFloat = 12
            static let labelFontSize: CGFloat = 14
            static let iconButtonWidth: CGFloat = 32
            static let iconSize: CGFloat = 16
            static let resizeBorder: CGFloat = 6
            static let scrollFade: CGFloat = 20
            static let wheelStep: CGFloat = 48
            static let promptPaddingY: CGFloat = 4
        }
        enum Prediction {
            static let gap: CGFloat = 8
            static let paddingX: CGFloat = 8
            static let paddingY: CGFloat = 4
            static let keyGap: CGFloat = 8
        }
        enum Palette {
            static let padding: CGFloat = 12
            static let sectionGap: CGFloat = 12
            static let groupGap: CGFloat = 8
            static let itemGap: CGFloat = 4
            static let inset: CGFloat = 2
            static let controlHeight: CGFloat = 28
            static let controlPaddingX: CGFloat = 8
            static let searchRadius: CGFloat = 8
            static let searchFontSize: CGFloat = 14
            static let searchIconSize: CGFloat = 13
            static let modeFontSize: CGFloat = 12
            static let tabIconSize: CGFloat = 14
            static let textRowHeight: CGFloat = 16
            static let headingFontSize: CGFloat = 11
            static let cellRadius: CGFloat = 6
            static let emojiScale: CGFloat = 0.7
            static let symbolScale: CGFloat = 0.55
            static let kaomojiScale: CGFloat = 0.4
            static let kaomojiMinFontSize: CGFloat = 9
            static let kaomojiPaddingX: CGFloat = 4
            static let selectionStroke: CGFloat = 2
            static let scrollbarWidth: CGFloat = 3
            static let scrollbarMinLength: CGFloat = 16
            static let tileSize: CGFloat = 48
            static let tilePadding: CGFloat = 8
            static let previewGlyphSize: CGFloat = 40
            static let previewSymbolBoost: CGFloat = 1.2
            static let previewKaomojiFontSize: CGFloat = 18
            static let previewKaomojiWidth: CGFloat = 0.45
            static let previewHeadingHeight: CGFloat = 20
            static let previewLabelFontSize: CGFloat = 10
            static let previewNameLines: CGFloat = 2
            static let chipPaddingX: CGFloat = 4
            static let chipPaddingY: CGFloat = 2
            static let chipRadius: CGFloat = 3
            static let nameFontSize: CGFloat = 13
            static let detailFontSize: CGFloat = 11
            static let codeFontSize: CGFloat = 10
            static let previewChipSmallFontSize: CGFloat = 8
            static let skinButtonPadding: CGFloat = 3
            static let pickerCellSize: CGFloat = 36
            static let cellPadding: CGFloat = 4
            static let probeFontSize: CGFloat = 20
            static let openRise: CGFloat = 6
            static let contentShift: CGFloat = 18
            static let popScale: CGFloat = 0.9
            static let pinBounce: CGFloat = 1.35
        }
        enum Snapshot {
            static let margin: CGFloat = 16
            static let scale: CGFloat = 2
        }
        enum SettingsWindows {
            static let pagePaddingX: CGFloat = 36
            static let scrollLine: CGFloat = 40
            static let listHeight: CGFloat = 220
            static let buttonWidth: CGFloat = 96
            static let buttonPaddingX: CGFloat = 12
            static let pagePaddingTop: CGFloat = 20
            static let titleFontSize: CGFloat = 28
            static let sectionFontSize: CGFloat = 14
            static let bodyFontSize: CGFloat = 14
            static let captionFontSize: CGFloat = 12
            static let iconFontSize: CGFloat = 16
            static let sectionGap: CGFloat = 28
            static let sectionTitleHeight: CGFloat = 28
            static let cardGap: CGFloat = 4
            static let cardRadius: CGFloat = 4
            static let cardPaddingX: CGFloat = 16
            static let rowHeight: CGFloat = 48
            static let controlHeight: CGFloat = 32
            static let dropdownHeight: CGFloat = 384
            static let controlWidth: CGFloat = 240
            static let switchWidth: CGFloat = 40
            static let switchHeight: CGFloat = 20
            static let resetSize: CGFloat = 28
            static let navItemHeight: CGFloat = 36
            static let navHeaderHeight: CGFloat = 32
            static let navPaddingX: CGFloat = 12
            static let navIndicatorWidth: CGFloat = 3
            static let navIndicatorHeight: CGFloat = 16
            static let navIconGap: CGFloat = 12
            static let searchHeight: CGFloat = 32
            static let noteLineHeight: CGFloat = 18
            static let titleHeight: CGFloat = 52
            static let bodyLineHeight: CGFloat = 20
            static let contentMaxWidth: CGFloat = 1000
            static let controlGap: CGFloat = 8
            static let toggleWidth: CGFloat = 96
            static let stepperWidth: CGFloat = 160
            static let secondsLabelWidth: CGFloat = 56
            static let navWidth: CGFloat = 280
            static let windowWidth: CGFloat = 1000
            static let windowHeight: CGFloat = 700
            static let windowMinWidth: CGFloat = 640
            static let windowMinHeight: CGFloat = 480
            static let navGroupGap: CGFloat = 12
            static let navHeaderFontSize: CGFloat = 12
            static let controlRadius: CGFloat = 4
            static let fieldPaddingX: CGFloat = 11
            static let focusStroke: CGFloat = 2
            static let chevronSize: CGFloat = 12
            static let flyoutPadding: CGFloat = 4
            static let flyoutItemHeight: CGFloat = 32
            static let flyoutRadius: CGFloat = 8
            static let tableRowHeight: CGFloat = 30
            static let tableHeaderHeight: CGFloat = 32
            static let scrollbarThin: CGFloat = 2
            static let scrollbarWide: CGFloat = 6
            static let scrollbarMargin: CGFloat = 3
            static let scrollbarHit: CGFloat = 14
            static let scrollbarMinThumb: CGFloat = 24
            static let progressRingSize: CGFloat = 32
            static let progressRingStroke: CGFloat = 3
            static let pageEnterOffset: CGFloat = 12
            static let wheelStep: CGFloat = 48
            static let wizardWidth: CGFloat = 920
            static let wizardHeight: CGFloat = 640
            static let wizardTextWidth: CGFloat = 380
            static let wizardPadding: CGFloat = 32
            static let wizardFooterHeight: CGFloat = 72
            static let wizardStepBar: CGFloat = 4
            static let wizardOptionHeight: CGFloat = 44
            static let wizardOptionNoteHeight: CGFloat = 64
            static let wizardOptionGap: CGFloat = 6
            static let wizardRadioSize: CGFloat = 20
            static let wizardDemoFontSize: CGFloat = 20
            static let wizardDemoLineHeight: CGFloat = 34
            static let wizardKeycapHeight: CGFloat = 40
            static let wizardKeycapMinWidth: CGFloat = 48
            static let wizardModeSize: CGFloat = 28
            static let wizardHeroSize: CGFloat = 72
            static let stepperButtonWidth: CGFloat = 32
            static let iconButtonWidth: CGFloat = 40
            static let dialogRadius: CGFloat = 8
            static let sliderTrackHeight: CGFloat = 4
            static let sliderThumbSize: CGFloat = 20
            static let sliderThumbInner: CGFloat = 12
            static let sliderThumbInnerHover: CGFloat = 14
            static let cardPaddingY: CGFloat = 12
            static let footerGap: CGFloat = 8
            static let labelMinWidth: CGFloat = 160
            static let radioSize: CGFloat = 20
            static let radioDot: CGFloat = 10
            static let themeSwatchWidth: CGFloat = 40
            static let themeSwatchHeight: CGFloat = 20
            static let themeSwatchGap: CGFloat = 3
            static let themeSwatchSelectionWidth: CGFloat = 12
            static let themeSwatchSelectionHeight: CGFloat = 10
            static let themeSwatchRadius: CGFloat = 6
            static let themeSwatchFontSize: CGFloat = 11
            static let aboutIcon: CGFloat = 64
            static let keymapListHeight: CGFloat = 400
            static let segmentInset: CGFloat = 2
            static let listArrowWidth: CGFloat = 24
            static let titleBarHeight: CGFloat = 32
            static let titleBarIconSize: CGFloat = 16
            static let titleBarPaddingX: CGFloat = 16
            static let aboutTitleFontSize: CGFloat = 20
            static let switchKnobOff: CGFloat = 12
            static let switchKnobOn: CGFloat = 14
            static let switchKnobPressed: CGFloat = 2
            static let segmentMinWidth: CGFloat = 120
            static let tableRowInset: CGFloat = 2
            static let tableIndicatorInset: CGFloat = 8
            static let tooltipOffset: CGFloat = 24
            static let previewLines: CGFloat = 2
            static let macroPreviewLines: CGFloat = 5
            static let reportLines: CGFloat = 4
            static let statusLines: CGFloat = 3
            static let pageScroll: CGFloat = 0.8
            static let tablePageRows: CGFloat = 4
        }
        enum StandardTheme {
            static let cornerRadius: CGFloat = 12
        }
        enum Onboarding {
            static let width: CGFloat = 900
            static let height: CGFloat = 600
            static let stageWidth: CGFloat = 440
            static let padding: CGFloat = 24
            static let stagePadding: CGFloat = 24
            static let fieldTop: CGFloat = 96
            static let cardRadius: CGFloat = 12
            static let cardPadding: CGFloat = 12
            static let cardGap: CGFloat = 8
            static let themeSampleWidth: CGFloat = 48
            static let dotSize: CGFloat = 7
            static let dotGap: CGFloat = 4
            static let fieldHeight: CGFloat = 46
            static let fieldRadius: CGFloat = 10
            static let fieldFontSize: CGFloat = 19
            static let applicationTabFontSize: CGFloat = 12
            static let infoSymbolWidth: CGFloat = 28
            static let demoGap: CGFloat = 8
            static let badgeRadius: CGFloat = 6
            static let counterHeight: CGFloat = 16
            static let checkSize: CGFloat = 20
            static let badgeHeight: CGFloat = 18
            static let sliderThumb: CGFloat = 20
            static let sliderRail: CGFloat = 4
            static let buttonMinWidth: CGFloat = 64
        }
        enum Bubble {
            static let width: CGFloat = 288
            static let padding: CGFloat = 12
            static let radius: CGFloat = 12
            static let pointerLength: CGFloat = 8
            static let pointerWidth: CGFloat = 16
            static let gap: CGFloat = 4
            static let screenMargin: CGFloat = 12
        }
    }
    enum Motion {
        enum ModeIndicator {
            static let visible: Double = 800
            static let fade: Double = 120
        }
        enum CorrectionUnderline {
            static let appear: Double = 80
        }
        enum CandidateRest {
            static let fadeIn: Double = 250
        }
        enum CandidateWindow {
            static let resize: Double = 150
            static let update: Double = 120
        }
        enum Settings {
            static let disclosure: Double = 167
        }
        enum SettingsWindows {
            static let pageEnter: Double = 167
            static let hover: Double = 83
            static let toggle: Double = 167
            static let flyout: Double = 167
            static let navIndicator: Double = 167
            static let scroll: Double = 200
            static let scrollbarIdle: Double = 1200
            static let scrollbarFade: Double = 250
            static let progressRing: Double = 1400
            static let wizardKey: Double = 85
            static let wizardKeyPress: Double = 320
            static let wizardPause: Double = 700
            static let wizardHold: Double = 1400
            static let wizardPage: Double = 220
        }
        enum Onboarding {
            static let keystroke: Double = 85
            static let hold: Double = 1400
            static let page: Double = 220
        }
        enum Palette {
            static let open: Double = 140
            static let selection: Double = 110
            static let indicator: Double = 200
            static let content: Double = 170
            static let pop: Double = 220
        }
    }
    enum Opacity {
        enum Glass {
            static let line: CGFloat = 0.26
            static let lineContrast: CGFloat = 0.5
            static let badge: CGFloat = 0.1
            static let badgeContrast: CGFloat = 0.26
            static let focusTint: CGFloat = 0.16
            static let focusTintContrast: CGFloat = 0.3
            static let correctionTag: CGFloat = 0.16
            static let correctionTagContrast: CGFloat = 0.3
            static let commandTag: CGFloat = 0.16
            static let commandTagContrast: CGFloat = 0.3
        }
        enum Rounded {
            static let badge: CGFloat = 0.12
            static let badgeContrast: CGFloat = 0.25
            static let focusTint: CGFloat = 0.2
            static let focusTintContrast: CGFloat = 0.35
        }
        enum Badge {
            static let selected: CGFloat = 0.25
        }
        enum Variant {
            static let unavailable: CGFloat = 0.4
        }
        enum Keycap {
            static let deskFill: CGFloat = 0.12
            static let deskStroke: CGFloat = 0.6
        }
        enum Shadow {
            static let window: CGFloat = 0.22
        }
        enum Settings {
            static let keyFilter: CGFloat = 0.15
            static let subtleSelected: CGFloat = 0.08
            static let subtleHover: CGFloat = 0.05
        }
        enum Onboarding {
            static let stageGlow: CGFloat = 0.32
            static let stageGlowSecondary: CGFloat = 0.18
            static let cardSelected: CGFloat = 0.12
            static let cardIdle: CGFloat = 0.05
            static let field: CGFloat = 0.82
            static let fieldStroke: CGFloat = 0.14
            static let caption: CGFloat = 0.92
            static let captionStroke: CGFloat = 0.1
            static let sliderRail: CGFloat = 0.6
            static let sliderRailDisabled: CGFloat = 0.3
            static let swatchText: CGFloat = 0.7
            static let swatchFrame: CGFloat = 0.6
        }
        enum Palette {
            static let scrollbar: CGFloat = 0.45
        }
        enum SettingsWindows {
            static let disabledOverlay: CGFloat = 0.4
            static let accentDisabled: CGFloat = 0.35
            static let link: CGFloat = 0.4
            static let linkHoverMix: CGFloat = 0.35
            static let sliderTrackDisabled: CGFloat = 0.5
            static let previewChip: CGFloat = 0.06
            static let tableStripe: CGFloat = 0.035
            static let smoke: CGFloat = 0.3
        }
        enum Candidate {
            static let unselectableNumber: CGFloat = 0.4
        }
    }
}
