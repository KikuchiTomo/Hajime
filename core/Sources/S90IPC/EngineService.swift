import Foundation
import S90Application
import S90Domain

@MainActor
public final class EngineService {
    public struct ConnectionID: Hashable, Sendable {
        let rawValue: UInt64
    }

    public static let maximumSessionsPerConnection = 64
    public static let maximumSessions = 1024
    /// 手書きの窓を開いているあいだ，DLL が選んだ文字を取りに来る(wake)間隔
    public static let handwritingPollMilliseconds = milliseconds(DefaultSettings.handwritingPollInterval)
    /// 候補の窓を出しているあいだ，DLL がマウスで押した候補を取りに来る間隔
    public static let candidateClickPollMilliseconds = milliseconds(DefaultSettings.candidateClickPollInterval)

    private struct Connection {
        var hasGreeted = false
        var sessions: Set<UInt32> = []
        /// 候補ウィンドウのプロセスからの接続か(実行ファイルを EnginePipeServer が確かめる)．手書きの窓で選んだ文字はこの接続からだけ受ける
        var isCandidateWindow = false
    }

    /// 開いている手書きの窓(R-14)．選んだ文字は窓を開いたセッションに預け，DLL の wake で入れる
    /// (DLL は要求にしか答えられないので，エンジンから入力欄に押し込めない)
    private struct Handwriting {
        let session: UInt32
        var chosen: String?
    }

    private struct Session {
        let owner: ConnectionID
        let input: InputSession
        var hasSettled = false
        /// 裏で求めている打ち間違いの訂正
        var correction: CorrectionWork?
    }

    /// 打ち間違いの訂正を裏で求めている途中の仕事．求め終わったら result が入り，次の wake で使う
    private struct CorrectionWork {
        enum Purpose {
            /// Space で変換するのを待たせている(.awaitCorrections)．期限を過ぎたら待たずに変換する
            case conversion(deadline: ContinuousClock.Instant)
            /// 打鍵が止まったので見直す
            case review
        }

        let id: UInt64
        let purpose: Purpose
        let task: Task<Void, Never>
        var result: [String: [ReadingCorrection]]?
    }

    /// 訂正を求めているあいだ，求め終わったかを見に来てもらう間隔(ミリ秒)．
    /// DLL からエンジンへは要求と応答しか無いので，DLL のタイマーの wake で結果を渡す
    public static let correctionPollMilliseconds: UInt32 = 30

    private let makeSession: () -> InputSession
    private let settings: any SettingsStoring
    private let ui: (WireUiCommand) -> Void
    private let openSettings: () -> Void
    private let hints: (LatticePanel, Settings) -> [WireKeyHint]
    /// 打ち間違いの訂正を別に求めるもの(Zenzai があるとき)．nil なら InputSession が変換器で求める
    private let typoService: (any TypoCorrecting)?
    private let now: () -> ContinuousClock.Instant
    private var nextCorrection: UInt64 = 1
    /// 同期の操作(Windows の設定の画面から頼まれる)．無ければ同期の要求に malformed を返す
    let sync: (any SyncControlling)?
    /// 設定に関わるファイルの読み書き．無ければファイルの要求に malformed を返す
    private let files: (any SettingsFileHandling)?
    private var isRunningFileWork = false
    private let services: SettingsServices
    private var connections: [ConnectionID: Connection] = [:]
    private var sessions: [UInt32: Session] = [:]
    private var nextConnection: UInt64 = 1
    private var nextSession: UInt32 = 1
    private var lastAnchor: WireRect?
    private var handwriting: Handwriting?
    /// 候補の窓を出しているセッション．候補ウィンドウで押した候補は，このセッションの次の wake で選ぶ
    private var shownCandidates: UInt32?
    /// 候補ウィンドウでマウスで押した候補(押したときに出ていたセッションと対象)
    private var chosen: (session: UInt32, target: WirePointerTarget)?

    public init(makeSession: @escaping () -> InputSession, settings: any SettingsStoring, ui: @escaping (WireUiCommand) -> Void,
                openSettings: @escaping () -> Void, hints: @escaping (LatticePanel, Settings) -> [WireKeyHint] = { _, _ in [] },
                typoService: (any TypoCorrecting)? = nil, now: @escaping () -> ContinuousClock.Instant = { ContinuousClock.now },
                sync: (any SyncControlling)? = nil, files: (any SettingsFileHandling)? = nil,
                services: SettingsServices = SettingsServices()) {
        self.services = services
        self.typoService = typoService
        self.now = now
        self.sync = sync
        self.files = files
        self.makeSession = makeSession
        self.settings = settings
        self.ui = ui
        self.openSettings = openSettings
        self.hints = hints
    }

    public func connect(isCandidateWindow: Bool = false) -> ConnectionID {
        let id = ConnectionID(rawValue: nextConnection)
        nextConnection += 1
        connections[id] = Connection(isCandidateWindow: isCandidateWindow)
        return id
    }

    public func disconnect(_ id: ConnectionID) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        for session in connection.sessions {
            sessions.removeValue(forKey: session)?.correction?.task.cancel()
            closeHandwriting(ofSession: session)
        }
        if !connection.sessions.isEmpty { ui(.hide) }
    }

    public var sessionCount: Int { sessions.count }

    public func handle(_ request: WireRequest, from id: ConnectionID) -> WireResponse {
        let response = WireResponse(id: request.id, body: body(for: request.body, from: id))
        // 設定の項目は大きくなりうる(ユーザー辞書など)．送れない大きさなら，項目を分けて頼んでもらう
        switch response.body {
        case .settingsFields, .userDictionary, .languagePreview:
            if Self.fits(response) { return response }
        default:
            return response
        }
        return WireResponse(id: request.id, body: .error(code: .tooLarge))
    }

    private static func fits(_ response: WireResponse) -> Bool {
        guard let data = try? JSONEncoder().encode(response) else { return false }
        return data.count <= WireProtocol.maximumMessageBytes
    }

    /// 要求への答え方．すぐに答えるか，時間のかかる仕事(ファイルの読み書き)を終えてから答えるか
    public enum Reply: Sendable {
        case now(WireResponse)
        /// メインアクターで動かして待つ．重い部分はメインスレッドの外で動くので，待つあいだもほかの要求に答えられる
        case later(@MainActor @Sendable () async -> WireResponse)
    }

    /// 名前付きパイプから来た要求に答える．ファイルの読み書きは .later，ほかは handle と同じ
    public func reply(to request: WireRequest, from id: ConnectionID) -> Reply {
        guard connections[id]?.hasGreeted == true, let work = fileWork(for: request.body) else { return .now(handle(request, from: id)) }
        guard let files else { return .now(WireResponse(id: request.id, body: .error(code: .malformed))) }
        guard !isRunningFileWork else { return .now(WireResponse(id: request.id, body: .fileFailed(reason: .busy))) }
        isRunningFileWork = true
        return .later { [self] in
            defer { isRunningFileWork = false }
            do throws(SettingsFileFailure) {
                return WireResponse(id: request.id, body: try await work(files))
            } catch {
                return WireResponse(id: request.id, body: .fileFailed(reason: WireFileFailure(error)))
            }
        }
    }

    private func body(for request: WireRequestBody, from id: ConnectionID) -> WireResponseBody {
        guard var connection = connections[id] else { return .error(code: .malformed) }
        if case .hello(let version) = request {
            guard version == WireProtocol.version else { return .error(code: .unsupportedVersion) }
            connection.hasGreeted = true
            connections[id] = connection
            return .hello(protocolVersion: WireProtocol.version)
        }
        guard connection.hasGreeted else { return .error(code: .unsupportedVersion) }
        switch request {
        case .hello:
            return .error(code: .malformed)
        case .openSession:
            guard connection.sessions.count < Self.maximumSessionsPerConnection, sessions.count < Self.maximumSessions else {
                return .error(code: .tooManySessions)
            }
            let session = nextSession
            nextSession &+= 1
            if nextSession == 0 { nextSession = 1 }
            let input = makeSession()
            sessions[session] = Session(owner: id, input: input)
            connection.sessions.insert(session)
            connections[id] = connection
            return .sessionOpened(session: session, state: state(of: input, wakeAfter: nil))
        case .closeSession(let session):
            guard owned(session, by: id) != nil else { return .error(code: .unknownSession) }
            sessions.removeValue(forKey: session)?.correction?.task.cancel()
            connection.sessions.remove(session)
            connections[id] = connection
            closeHandwriting(ofSession: session)
            return .done
        case .key(let session, let input, let context):
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            return key(input, context: context, session: session, current: current)
        case .setMode(let session, let mode):
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            cancelCorrections(of: session)
            let actions = current.input.setMode(InputMode(mode))
            return edit(actions, handled: true, session: session, anchor: lastAnchor)
        case .deactivate(let session):
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            cancelCorrections(of: session)
            let actions = current.input.deactivate()
            ui(.hide)
            // 入力先から外れたら手書きの窓も閉じる．選んだ文字が別の入力欄に入らないように
            closeHandwriting(ofSession: session)
            return edit(actions, handled: true, session: session, anchor: lastAnchor)
        case .wake(let session, let context):
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            return wake(session: session, current: current, context: context)
        case .openHandwriting(let session, let context):
            // 入力メニューの「手書き入力」．キーの「手書き入力」と同じく，組み立て中の文字を確定してから窓を開く
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            if let caret = context.caret { lastAnchor = caret }
            return edit(current.input.openHandwriting(), handled: true, session: session, anchor: context.caret ?? lastAnchor)
        case .caret(let session, let rect):
            guard owned(session, by: id) != nil else { return .error(code: .unknownSession) }
            lastAnchor = rect
            ui(.move(anchor: rect))
            return .done
        case .handwritingChosen(let text):
            guard connection.isCandidateWindow, Self.isValidHandwritingText(text) else { return .error(code: .malformed) }
            handwriting?.chosen = text
            return .done
        case .chooseCandidate(let target):
            // 候補ウィンドウで候補を押した．押したときに候補を出していたセッションの次の wake で，キーで選んだのと同じに処理する
            guard connection.isCandidateWindow, let session = shownCandidates else { return .error(code: .malformed) }
            chosen = (session, target)
            return .done
        case .handwritingClosed:
            guard connection.isCandidateWindow else { return .error(code: .malformed) }
            if handwriting?.chosen == nil { handwriting = nil }
            return .done
        case .readSettings:
            return .settings(settings: snapshot)
        case .menu(let command):
            // 入力メニュー(言語バーの項目)で選んだ操作．キー設定の表の同じコマンドと同じに扱う
            switch command {
            case .toggleLiveConversion:
                perform(.toggleLiveConversion)
            case .openSettings:
                perform(.openSettings)
            }
            return .done
        case .readSettingsFields(let names, let defaults):
            return fields { () throws(SettingsFields.Failure) in
                try SettingsFields.read(defaults ? DefaultSettings.settings : settings.current, names: names)
            }
        case .writeSettingsFields(let values):
            return fields { () throws(SettingsFields.Failure) in
                let merged = try SettingsFields.merge(values, into: settings.current)
                do {
                    try settings.update { $0 = merged.settings }
                } catch {
                    throw .malformed
                }
                return try SettingsFields.read(settings.current, names: merged.names)
            }
        case .readKeymapPreset(let preset):
            return fields { () throws(SettingsFields.Failure) in try SettingsFields.keymapPreset(named: preset) }
        case .resetLearning:
            services.resetLearning()
            return .done
        case .readUsage:
            return usage
        case .resetUsage:
            services.usage?.reset()
            return usage
        case .previewLanguage(let text, let precedingText):
            let words = services.previewLanguage(text, precedingText)
            return .languagePreview(words: words.map { WirePreviewWord(typed: $0.typed, shown: $0.shown, language: $0.language.rawValue) })
        case .readUserDictionary(let offset, let limit):
            let entries = settings.current.userDictionary
            let start = min(Int(offset), entries.count)
            let end = min(start + min(Int(limit), Self.maximumDictionaryPage), entries.count)
            return .userDictionary(entries: entries[start..<end].map { WireDictionaryEntry(reading: $0.reading, word: $0.word) },
                                   total: UInt32(clamping: entries.count))
        case .addUserDictionaryEntry(let entry):
            var result = UserDictionaryEditing.AddResult.invalid
            do {
                try settings.update { result = UserDictionaryEditing.add(reading: entry.reading, word: entry.word, to: &$0.userDictionary) }
            } catch {
                return .error(code: .malformed)
            }
            return .dictionaryAdded(result: WireDictionaryAddResult(result))
        case .removeUserDictionaryEntry(let entry):
            do {
                try settings.update { $0.userDictionary.removeAll { $0 == UserDictionaryEntry(reading: entry.reading, word: entry.word) } }
            } catch {
                return .error(code: .malformed)
            }
            return .done
        case .mergeUserDictionary(let wanted):
            var added = 0
            do {
                try settings.update {
                    added = UserDictionaryEditing.merge(wanted.map { UserDictionaryEntry(reading: $0.reading, word: $0.word) }, into: &$0.userDictionary)
                }
            } catch {
                return .error(code: .malformed)
            }
            return .dictionaryMerged(added: UInt32(clamping: added))
        case .checkKeymap(let values):
            do {
                return .keymapReport(report: try SettingsFields.keymapReport(values))
            } catch {
                return .error(code: .malformed)
            }
        case .readSymbolDefaults:
            // 記号のページに既定の決まりを出し，利用者の決まりと重ねるため(macOS の SymbolsPage と同じ表)
            return .symbolDefaults(sequences: Self.symbolDefaults(.sequence), readings: Self.symbolDefaults(.reading))
        case .readSync, .setSyncFolder, .setSyncEnabled, .setSyncScope, .setSyncLocalField, .syncNow:
            return syncResponse(for: request) ?? .error(code: .malformed)
        case .importDictionary, .removeDictionary, .importUserDictionary, .exportUserDictionary, .exportSettings, .importSettings, .importProfileRules, .exportProfileRules,
             .importRuleList, .exportRuleList:
            // ファイルの読み書きは reply で受ける(時間がかかるので，答えるのを待つ形にする)
            return .error(code: .malformed)
        case .writeSettings(let wanted):
            do {
                try settings.update { current in
                    if let theme = ThemePreference(rawValue: wanted.theme) { current.theme = theme }
                    if let style = InputStyle(rawValue: wanted.inputStyle) { current.inputStyle = style }
                    current.liveConversion = wanted.liveConversion
                    current.showsModeIndicator = wanted.showsModeIndicator
                    current.showsKeyHints = wanted.showsKeyHints
                    current.candidateFontSize = wanted.candidateFontSize
                    current.clampToValidRanges()
                }
            } catch {
                return .error(code: .malformed)
            }
            return .settings(settings: snapshot)
        }
    }

    private static func symbolDefaults(_ kind: SymbolRule.Kind) -> [WireSymbolDefault] {
        SymbolRuleEditing.defaults(kind).map { WireSymbolDefault(input: $0.input, output: $0.output) }
    }

    /// ユーザー辞書を 1 回で読む語の数の上限．1 語の大きさの上限から，応答がメッセージの上限に収まる数にする
    public static let maximumDictionaryPage = 500

    private var usage: WireResponseBody {
        guard let counts = services.usage?.counts else { return .error(code: .malformed) }
        guard let data = try? JSONEncoder().encode(counts), let values = String(data: data, encoding: .utf8) else { return .error(code: .malformed) }
        return .usage(values: values, firstCandidateRate: counts.firstCandidateRate)
    }

    private func fields(_ make: () throws(SettingsFields.Failure) -> String) -> WireResponseBody {
        do {
            return .settingsFields(values: try make())
        } catch {
            return .error(code: .malformed)
        }
    }

    public var snapshot: WireSettingsSnapshot {
        let current = settings.current
        return WireSettingsSnapshot(theme: current.theme.rawValue, inputStyle: current.inputStyle.rawValue, liveConversion: current.liveConversion,
                                    showsModeIndicator: current.showsModeIndicator, showsKeyHints: current.showsKeyHints,
                                    candidateFontSize: current.candidateFontSize, handwriting: current.handwriting)
    }

    private func owned(_ session: UInt32, by id: ConnectionID) -> Session? {
        guard let current = sessions[session], current.owner == id else { return nil }
        return current
    }

    private func key(_ input: WireKeyInput, context wire: WireFieldContext, session: UInt32, current: Session) -> WireResponseBody {
        let context = InputContext(wire, settings: settings.current)
        if let caret = wire.caret { lastAnchor = caret }
        guard let event = KeyEvent(input) else {
            return .edit(handled: false, operations: [], state: state(of: current.input, wakeAfter: nil))
        }
        // 次のキーが来たら，前のキーの並びの訂正は要らない(待たせていた変換も InputSession がやめる)
        cancelCorrections(of: session)
        let result = current.input.handle(event, context: context)
        sessions[session]?.hasSettled = false
        var actions = result.actions
        if actions.contains(.awaitCorrections) {
            // 訂正を求め終わるまで変換を待つ(macOS の S90InputController と同じ)．求めるものが無ければすぐ変換を続ける
            if let request = current.input.conversionCorrectionRequest, typoService != nil {
                startCorrections(request, purpose: .conversion(deadline: now() + .seconds(DefaultSettings.correctionWaitBeforeConversion)), session: session)
            } else {
                actions += current.input.resumeConversion(context: context)
            }
        }
        return edit(actions, handled: result.handled, session: session, anchor: lastAnchor)
    }

    private func wake(session: UInt32, current: Session, context wire: WireFieldContext) -> WireResponseBody {
        let context = InputContext(wire, settings: settings.current)
        if let caret = wire.caret { lastAnchor = caret }
        var actions: [ClientAction] = []
        if handwriting?.session == session, let text = handwriting?.chosen {
            handwriting = nil
            actions += current.input.insert(text)
        }
        if let choice = chosen, choice.session == session {
            chosen = nil
            actions += current.input.choose(PointerTarget(choice.target), context: context)
        }
        if let work = current.correction {
            switch work.purpose {
            case .conversion(let deadline):
                if let result = work.result {
                    sessions[session]?.correction = nil
                    current.input.provideCorrections(result)
                    actions += current.input.resumeConversion(context: context)
                } else if now() >= deadline {
                    // 長くかかるときは待つのをやめて，直さずに変換する
                    cancelCorrections(of: session)
                    actions += current.input.resumeConversion(context: context)
                }
            case .review:
                if let result = work.result {
                    sessions[session]?.correction = nil
                    current.input.provideCorrections(result)
                    actions += current.input.review(context: context)
                }
            }
        } else if current.input.awaitsSettle {
            actions += current.input.settle(context: context)
            sessions[session]?.hasSettled = true
        } else if current.input.awaitsReview {
            // 訂正は裏で求め，求め終わったあとの wake で見直す(打鍵を待たせない)
            if typoService != nil, let request = current.input.correctionRequest {
                startCorrections(request, purpose: .review, session: session)
            } else {
                actions += current.input.review(context: context)
            }
        }
        return edit(actions, handled: true, session: session, anchor: lastAnchor)
    }

    private func startCorrections(_ request: (keys: [String], leftContext: String?), purpose: CorrectionWork.Purpose, session: UInt32) {
        guard let typoService else { return }
        cancelCorrections(of: session)
        let id = nextCorrection
        nextCorrection &+= 1
        let task = Task { @MainActor [weak self] in
            let result = await typoService.corrections(forKeys: request.keys, leftContext: request.leftContext)
            guard !Task.isCancelled, let self, self.sessions[session]?.correction?.id == id else { return }
            self.sessions[session]?.correction?.result = result
        }
        sessions[session]?.correction = CorrectionWork(id: id, purpose: purpose, task: task)
    }

    private func cancelCorrections(of session: UInt32) {
        sessions[session]?.correction?.task.cancel()
        sessions[session]?.correction = nil
    }

    /// 裏で求めている訂正がすべて終わるまで待つ(テスト用)
    func waitForCorrections() async {
        for task in sessions.values.compactMap(\.correction?.task) {
            await task.value
        }
    }

    private func edit(_ actions: [ClientAction], handled: Bool, session: UInt32, anchor: WireRect?) -> WireResponseBody {
        let current = settings.current
        let routed = RoutedActions(actions, anchor: anchor, hints: { [hints] in hints($0, current) })
        routed.ui.forEach(ui)
        for command in routed.ui {
            switch command {
            case .showCandidates, .showBranchMap: shownCandidates = session
            case .hide where shownCandidates == session:
                shownCandidates = nil
                chosen = nil
            default: break
            }
        }
        for action in routed.host {
            if action == .showHandwriting {
                openHandwriting(for: session, anchor: anchor)
            } else {
                perform(action)
            }
        }
        guard let input = sessions[session]?.input else {
            return .edit(handled: handled, operations: routed.edits, state: WireSessionState(mode: .japanese, isComposing: false, keymap: current.keymap, wakeAfterMilliseconds: nil,
                                                                                                  keyboardLayout: WireSessionState.keyboardLayout(for: current)))
        }
        return .edit(handled: handled, operations: routed.edits, state: state(of: input, wakeAfter: wakeAfter(session)))
    }

    private func wakeAfter(_ session: UInt32) -> UInt32? {
        let typing = typingWakeAfter(session)
        var interval = typing
        if shownCandidates == session { interval = min(interval ?? .max, Self.candidateClickPollMilliseconds) }
        guard handwriting?.session == session else { return interval }
        return min(interval ?? .max, Self.handwritingPollMilliseconds)
    }

    private func typingWakeAfter(_ session: UInt32) -> UInt32? {
        guard let current = sessions[session] else { return nil }
        if current.correction != nil { return Self.correctionPollMilliseconds }
        let delays = settings.current
        if current.input.awaitsSettle {
            return Self.milliseconds(delays.liveConversionDelay)
        }
        if current.input.awaitsReview {
            let remaining = current.hasSettled ? delays.correctionDelay - delays.liveConversionDelay : delays.correctionDelay
            return Self.milliseconds(remaining)
        }
        return nil
    }

    private func openHandwriting(for session: UInt32, anchor: WireRect?) {
        handwriting = Handwriting(session: session)
        ui(.showHandwriting(anchor: anchor, recognitionDelayMilliseconds: Self.milliseconds(DefaultSettings.handwritingRecognitionDelay),
                            recognitionTimeoutMilliseconds: Self.milliseconds(DefaultSettings.handwritingRecognitionTimeout)))
    }

    private func closeHandwriting(ofSession session: UInt32) {
        guard handwriting?.session == session else { return }
        handwriting = nil
        ui(.hideHandwriting)
    }

    /// 手書きの窓の候補として受け取ってよい文字列か．空・長すぎる・制御文字を含むものは断る
    static func isValidHandwritingText(_ text: String) -> Bool {
        !text.isEmpty && text.count <= DefaultSettings.maximumHandwritingTextLength
            && !text.unicodeScalars.contains { $0.properties.generalCategory == .control || $0.properties.generalCategory == .format }
    }

    private static func milliseconds(_ seconds: Double) -> UInt32 {
        UInt32(clamping: Int((max(seconds, 0) * 1000).rounded()))
    }

    private func state(of input: InputSession, wakeAfter: UInt32?) -> WireSessionState {
        WireSessionState(mode: input.mode, isComposing: input.isComposing, keymap: settings.current.keymap, wakeAfterMilliseconds: wakeAfter,
                         keyboardLayout: WireSessionState.keyboardLayout(for: settings.current))
    }

    private func perform(_ action: HostAction) {
        switch action {
        case .selectInputStyle(let style):
            try? settings.update { $0.inputStyle = style }
            // 切り替えたことを入力位置の近くに出す(macOS の ClientActionPresenter と同じ)
            if settings.current.showsModeIndicator {
                ui(.showMode(mode: .japanese, anchor: lastAnchor, label: ModeIndicatorLabels.label(for: style)))
            }
        case .toggleLiveConversion:
            try? settings.update { $0.liveConversion.toggle() }
        case .openSettings:
            openSettings()
        case .showHandwriting:
            // セッションが要るので edit で扱う
            break
        }
    }

    public var presentation: WirePresentation {
        let current = settings.current
        return WirePresentation(theme: current.theme.rawValue, fontSize: current.candidateFontSize,
                                modeIndicatorMilliseconds: Self.milliseconds(current.modeIndicatorDuration),
                                customTheme: current.activeCustomTheme.map(WireCustomTheme.init))
    }
}

extension PointerTarget {
    init(_ wire: WirePointerTarget) {
        switch wire {
        case .segment(let index): self = .segment(Int(index))
        case .alternative(let index): self = .alternative(Int(index))
        case .variant(let index): self = .variant(Int(index))
        case .entry(let index): self = .entry(Int(index))
        case .listVariant(let index): self = .listVariant(Int(index))
        }
    }
}
