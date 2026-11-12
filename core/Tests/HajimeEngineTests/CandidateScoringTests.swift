import Foundation
import HajimeApplication
import HajimeDomain
@testable import HajimeEngine
import HajimeTestSupport
import Testing

/// 候補を Zenzai の検証木で採点する(ADR 0016)．本物のモデルが要るものは，環境変数 HAJIME_ZENZAI_MODEL にモデルの場所があるときだけ動かす
@Suite("検証木の採点", .serialized)
@MainActor
struct CandidateScoringTests {
    private func makeEngine(zenzai: Bool) throws -> AzooKeyConverterEngine {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-scoring-\(UUID().uuidString)")
        let model = try zenzai ? ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"].map { try ZenzaiModel.verified(at: URL(fileURLWithPath: $0)) } : nil
        return try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "scoring", zenzai: model)
    }

    @Test("採点が目安より遅ければ評価するトークンを減らし，上限近くまで使って速ければ少し増やす")
    func adaptsTokenLimit() {
        let budget = DefaultSettings.candidateScoringBudget
        let limit = DefaultSettings.candidateTreeTokenLimit
        // 目安の 2 倍かかったら，使ったトークンの半分にする
        #expect(AzooKeyConverterEngine.nextCandidateTreeTokenLimit(current: limit, tokens: 100, seconds: budget * 2) == 50)
        // 下限より少なくはしない
        #expect(AzooKeyConverterEngine.nextCandidateTreeTokenLimit(current: limit, tokens: 10, seconds: budget * 10)
                == DefaultSettings.minimumCandidateTreeTokens)
        // 上限近くまで使って速ければ増やす(上限は超えない)
        #expect(AzooKeyConverterEngine.nextCandidateTreeTokenLimit(current: 40, tokens: 40, seconds: budget * 0.3) == 50)
        #expect(AzooKeyConverterEngine.nextCandidateTreeTokenLimit(current: limit, tokens: limit, seconds: budget * 0.3) == limit)
        // 木が小さくて速いだけなら変えない(上限を使い切っていないので，増やしてよいかは分からない)
        #expect(AzooKeyConverterEngine.nextCandidateTreeTokenLimit(current: 40, tokens: 10, seconds: budget * 0.3) == 40)
    }

    @Test("Zenzai が無ければすべて採点できない(nil)．入力は止めない")
    func withoutZenzai() throws {
        let session = try makeEngine(zenzai: false).makeSession()
        #expect(session.scores(of: ["雨", "飴"], reading: "あめ", before: "", after: "").allSatisfy { $0 == nil })
    }

    @Test("文脈に合う表記ほど点数が高い", .enabled(if: ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil))
    func prefersFittingText() throws {
        let session = try makeEngine(zenzai: true).makeSession()
        let scores = session.scores(of: ["今日は雨", "京は雨", "今日は飴"], reading: "きょうはあめ", before: "", after: "")
        let values = try scores.map { try #require($0) }
        #expect(values.allSatisfy { $0.isFinite && $0 < 0 })
        #expect(values[0] > values[1])
        #expect(values[0] > values[2])
    }

    @Test("前後の文節の文字を文脈にして，文節の表記を比べる", .enabled(if: ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil))
    func usesBeforeAndAfter() throws {
        let session = try makeEngine(zenzai: true).makeSession()
        // 「きしゃ」は前の文字で変わる(新聞の → 記者，駅で → 汽車)
        let reporter = session.scores(of: ["記者", "汽車"], reading: "きしゃ", before: "新聞の", after: "が取材に来た")
        let train = session.scores(of: ["記者", "汽車"], reading: "きしゃ", before: "駅で", after: "に乗った")
        let r = try reporter.map { try #require($0) }, t = try train.map { try #require($0) }
        #expect(r[0] > r[1])
        #expect(t[1] > t[0])
    }

    @Test("同じ問いは覚えておき，左の文脈が変わったら求め直す", .enabled(if: ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil))
    func cachesUntilContextChanges() throws {
        let session = try makeEngine(zenzai: true).makeSession()
        let first = session.scores(of: ["記者", "汽車"], reading: "きしゃ", before: "", after: "")
        #expect(session.scores(of: ["記者", "汽車"], reading: "きしゃ", before: "", after: "") == first)
        session.setLeftContext("駅のホームで")
        let changed = session.scores(of: ["記者", "汽車"], reading: "きしゃ", before: "", after: "")
        #expect(changed != first)
    }
}
