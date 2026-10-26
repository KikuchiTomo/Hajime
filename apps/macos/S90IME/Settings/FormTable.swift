import AppKit
import SwiftUI

/// Form(.grouped)の中に置く表を，表の中でスクロールできるようにする．
///
/// Form は中に置いた表(Table)を行に埋め込むものとして扱い，表の縦のスクロールを止める(スクロールバーを出さず，ホイールでも動かない)．
/// 高さを決めた表では，はみ出した行が見えなくなる．scrollDisabled(false)・isScrollEnabled・別の NSHostingView に入れる，
/// のどれでも戻らない(macOS 26 で確かめた)．表は止められたホイールの動きを外(レスポンダチェーン)へ渡すので，
/// 表を AppKit の入れ物(DetachedContainer)に入れてその動きを受け，表の中を動かす．
/// 表は入れ物の中の NSHostingView で描く．中身は更新のたびに入れ替えるので，状態とバインディングはそのまま効く
struct FormTableHost<Content: View>: NSViewRepresentable {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeNSView(context: Context) -> DetachedContainer {
        let hosting = NSHostingView(rootView: content)
        // 大きさは外(Form の行の frame)で決める
        hosting.sizingOptions = []
        return DetachedContainer(hosting: hosting)
    }

    func updateNSView(_ view: DetachedContainer, context: Context) {
        view.hosting.rootView = content
    }

    /// 表を入れる入れ物．表が渡してきたホイールの動きで，表の中をスクロールする
    final class DetachedContainer: NSView, FormTableContainer {
        let hosting: NSHostingView<Content>

        init(hosting: NSHostingView<Content>) {
            self.hosting = hosting
            super.init(frame: .zero)
            hosting.frame = bounds
            hosting.autoresizingMask = [.width, .height]
            addSubview(hosting)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        /// 中の表のスクロールビュー(表の行を並べる NSTableView を持つもの)
        private var tableScrollView: NSScrollView? {
            var stack: [NSView] = [hosting]
            while let view = stack.popLast() {
                if let scroll = view as? NSScrollView, scroll.documentView is NSTableView { return scroll }
                stack.append(contentsOf: view.subviews)
            }
            return nil
        }

        override func layout() {
            super.layout()
            // Form が消したスクロールバーを出す(行がはみ出していることが見て分かるように)
            guard let scroll = tableScrollView else { return }
            if !scroll.hasVerticalScroller {
                scroll.hasVerticalScroller = true
                scroll.autohidesScrollers = true
            }
            watch(scroll.contentView)
            placeHeader()
        }

        // MARK: 列の見出し
        //
        // 列の見出しは，表のスクロールビューの上の端に重ねた別の入れ物(高さは見出しの高さ)に描かれる．Form の中の表では
        // 上の余白(contentInsets)が 0 になるので，行は見出しの下に潜る．上の端を見出しの高さぶん上(-見出しの高さ)にして
        // 1 行目を見出しの下から並べる．SwiftUI が表を描き直すと位置を 0 に戻すので，上の端にいるあいだは戻し直す

        /// 見張っているスクロールの中身
        private weak var watchedClip: NSClipView?
        /// 表の上の端にいるか．上の端にいるあいだに SwiftUI が位置を 0 に戻したら，見出しの下に戻す
        private var isAtTop = true

        private var header: NSTableHeaderView? {
            (tableScrollView?.documentView as? NSTableView)?.headerView
        }

        private func watch(_ clip: NSClipView) {
            guard watchedClip !== clip else { return }
            watchedClip.map { NotificationCenter.default.removeObserver(self, name: NSView.boundsDidChangeNotification, object: $0) }
            watchedClip = clip
            isAtTop = true
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(clipMoved), name: NSView.boundsDidChangeNotification, object: clip)
        }

        @objc private func clipMoved(_ notification: Notification) {
            placeHeader()
        }

        /// 上の端にいれば，1 行目を見出しの下に並べる
        private func placeHeader() {
            guard let scroll = tableScrollView, let header, header.frame.height > 0 else { return }
            let clip = scroll.contentView
            let top = -header.frame.height
            if isAtTop, clip.bounds.origin.y != top, clip.bounds.origin.y <= 0 {
                clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: top))
                scroll.reflectScrolledClipView(clip)
            } else if clip.bounds.origin.y > 0 {
                isAtTop = false
            }

        }

        /// 表はスクロールを止められているので，ホイールの動きを受け取って表の中を動かす．
        /// 表の端まで動かしたあとの動きは外(ページ)へ渡し，ページもスクロールできるようにする
        override func scrollWheel(with event: NSEvent) {
            guard let scroll = tableScrollView else { return super.scrollWheel(with: event) }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * scroll.verticalLineScroll
            if !scrollTable(by: delta) { super.scrollWheel(with: event) }
        }

        /// 表の中を delta だけ動かす．端にいて動かせなければ false．上の端は見出しの高さぶん上
        @discardableResult
        func scrollTable(by delta: CGFloat) -> Bool {
            guard let scroll = tableScrollView, let document = scroll.documentView else { return false }
            let clip = scroll.contentView
            let top = -(header?.frame.height ?? 0)
            let bottom = max(top, document.frame.height - clip.bounds.height)
            let current = clip.bounds.origin.y
            let target = min(max(current - delta, top), bottom)
            guard target != current else { return false }
            isAtTop = target == top
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
            scroll.reflectScrolledClipView(clip)
            placeHeader()
            return true
        }
    }
}

/// FormTableHost の入れ物の目印(見本の画像に写すときに探す)
protocol FormTableContainer: NSView {
    /// 表の中を delta だけ動かす(ホイールと同じ道筋)．動かせなければ false
    @discardableResult func scrollTable(by delta: CGFloat) -> Bool
}

/// 表が空のとき(検索に合う行が無いときも)に表の中に出す 1 行．システム設定の空の一覧と同じく，薄い小さな字だけにする
struct EmptyListLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 表を選んだり右クリックしたりするのを妨げない
            .allowsHitTesting(false)
    }
}
