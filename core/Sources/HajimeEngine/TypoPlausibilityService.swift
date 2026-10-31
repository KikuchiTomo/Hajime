import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import HajimeApplication
import HajimeDomain

/// 打ち間違いの訂正の候補を，Zenzai を使わない軽い変換のもっともらしさで絞る(R-02)．
///
/// 1 か所の打ち間違いを全部試す探し方(KeyEditSearch・KanaEditSearch)は，候補ごとに軽い変換をするので数が多い(30 キーで千回を超える)．
/// ZenzaiTypoService の変換器で続けて行うと Zenzai の探索を待たせるので，別の変換器をこのアクターに持ち，
/// Zenzai の探索と並べて動かす(azooKey の変換器はスレッドセーフではないので，このアクターの中だけで使う)．
/// 辞書を別に持つぶんメモリは増える．学習はしない(読むだけ)
actor TypoPlausibilityService {
    private let converter: KanaKanjiConverter
    private let memoryDirectory: URL
    private let versionString: String

    init(memoryDirectory: URL, versionString: String) {
        self.converter = KanaKanjiConverter.withDefaultDictionary()
        self.memoryDirectory = memoryDirectory
        self.versionString = versionString
    }

    /// 1 か所の打ち間違いを全部試し，言語モデルにかける候補に絞る(KeyEditSearch.rankedEdits)
    func rankedKeyEdits(of keys: String, from: Int) -> [KeyEditSearch.Edit] {
        KeyEditSearch.rankedEdits(of: keys, from: from, plausibility: plausibility(of:))
    }

    /// かなの単位の訂正の候補を絞る(KanaEditSearch.rankedEdits)．読みにかなにならない英字が残るときは探さない
    func rankedKanaEdits(ofKeys keys: String) -> [KanaEditSearch.RankedEdit] {
        let reading = KeyEditSearch.rawReading(of: keys)
        guard !reading.isEmpty, !reading.contains(where: \.isASCII) else { return [] }
        return KanaEditSearch.rankedEdits(
            of: reading,
            in: unconvertedSpans(of: reading),
            plausibility: plausibility(of:),
            unconverted: { self.unconvertedSpans(of: $0, minimumLength: 1) }
        )
    }

    /// 候補ごとに，読みを変換したときのもっともらしさの打ったままの読みとの差を入れる(KeyEditSearch.withPlausibility)
    func withPlausibility(_ corrections: [ReadingCorrection], typedKeys keys: String) -> [ReadingCorrection] {
        KeyEditSearch.withPlausibility(corrections, typedKeys: keys, plausibility: plausibility(of:))
    }

    /// 読みを Zenzai を使わずに変換したとき，語にならずかなのまま残った部分
    private func unconvertedSpans(of reading: String, minimumLength: Int = DefaultSettings.minimumUnconvertedSpanLength) -> [Range<Int>] {
        guard !Task.isCancelled else { return [] }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        let data = converter.requestCandidates(composing, options: options).mainResults
            .first { AzooKeyConverterSession.readingCount($0.composingCount, readingLength: reading.count) == reading.count }?.data ?? []
        converter.stopComposition()
        return AzooKeyConverterSession.unconvertedSpans(of: data, minimumLength: minimumLength)
    }

    /// 読みを変換したときのもっともらしさ(Zenzai を使わない軽い変換の点数)．読みごとに覚えておく
    private var plausibilityCache: [String: Double] = [:]

    private func plausibility(of reading: String) -> Double {
        if let cached = plausibilityCache[reading] { return cached }
        // 取り消されたら変換せずにすぐ返す(覚えない)．残りの候補の計算を速く終わらせるため
        guard !Task.isCancelled else { return -.infinity }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        let best = converter.requestCandidates(composing, options: options).mainResults
            .first { AzooKeyConverterSession.readingCount($0.composingCount, readingLength: reading.count) == reading.count }
            .map { Double($0.value) } ?? -.infinity
        converter.stopComposition()
        if plausibilityCache.count > DefaultSettings.maximumPlausibilityCacheEntries { plausibilityCache.removeAll() }
        plausibilityCache[reading] = best
        return best
    }

    /// ZenzaiTypoService が前に使っていたものと同じ(Zenzai を使わず，1 件だけ求め，学習しない)
    private var options: ConvertRequestOptions {
        var options = ConvertRequestOptions(
            N_best: DefaultSettings.engineCandidateCount,
            requireJapanesePrediction: .disabled,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: false,
            fullWidthRomanCandidate: false,
            halfWidthKanaCandidate: false,
            learningType: .onlyOutput,
            memoryDirectoryURL: memoryDirectory,
            sharedContainerURL: memoryDirectory,
            textReplacer: .empty,
            specialCandidateProviders: [],
            zenzaiMode: .off,
            metadata: .init(versionString: versionString)
        )
        options.N_best = 1
        options.learningType = .nothing
        options.typoCorrectionMode = .disabled
        return options
    }
}
