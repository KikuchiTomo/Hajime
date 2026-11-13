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
/// 組み立ては，上の部分を先に出し，続きを描画の区切りごとに足す(PageBuild)．
/// 残したページは，そのページに出している設定が変わったときだけ描き直す(ObservedSettings)．ほかのページの設定を変えても描き直さないので，
/// どのページも捨てずに残す(キー設定のページも，開くたびに 0.3 秒かけて組み立てずに済む)
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
        /// 下の部分をまだ組み立てているページの数
        private var unfinished = 0
        /// 組み立ての途中のページがあるか(計測と見本の書き出しで，組み立てが済むのを待つ)
        var isBuilding: Bool { unfinished > 0 }

        /// ページの最初の部分を組み立てたか
        func isBuilt(_ page: SettingsView.Page) -> Bool { pages[page] != nil }
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
            // 見えている上の部分だけを先に組み立てて出し，下の部分は描画の区切りごとに足す(PageBuild)
            let progress = PageBuild()
            let view = NSHostingView(rootView: makePage(page).environment(progress))
            // ページの大きさで窓の大きさを変えない
            view.sizingOptions = []
            add(view)
            pages[page] = view
            view.isHidden = page != current
            if page == current { loading.isHidden = true }
            unfinished += 1
            buildRest(progress)
        }

        /// 今の段を画面に描いてから，次の段を組み立てる．ページが使う段は描いたあとで分かるので，描いてから残りがあるかを見る
        private func buildRest(_ progress: PageBuild) {
            afterNextFrame { [weak self] in
                guard let self else { return }
                if progress.isFinished {
                    unfinished -= 1
                } else {
                    progress.advance()
                    buildRest(progress)
                }
            }
        }

        private func add(_ view: NSView) {
            view.frame = safeAreaRect
            addSubview(view)
        }

        /// ページは安全な範囲(safeAreaRect)に置く．macOS 26 では左の一覧が中身の上に浮かび，中身の欄は一覧の下まで広がる．
        /// SwiftUI のページは自分の外の安全な範囲を知らないので，そのまま広げると左端が一覧の下に隠れる
        override func layout() {
            super.layout()
            for view in subviews { view.frame = safeAreaRect }
        }
    }
}

/// 初めて開くページの組み立ての進み．
///
/// Form(.grouped)は行を見えるまで作らずに済ませる仕組みを持たず，1 行(スイッチやポップアップは AppKit の部品)に 7〜10 ms かかる．
/// 80 行ある変換のページは，開くのに 0.6 秒かかっていた．ページを段に分け，上の部分(段 0)を先に組み立てて出し，
/// 続き(BuiltLater・表の行)は描画の区切りごとに 1 段ずつ足す．1 段は 8 行ほどにして，足している間も操作を待たせない．
/// 組み立て終えたページは残すので，2 回目からは分けない
@MainActor @Observable
final class PageBuild {
    /// ここまでの段を組み立てている(0 は最初に出す部分)
    private(set) var stage = 0
    /// ページが使っているいちばん後ろの段
    @ObservationIgnored private var lastStage = 0

    /// ページのすべての段を組み立てたか
    var isFinished: Bool { stage >= lastStage }

    func advance() {
        stage += 1
    }

    /// stage の段を組み立ててよいか．まだなら，その段まで進んだときに読んだ画面を描き直す
    func includes(_ stage: Int) -> Bool {
        lastStage = max(lastStage, stage)
        return self.stage >= stage
    }

    /// 表の行を 1 段に何行ずつ増やすか(行ごとにポップアップやボタンを持つ表で，1 行に 15〜20 ms かかる)
    static let tableRowsPerStage = 4

    /// 表に出す行の数．first の段より前は表の枠だけを出し，first の段から 1 段ごとに tableRowsPerStage 行ずつ増やして，
    /// 見えている行(visibleRows)が埋まった段ですべての行を出す(nil)．
    /// 表は見えている行だけを作るので，見えている行を埋めたあとは，まとめて出しても重くならない
    func rowLimit(visibleRows: Int, startingAt first: Int = 1) -> Int? {
        let stages = (visibleRows + Self.tableRowsPerStage - 1) / Self.tableRowsPerStage
        return includes(first + stages - 1) ? nil : Self.tableRowsPerStage * max(0, stage - first + 1)
    }
}

/// ページのうち，あとの段(1 以上)で組み立てる部分．Form の Section や行を入れる．
/// 設定の画面の外で描くとき(見本の書き出し)は，すぐに組み立てる
struct BuiltLater<Content: View>: View {
    @Environment(PageBuild.self) private var build: PageBuild?
    let stage: Int
    @ViewBuilder let content: () -> Content

    var body: some View {
        if build?.includes(stage) ?? true {
            content()
        }
    }
}
