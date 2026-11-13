import Foundation
import HajimeDomain

/// jinen(読みと左文脈から表記を出すかな漢字変換のモデル．Qwen3 系)のファイル．Zenzai とは別のモデルで，合議(ADR 0016)に使う．
///
/// 外から取得するファイルなので，SHA-256 がリポジトリに書いた値と一致したものだけを使う(docs/dev/SECURITY-MODEL.md)．
/// ライセンスは CC BY-SA 4.0 で，国立国会図書館の書誌データの出典の表示が要る(THIRD_PARTY_NOTICES.md)．
public struct JinenModel: Sendable, Equatable {
    public enum Variant: String, Sendable, Equatable, CaseIterable {
        /// togatogah/jinen-v2-small.gguf の jinen-v2-small-Q5_K_M.gguf．Hugging Face のコミット 3461d0573ab447985badde3174165b967d06076c
        case small
        /// togatogah/jinen-v2-xsmall.gguf の jinen-v2-xsmall-Q5_K_M.gguf．Hugging Face のコミット 3910fd01bf4ba86eca89617f18db9b0c1c5b2283
        case xsmall

        public var fileName: String {
            switch self {
            case .small: "jinen-v2-small-Q5_K_M.gguf"
            case .xsmall: "jinen-v2-xsmall-Q5_K_M.gguf"
            }
        }

        public var expectedSHA256: String {
            switch self {
            case .small: "80482707513d6b67dafc31774371cf95d765542abf8d74eebf5f32f92d788bd3"
            case .xsmall: "24ff3af5db712fbbb4aa9254ee28ec4d731207134471ab68b06c1828726284c2"
            }
        }

        public var expectedSize: Int {
            switch self {
            case .small: 81_117_824
            case .xsmall: 28_261_056
            }
        }
    }

    public let url: URL
    public let variant: Variant

    /// ファイルを確かめてから作る．大きさとハッシュのどちらかが違えば使わない
    public static func verified(at url: URL, variant: Variant = .small) throws(ZenzaiModel.VerificationError) -> JinenModel {
        try verified(at: url, variant: variant, previous: nil).model
    }

    /// 前回の記録(ADR 0017)と同じファイルなら，ハッシュを求めずに使う(StartupResources)
    static func verified(at url: URL, variant: Variant, previous: VerificationRecord.Entry?)
        throws(ZenzaiModel.VerificationError) -> (model: JinenModel, record: VerificationRecord.Entry?) {
        let record = try ZenzaiModel.check(url, expectedSize: variant.expectedSize, expectedSHA256: variant.expectedSHA256, previous: previous)
        return (JinenModel(url: url, variant: variant), record)
    }
}
