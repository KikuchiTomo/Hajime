import S90Application
import S90Domain

@MainActor
public final class EngineService {
    public struct ConnectionID: Hashable, Sendable {
        let rawValue: UInt64
    }

    public static let maximumSessionsPerConnection = 64
    public static let maximumSessions = 1024

    private struct Connection {
        var hasGreeted = false
        var sessions: Set<UInt32> = []
    }

    private struct Session {
        let owner: ConnectionID
        let input: InputSession
        var hasSettled = false
    }

    private let makeSession: () -> InputSession
    private let settings: any SettingsStoring
    private let ui: (WireUiCommand) -> Void
    private let openSettings: () -> Void
    private let hints: (LatticePanel, Settings) -> [WireKeyHint]
    private var connections: [ConnectionID: Connection] = [:]
    private var sessions: [UInt32: Session] = [:]
    private var nextConnection: UInt64 = 1
    private var nextSession: UInt32 = 1
    private var lastAnchor: WireRect?

    public init(makeSession: @escaping () -> InputSession, settings: any SettingsStoring, ui: @escaping (WireUiCommand) -> Void,
                openSettings: @escaping () -> Void, hints: @escaping (LatticePanel, Settings) -> [WireKeyHint] = { _, _ in [] }) {
        self.makeSession = makeSession
        self.settings = settings
        self.ui = ui
        self.openSettings = openSettings
        self.hints = hints
    }

    public func connect() -> ConnectionID {
        let id = ConnectionID(rawValue: nextConnection)
        nextConnection += 1
        connections[id] = Connection()
        return id
    }

    public func disconnect(_ id: ConnectionID) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        for session in connection.sessions {
            sessions.removeValue(forKey: session)
        }
        if !connection.sessions.isEmpty { ui(.hide) }
    }

    public var sessionCount: Int { sessions.count }

    public func handle(_ request: WireRequest, from id: ConnectionID) -> WireResponse {
        WireResponse(id: request.id, body: body(for: request.body, from: id))
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
            sessions.removeValue(forKey: session)
            connection.sessions.remove(session)
            connections[id] = connection
            return .done
        case .key(let session, let input, let context):
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            return key(input, context: context, session: session, current: current)
        case .setMode(let session, let mode):
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            let actions = current.input.setMode(InputMode(mode))
            return edit(actions, handled: true, session: session, anchor: lastAnchor)
        case .deactivate(let session):
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            let actions = current.input.deactivate()
            ui(.hide)
            return edit(actions, handled: true, session: session, anchor: lastAnchor)
        case .wake(let session, let context):
            guard let current = owned(session, by: id) else { return .error(code: .unknownSession) }
            return wake(session: session, current: current, context: context)
        case .caret(let session, let rect):
            guard owned(session, by: id) != nil else { return .error(code: .unknownSession) }
            lastAnchor = rect
            ui(.move(anchor: rect))
            return .done
        }
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
        let result = current.input.handle(event, context: context)
        sessions[session]?.hasSettled = false
        return edit(result.actions, handled: result.handled, session: session, anchor: lastAnchor)
    }

    private func wake(session: UInt32, current: Session, context wire: WireFieldContext) -> WireResponseBody {
        let context = InputContext(wire, settings: settings.current)
        if let caret = wire.caret { lastAnchor = caret }
        var actions: [ClientAction] = []
        if current.input.awaitsSettle {
            actions += current.input.settle(context: context)
            sessions[session]?.hasSettled = true
        } else if current.input.awaitsReview {
            actions += current.input.review(context: context)
        }
        return edit(actions, handled: true, session: session, anchor: lastAnchor)
    }

    private func edit(_ actions: [ClientAction], handled: Bool, session: UInt32, anchor: WireRect?) -> WireResponseBody {
        let current = settings.current
        let routed = RoutedActions(actions, anchor: anchor, hints: { [hints] in hints($0, current) })
        routed.ui.forEach(ui)
        routed.host.forEach(perform)
        guard let input = sessions[session]?.input else {
            return .edit(handled: handled, operations: routed.edits, state: WireSessionState(mode: .japanese, isComposing: false, keymap: current.keymap, wakeAfterMilliseconds: nil))
        }
        return .edit(handled: handled, operations: routed.edits, state: state(of: input, wakeAfter: wakeAfter(session)))
    }

    private func wakeAfter(_ session: UInt32) -> UInt32? {
        guard let current = sessions[session] else { return nil }
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

    private static func milliseconds(_ seconds: Double) -> UInt32 {
        UInt32(clamping: Int((max(seconds, 0) * 1000).rounded()))
    }

    private func state(of input: InputSession, wakeAfter: UInt32?) -> WireSessionState {
        WireSessionState(mode: input.mode, isComposing: input.isComposing, keymap: settings.current.keymap, wakeAfterMilliseconds: wakeAfter)
    }

    private func perform(_ action: HostAction) {
        switch action {
        case .selectInputStyle(let style):
            try? settings.update { $0.inputStyle = style }
        case .toggleLiveConversion:
            try? settings.update { $0.liveConversion.toggle() }
        case .openSettings:
            openSettings()
        case .showHandwriting:
            break
        }
    }

    public var presentation: WirePresentation {
        let current = settings.current
        return WirePresentation(theme: current.theme.rawValue, fontSize: current.candidateFontSize,
                                modeIndicatorMilliseconds: Self.milliseconds(current.modeIndicatorDuration))
    }
}
