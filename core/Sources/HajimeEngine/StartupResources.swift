import Foundation
import HajimeDomain

/// 起動のときに確かめてから使うファイル(Zenzai のモデル 2 つと同梱の辞書)を確かめた結果．
///
/// どれも外から取得するファイルなので，それぞれの verified がハッシュを確かめ終えたものだけを使う(docs/dev/SECURITY-MODEL.md)．
/// 3 つは互いに関係しないので同時に確かめ，すべて終わってから返す(起動から最初の変換までの時間を縮めるため)．
/// 確かめられなかったものは失敗の結果にし，理由は呼ぶ側(composition root)が記録する．そのファイルなしで入力は続ける
public struct StartupResources: Sendable {
    public private(set) var zenzai: Result<ZenzaiModel, ZenzaiModel.VerificationError>?
    public private(set) var fastZenzai: Result<ZenzaiModel, ZenzaiModel.VerificationError>?
    public private(set) var dictionary: Result<BundledDictionary, BundledDictionary.VerificationError>?

    private init() {}

    /// 場所を渡さなかったものは確かめずに nil にする
    public static func verified(zenzai: URL?, fastZenzai: URL?, dictionary: URL?) -> StartupResources {
        let jobs = [zenzai.map(Job.zenzai), fastZenzai.map(Job.fastZenzai), dictionary.map(Job.dictionary)].compactMap { $0 }
        var resources = StartupResources()
        for outcome in ConcurrentWork.map(jobs, { $0.run() }) {
            switch outcome {
            case .zenzai(let result): resources.zenzai = result
            case .fastZenzai(let result): resources.fastZenzai = result
            case .dictionary(let result): resources.dictionary = result
            }
        }
        return resources
    }

    private enum Job: Sendable {
        case zenzai(URL)
        case fastZenzai(URL)
        case dictionary(URL)

        func run() -> Outcome {
            switch self {
            case .zenzai(let url):
                .zenzai(Result { () throws(ZenzaiModel.VerificationError) in try ZenzaiModel.verified(at: url, variant: .small) })
            case .fastZenzai(let url):
                .fastZenzai(Result { () throws(ZenzaiModel.VerificationError) in try ZenzaiModel.verified(at: url, variant: .xsmall) })
            case .dictionary(let url):
                .dictionary(Result { () throws(BundledDictionary.VerificationError) in try BundledDictionary.verified(at: url) })
            }
        }
    }

    private enum Outcome: Sendable {
        case zenzai(Result<ZenzaiModel, ZenzaiModel.VerificationError>)
        case fastZenzai(Result<ZenzaiModel, ZenzaiModel.VerificationError>)
        case dictionary(Result<BundledDictionary, BundledDictionary.VerificationError>)
    }
}
