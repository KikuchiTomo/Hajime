import Foundation
import HajimeDomain

/// 入れるときに中身を決める語(TextTemplate)に渡す値を作る．今の日時は暦のポートから読み，UUID と乱数はその都度作る．
/// 動的なユーザー辞書(SupplementedConverter)・変換マクロ(AssociationFinder)・設定の画面の「試す」(ConversionMacroPreview)で使う
@MainActor
public struct TemplateValueSource {
    private let calendar: (any CalendarReading)?

    /// calendar が無ければ日時の名前(`{date}` など)は置き換えない
    public init(calendar: (any CalendarReading)?) {
        self.calendar = calendar
    }

    public func values() -> TextTemplate.Values {
        TextTemplate.Values(now: calendar?.now(), uuid: { UUID().uuidString }, random: { Int.random(in: $0) })
    }
}
