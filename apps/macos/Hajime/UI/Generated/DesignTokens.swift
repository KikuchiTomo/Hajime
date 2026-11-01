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
        enum Candidate {
            static let rowHeight: CGFloat = 22
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
            static let variantPaddingX: CGFloat = 6
            static let sectionPaddingY: CGFloat = 3
            static let minWidth: CGFloat = 180
            static let variantInsetY: CGFloat = 1
        }
        enum ModeIndicator {
            static let fontSize: CGFloat = 14
            static let paddingX: CGFloat = 10
            static let paddingY: CGFloat = 3
        }
        enum Branch {
            static let trunkGap: CGFloat = 10
            static let branchIndent: CGFloat = 14
            static let branchStemX: CGFloat = 5
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
            static let ruleCheckColumnWidth: CGFloat = 40
            static let ruleKeyColumnWidth: CGFloat = 160
            static let ruleProfileColumnWidth: CGFloat = 210
            static let tableHeaderInset: CGFloat = 10
            static let tableColumnSpacing: CGFloat = 17
            static let tablePopupTextInset: CGFloat = 21
            static let themeEditorWidth: CGFloat = 640
            static let themeEditorHeight: CGFloat = 720
            static let userDictionaryTableHeight: CGFloat = 330
            static let previewPadding: CGFloat = 24
            static let keyFilterRadius: CGFloat = 5
            static let fontSliderWidth: CGFloat = 220
            static let secondsSliderWidth: CGFloat = 180
            static let secondsLabelWidth: CGFloat = 52
            static let themeSwatchWidth: CGFloat = 40
            static let themeSwatchHeight: CGFloat = 20
            static let themeSwatchGap: CGFloat = 3
            static let themeSwatchFontSize: CGFloat = 11
            static let themeSwatchSelectionWidth: CGFloat = 12
            static let themeSwatchSelectionHeight: CGFloat = 10
            static let themeSwatchRadius: CGFloat = 6
        }
        enum Glass {
            static let cornerRadius: CGFloat = 12
            static let padding: CGFloat = 10
            static let rowHeight: CGFloat = 28
            static let labelFontSize: CGFloat = 11.5
            static let keyFontSize: CGFloat = 10.5
            static let badgeSize: CGFloat = 17
            static let selectionRadius: CGFloat = 7
            static let keycapRadius: CGFloat = 4
            static let keycapPaddingX: CGFloat = 5
            static let keycapHeight: CGFloat = 17
            static let hintGap: CGFloat = 10
            static let footerHeight: CGFloat = 28
            static let trunkGap: CGFloat = 6
            static let branchIndent: CGFloat = 28
            static let branchStemX: CGFloat = 12
            static let lineWidth: CGFloat = 1.5
            static let lineWidthSelected: CGFloat = 2
            static let underlineOffset: CGFloat = 4
            static let modeIndicatorSize: CGFloat = 34
            static let modeIndicatorFontSize: CGFloat = 17
            static let selectionInsetY: CGFloat = 2
            static let variantInsetY: CGFloat = 4
            static let curveStartOverlap: CGFloat = 2
            static let curveEndGap: CGFloat = 3
            static let curveBend: CGFloat = 0.35
            static let dotPitch: CGFloat = 5
            static let keycapPartGap: CGFloat = 1
            static let shadowRadius: CGFloat = 12
            static let shadowOffsetY: CGFloat = 3
            static let tagHeight: CGFloat = 16
            static let tagPaddingX: CGFloat = 6
            static let tagRadius: CGFloat = 8
            static let noteIconSize: CGFloat = 18
            static let noteGap: CGFloat = 6
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
            static let candidateGap: CGFloat = 6
            static let candidateFontSize: CGFloat = 18
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
            static let previewHeight: CGFloat = 240
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
            static let rowHeight: CGFloat = 52
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
            static let stepperWidth: CGFloat = 96
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
        }
        enum StandardTheme {
            static let cornerRadius: CGFloat = 12
        }
        enum Onboarding {
            static let width: CGFloat = 900
            static let height: CGFloat = 600
            static let stageWidth: CGFloat = 440
            static let padding: CGFloat = 36
            static let stagePadding: CGFloat = 28
            static let cardRadius: CGFloat = 12
            static let cardPadding: CGFloat = 14
            static let cardGap: CGFloat = 10
            static let dotSize: CGFloat = 7
            static let dotGap: CGFloat = 6
            static let fieldHeight: CGFloat = 46
            static let fieldRadius: CGFloat = 10
            static let fieldFontSize: CGFloat = 19
            static let applicationTabFontSize: CGFloat = 12
            static let infoSymbolWidth: CGFloat = 28
            static let demoGap: CGFloat = 14
            static let badgeRadius: CGFloat = 6
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
            static let wizardKey: Double = 110
            static let wizardKeyPress: Double = 320
            static let wizardPause: Double = 700
            static let wizardHold: Double = 2200
            static let wizardPage: Double = 250
        }
        enum Onboarding {
            static let keystroke: Double = 85
            static let hold: Double = 1400
            static let page: Double = 220
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
        }
    }
}
