import S90Domain

/// 入力方式ごとのキーの解釈(R-05)．ローマ字入力は InputSession の共通の処理がそのまま受け持ち，
/// ほかの方式はこれを実装して InputSession に足す(docs/dev/ARCHITECTURE.md)
@MainActor
protocol InputStyleHandling: AnyObject {
    /// キーを解釈する．nil ならローマ字入力と共通の処理に回す
    func interpret(_ event: KeyEvent, state: InputStyleState) -> InputStyleInterpretation?
    /// 方式の側で文字を組み立てているか(EN 入力の英字など．読みは InputSession が持つので含めない)
    var isComposing: Bool { get }
    /// 方式の側で組み立てている文字を確定する
    func commit() -> [ClientAction]
    /// 方式の側で組み立てている文字を見せる
    func render() -> [ClientAction]
}

/// 解釈に要る入力の状態
struct InputStyleState {
    var settings: Settings
    /// 候補を選んでいるとき，番号キーで選べる候補の数．選んでいなければ 0
    var selectableCount: Int
}

enum InputStyleInterpretation: Equatable, CustomStringConvertible {
    /// 方式の側で処理し終えた．結果をそのまま返す
    case handled(KeyResult)
    /// この文字を読みに足す(かな入力)．読みの組み立てと表示は InputSession が行う
    case insertKana(String)

    // かなは入力内容なので，ログには長さだけを出す
    var description: String {
        switch self {
        case .handled: "handled"
        case .insertKana(let kana): "insertKana(length: \(kana.count))"
        }
    }
}

/// かな入力(JIS かな配列)．キーの刻印からかなを引く．状態は持たない
@MainActor
final class KanaInput: InputStyleHandling {
    /// かなは読みに足すので，方式の側では何も組み立てない
    var isComposing: Bool { false }
    func commit() -> [ClientAction] { [] }
    func render() -> [ClientAction] { [] }

    func interpret(_ event: KeyEvent, state: InputStyleState) -> InputStyleInterpretation? {
        guard !event.modifiers.contains(.option) else { return nil }
        if case .character(let character) = event.key, state.settings.numberKeySelection,
            let digit = character.wholeNumberValue, (1...state.selectableCount).contains(digit) {
            // 候補を選んでいるときの番号キーは，ローマ字入力と同じく候補を選ぶ．選べる数を超える番号はかなにする
            return nil
        }
        let shift = event.modifiers.contains(.shift)
        let kana: String? = switch event.key {
        case .character: event.keyLabel.flatMap { KanaLayout.text(forKey: $0, shift: shift, settings: state.settings) }
        case .yen: KanaLayout.text(forKey: "¥", shift: false, settings: state.settings)
        default: nil
        }
        return kana.map(InputStyleInterpretation.insertKana)
    }
}
