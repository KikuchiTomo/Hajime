/// パレットを開いているあいだのキー操作(R-26)．文字のキーは探す欄に入るので，表には文字でないキーと修飾キーとの組み合わせだけを置く
public enum PaletteCommand: Sendable, Hashable, CaseIterable {
    /// 選んでいる文字を入れる(設定によって閉じる)
    case insert
    /// 選んでいる文字を入れ，閉じずに続ける
    case insertAndContinue
    case moveUp
    case moveDown
    case moveLeft
    case moveRight
    case pageUp
    case pageDown
    case first
    case last
    /// 次と前のまとまり
    case nextSection
    case previousSection
    /// 絵文字と記号を切り替える
    case switchKind
    /// 選んでいる絵文字の肌の色の帯を開く
    case skinTone
    /// 選んでいる文字をピン留めする．留めてあれば外す
    case pin
    /// 探す欄の左の 1 文字を消す
    case deleteBackward
    /// 肌の色の帯を閉じ，探す語を消し，最後にパレットを閉じる
    case cancel
}

public enum PaletteKeymap {
    /// キーとコマンド．足元の案内もここから引く
    public static let standard: [(stroke: KeyStroke, command: PaletteCommand)] = [
        (KeyStroke(.enter), .insert),
        (KeyStroke(.enter, shift: true), .insertAndContinue),
        (KeyStroke(.up), .moveUp),
        (KeyStroke(.down), .moveDown),
        (KeyStroke(.left), .moveLeft),
        (KeyStroke(.right), .moveRight),
        (KeyStroke(.pageUp), .pageUp),
        (KeyStroke(.pageDown), .pageDown),
        (KeyStroke(.home), .first),
        (KeyStroke(.end), .last),
        (KeyStroke(.tab), .nextSection),
        (KeyStroke(.tab, shift: true), .previousSection),
        (KeyStroke(.tab, control: true), .switchKind),
        (KeyStroke(.enter, option: true), .skinTone),
        (KeyStroke(.character("d"), control: true), .pin),
        (KeyStroke(.backspace), .deleteBackward),
        (KeyStroke(.escape), .cancel),
    ]

    public static func command(for event: KeyEvent) -> PaletteCommand? {
        guard let stroke = KeyStroke(event) else { return nil }
        return standard.first { $0.stroke == stroke }?.command
    }

    /// コマンドに割り当てたキー(案内に出す)
    public static func stroke(for command: PaletteCommand) -> KeyStroke? {
        standard.first { $0.command == command }?.stroke
    }
}
