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
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("s90-snapshots", isDirectory: true)
        print(output.path)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let sample = CustomTheme(id: "sample", name: "夕焼け", base: .automatic, surface: HexColor("#2B1B17")!, text: HexColor("#FFE8D6")!,
                                 textMuted: HexColor("#C9A68F")!, selection: HexColor("#FF7A3D")!, selectionText: HexColor("#1A0E0A")!,
                                 correction: HexColor("#FFD23F")!, line: HexColor("#6B4A3E")!, fontName: "HiraMaruProN-W4", cornerRadius: 4, branchStyle: .straight)
        let looks: [(theme: ThemeChoice, appearance: NSAppearance.Name, name: String)] = [
            (ThemeChoice(.automatic, custom: sample), .darkAqua, "custom"),
            (ThemeChoice(.automatic), .aqua, "glass-light"), (ThemeChoice(.automatic), .darkAqua, "glass-dark"), (ThemeChoice(.platinum), .aqua, "platinum"), (ThemeChoice(.desk), .darkAqua, "desk"),
            (ThemeChoice(.washi), .aqua, "washi"), (ThemeChoice(.neon), .darkAqua, "neon"), (ThemeChoice(.terminal), .darkAqua, "terminal"), (ThemeChoice(.nordic), .aqua, "nordic"),
            (ThemeChoice(.contrast), .darkAqua, "contrast"),
        ]
        for look in looks {
            let appearance = NSAppearance(named: look.appearance)
            NSAppearance.current = appearance
            render(listView(theme: look.theme, appearance: appearance), name: "list-\(look.name)", to: output, appearance: appearance)
            render(latticeView(theme: look.theme, appearance: appearance), name: "branch-\(look.name)", to: output, appearance: appearance)
            render(previewView(theme: look.theme, appearance: appearance), name: "branch-preview-\(look.name)", to: output, appearance: appearance)
            render(correctionView(theme: look.theme, appearance: appearance), name: "correction-\(look.name)", to: output, appearance: appearance)
            render(modeView(theme: look.theme, appearance: appearance), name: "mode-\(look.name)", to: output, appearance: appearance)
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

    private static func modeView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = ModeIndicatorView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        view.label = UIStrings.ModeIndicator.label(for: InputMode.japanese)
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        return backdropped(view)
    }

    /// glass の地のぼかしは画像に写らないので，書き出すときだけ面を塗り，影の代わりに余白を付けて地の上に置く
    private static func backdropped(_ view: NSView) -> NSView {
        let margin: CGFloat = 16
        let container = SnapshotDesk(frame: NSRect(x: 0, y: 0, width: view.frame.width + margin * 2, height: view.frame.height + margin * 2))
        view.frame.origin = NSPoint(x: margin, y: margin)
        container.addSubview(view)
        return container
    }

    private static func listView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = CandidatePanel(
            variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
            selectedVariant: nil,
            entries: ["変換", "返還", "偏官", "へんかん", "ヘンカン"].map { .init(text: $0, annotation: nil) },
            selectedEntry: 1, focus: .candidate, position: 2, total: 12, note: nil
        )
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    private static func correctionView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = CandidateView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = CandidatePanel(
            variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
            selectedVariant: nil,
            entries: [.init(text: "python", annotation: nil), .init(text: "pyてょn", annotation: "入力のまま"), .init(text: "Python", annotation: nil)],
            selectedEntry: 0, focus: .candidate, position: 1, total: 3, note: "Space 入力のままに戻す"
        )
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    private static func latticeView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = SamplePanels.lattice
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 確信の低い文節が 2 つあり，注目していない方に次の候補を添えた分岐図
    private static func previewView(theme: ThemeChoice, appearance: NSAppearance?) -> NSView {
        let view = BranchView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        view.fillsSurface = true
        let panel = LatticePanel(columns: [
            .init(text: "Cloudflareで", isFocused: false, isUncertain: false),
            .init(text: "撮った", isFocused: false, isUncertain: true, preview: "取った"),
            .init(text: "ドメイン", alternatives: ["ドメイン", "どめいん"], selectedAlternative: 0,
                  variants: ["どめいん", "ドメイン", "ﾄﾞﾒｲﾝ"], isFocused: true, isUncertain: true),
        ], position: 1, total: 2)
        view.panel = panel
        view.frame = NSRect(origin: .zero, size: view.fittingSize(for: panel))
        return backdropped(view)
    }

    /// 書き出した画像の地．入力先のアプリの画面の代わりに，薄い色の面を敷く
    private final class SnapshotDesk: NSView {
        override func draw(_ dirtyRect: NSRect) {
            NSColor.underPageBackgroundColor.setFill()
            bounds.fill()
        }
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
