import AppKit
import SwiftUI

/// Form(.grouped)の中に置く表を，表の中でスクロールできるようにする．
///
/// Form は中に置いた表(Table)を行に埋め込むものとして扱い，表の縦のスクロールを止める(スクロールバーを出さず，ホイールでも動かない)．
/// 高さを決めた表では，はみ出した行が見えなくなる．scrollDisabled(false)・isScrollEnabled・別の NSHostingView に入れる，
/// のどれでも戻らない(macOS 26 で確かめた)．表は止められたホイールの動きを外(レスポンダチェーン)へ渡すので，
/// 表を AppKit の入れ物(DetachedContainer)に入れてその動きを受け，表の中を動かす．
/// 表は入れ物の中の NSHostingView で描く．中身は更新のたびに入れ替えるので，状態とバインディングはそのまま効く．
/// 列の見出しは表の外に FormTableHeader で描く
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
            guard let scroll = tableScrollView, !scroll.hasVerticalScroller else { return }
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
        }

        /// 表はスクロールを止められているので，ホイールの動きを受け取って表の中を動かす．
        /// 表の端まで動かしたあとの動きは外(ページ)へ渡し，ページもスクロールできるようにする
        override func scrollWheel(with event: NSEvent) {
            guard let scroll = tableScrollView else { return super.scrollWheel(with: event) }
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * scroll.verticalLineScroll
            if !scrollTable(by: delta) { super.scrollWheel(with: event) }
        }

        /// 表の中を delta だけ動かす．端にいて動かせなければ false
        @discardableResult
        func scrollTable(by delta: CGFloat) -> Bool {
            guard let scroll = tableScrollView, let document = scroll.documentView else { return false }
            let clip = scroll.contentView
            let bottom = max(0, document.frame.height - clip.bounds.height)
            let current = clip.bounds.origin.y
            let target = min(max(current - delta, 0), bottom)
            guard target != current else { return false }
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: target))
            scroll.reflectScrolledClipView(clip)
            return true
        }
    }
}

/// 表の列の見出し．FormTableHost の表の上(スクロールの外)に置き，表の見出しは .tableColumnHeaders(.hidden) で隠す．
///
/// 表の見出し(NSTableHeaderView)は，Form の中では地が描かれず，位置も SwiftUI に動かされる．スクロールすると行が見出しの下を通って
/// 重なり，外から位置や地を直しても描き直しで戻された．見出しを表の外に描けば，行は見出しの下を通らない．
/// 列の幅は表の列と同じ値(DesignTokens)を使い，最後の列だけを残りの幅にする
struct FormTableHeader: View {
    struct Column {
        let title: String
        /// nil なら残りの幅
        var width: CGFloat?
        /// 押して並べ替える列なら，押したときの動き
        var sort: (() -> Void)?
        /// 並べ替えている向き(昇順なら true)．並べ替えていなければ nil
        var ascending: Bool?
        /// 列の中身の文字が左に余白を持つとき(ポップアップなど)，見出しもその分ずらす
        var leadingInset: CGFloat = 0
    }

    let columns: [Column]

    var body: some View {
        HStack(spacing: DesignTokens.Size.Settings.tableColumnSpacing) {
            ForEach(columns.indices, id: \.self) { index in
                cell(columns[index])
                    .padding(.leading, columns[index].leadingInset)
                    .frame(width: columns[index].width, alignment: .leading)
                    .frame(maxWidth: columns[index].width == nil ? .infinity : nil, alignment: .leading)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, DesignTokens.Size.Settings.tableHeaderInset)
    }

    @ViewBuilder
    private func cell(_ column: Column) -> some View {
        if let sort = column.sort {
            Button(action: sort) {
                HStack {
                    Text(column.title)
                    if let ascending = column.ascending {
                        Image(systemName: ascending ? "chevron.up" : "chevron.down").imageScale(.small)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(UIStrings.RuleList.sortHint)
        } else {
            Text(column.title)
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
