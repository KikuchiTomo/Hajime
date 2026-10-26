/// キー設定の表の 1 行．状態 × キー × コマンド
public struct KeymapEntry: Sendable, Hashable, Codable {
    public var state: KeymapState
    public var stroke: KeyStroke
    public var command: KeymapCommand

    public init(_ state: KeymapState, _ stroke: KeyStroke, _ command: KeymapCommand) {
        self.state = state
        self.stroke = stroke
        self.command = command
    }

    private enum CodingKeys: String, CodingKey { case state, key, command }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        state = try container.decode(KeymapState.self, forKey: .state)
        stroke = try container.decode(KeyStroke.self, forKey: .key)
        command = try container.decode(KeymapCommand.self, forKey: .command)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(stroke, forKey: .key)
        try container.encode(command, forKey: .command)
    }
}

/// キー設定の表(R-17)．行は好きなだけ足せる．
///
/// キーを押したとき，今の状態で効く行を次の順に探し，最初に見つかったコマンドを行う(docs/dev/adr/0009-keymap.md)．
/// 1. 今の状態を書いた行．同じキーの行が複数あれば，表の下にある行
/// 2. いつでも の行のうち，コマンドが今の状態で効くもの．同じキーの行が複数あれば，表の下にある行
///
/// 表に無いキーは，文字なら読みに足し，それ以外は組み立て中なら何もせず，組み立てていなければアプリに渡す
public struct Keymap: Sendable, Equatable {
    public var entries: [KeymapEntry]
    /// この版が知らないコマンドや状態の行．新しい版で書いた表を古い版で開いて保存しても失わないよう，そのまま書き戻す
    public var unknownEntries: [JSONValue] = []

    public init(_ entries: [KeymapEntry]) {
        self.entries = entries
    }

    /// state でこのキーを押したときに行うコマンド．無ければ nil
    public func command(for event: KeyEvent, in state: KeymapState) -> KeymapCommand? {
        guard let stroke = KeyStroke(event) else { return nil }
        return command(for: stroke, in: state)
    }

    public func command(for stroke: KeyStroke, in state: KeymapState) -> KeymapCommand? {
        winner(for: stroke, in: state).map { entries[$0].command }
    }

    /// state でこのキーを押したときに使う行の位置
    private func winner(for stroke: KeyStroke, in state: KeymapState) -> Int? {
        if let index = entries.lastIndex(where: { $0.state == state && $0.stroke == stroke && $0.command.states.contains(state) }) {
            return index
        }
        return entries.lastIndex { $0.state == .anywhere && $0.stroke == stroke && $0.command.states.contains(state) }
    }

    /// state でこのコマンドを行うキー．表の上にある順．同じキーのほかの行に負けるものは含めない(足元の案内に出す)
    public func strokes(for command: KeymapCommand, in state: KeymapState) -> [KeyStroke] {
        let specific = entries.indices.filter { entries[$0].state == state }
        let anywhere = entries.indices.filter { entries[$0].state == .anywhere }
        var strokes: [KeyStroke] = []
        for index in specific + anywhere where entries[index].command == command && winner(for: entries[index].stroke, in: state) == index {
            if !strokes.contains(entries[index].stroke) { strokes.append(entries[index].stroke) }
        }
        return strokes
    }

    // MARK: 重なり

    /// 行がほかの行に負けて使われないこと
    public enum Overlap: Sendable, Equatable {
        /// 同じキーのほかの行に負け，どの状態でも使われない
        case hidden(by: [Int])
        /// いつでも の行が，一部の状態で，その状態を書いた行に負ける
        case partlyHidden(states: [KeymapState], by: [Int])
    }

    /// 行 index がほかの行に負けるか．負けなければ nil
    public func overlap(at index: Int) -> Overlap? {
        guard entries.indices.contains(index) else { return nil }
        let entry = entries[index]
        let states = entry.state == .anywhere ? KeymapState.concrete.filter { entry.command.states.contains($0) } : [entry.state]
        var lostStates: [KeymapState] = []
        var winners: [Int] = []
        for state in states {
            guard let winner = winner(for: entry.stroke, in: state), winner != index else { continue }
            lostStates.append(state)
            if !winners.contains(winner) { winners.append(winner) }
        }
        guard !lostStates.isEmpty else { return nil }
        if lostStates.count == states.count { return .hidden(by: winners) }
        return .partlyHidden(states: lostStates, by: winners)
    }

    /// 確定・取り消しのように，無いと入力を終えられなくなるコマンドのうち，キーの無いもの(状態とコマンドの組)
    public var missingEssentials: [(state: KeymapState, command: KeymapCommand)] {
        var missing: [(KeymapState, KeymapCommand)] = []
        for state in [KeymapState.composing, .converting] {
            for command in [KeymapCommand.commit, .cancel] where strokes(for: command, in: state).isEmpty {
                missing.append((state, command))
            }
        }
        return missing
    }

    // MARK: 整える

    /// 置けない行(状態で効かないコマンド)を除き，行の数を上限までにする．設定のファイルを読むときに通す
    public mutating func clampToValidRanges() {
        entries = Array(entries.filter { $0.command.isAvailable(in: $0.state) }.prefix(DefaultSettings.maximumKeymapEntries))
        unknownEntries = Array(unknownEntries.prefix(max(DefaultSettings.maximumKeymapEntries - entries.count, 0)))
    }
}

extension Keymap: Codable {
    /// 行の配列として読み書きする．読めない行(この版が知らないコマンドなど)は unknownEntries に残す
    public init(from decoder: any Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var entries: [KeymapEntry] = []
        var unknown: [JSONValue] = []
        while !container.isAtEnd {
            if let entry = try? container.decode(KeymapEntry.self) {
                entries.append(entry)
            } else if let value = try? container.decode(JSONValue.self) {
                unknown.append(value)
            } else {
                break
            }
        }
        self.init(entries)
        unknownEntries = unknown
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.unkeyedContainer()
        for entry in entries { try container.encode(entry) }
        for value in unknownEntries { try container.encode(value) }
    }
}
