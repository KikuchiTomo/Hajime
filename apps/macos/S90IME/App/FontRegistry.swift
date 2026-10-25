import AppKit
import CoreText

/// 同梱したフォント(Resources/Fonts)をこのプロセスだけに登録する．
enum FontRegistry {
    static let labelFontName = "BIZUDGothic-Regular"

    static func registerBundledFonts() {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Fonts", isDirectory: true),
            let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}
