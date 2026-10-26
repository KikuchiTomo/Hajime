import AppKit
import QuartzCore
import SwiftUI

/// 右に出すページ．一度開いたページは作ったまま残し，切り替えでは見せるページを替えるだけにする．
///
/// macOS の Form(.grouped)は行を必要になるまで作らずに済ませる仕組み(Lazy)を持たない．切り替えのたびにすべての行の部品
/// (ポップアップやスイッチは AppKit の部品)を作り直し，1 回に 40〜470 ms，記号のページは 1.8 秒かかっていた(最適化したビルドで測った値)．
/// ページごとに別の NSHostingView に入れ，見せないページは isHidden にする．同じ SwiftUI の木に並べると，見せないページも
/// 切り替えのたびに組み直され(13 ページで 1 回 60〜140 ms)，窓から外すと戻すときに部品を付け直す(1 回 30〜60 ms)ため．
/// 初めて開くページは，先に「読み込み中」を出してから，次の描画の区切りで組み立てる(押したことがすぐ画面に出るように)．
/// 残したページも設定を変えるたびに描き直すので，すべてのページを開いたあとは設定を 1 つ変えるのに 65 ms ほどかかる．
/// 切り替えの速さを優先し，ページは捨てない(5 ページまでに絞ると，設定の変更は 12 ms になるが切り替えが 30〜250 ms に戻る)．
/// ただし描き直しが特に重いページ(Page.keepsWhenHidden が false)は，ほかのページに移ったら捨てる
struct SettingsPageStack: NSViewRepresentable {
    let current: SettingsView.Page
    let makePage: (SettingsView.Page) -> AnyView

    func makeNSView(context: Context) -> PageStackView {
        PageStackView()
    }

    func updateNSView(_ view: PageStackView, context: Context) {
        view.makePage = makePage
        view.show(current)
    }

    @MainActor
    final class PageStackView: NSView {
        var makePage: ((SettingsView.Page) -> AnyView)?
        private var pages: [SettingsView.Page: NSView] = [:]
        private var current: SettingsView.Page?
        private lazy var loading: NSView = {
            let view = NSHostingView(rootView: ProgressView(UIStrings.Settings.loading).controlSize(.small))
            add(view)
            return view
        }()

        override var isFlipped: Bool { true }

        func show(_ page: SettingsView.Page) {
            guard page != current else { return }
            current = page
            for (key, view) in pages { view.isHidden = key != page }
            // 残さないページは，切り替えた画面を描いてから捨てる(捨てるのにも時間がかかるので，切り替えを待たせない)
            let discarded = pages.keys.filter { $0 != page && !$0.keepsWhenHidden }
            if !discarded.isEmpty {
                let views = discarded.compactMap { pages.removeValue(forKey: $0) }
                afterNextFrame { views.forEach { $0.removeFromSuperview() } }
            }

            guard pages[page] == nil else {
                loading.isHidden = true
                return
            }
            loading.isHidden = false
            // 「読み込み中」と左の一覧の選択を先に画面に出してから組み立てる
            afterNextFrame { [weak self] in self?.build(page) }
        }

        /// 今の切り替えを画面に描いてから work を行う．
        /// SwiftUI の更新の途中(updateNSView)では描けないので，更新が済んでから描き，その次の区切りで行う
        private func afterNextFrame(_ work: @escaping @MainActor () -> Void) {
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated {
                    self?.window?.displayIfNeeded()
                    CATransaction.flush()
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated { work() }
                    }
                }
            }
        }

        private func build(_ page: SettingsView.Page) {
            guard pages[page] == nil, let makePage else { return }
            let view = NSHostingView(rootView: makePage(page))
            // ページの大きさで窓の大きさを変えない
            view.sizingOptions = []
            add(view)
            pages[page] = view
            view.isHidden = page != current
            if page == current { loading.isHidden = true }
        }

        private func add(_ view: NSView) {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }
}
