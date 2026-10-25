import S90Domain

/// ターミナルでのキーの扱いを決める(R-07)．行の状態は CommandLineState が持ち，ここはキーごとの判断だけをする．
///
/// InputSession はキーをまずここに通し，返った判断に従う．Control の組み合わせや Enter のように，
/// ほかの処理より先に行の状態を変えるべきキーがあるので，入力方式の処理より前に呼ぶ
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
        if event.modifiers.contains(.control) {
            // Ctrl+C・Ctrl+U は行を捨てる
            if case .character(let character) = event.key, ["c", "u"].contains(character.lowercased()) { state.endLine() }
            return .continue
        }
        switch event.key {
        case .enter where !isComposing:
            state.endLine()
            return .continue
        case .up, .down:
            // 履歴を呼び出すと，行の中身が分からなくなる
            if !isComposing { state.endLine() }
            return .continue
        case .backspace where !isComposing:
            state.didDeleteBackward()
            return .continue
        case .space where !isComposing && state.passesThrough:
            state.didPass(" ")
            return .continue
        case .space:
            guard let keys = composingKeys, state.didTypeFirstWord(keys) else { return .continue }
            return .commitCommand(keys)
        case .character(let character) where state.passesThrough && !isComposing:
            // コマンドの行では英字も記号もそのまま流す
            state.didPass(character)
            return .passThrough
        case .character(let character) where isComposing && state.region == .quoted(character):
            // 引用符の中の日本語は，閉じる引用符で確定し，引用符はそのまま流す
            state.didPass(character)
            return .commitAndPass
        case .character(let character) where !isComposing && state.region == .quoted(character):
            state.didPass(character)
            return .passThrough
        default:
            return .continue
        }
    }

    func didCommitText(length: Int) { state.didCommitText(length: length) }
    func endLine() { state.endLine() }
}
