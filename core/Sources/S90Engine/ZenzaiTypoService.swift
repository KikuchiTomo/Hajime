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

    public func corrections(forKeys keys: [String], leftContext: String?) -> [String: [ReadingCorrection]] {
        var result: [String: [ReadingCorrection]] = [:]
        for key in keys where !key.isEmpty {
            var composing = ComposingText()
            composing.insertAtCursorPosition(key, inputStyle: .roman2kana)
            let config = ExperimentalTypoCorrectionConfig(
                beamSize: DefaultSettings.typoCorrectionBeamSize, topK: DefaultSettings.typoCorrectionTopK, nBest: DefaultSettings.typoCorrectionCandidateCount)
            let candidates = converter.experimentalRequestTypoCorrection(
                leftSideContext: leftContext ?? "", composingText: composing, options: options(leftContext: leftContext), inputStyle: .roman2kana, config: config)
            converter.stopComposition()
            result[key] = candidates.map {
                ReadingCorrection(keys: $0.correctedInput, reading: $0.convertedText, score: Double($0.score), cost: Double($0.channelCost))
            }
        }
        return result
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
