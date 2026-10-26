/// 候補の窓をマウスで押した対象．窓の描き方を知るアプリ側が押した位置から決め，InputSession.choose に渡す
public enum PointerTarget: Sendable, Hashable {
    /// 分岐図の幹の文節(左から 0)
    case segment(Int)
    /// 注目している文節の下の枝(変換の候補)．見えているページの中の位置(上から 0)
    case alternative(Int)
    /// 注目している文節の上の枝(字種)．幹に近いものから 0
    case variant(Int)
    /// 候補の一覧の見えている行(上から 0)
    case entry(Int)
    /// 候補の一覧の上の字種の行(左から 0．ScriptVariant.allCases の順)
    case listVariant(Int)
}
