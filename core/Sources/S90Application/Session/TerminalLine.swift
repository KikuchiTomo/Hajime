import S90Domain

/// ターミナルでのキーの扱いを決める(R-07)．行の状態は CommandLineState が持つ．
///
/// キーごとに 2 回呼ぶ．
/// - `decide`: InputSession がキーを処理する前．コマンドの行で英字を流すか，コマンドの名前を確定するかを決める
/// - `didHandle`: 処理したあと．アプリに渡った文字と Enter・Backspace などを行の状態に数える．
///   アプリに渡ったかは処理の結果でしか分からないので，状態を変えるのはここにまとめる
@MainActor
final class TerminalLine {
    enum Decision: Equatable {
        /// ふつうの処理に回す
        case `continue`
        /// 組み立てずにアプリへ渡す
        case passThrough
        /// 打ったとおりの英字にして確定し，コマンドの行に入る
        case commitCommand(String)
        /// 組み立て中の文字を確定してから，キーをアプリへ渡す(閉じる引用符)
        case commitAndPass
    }

    private(set) var state = CommandLineState()

    /// - Parameters:
    ///   - composingKeys: 読みを組み立てているなら，その打ったキー(ローマ字)．組み立てていなければ nil
    ///   - isComposing: 何かを組み立てているか(EN 入力の英字を含む)
    func decide(_ event: KeyEvent, isComposing: Bool, composingKeys: String?) -> Decision {
        guard !event.modifiers.contains(.control) else { return .continue }
        switch event.key {
        case .space where !isComposing:
            return .continue
        case .space:
            guard let keys = composingKeys, state.didTypeFirstWord(keys) else { return .continue }
            return .commitCommand(keys)
        case .character where state.passesThrough && !isComposing:
            // コマンドの行では英字も記号もそのまま流す
            return .passThrough
        case .character(let character) where isComposing && state.region == .quoted(character):
            // 引用符の中の日本語は，閉じる引用符で確定し，引用符はそのまま流す
            return .commitAndPass
        default:
            return .continue
        }
    }

    /// キーを処理したあとに呼ぶ．passedToApp はキーがアプリに渡ったか
    func didHandle(_ event: KeyEvent, passedToApp: Bool) {
        guard passedToApp else { return }
        if event.modifiers.contains(.control) {
            // Ctrl+C・Ctrl+U がシェルに届いたら行を捨てる
            if case .character(let character) = event.key, ["c", "u"].contains(character.lowercased()) { state.endLine() }
            return
        }
        switch event.key {
        case .enter, .up, .down:
            // 行を実行したか，履歴を呼び出して行の中身が分からなくなった
            state.endLine()
        case .backspace:
            state.didDeleteBackward()
        case .space:
            state.didPass(" ")
        case .character(let character):
            state.didPass(character)
        default:
            break
        }
    }

    func didCommitText(length: Int) { state.didCommitText(length: length) }
    func endLine() { state.endLine() }
}

extension TerminalLine.Decision: CustomStringConvertible {
    // 確定するコマンドは打った文字なので，ログには長さだけを出す
    var description: String {
        switch self {
        case .continue: "continue"
        case .passThrough: "passThrough"
        case .commitCommand(let keys): "commitCommand(length: \(keys.count))"
        case .commitAndPass: "commitAndPass"
        }
    }
}
