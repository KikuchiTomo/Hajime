import Foundation
import HajimeApplication
import HajimeDomain

/// 起動のときに確かめてから使うファイル(Zenzai モデル 2 つ，Jinen モデル 2 つと同梱の辞書)を確かめた結果．
///
/// どれも外から取得するファイルなので，それぞれの verified がハッシュを確かめ終えたものだけを使う(docs/dev/SECURITY-MODEL.md)．
/// どれも互いに関係しないので同時に確かめ，すべて終わってから返す(起動から最初の変換までの時間を縮めるため)．
/// 確かめられなかったものは失敗の結果にし，理由は呼ぶ側(composition root)が記録する．そのファイルなしで入力は続ける．
/// 前回確かめて合ったファイルが，大きさ・更新日時・ファイル ID もアプリのバージョンも変わっていなければ，ハッシュを求め直さない(ADR 0017)
public struct StartupResources: Sendable {
    public private(set) var zenzai: Result<ZenzaiModel, ZenzaiModel.VerificationError>?
    public private(set) var fastZenzai: Result<ZenzaiModel, ZenzaiModel.VerificationError>?
    /// 合議(ADR 0016 の案 2)に使う jinen の small と xsmall
    public private(set) var jinen: Result<JinenModel, ZenzaiModel.VerificationError>?
    public private(set) var fastJinen: Result<JinenModel, ZenzaiModel.VerificationError>?
    public private(set) var dictionary: Result<BundledDictionary, BundledDictionary.VerificationError>?

    private init() {}

    /// 場所を渡さなかったものは確かめずに nil にする．
    /// records を渡すと，前回の記録(appVersion が同じものだけ)と同じファイルはハッシュを求めずに使い，確かめて合ったものを記録し直す
    public static func verified(zenzai: URL?, fastZenzai: URL?, jinen: URL? = nil, fastJinen: URL? = nil, dictionary: URL?,
                                records: (any VerificationRecordStoring)? = nil, appVersion: String = "") -> StartupResources {
        let loaded = records?.load()
        let previous = loaded?.entries(for: appVersion) ?? [:]
        let recording = records != nil && !appVersion.isEmpty
        let jobs = [zenzai.map(Job.zenzai), fastZenzai.map(Job.fastZenzai), jinen.map(Job.jinen), fastJinen.map(Job.fastJinen),
                    dictionary.map(Job.dictionary)].compactMap { $0 }
        var resources = StartupResources()
        var record = VerificationRecord(appVersion: appVersion)
        for (job, (outcome, entry)) in zip(jobs, ConcurrentWork.map(jobs, { $0.run(previous: previous[$0.key], recording: recording) })) {
            record.entries[job.key] = entry
            switch outcome {
            case .zenzai(let result): resources.zenzai = result
            case .fastZenzai(let result): resources.fastZenzai = result
            case .jinen(let result): resources.jinen = result
            case .fastJinen(let result): resources.fastJinen = result
            case .dictionary(let result): resources.dictionary = result
            }
        }
        if let records, recording, record != loaded { records.save(record) }
        return resources
    }

    /// 実行ファイルを見分ける値(大きさ・更新日時・ファイル ID)．アプリのバージョンを持たない Windows のエンジンで，
    /// 記録の appVersion に使う(入れ直せば実行ファイルが置き換わって値が変わる)．読めなければ nil
    public static func executableIdentity(at url: URL) -> String? {
        FileDigest.stamp(at: url).map { "executable:\(FileStamp.digest(of: [(name: url.lastPathComponent, stamp: $0)]))" }
    }

    private enum Job: Sendable {
        case zenzai(URL)
        case fastZenzai(URL)
        case jinen(URL)
        case fastJinen(URL)
        case dictionary(URL)

        /// 記録(VerificationRecord.entries)の名前
        var key: String {
            switch self {
            case .zenzai: "zenzai.small"
            case .fastZenzai: "zenzai.xsmall"
            case .jinen: "jinen.small"
            case .fastJinen: "jinen.xsmall"
            case .dictionary: "dictionary"
            }
        }

        /// 確かめた結果と，合ったときの記録(記録しないときと合わなかったときは nil)
        func run(previous: VerificationRecord.Entry?, recording: Bool) -> (Outcome, VerificationRecord.Entry?) {
            switch self {
            case .zenzai(let url):
                let result = Result { () throws(ZenzaiModel.VerificationError) in try ZenzaiModel.verified(at: url, variant: .small, previous: previous) }
                return (.zenzai(result.map(\.model)), recording ? (try? result.get())?.record : nil)
            case .fastZenzai(let url):
                let result = Result { () throws(ZenzaiModel.VerificationError) in try ZenzaiModel.verified(at: url, variant: .xsmall, previous: previous) }
                return (.fastZenzai(result.map(\.model)), recording ? (try? result.get())?.record : nil)
            case .jinen(let url):
                let result = Result { () throws(ZenzaiModel.VerificationError) in try JinenModel.verified(at: url, variant: .small, previous: previous) }
                return (.jinen(result.map(\.model)), recording ? (try? result.get())?.record : nil)
            case .fastJinen(let url):
                let result = Result { () throws(ZenzaiModel.VerificationError) in try JinenModel.verified(at: url, variant: .xsmall, previous: previous) }
                return (.fastJinen(result.map(\.model)), recording ? (try? result.get())?.record : nil)
            case .dictionary(let url):
                let result = Result { () throws(BundledDictionary.VerificationError) in
                    try BundledDictionary.verified(at: url, previous: previous, recording: recording)
                }
                return (.dictionary(result.map(\.dictionary)), recording ? (try? result.get())?.record : nil)
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
