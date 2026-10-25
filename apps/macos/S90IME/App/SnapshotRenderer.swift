#if DEBUG
import AppKit
import S90Application
import S90Domain
import S90Persistence
import SwiftUI

/// 候補ウィンドウの見た目を画像に書き出す(デバッグビルドだけ)．
/// 入力メソッドとして動かさずに描画を確かめ，PR に貼るスクリーンショットを作るため．
///
/// 使い方: Debug でビルドした "s90.tokyo IME Debug.app/Contents/MacOS/s90.tokyo IME Debug" --render-snapshots
/// サンドボックスの中で動くので，書き出し先はサンドボックスの一時ディレクトリになる．場所は標準出力に出す
@MainActor
enum SnapshotRenderer {
    static let argument = "--render-snapshots"

    static func runIfRequested() {
        let arguments = CommandLine.arguments
        guard arguments.contains(argument) else { return }
        FontRegistry.registerBundledFonts()
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("s90-snapshots", isDirectory: true)
        print(output.path)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for theme in [ThemePreference.platinum, .desk, .native] {
            let appearance = NSAppearance(named: theme == .desk ? .darkAqua : .aqua)
            render(listView(theme: theme, appearance: appearance), name: "list-\(theme.rawValue)", to: output, appearance: appearance)
            render(latticeView(theme: theme, appearance: appearance), name: "branch-\(theme.rawValue)", to: output, appearance: appearance)
            render(previewView(theme: theme, appearance: appearance), name: "branch-preview-\(theme.rawValue)", to: output, appearance: appearance)
            render(correctionView(theme: theme, appearance: appearance), name: "correction-\(theme.rawValue)", to: output, appearance: appearance)
        }
        render(settingsView(), name: "settings", to: output, appearance: NSAppearance(named: .aqua))
        exit(0)
    }

    /// 設定の画面(入力のタブ)．設定は一時ディレクトリに置き，利用者の設定に触れない
    private static func settingsView() -> NSView {
        let store = FileSettingsStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("s90-snapshot-settings.json"))
        let view = NSHostingView(rootView: SettingsView(model: SettingsModel(store: store, usage: nil, resetLearning: {})))
        view.frame = NSRect(origin: .zero, size: SettingsView.size)
        view.layoutSubtreeIfNeeded()
        return view
    }

    private static func listView(theme: ThemePreference, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        let panel = CandidatePanel(
            variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
            selectedVariant: nil,
            entries: ["変換", "返還", "偏官", "へんかん", "ヘンカン"].map { .init(text: $0, annotation: nil) },
            selectedEntry: 1, focus: .candidate, position: 2, total: 12, note: nil
        )
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return view
    }

    private static func correctionView(theme: ThemePreference, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        let panel = CandidatePanel(
            variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
            selectedVariant: nil,
            entries: [.init(text: "python", annotation: nil), .init(text: "pyてょn", annotation: "入力のまま"), .init(text: "Python", annotation: nil)],
            selectedEntry: 0, focus: .candidate, position: 1, total: 3, note: "Space 入力のままに戻す"
        )
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return view
    }

    private static func latticeView(theme: ThemePreference, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        let panel = LatticePanel(columns: [
            .init(text: "私の", isFocused: false, isUncertain: false),
            .init(text: "名前は", isFocused: false, isUncertain: false, isDecided: true),
            .init(text: "中のです", alternatives: ["中のです", "中野です", "仲のです", "なかのです", "那珂のです"], selectedAlternative: 1,
                  variants: ["なかのです", "ナカノデス", "ﾅｶﾉﾃﾞｽ"], isFocused: true, isUncertain: true),
        ], position: 1, total: 8)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return view
    }

    /// 迷う文節が 2 つあり，注目していない方に次の候補を添えた分岐図
    private static func previewView(theme: ThemePreference, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        let panel = LatticePanel(columns: [
            .init(text: "Cloudflareで", isFocused: false, isUncertain: false),
            .init(text: "撮った", isFocused: false, isUncertain: true, preview: "取った"),
            .init(text: "ドメイン", alternatives: ["ドメイン", "どめいん"], selectedAlternative: 0,
                  variants: ["どめいん", "ドメイン", "ﾄﾞﾒｲﾝ"], isFocused: true, isUncertain: true),
        ], position: 1, total: 2)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return view
    }

    private static func render(_ view: NSView, name: String, to directory: URL, appearance: NSAppearance?) {
        view.appearance = appearance
        // 2 倍(Retina)で描き，1 ドットの線がデバイスのピクセルにそろうかを確かめられるようにする
        let scale: CGFloat = 2
        let size = view.bounds.size
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = size
        NSAppearance.current = appearance ?? NSAppearance(named: .aqua)!
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
    }
}
#endif
