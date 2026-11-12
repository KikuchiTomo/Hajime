import AppKit

/// 開く・保存の窓を，メインスレッドを止めずに出す．
///
/// 設定の画面は，入力ソースの Hajime IME と同じプロセスで動く．runModal で窓を出すとメインスレッドが止まり，
/// 窓の名前の欄や検索の欄に打った文字(入力ソースの Hajime IME が受け取る)を処理できずに，窓と互いに待って止まる
/// (ぐるぐるが出て書き出せない)．開発版は入力ソースに登録しないので，この止まり方は起きない．
/// そのため，前にある窓(設定の窓)のシートとして出し，閉じたら選んだ場所で続きを行う
@MainActor
enum FilePanel {
    /// 1 つを選ぶ(保存の窓では保存する場所)．取り消したら何もしない
    static func chooseOne(_ panel: NSSavePanel, then chosen: @escaping @MainActor (URL) -> Void) {
        present(panel) { urls in
            if let url = urls.first { chosen(url) }
        }
    }

    /// いくつでも選ぶ(開く窓で allowsMultipleSelection を付けたとき)．取り消したら何もしない
    static func chooseMany(_ panel: NSOpenPanel, then chosen: @escaping @MainActor ([URL]) -> Void) {
        present(panel) { urls in
            if !urls.isEmpty { chosen(urls) }
        }
    }

    private static func present(_ panel: NSSavePanel, then chosen: @escaping @MainActor ([URL]) -> Void) {
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            let urls = (panel as? NSOpenPanel)?.urls ?? panel.url.map { [$0] } ?? []
            MainActor.assumeIsolated { chosen(urls) }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }
}
