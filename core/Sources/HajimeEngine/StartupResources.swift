import Foundation
import HajimeDomain

/// 起動のときに確かめてから使うファイル(Zenzai モデル 2 つ，Jinen モデル 2 つと同梱の辞書)を確かめた結果．
///
/// どれも外から取得するファイルなので，それぞれの verified がハッシュを確かめ終えたものだけを使う(docs/dev/SECURITY-MODEL.md)．
/// どれも互いに関係しないので同時に確かめ，すべて終わってから返す(起動から最初の変換までの時間を縮めるため)．
/// 確かめられなかったものは失敗の結果にし，理由は呼ぶ側(composition root)が記録する．そのファイルなしで入力は続ける
public struct StartupResources: Sendable {
    public private(set) var zenzai: Result<ZenzaiModel, ZenzaiModel.VerificationError>?
    public private(set) var fastZenzai: Result<ZenzaiModel, ZenzaiModel.VerificationError>?
    /// 合議(ADR 0016 の案 2)に使う jinen の small と xsmall
    public private(set) var jinen: Result<JinenModel, ZenzaiModel.VerificationError>?
    public private(set) var fastJinen: Result<JinenModel, ZenzaiModel.VerificationError>?
    public private(set) var dictionary: Result<BundledDictionary, BundledDictionary.VerificationError>?

    private init() {}

    /// 場所を渡さなかったものは確かめずに nil にする
    public static func verified(zenzai: URL?, fastZenzai: URL?, jinen: URL? = nil, fastJinen: URL? = nil, dictionary: URL?) -> StartupResources {
        let jobs = [zenzai.map(Job.zenzai), fastZenzai.map(Job.fastZenzai), jinen.map(Job.jinen), fastJinen.map(Job.fastJinen),
                    dictionary.map(Job.dictionary)].compactMap { $0 }
        var resources = StartupResources()
        for outcome in ConcurrentWork.map(jobs, { $0.run() }) {
            switch outcome {
            case .zenzai(let result): resources.zenzai = result
            case .fastZenzai(let result): resources.fastZenzai = result
            case .jinen(let result): resources.jinen = result
            case .fastJinen(let result): resources.fastJinen = result
            case .dictionary(let result): resources.dictionary = result
            }
        }
        return resources
    }

    private enum Job: Sendable {
        case zenzai(URL)
        case fastZenzai(URL)
        case jinen(URL)
        case fastJinen(URL)
        case dictionary(URL)

        func run() -> Outcome {
            switch self {
            case .zenzai(let url):
                .zenzai(Result { () throws(ZenzaiModel.VerificationError) in try ZenzaiModel.verified(at: url, variant: .small) })
            case .fastZenzai(let url):
                .fastZenzai(Result { () throws(ZenzaiModel.VerificationError) in try ZenzaiModel.verified(at: url, variant: .xsmall) })
            case .jinen(let url):
                .jinen(Result { () throws(ZenzaiModel.VerificationError) in try JinenModel.verified(at: url, variant: .small) })
            case .fastJinen(let url):
                .fastJinen(Result { () throws(ZenzaiModel.VerificationError) in try JinenModel.verified(at: url, variant: .xsmall) })
            case .dictionary(let url):
                .dictionary(Result { () throws(BundledDictionary.VerificationError) in try BundledDictionary.verified(at: url) })
            }
        }
    }

    private enum Outcome: Sendable {
        case zenzai(Result<ZenzaiModel, ZenzaiModel.VerificationError>)
        case fastZenzai(Result<ZenzaiModel, ZenzaiModel.VerificationError>)
        case jinen(Result<JinenModel, ZenzaiModel.VerificationError>)
        case fastJinen(Result<JinenModel, ZenzaiModel.VerificationError>)
        case dictionary(Result<BundledDictionary, BundledDictionary.VerificationError>)
    }
}
