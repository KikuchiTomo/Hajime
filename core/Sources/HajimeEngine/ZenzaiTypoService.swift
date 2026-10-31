import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import HajimeApplication
import HajimeDomain

/// 打ち間違いの訂正を，入力を処理するメインスレッドとは別に求める(R-02)．
///
/// 訂正は探す幅を広げると 1 文に 1 秒ほどかかる．メインスレッドで求めると打鍵が止まるので，
/// 表示に使う変換器とは別の変換器を持ち，このアクターの中だけで使う(azooKey の変換器はスレッドセーフではない)．
/// Zenzai も表示の変換とは別の推論の文脈で使う(ZenzaiModel.separateContextURL)．同じ文脈を使うと，
/// 訂正を求めているあいだ表示の変換が文脈の順番を待って止まる．
/// 1 か所の打ち間違いを全部試す候補を軽い変換で絞る仕事は，別の変換器(TypoPlausibilityService)で Zenzai の探索と並べて行う．
/// 辞書と推論の文脈を別に持つぶん，メモリは増える(モデルの重みは共有する)．学習はしない(読むだけ)
public actor ZenzaiTypoService: TypoCorrecting {
    private let converter: KanaKanjiConverter
    private let plausibility: TypoPlausibilityService
    private let zenzai: ZenzaiModel
    private let memoryDirectory: URL
    private let versionString: String

    public init(zenzai: ZenzaiModel, memoryDirectory: URL, versionString: String) {
        self.converter = KanaKanjiConverter.withDefaultDictionary()
        self.plausibility = TypoPlausibilityService(memoryDirectory: memoryDirectory, versionString: versionString)
        self.zenzai = zenzai
        self.memoryDirectory = memoryDirectory
        self.versionString = versionString
    }

    /// 求めているあいだに呼んだ側が取り消したら(次のキーが来た，Space で待ちきれなかった)，途中でやめて空を返す．
    /// 古い訂正を最後まで求め続けると，CPU を取り合って打鍵と変換が遅くなり，次の訂正の求めも待たせるため．
    /// 求め終わった並びの候補と途中までの探索は覚えておき，次に同じ並びやその続きを求めるときに使う
    public func corrections(forKeys keys: [String], leftContext: String?) async -> [String: [ReadingCorrection]] {
        var result: [String: [ReadingCorrection]] = [:]
        var previous = lastSearchedKeys
        for key in keys where !key.isEmpty {
            guard !Task.isCancelled else { return [:] }
            // 前に見直した部分は探し直さない(打っているあいだは新しく打った数文字だけを試すので速い)
            let from = KeyEditSearch.searchStart(keys: key, previous: previous)
            // 取り消したあとの結果は使わず，探した位置も進めない(次に同じキーで探し直す)
            guard let found = await corrections(forKey: key, from: from, leftContext: leftContext) else { return [:] }
            previous = key
            lastSearchedKeys = key
            result[key] = found
        }
        return result
    }

    /// corrections と同じ並びを同じ順に求めて覚えておく．探した位置(lastSearchedKeys)は進めないので，
    /// あとで corrections を呼んだときの結果は，前もって求めなかったときと同じになる
    public func prefetch(forKeys keys: [String], leftContext: String?) async {
        var previous = lastSearchedKeys
        for key in keys where !key.isEmpty {
            guard !Task.isCancelled else { return }
            let from = KeyEditSearch.searchStart(keys: key, previous: previous)
            guard await corrections(forKey: key, from: from, leftContext: leftContext) != nil else { return }
            previous = key
        }
    }

    /// 1 つの並びの訂正の候補．取り消されたら nil
    private func corrections(forKey key: String, from: Int, leftContext: String?) async -> [ReadingCorrection]? {
        let memoKey = MemoKey(keys: key, leftContext: leftContext, from: from)
        if let memoized = memoized[memoKey] { return memoized }
        // Zenzai の探索が拾わない誤り(かなの書き誤りなど)を，1 か所の打ち間違いを全部試して補う．
        // 読みそのものの誤り(言い違い・書き違い)は，変換で語にならずかなのまま残った部分のかなを変えて探す．
        // どちらも候補を軽い変換で絞る仕事は別の変換器で行い，そのあいだにこちらで Zenzai の探索をする
        async let rankedEdits = plausibility.rankedKeyEdits(of: key, from: from)
        async let rankedKanaEdits = plausibility.rankedKanaEdits(ofKeys: key)
        let beam = beamCorrections(forKey: key, leftContext: leftContext)
        let (edits, kanaEdits) = await (rankedEdits, rankedKanaEdits)
        guard !Task.isCancelled else { return nil }
        let keyCorrections = KeyEditSearch.scoredCorrections(of: key, ranked: edits) { self.languageModelScores(forKeys: $0, leftContext: leftContext) }
        guard !Task.isCancelled else { return nil }
        let kanaCorrections = KanaEditSearch.scoredCorrections(ranked: kanaEdits) { self.languageModelScores(forKeys: $0, leftContext: leftContext) }
        guard !Task.isCancelled else { return nil }
        let merged = await plausibility.withPlausibility(KeyEditSearch.merge(beam, keyCorrections, kanaCorrections), typedKeys: key)
        guard !Task.isCancelled else { return nil }
        let result = withContextFreeScores(merged, leftContext: leftContext)
        guard !Task.isCancelled else { return nil }
        if memoized.count >= DefaultSettings.maximumMemoizedCorrections { memoized.removeAll() }
        memoized[memoKey] = result
        return result
    }

    /// Zenzai の探索による訂正の候補．取り消されたら途中でやめる(途中までの探索は変換器が覚えている)
    private func beamCorrections(forKey key: String, leftContext: String?) -> [ReadingCorrection] {
        var composing = ComposingText()
        composing.insertAtCursorPosition(key, inputStyle: .roman2kana)
        let config = ExperimentalTypoCorrectionConfig(
            beamSize: DefaultSettings.typoCorrectionBeamSize, topK: DefaultSettings.typoCorrectionTopK, nBest: DefaultSettings.typoCorrectionCandidateCount)
        let candidates = converter.experimentalRequestTypoCorrection(
            leftSideContext: leftContext ?? "", composingText: composing, options: options(leftContext: leftContext), inputStyle: .roman2kana, config: config,
            shouldStop: { Task.isCancelled })
        converter.stopComposition()
        return candidates.map {
            ReadingCorrection(keys: $0.correctedInput, reading: $0.convertedText, score: Double($0.score), cost: Double($0.channelCost))
        }
    }

    /// 求めた訂正の候補を見分ける鍵．探し始める位置(from)で候補が変わるので含める
    private struct MemoKey: Hashable {
        var keys: String
        var leftContext: String?
        var from: Int
    }

    /// 求めた訂正の候補．打っているあいだに前もって求めたものを，打鍵が止まって見直すときに使う
    private var memoized: [MemoKey: [ReadingCorrection]] = [:]

    /// 左の文脈があるとき，打ったままと点数の高い候補(DefaultSettings.contextFreeCandidateCount 件)に，文脈を使わない点数を付ける．
    /// 言語モデルの採点を 1 回だけ足す(候補ごとに探し直さない)．文脈が無ければ何もしない
    private func withContextFreeScores(_ corrections: [ReadingCorrection], leftContext: String?) -> [ReadingCorrection] {
        guard let leftContext, !leftContext.isEmpty, !Task.isCancelled else { return corrections }
        let top = corrections.filter { !$0.isUnchanged }.sorted { $0.rank > $1.rank }.prefix(DefaultSettings.contextFreeCandidateCount)
        let targets = corrections.filter(\.isUnchanged).prefix(1) + top
        guard targets.count > 1 else { return corrections }
        let scores = languageModelScores(forKeys: targets.map(\.keys), leftContext: nil)
        var free: [String: Double] = [:]
        for (target, score) in zip(targets, scores) {
            if let score { free[target.keys] = score - target.cost }
        }
        return corrections.map { correction in
            var correction = correction
            correction.contextFreeScore = free[correction.keys]
            return correction
        }
    }

    /// 前に 1 か所の打ち間違いを探したキーの並び(見直しで求め終えたもの)
    private var lastSearchedKeys: String?

    private func languageModelScores(forKeys keys: [String], leftContext: String?) -> [Double?] {
        guard !Task.isCancelled else { return keys.map { _ in nil } }
        let inputs = keys.map { key -> ComposingText in
            var composing = ComposingText()
            composing.insertAtCursorPosition(key, inputStyle: .roman2kana)
            return composing
        }
        let scores = converter.experimentalScoreTypoInputs(
            leftSideContext: leftContext ?? "", inputs: inputs, options: options(leftContext: leftContext), inputStyle: .roman2kana,
            shouldStop: { Task.isCancelled })
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
                weight: zenzai.separateContextURL,
                inferenceLimit: DefaultSettings.zenzaiInferenceLimit,
                personalizationMode: nil,
                versionDependentMode: .v3(.init(leftSideContext: leftContext, maxLeftSideContextLength: DefaultSettings.maximumLeftContextLength))
            ),
            metadata: .init(versionString: versionString)
        )
    }
}
