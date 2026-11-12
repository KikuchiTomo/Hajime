import Foundation
import HajimeDomain

/// パレットの表(R-26)から，かな漢字変換の候補に足す絵文字を読みで引く(設定の「絵文字に変換」)．
///
/// パレットと同じ表を使うので，OS が描けない新しい絵文字は出さず(PaletteCatalogFile が除く)，肌の色はパレットで選んだ色にする．
/// 変換で選んだ絵文字は，パレットの使い方(PaletteUsage)に読みを探した語として覚える．パレットでその読みで探して選んだときと
/// 同じ記録なので，どちらで選んでも次からその読みの絵文字の先頭に出る．表を読み終えるまでは絵文字を出さない
@MainActor
public final class PaletteEmojiLookup: EmojiLooking {
    private let catalog: any PaletteCatalogProviding
    private let usage: any PaletteUsageStoring
    private let settings: any SettingsReading
    private let now: () -> Date
    /// 引いた名前(名前の無い絵文字は nil)．名前は候補の窓を描くたびに引くので，表を頭から探し直さないよう覚える．
    /// 覚えるのは表の絵文字の数まで
    private var names: [String: String?] = [:]

    public init(catalog: any PaletteCatalogProviding, usage: any PaletteUsageStoring, settings: any SettingsReading, now: @escaping () -> Date) {
        self.catalog = catalog
        self.usage = usage
        self.settings = settings
        self.now = now
    }

    public func emoji(for reading: String, word: EmojiWord, limit: Int) -> [String] {
        guard let index = catalog.index else { return [] }
        let current = usage.usage
        let ranking = usesHistory
            ? PaletteSearch.Ranking(usage: current.scores(at: now()), learned: current.learnedChoices(for: Self.query(reading)), pinned: Set(current.pinned))
            : PaletteSearch.Ranking()
        return index.search.emoji(reading: reading, word: word, ranking: ranking, limit: limit).map { $0.text(skinTone: current.effectiveSkinTone(for: $0.text)) }
    }

    public func name(of emoji: String) -> String? {
        if let cached = names[emoji] { return cached }
        guard let index = catalog.index else { return nil }
        let item = index.catalog.item(for: emoji)
        let name = item.flatMap { $0.kind == .emoji && !$0.japaneseName.isEmpty ? $0.japaneseName : nil }
        names[emoji] = name
        return name
    }

    public func didCommit(_ emoji: String, reading: String) {
        // 肌の色を変えた形も，パレットと同じく肌の色を変えていない形で数える
        guard recordsHistory, let item = catalog.index?.catalog.item(for: emoji), item.kind == .emoji else { return }
        usage.update { $0.record(item.text, query: Self.query(reading), at: now()) }
    }

    /// 読みを，パレットでかなを打って探したときと同じ語にする(学習の記録を共有するため)
    private static func query(_ reading: String) -> PaletteSearch.Query {
        PaletteSearch.Query(typed: "", kana: reading)
    }

    /// 選んだ記録を並びに使うか．学ばず学んだことも使わない設定と，パレットの履歴を残さない設定では使わない
    private var usesHistory: Bool {
        settings.current.learning != .disabled && settings.current.paletteRecordsHistory
    }

    /// 選んだことを記録するか．新しく学ばない設定と，パレットの履歴を残さない設定では記録しない
    private var recordsHistory: Bool {
        settings.current.learning == .enabled && settings.current.paletteRecordsHistory
    }
}
