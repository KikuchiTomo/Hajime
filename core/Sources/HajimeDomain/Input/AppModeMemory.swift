/// アプリごとに最後に使ったモードを覚える(除外設定の「IME のオンオフを記憶」)．
///
/// 覚えるのは入力先のアプリから外れたときのモードで，メモリーの中だけに置く(アプリの識別子をファイルに書かない)．
/// 最後に使ったモードは，アプリの決まりが無いときにモードを揃えるのにも使う(Windows はセッションごとにモードを持つため)
public struct AppModeMemory: Sendable, Equatable {
    /// 覚えておくアプリの数の上限．超えたら古いものから忘れる
    public let capacity: Int
    /// どのアプリでも最後に使ったモード
    public private(set) var lastMode: InputMode?
    private var modes: [String: InputMode] = [:]
    /// 覚えた順(古い順)
    private var order: [String] = []
    /// いま入力先のアプリ(enter で移ったもの)
    private var current: String?

    public init(capacity: Int = DefaultSettings.maximumRememberedApplications) {
        self.capacity = max(1, capacity)
    }

    /// アプリで今使っているモードを覚える．アプリから外れたときと，モードを変えうる操作のたびに呼ぶ
    public mutating func record(_ mode: InputMode, application: String?) {
        lastMode = mode
        guard let key = application.map(Self.key), !key.isEmpty else { return }
        // キーごとに呼ばれるので，同じアプリを続けて覚えるときは並びを変えない
        guard order.last != key else {
            modes[key] = mode
            return
        }
        if modes.updateValue(mode, forKey: key) != nil {
            order.removeAll { $0 == key }
        }
        order.append(key)
        if order.count > capacity {
            modes.removeValue(forKey: order.removeFirst())
        }
    }

    /// 入力先がアプリに移ったときに切り替えるモード．同じアプリの中で入力欄を移っただけなら切り替えない．切り替えないときは nil．
    /// macOS は入力欄ごとに入力先が移ったと知らされるので，これで同じアプリの中の移動を除く
    public mutating func enter(_ application: String?, profile: AppProfile) -> InputMode? {
        let key = application.map(Self.key)
        defer { current = key }
        guard key == nil || key != current else { return nil }
        return mode(entering: application, profile: profile)
    }

    /// アプリに入力先を移したときに切り替えるモード．切り替えないときは nil
    public func mode(entering application: String?, profile: AppProfile) -> InputMode? {
        switch profile.modeOnFocus {
        case .unchanged: nil
        case .fixed(let mode): mode
        case .remembered: application.flatMap(mode(of:))
        }
    }

    /// アプリで最後に使ったモード．覚えていなければ nil
    public func mode(of application: String) -> InputMode? {
        modes[Self.key(application)]
    }

    /// 識別子の大文字と小文字は区別しない(Windows の実行ファイルの名前は大文字を含むことがある)
    static func key(_ application: String) -> String { application.lowercased() }
}
