import AppKit
import InputMethodKit
import os
import HajimeApplication
import HajimeDomain

/// ClientAction を InputMethodKit の操作に置き換える．判断はしない(docs/dev/ARCHITECTURE.md)．
@MainActor
final class ClientActionPresenter {
    /// 手書きの窓で選んだ文字を，組み立て中の文字と合わせて入れるのに使う
    private let session: InputSession
    private let candidatePanel: CandidatePanelController
    private let modeIndicator: ModeIndicatorController
    private let note: NoteController
    private let prediction: PredictionController
    private let openSettings: () -> Void
    /// 設定のユーザー辞書の画面を開き，語と読みを登録の欄に入れる(空なら入れない)
    private let openWordRegistration: (_ word: String, _ reading: String) -> Void
    /// 語の読み(入力先で選んでいた文字を登録するとき)．分からなければ nil
    private let readingOf: (String) -> String?
    private let handwriting: HandwritingController
    private let palette: PaletteController
    private let settings: any SettingsStoring
    /// コマンドの候補を選んで確定したときに動かす(R-22)
    private let runCommand: (LauncherCommand) -> Void
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "settings")

    init(session: InputSession, candidatePanel: CandidatePanelController, modeIndicator: ModeIndicatorController, note: NoteController,
         prediction: PredictionController, settings: any SettingsStoring,
         openSettings: @escaping () -> Void, openWordRegistration: @escaping (_ word: String, _ reading: String) -> Void,
         readingOf: @escaping (String) -> String?, handwriting: HandwritingController, palette: PaletteController,
         runCommand: @escaping (LauncherCommand) -> Void) {
        self.session = session
        self.openWordRegistration = openWordRegistration
        self.readingOf = readingOf
        self.palette = palette
        self.runCommand = runCommand
        self.openSettings = openSettings
        self.handwriting = handwriting
        self.candidatePanel = candidatePanel
        self.modeIndicator = modeIndicator
        self.note = note
        self.prediction = prediction
        self.settings = settings
    }

    /// 最後にキーを受けたときの入力先の文脈．候補をマウスで押したときも同じ文脈で処理する
    var context = InputContext()
    /// 次に組み立て中の文字を出すか確定するときに置き換える入力先の範囲(再変換で選んでいた文字)．1 回使ったら消す
    var replacement: NSRange?

    func apply(_ actions: [ClientAction], to client: any IMKTextInput) {
        // 候補をマウスで押したら，キーで選んだのと同じに処理して入力先に反映する
        candidatePanel.onChoose = { [weak self, weak client = client as AnyObject] target in
            guard let self, let client = client as? any IMKTextInput else { return }
            self.apply(self.session.choose(target, context: self.context), to: client)
        }
        // 同じ操作の列の中で，消したあとに出し直す窓(InputSession は案内を消すときなどに hideCandidates を前に足す)．
        // 置く場所はキーを返したあとに決めるので，ここで消すと 1 コマ消えてから出る．出し直すなら消さずに中身を変える
        let showsCandidatesLater = actions.indices.map { index in
            actions[(index + 1)...].contains { if case .showCandidates = $0 { true } else if case .showLattice = $0 { true } else { false } }
        }
        let showsPredictionLater = actions.indices.map { index in
            actions[(index + 1)...].contains { if case .showPrediction(let shown) = $0 { shown != nil } else { false } }
        }
        for (index, action) in actions.enumerated() {
            switch action {
            case .commit(let text):
                client.insertText(text, replacementRange: takeReplacement())
            case .setMarkedText(let marked):
                let attributed = Self.attributedString(for: marked)
                markedLength = (marked.text as NSString).length
                client.setMarkedText(attributed, selectionRange: NSRange(location: (marked.textBeforeCaret as NSString).length, length: 0), replacementRange: takeReplacement())
                // 予測の窓と候補の窓は組み立て中の文字に付いていく(置き直すのはキーを返したあと)
                if prediction.isVisible || candidatePanel.isVisible { placesWindows = true }
            case .showCandidates(let panel):
                note.hide()
                showCandidates(.list(panel))
            case .showLattice(let panel):
                note.hide()
                showCandidates(.lattice(panel))
            case .hideCandidates:
                note.hide()
                guard !showsCandidatesLater[index] else { break }
                shownCandidates = nil
                candidatePanel.hide()
            case .requestReconversion:
                // 入力コントローラが入力先の選んでいる文字を読んで再変換する(HajimeInputController.reconvert)
                break
            case .replacePrecedingText(let length):
                // 確定を取り消す: 入力位置の前の確定した文字を，次に出す組み立て中の文字で置き換える(再変換と同じ置き換え)
                let selection = client.selectedRange()
                if selection.location != NSNotFound, selection.location >= length {
                    replacement = NSRange(location: selection.location - length, length: length + selection.length)
                }
            case .awaitCorrections:
                // 入力コントローラが裏で訂正を求め，届いたら変換を直す(HajimeInputController.correctAfterConversion)
                break
            case .openSettings:
                openSettings()
            case .openWordRegistration(let word, let reading):
                // 入力していなければ，入力先で選んでいる文字を登録する
                let registered = word ?? HajimeInputController.selectedWord(of: client) ?? ""
                openWordRegistration(registered, reading ?? (registered.isEmpty ? "" : readingOf(registered) ?? ""))
            case .openUserDictionary:
                openWordRegistration("", "")
            case .openMenu:
                // 入力コントローラが入力位置に入力メニューを出す(HajimeInputController.handle)
                break
            case .runCommand(let command):
                // 確定したときの設定にまだあり，使う設定のときだけ動かす(Windows の EngineService と同じ)
                guard settings.current.launcherCommands, settings.current.commands.contains(command) else { break }
                runCommand(command)
            case .showHandwriting:
                // 窓はフォーカスを奪わないので，選んだときも入力先は開いたときのまま(入力先から外れたら窓を閉じる)
                handwriting.show(caret: caretRect(of: client), owner: self) { [weak self] text in
                    guard let self else { return }
                    self.apply(self.session.insert(text), to: client)
                }
            case .showPalette(let shown):
                // パレットの窓はアプリで 1 つなので，マウスの操作は今キーを受けている入力先のセッションに渡す
                palette.onTarget = { [weak self, weak client = client as AnyObject] target in
                    guard let self, let client = client as? any IMKTextInput else { return }
                    self.apply(self.session.palette(target, context: self.context), to: client)
                }
                palette.show(shown, caret: caretRect(of: client), theme: ThemeChoice(settings.current), cellSize: settings.current.paletteCellSize)
            case .hidePalette:
                palette.hide()
            case .toggleLiveConversion:
                do {
                    try settings.update { $0.liveConversion.toggle() }
                } catch {
                    logger.error("ライブ変換の設定を保存できませんでした: \(String(describing: error), privacy: .public)")
                }
            case .showNote(let shown):
                note.show(shown, caret: caretRect(of: client), theme: ThemeChoice(settings.current))
            case .showPrediction(let shown):
                // 候補の窓を出す・消す操作では触らず，これだけで出し入れする
                if let shown {
                    showPrediction(shown)
                } else if !showsPredictionLater[index] {
                    shownPrediction = nil
                    prediction.hide()
                }
            case .showModeIndicator(let mode):
                modeIndicator.show(mode, caret: caretRect(of: client), theme: ThemeChoice(settings.current), duration: settings.current.modeIndicatorDuration)
            case .selectMode(let mode):
                client.selectMode(mode == .japanese ? AppIdentity.japaneseModeID : AppIdentity.directModeID)
            case .selectInputStyle(let style):
                do {
                    try settings.update { $0.inputStyle = style }
                    // 切り替えたことを入力位置の近くに出す
                    if settings.current.showsModeIndicator {
                        modeIndicator.show(style, caret: caretRect(of: client), theme: ThemeChoice(settings.current), duration: settings.current.modeIndicatorDuration)
                    }
                } catch {
                    logger.error("入力方式を保存できませんでした: \(String(describing: error), privacy: .public)")
                }
            }
        }
        if placesWindows {
            placesWindows = false
            schedulePlacement(for: client)
        }
    }

    /// 出している(出す)候補の窓の中身
    private enum ShownCandidates {
        case list(CandidatePanel)
        case lattice(LatticePanel)
    }

    /// 出している(出す)候補の窓と予測の窓の中身．置く場所が決まったときに出す・置き直すのに使う
    private var shownCandidates: ShownCandidates?
    private var shownPrediction: Prediction?
    /// 今の apply で，キーを返したあとに窓を置く場所を問い合わせるか
    private var placesWindows = false
    /// 置く場所の問い合わせの世代．続けて打ったときは最後の 1 回だけ問い合わせ，古い結果で置き直さない
    private var placementGeneration = 0
    /// 最後に候補の窓・予測の窓を置いた場所(次の場所が決まるまで，出ている窓の中身はここで変える)
    private var candidateCaret: NSRect?
    private var predictionEnd: NSRect?

    /// 候補の窓の中身を変える．出ていれば前の場所ですぐ変え，場所はキーを返したあとに問い合わせて置き直す．
    /// 出ていなければ，場所が決まるまで出さない(見当違いの場所に一瞬出ないように)
    private func showCandidates(_ shown: ShownCandidates) {
        shownCandidates = shown
        if candidatePanel.isVisible, let candidateCaret { display(shown, caret: candidateCaret) }
        placesWindows = true
    }

    /// 予測の窓の中身を変える．出し方は候補の窓と同じ
    private func showPrediction(_ shown: Prediction) {
        shownPrediction = shown
        if prediction.isVisible, let predictionEnd {
            prediction.show(shown, end: predictionEnd, theme: ThemeChoice(settings.current), fontSize: settings.current.candidateFontSize)
        }
        placesWindows = true
    }

    private func display(_ shown: ShownCandidates, caret: NSRect) {
        switch shown {
        case .list(let panel):
            candidatePanel.show(panel, caret: caret, theme: ThemeChoice(settings.current), fontSize: settings.current.candidateFontSize,
                                keys: settings.current.keymap, showsHints: settings.current.showsKeyHints)
        case .lattice(let panel):
            candidatePanel.showLattice(panel, caret: caret, theme: ThemeChoice(settings.current), fontSize: settings.current.candidateFontSize,
                                       keys: settings.current.keymap, showsHints: settings.current.showsKeyHints)
        }
    }

    /// 窓を置く場所を，キーを返したあと(入力先のアプリが組み立て中の文字を受け取ったあと)に 1 回だけ問い合わせる．
    /// 入力先への問い合わせは，アプリが組み立て中の文字を並べ終えるまで返らないので，キーの処理の中では待たない
    private func schedulePlacement(for client: any IMKTextInput) {
        placementGeneration &+= 1
        let generation = placementGeneration
        DispatchQueue.main.async { [weak self, weak client = client as AnyObject] in
            MainActor.assumeIsolated {
                guard let self, generation == self.placementGeneration, let client = client as? any IMKTextInput else { return }
                self.placeWindows(in: client)
            }
        }
    }

    /// 組み立て中の文字の位置を問い合わせ，候補の窓と予測の窓の両方を置く(同じ問い合わせの結果を両方に使う)
    private func placeWindows(in client: any IMKTextInput) {
        guard shownCandidates != nil || shownPrediction != nil else { return }
        let start = lineRect(of: client, at: 0)
        let end = markedLength > 1 ? lineRect(of: client, at: markedLength - 1) : start
        if let shown = shownCandidates {
            var anchorIndex: Int?
            if case .list(let panel) = shown { anchorIndex = panel.anchor }
            let left = anchorIndex.map { index in
                index == 0 || markedLength <= 1 ? start : index == markedLength - 1 ? end : lineRect(of: client, at: min(max(index, 0), markedLength - 1))
            }
            let caret = Self.panelAnchor(start: start, end: end, left: left, markedLength: markedLength)
            if !candidatePanel.isVisible || caret != candidateCaret { display(shown, caret: caret) }
            candidateCaret = caret
        }
        if let shown = shownPrediction {
            if prediction.isVisible {
                if end != predictionEnd { prediction.move(end: end) }
            } else {
                prediction.show(shown, end: end, theme: ThemeChoice(settings.current), fontSize: settings.current.candidateFontSize)
            }
            predictionEnd = end
        }
    }

    /// 出している分岐図が，候補と先の枝を左へ出しているか．矢印キーを表示の向きに効かせるために，キーを渡す前にコアへ知らせる
    var isBranchMirrored: Bool { candidatePanel.isBranchMirrored }

    /// 修飾キーの押し方が変わった(分岐図のキーの案内を，押し続けているあいだだけ出す)
    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        candidatePanel.modifiersChanged(flags)
    }

    func hideWindows() {
        shownCandidates = nil
        shownPrediction = nil
        candidatePanel.hide()
        note.hide()
        prediction.hide()
    }

    /// この入力先で開いた手書きの窓を閉じる
    func closeHandwriting() {
        handwriting.close(openedBy: self)
    }

    private static let noReplacement = NSRange(location: NSNotFound, length: 0)

    private func takeReplacement() -> NSRange {
        defer { replacement = nil }
        return replacement ?? Self.noReplacement
    }

    private func caretRect(of client: any IMKTextInput) -> NSRect {
        lineRect(of: client, at: 0)
    }

    /// 組み立て中の文字の index 番目(UTF-16)の字がある行の長方形．アプリが教えなければ .zero
    private func lineRect(of client: any IMKTextInput, at index: Int) -> NSRect {
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
        return rect
    }

    /// 最後に出した組み立て中の文字の長さ(UTF-16)
    private var markedLength = 0

    /// 候補の窓を置く基準．左端は anchor の字(left．無ければ組み立て中の文字の頭)，上の辺は頭の行の上，下の辺は最後の行の下．
    /// 組み立て中の文字が何行かに折り返しても，窓を文字に重ねない(下に置くときは最後の行の下，上に置くときは頭の行の上)
    private static func panelAnchor(start: NSRect, end: NSRect, left: NSRect?, markedLength: Int) -> NSRect {
        guard start != .zero, markedLength > 1 else { return start }
        let left = left ?? start
        let lines = [start, end, left].filter { $0 != .zero }
        let bottom = lines.map(\.minY).min() ?? start.minY
        let top = max(start.maxY, bottom)
        return NSRect(x: left == .zero ? start.minX : left.minX, y: bottom, width: max(left.width, 1), height: top - bottom)
    }

    private static func attributedString(for marked: MarkedText) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for (index, segment) in marked.segments.enumerated() {
            var attributes: [NSAttributedString.Key: Any] = [
                // 文節の区切りをアプリに伝える．区切りごとに下線が分かれて見える
                .markedClauseSegment: index,
            ]
            switch segment.style {
            case .reading, .converted:
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            case .focused:
                attributes[.underlineStyle] = NSUnderlineStyle.thick.rawValue
            case .correction:
                attributes[.underlineStyle] = NSUnderlineStyle([.single, .patternDot]).rawValue
            }
            result.append(NSAttributedString(string: segment.text, attributes: attributes))
        }
        return result
    }
}
