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
            static let cornerRadiusNative: CGFloat = 6
            static let shadowOffset: CGFloat = 2
            static let labelFontSize: CGFloat = 11
            static let variantPaddingX: CGFloat = 6
            static let sectionPaddingY: CGFloat = 3
            static let minWidth: CGFloat = 180
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
    }
}
