// HTML のファイルを WKWebView で描いて PNG に書き出す．公式サイトの説明用の画像(tools/site/make_site_images.py)を作るのに使う．
// 使い方: swift tools/site/render_html.swift <HTML> <PNG> <幅> <高さ> [倍率]
import AppKit
import WebKit

let arguments = CommandLine.arguments
guard arguments.count >= 5, Double(arguments[3]) != nil, Double(arguments[4]) != nil else {
    print("使い方: swift render_html.swift <HTML> <PNG> <幅> <高さ> [倍率]")
    exit(2)
}

final class Renderer: NSObject, WKNavigationDelegate {
    let view: WKWebView
    let window: NSWindow
    let source: URL
    let output: URL
    let width: Double
    let height: Double
    let scale: Double

    init(source: URL, output: URL, width: Double, height: Double, scale: Double) {
        self.source = source
        self.output = output
        self.width = width
        self.height = height
        self.scale = scale
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        view = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        // 画面の外に置いた窓に入れる(窓に入っていないと，画像の読み込みと描画が進まないことがある)
        window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.contentView = view
        super.init()
        view.navigationDelegate = self
        window.orderBack(nil)
        view.loadFileURL(source, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // 画像と書体の読み込みを待ってから撮る
        let ready = "Promise.all([document.fonts.ready, ...Array.from(document.images).map(i => i.decode().catch(() => null))]).then(() => true)"
        webView.callAsyncJavaScript("return await \(ready)", in: nil, in: .page) { _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.snapshot() }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("読み込みに失敗: \(error.localizedDescription)")
        exit(1)
    }

    private func snapshot() {
        let output = output
        let configuration = WKSnapshotConfiguration()
        configuration.rect = NSRect(x: 0, y: 0, width: width, height: height)
        configuration.snapshotWidth = NSNumber(value: width * scale / Double(NSScreen.main?.backingScaleFactor ?? 2))
        view.takeSnapshot(with: configuration) { image, error in
            guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
                  let png = bitmap.representation(using: .png, properties: [:]) else {
                print("撮れませんでした: \(error?.localizedDescription ?? "")")
                exit(1)
            }
            do { try png.write(to: output) } catch {
                print("書き出せませんでした: \(error.localizedDescription)")
                exit(1)
            }
            exit(0)
        }
    }
}

let application = NSApplication.shared
application.setActivationPolicy(.prohibited)
let renderer = Renderer(source: URL(fileURLWithPath: arguments[1]), output: URL(fileURLWithPath: arguments[2]),
                        width: Double(arguments[3]) ?? 0, height: Double(arguments[4]) ?? 0,
                        scale: arguments.count > 5 ? Double(arguments[5]) ?? 2 : 2)
DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
    print("時間切れ")
    exit(1)
}
application.run()
_ = renderer
