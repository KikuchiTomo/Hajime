/// ターミナルで打っている行の状態(R-07)．コマンドの行では英字をそのまま流し，引用符の中と # の後ろだけ日本語にする．
///
/// ターミナルでも日本語の文を打つ(対話型のツールへの指示など)ので，行の頭から英字を流すことはしない．
/// 行の頭でよく使うコマンドの名前を打って Space を押したときだけ，コマンドの行とみなす(Q-03)
public struct CommandLineState: Sendable, Equatable {
    public enum Region: Sendable, Equatable {
        /// 行の頭．まだ何も確定していない
        case lineStart
        /// コマンドの行．英字をそのまま流す
        case command
        /// 引用符の中．閉じる引用符まで日本語を打てる
        case quoted(Character)
        /// # の後ろ(コメント)．行の終わりまで日本語を打てる
        case comment
        /// コマンドの行ではない(日本語の文など)．行の終わりまでふつうに入力する
        case text
    }

    public private(set) var region: Region = .lineStart
    /// この行に入れた文字数．Backspace で行の頭まで戻ったかを知るのに使う
    private var length = 0
    /// 最後にそのまま流した文字．# が語の頭にあるか(コメントか)を決めるのに使う
    private var lastPassed: Character?

    public init() {}

    /// 英字をそのまま流すか
    public var passesThrough: Bool { region == .command }

    /// 行の頭で打った読み(打ったキー)を Space で区切ったとき．コマンドの名前ならコマンドの行に入る
    public mutating func didTypeFirstWord(_ keys: String) -> Bool {
        guard region == .lineStart, CommandNames.contains(keys) else {
            if region == .lineStart { region = .text }
            return false
        }
        // 行の長さは，確定した「名前 + 空白」を didCommitText で数える
        region = .command
        lastPassed = " "
        return true
    }

    /// 組み立てずにアプリへ流した文字(空白を含む)．引用符と語の頭の # で領域が変わる
    public mutating func didPass(_ character: Character) {
        length += 1
        defer { lastPassed = character }
        switch region {
        case .lineStart:
            // 英数で行の頭に英字や数字を打ったら，もう行の頭ではない．日本語のモードでは英字と数字は組み立てに回るので，
            // ここに来るのは英数で打ったものだけ．行の頭の空白や「(」「\」などの記号はコマンドの前に付くことがあるので行の頭のまま
            if character.isLetter || character.isNumber { region = .text }
            // 行の頭の # はシェルのコメント．行の終わりまで日本語を打てる
            if character == "#" { region = .comment }
        case .command:
            if character == "\"" || character == "'" { region = .quoted(character) }
            // 「foo#bar」や「$#」は引数の一部なので，語の頭(直前が空白)の # だけをコメントにする
            if character == "#", lastPassed == " " { region = .comment }
        case .quoted(let quote):
            if character == quote { region = .command }
        case .comment, .text:
            break
        }
    }

    /// 日本語を確定した．行の頭なら，その行はコマンドではない
    public mutating func didCommitText(length committed: Int) {
        length += committed
        if region == .lineStart { region = .text }
    }

    /// 組み立てていないときに Backspace で 1 文字消した．行の頭まで戻ったら行の頭に戻す
    public mutating func didDeleteBackward() {
        length = max(length - 1, 0)
        if length == 0 { endLine() }
    }

    /// 行の中身が分からなくなった(入力欄を離れたとき，Option+文字のあと)．
    /// 何も入れていない行の頭ならそのまま．そうでなければ，コマンドの名前を見分けず英字も流さない「文の行」として扱う．
    /// 分からないときに日本語を打てなくなるより，ふつうに日本語を打てるほうへ倒すため．何度呼んでも同じ結果になる
    public mutating func becomeUnknown() {
        guard !(region == .lineStart && length == 0) else { return }
        region = .text
    }

    /// 中身の分からない文字が入った(貼り付け，Option+文字で å などが入ったかメタキーとして動いたか分からないとき)．
    /// 行の頭なら文の行にし，コマンドの行や引用符の中ならそのまま続ける
    public mutating func didInsertUnknownText() {
        length += 1
        if region == .lineStart { region = .text }
    }

    /// Enter・Ctrl+C・Ctrl+U・履歴の呼び出し・モードの切り替えなどで行が終わった(または行が分からなくなった)
    public mutating func endLine() {
        region = .lineStart
        length = 0
        lastPassed = nil
    }
}

extension CommandLineState: CustomStringConvertible, CustomDebugStringConvertible {
    // 最後に流した文字は入力内容なので，ログには領域と長さだけを出す
    public var description: String { "CommandLineState(region: \(region), length: \(length))" }
    public var debugDescription: String { description }
}

/// よく使うコマンドの名前．行の頭でこれを打って Space を押すと，コマンドの行とみなす
public enum CommandNames {
    public static func contains(_ word: String) -> Bool {
        names.contains(word)
    }

    private static let names: Set<String> = [
        "ls", "cd", "pwd", "cp", "mv", "rm", "mkdir", "rmdir", "touch", "cat", "less", "head", "tail", "grep", "rg", "find", "fd",
        "echo", "printf", "export", "source", "which", "whereis", "man", "chmod", "chown", "ln", "du", "df", "ps", "kill", "pkill",
        "top", "htop", "open", "sudo", "ssh", "scp", "rsync", "curl", "wget", "tar", "zip", "unzip", "sed", "awk", "sort", "uniq",
        "wc", "diff", "xargs", "tee", "env", "clear", "history", "exit", "code", "vim", "vi", "nvim", "nano", "emacs",
        "git", "gh", "make", "cmake", "swift", "xcodebuild", "xcrun", "xcodegen", "brew", "npm", "npx", "pnpm", "yarn", "bun",
        "node", "deno", "python", "python3", "pip", "pip3", "uv", "poetry", "ruby", "gem", "bundle", "rails", "go", "cargo",
        "rustc", "rustup", "java", "javac", "gradle", "mvn", "docker", "kubectl", "terraform", "aws", "gcloud", "firebase",
        "claude", "tmux", "screen", "launchctl", "defaults", "codesign", "security", "log", "say", "pbcopy", "pbpaste",
    ]
}
