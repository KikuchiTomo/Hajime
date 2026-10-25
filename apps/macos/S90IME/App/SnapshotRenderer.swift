#if DEBUG
import AppKit
import S90Application
import S90Domain

/// 候補ウィンドウの見た目を画像に書き出す(デバッグビルドだけ)．
/// 入力メソッドとして動かさずに描画を確かめ，PR に貼るスクリーンショットを作るため．
///
/// 使い方: "s90.tokyo IME.app/Contents/MacOS/s90.tokyo IME" --render-snapshots
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
            render(latticeView(theme: theme, appearance: appearance), name: "lattice-\(theme.rawValue)", to: output, appearance: appearance)
            render(correctionView(theme: theme, appearance: appearance), name: "correction-\(theme.rawValue)", to: output, appearance: appearance)
        }
        exit(0)
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
        let view = LatticeView()
        view.theme = ResolvedTheme.resolve(theme, appearance: appearance)
        let panel = LatticePanel(columns: [
            .init(text: "私の名前は", alternatives: ["私の名前は", "わたしの名前は", "ワタシの名前は"], selectedAlternative: 0, isFocused: false, showsAlternatives: false),
            .init(text: "中のです", alternatives: ["中のです", "なかのです", "中野です", "仲のです"], selectedAlternative: 0, isFocused: true, showsAlternatives: true),
        ])
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
