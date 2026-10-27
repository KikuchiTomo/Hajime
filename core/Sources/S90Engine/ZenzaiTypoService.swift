import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import S90Application
import S90Domain

/// 打ち間違いの訂正を，入力を処理するメインスレッドとは別に求める(R-02)．
///
/// 訂正は探す幅を広げると 1 文に 1 秒ほどかかる．メインスレッドで求めると打鍵が止まるので，
/// 表示に使う変換器とは別の変換器を持ち，このアクターの中だけで使う(azooKey の変換器はスレッドセーフではない)．
/// 辞書と Zenzai のモデルを別に読み込むぶん，メモリは増える．学習はしない(読むだけ)
public actor ZenzaiTypoService: TypoCorrecting {
    private let converter: KanaKanjiConverter
    private let zenzai: ZenzaiModel
    private let memoryDirectory: URL
    private let versionString: String

    public init(zenzai: ZenzaiModel, memoryDirectory: URL, versionString: String) {
        self.converter = KanaKanjiConverter.withDefaultDictionary()
        self.zenzai = zenzai
        self.memoryDirectory = memoryDirectory
        self.versionString = versionString
    }

    /// 求めているあいだに呼んだ側が取り消したら(次のキーが来た，Space で待ちきれなかった)，途中でやめて空を返す．
    /// 古い訂正を最後まで求め続けると，CPU を取り合って打鍵と変換が遅くなり，次の訂正の求めも待たせるため
    public func corrections(forKeys keys: [String], leftContext: String?) -> [String: [ReadingCorrection]] {
        var result: [String: [ReadingCorrection]] = [:]
        for key in keys where !key.isEmpty {
            guard !Task.isCancelled else { return [:] }
            var composing = ComposingText()
            composing.insertAtCursorPosition(key, inputStyle: .roman2kana)
            let config = ExperimentalTypoCorrectionConfig(
                beamSize: DefaultSettings.typoCorrectionBeamSize, topK: DefaultSettings.typoCorrectionTopK, nBest: DefaultSettings.typoCorrectionCandidateCount)
            let candidates = converter.experimentalRequestTypoCorrection(
                leftSideContext: leftContext ?? "", composingText: composing, options: options(leftContext: leftContext), inputStyle: .roman2kana, config: config)
            converter.stopComposition()
            guard !Task.isCancelled else { return [:] }
            let beam = candidates.map {
                ReadingCorrection(keys: $0.correctedInput, reading: $0.convertedText, score: Double($0.score), cost: Double($0.channelCost))
            }
            // Zenzai の探索が拾わない誤り(かなの書き誤りなど)を，1 か所の打ち間違いを全部試して補う
            // 前に見直した部分は探し直さない(打っているあいだは新しく打った数文字だけを試すので速い)
            let edits = KeyEditSearch.corrections(
                of: key,
                from: KeyEditSearch.searchStart(keys: key, previous: lastSearchedKeys),
                plausibility: plausibility(of:),
                languageModel: { self.languageModelScores(forKeys: $0, leftContext: leftContext) }
            )
            // 取り消したあとの結果は使わず，探した位置も進めない(次に同じキーで探し直す)
            guard !Task.isCancelled else { return [:] }
            // 読みそのものの誤り(言い違い・書き違い)は，変換で語にならずかなのまま残った部分のかなを変えて探す
            let kanaEdits = kanaCorrections(forKeys: key, leftContext: leftContext)
            guard !Task.isCancelled else { return [:] }
            lastSearchedKeys = key
            result[key] = KeyEditSearch.withPlausibility(KeyEditSearch.merge(beam, edits, kanaEdits), typedKeys: key, plausibility: plausibility(of:))
        }
        return result
    }

    /// かなの単位の訂正(KanaEditSearch)．読みにかなにならない英字が残るときは探さない
    private func kanaCorrections(forKeys keys: String, leftContext: String?) -> [ReadingCorrection] {
        let reading = KeyEditSearch.rawReading(of: keys)
        guard !reading.isEmpty, !reading.contains(where: \.isASCII) else { return [] }
        return KanaEditSearch.corrections(
            of: reading,
            in: unconvertedSpans(of: reading),
            plausibility: plausibility(of:),
            unconverted: { self.unconvertedSpans(of: $0, minimumLength: 1) },
            languageModel: { self.languageModelScores(forKeys: $0, leftContext: leftContext) }
        )
    }

    /// 読みを Zenzai を使わずに変換したとき，語にならずかなのまま残った部分
    private func unconvertedSpans(of reading: String, minimumLength: Int = DefaultSettings.minimumUnconvertedSpanLength) -> [Range<Int>] {
        guard !Task.isCancelled else { return [] }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        var options = options(leftContext: nil)
        options.zenzaiMode = .off
        options.N_best = 1
        options.learningType = .nothing
        options.typoCorrectionMode = .disabled
        let data = converter.requestCandidates(composing, options: options).mainResults
            .first { AzooKeyConverterSession.readingCount($0.composingCount, readingLength: reading.count) == reading.count }?.data ?? []
        converter.stopComposition()
        return AzooKeyConverterSession.unconvertedSpans(of: data, minimumLength: minimumLength)
    }

    /// 前に 1 か所の打ち間違いを探したキーの並び
    private var lastSearchedKeys: String?

    /// 読みを変換したときのもっともらしさ(Zenzai を使わない軽い変換の点数)．読みごとに覚えておく
    private var plausibilityCache: [String: Double] = [:]

    private func plausibility(of reading: String) -> Double {
        if let cached = plausibilityCache[reading] { return cached }
        // 取り消されたら変換せずにすぐ返す(覚えない)．残りの候補の計算を速く終わらせるため
        guard !Task.isCancelled else { return -.infinity }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        var options = options(leftContext: nil)
        options.zenzaiMode = .off
        options.N_best = 1
        options.learningType = .nothing
        options.typoCorrectionMode = .disabled
        let best = converter.requestCandidates(composing, options: options).mainResults
            .first { AzooKeyConverterSession.readingCount($0.composingCount, readingLength: reading.count) == reading.count }
            .map { Double($0.value) } ?? -.infinity
        converter.stopComposition()
        if plausibilityCache.count > DefaultSettings.maximumPlausibilityCacheEntries { plausibilityCache.removeAll() }
        plausibilityCache[reading] = best
        return best
    }

    private func languageModelScores(forKeys keys: [String], leftContext: String?) -> [Double?] {
        guard !Task.isCancelled else { return keys.map { _ in nil } }
        let inputs = keys.map { key -> ComposingText in
            var composing = ComposingText()
            composing.insertAtCursorPosition(key, inputStyle: .roman2kana)
            return composing
        }
        let scores = converter.experimentalScoreTypoInputs(
            leftSideContext: leftContext ?? "", inputs: inputs, options: options(leftContext: leftContext), inputStyle: .roman2kana)
        converter.stopComposition()
        return scores.map { $0.map(Double.init) }
    }

    private func options(leftContext: String?) -> ConvertRequestOptions {
        ConvertRequestOptions(
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
            zenzaiMode: .on(
                weight: zenzai.url,
                inferenceLimit: DefaultSettings.zenzaiInferenceLimit,
                personalizationMode: nil,
                versionDependentMode: .v3(.init(leftSideContext: leftContext, maxLeftSideContextLength: DefaultSettings.maximumLeftContextLength))
            ),
            metadata: .init(versionString: versionString)
        )
    }
}
