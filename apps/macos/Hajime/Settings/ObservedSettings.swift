import HajimeDomain
import Observation

/// 設定の画面に出す設定．読んだ項目が変わったときだけ，読んだ画面を描き直す．
///
/// 設定の全体を 1 つの値として知らせると，項目を 1 つ変えるたびに，設定を読むすべての行を描き直す．一度開いたページは
/// 作ったまま残すので(SettingsPageStack)，16 ページを開いたあとは 1 回の変更に 140〜160 ms かかっていた．
/// 項目(キーパス)ごとに印を持ち，画面は読んだ項目の印だけを見張る(Observation)．設定が変わったら，値の変わった項目の印だけを進める．
/// `model.settings.liveConversion` のように読めば，その項目だけを見張る．中に項目を持つ値(correction・wordLanguage)は，その値ごと見張る
@MainActor @dynamicMemberLookup
final class ObservedSettings {
    /// 項目が変わったことを画面に知らせる印．値そのものは持たず，変わるたびに進める
    @Observable
    final class Mark {
        var version = 0
    }

    private struct Field {
        let mark: Mark
        let differs: (HajimeDomain.Settings, HajimeDomain.Settings) -> Bool
    }

    private var current: HajimeDomain.Settings
    private var fields: [PartialKeyPath<HajimeDomain.Settings>: Field] = [:]
    private let whole = Mark()

    init(_ settings: HajimeDomain.Settings) {
        current = settings
    }

    subscript<Value: Equatable>(dynamicMember keyPath: KeyPath<HajimeDomain.Settings, Value>) -> Value {
        self[keyPath]
    }

    /// 項目の値．読んだ画面は，この項目が変わったときだけ描き直す
    subscript<Value: Equatable>(keyPath: KeyPath<HajimeDomain.Settings, Value>) -> Value {
        let mark: Mark
        if let field = fields[keyPath] {
            mark = field.mark
        } else {
            mark = Mark()
            fields[keyPath] = Field(mark: mark) { $0[keyPath: keyPath] != $1[keyPath: keyPath] }
        }
        _ = mark.version
        return current[keyPath: keyPath]
    }

    /// 設定の全体．読んだ画面は，どの項目が変わっても描き直す
    var all: HajimeDomain.Settings {
        _ = whole.version
        return current
    }

    /// 新しい設定に入れ替え，値の変わった項目を読んだ画面に知らせる(SettingsModel が設定の変更を受けて呼ぶ)
    func replace(with next: HajimeDomain.Settings) {
        let previous = current
        guard next != previous else { return }
        current = next
        whole.version &+= 1
        for field in fields.values where field.differs(previous, next) {
            field.mark.version &+= 1
        }
    }
}

extension ThemeChoice {
    /// 選んでいるテーマ．テーマにかかわる項目だけを見張る
    @MainActor
    init(_ settings: ObservedSettings) {
        self.init(settings.theme, custom: settings.activeCustomTheme)
    }
}
