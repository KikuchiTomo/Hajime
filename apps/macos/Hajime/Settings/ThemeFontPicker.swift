import AppKit
import SwiftUI

/// カスタムテーマの書体を選ぶ 2 行．この Mac に入っている書体のファミリーを選び，その中のスタイル(太さ・斜体など)を選ぶ．
/// 値は選んだ書体の PostScript 名で，nil なら元のテーマの書体
struct ThemeFontPicker: View {
    @Binding var fontName: String?

    var body: some View {
        let current = fontName.flatMap(InstalledFonts.face(named:))
        Picker(UIStrings.More.font, selection: Binding(
            get: { current?.family ?? fontName },
            set: { family in fontName = family.map { InstalledFonts.closestFace(in: $0, to: current)?.postScriptName ?? $0 } }
        )) {
            Text(UIStrings.More.themeFont).tag(String?.none)
            // 入っていない書体を保存していれば，その名前のまま出す(選び直すまで値を変えない)
            if let fontName, current == nil {
                Text(fontName).tag(String?.some(fontName))
            }
            ForEach(InstalledFonts.families, id: \.name) { family in
                Text(family.label).tag(String?.some(family.name))
            }
        }
        if let current {
            Picker(UIStrings.More.fontStyle, selection: $fontName) {
                ForEach(InstalledFonts.faces(of: current.family), id: \.postScriptName) { face in
                    Text(face.label).tag(String?.some(face.postScriptName))
                }
            }
        }
    }
}

/// この Mac に入っている書体．ファミリーの一覧は設定の画面を開いているあいだ変わらないものとして一度だけ読む
@MainActor
enum InstalledFonts {
    struct Family {
        let name: String
        /// 画面に出す名前(日本語の書体は日本語の名前)
        let label: String
    }

    struct Face: Equatable {
        let family: String
        let postScriptName: String
        let label: String
        /// NSFontManager の太さ(0〜15．5 が標準)
        let weight: Int
        let traits: NSFontTraitMask
    }

    /// 名前が「.」で始まるものは OS が内部で使う書体なので出さない
    static let families: [Family] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .map { Family(name: $0, label: NSFontManager.shared.localizedName(forFamily: $0, face: nil)) }
        .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

    /// ファミリーの中の書体．並びは OS の返す順(細いものから)
    static func faces(of family: String) -> [Face] {
        (NSFontManager.shared.availableMembers(ofFontFamily: family) ?? []).compactMap { member in
            guard member.count >= 4, let name = member[0] as? String, !name.hasPrefix("."), let style = member[1] as? String,
                  let weight = member[2] as? Int, let traits = member[3] as? UInt
            else { return nil }
            return Face(family: family, postScriptName: name, label: NSFontManager.shared.localizedName(forFamily: family, face: style),
                        weight: weight, traits: NSFontTraitMask(rawValue: traits))
        }
    }

    /// 保存した名前の書体．入っていなければ nil
    static func face(named name: String) -> Face? {
        guard let font = NSFont(name: name, size: NSFont.systemFontSize), let family = font.familyName else { return nil }
        return faces(of: family).first { $0.postScriptName == font.fontName }
    }

    /// ファミリーを選び直したときの書体．今の書体と太さと斜体が近いものを選ぶ．今の書体がなければ標準の太さ
    static func closestFace(in family: String, to current: Face?) -> Face? {
        let weight = current?.weight ?? standardWeight
        let italic = current?.traits.contains(.italicFontMask) ?? false
        return faces(of: family).min { lhs, rhs in
            distance(lhs, weight: weight, italic: italic) < distance(rhs, weight: weight, italic: italic)
        }
    }

    private static let standardWeight = 5

    private static func distance(_ face: Face, weight: Int, italic: Bool) -> Int {
        // 斜体の違いは太さの違いより大きく数える
        abs(face.weight - weight) + (face.traits.contains(.italicFontMask) == italic ? 0 : 16)
    }
}
