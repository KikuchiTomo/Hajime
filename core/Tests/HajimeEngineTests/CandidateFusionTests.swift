import Foundation
import HajimeApplication
import HajimeDomain
@testable import HajimeEngine
import HajimeTestSupport
import Testing

private let environment = ProcessInfo.processInfo.environment
private let hasModels = environment["HAJIME_ZENZAI_MODEL"] != nil && environment["HAJIME_JINEN_MODEL"] != nil
    && environment["HAJIME_BUNDLED_DICTIONARY"] != nil

/// 別のモデル(jinen)との合議(ADR 0016 の案 2)．本物のモデルが要るものは，環境変数 HAJIME_ZENZAI_MODEL・HAJIME_JINEN_MODEL・
/// HAJIME_BUNDLED_DICTIONARY があるときだけ動かす(make test-zenzai)．HAJIME_FAST_JINEN_MODEL(xsmall)は「自動」の判定にだけ使い，無くてもよい
@Suite("別のモデルとの合議", .serialized)
@MainActor
struct CandidateFusionTests {
    @Test("読みにそろえるとき，読みにある全角の記号に当たる半角の記号を全角に戻した表記も試す")
    func alignmentAttempts() {
        #expect(AzooKeyConverterSession.alignmentAttempts("性意識(", reading: "せいいしき（") == ["性意識(", "性意識（"])
        #expect(AzooKeyConverterSession.alignmentAttempts("何?", reading: "なに？") == ["何?", "何？"])
        // 読みに全角の記号が無ければ，そのままの表記だけ
        #expect(AzooKeyConverterSession.alignmentAttempts("3人", reading: "さんにん") == ["3人"])
    }

    /// ファイルを読まずに作った jinen のモデル(大きさの選び方だけを確かめる)
    private func engine(models: [JinenModel.Variant], choice: JinenModelChoice) throws -> AzooKeyConverterEngine {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-jinen-\(UUID().uuidString)")
        let model = { (variant: JinenModel.Variant) in
            models.contains(variant) ? JinenModel(url: directory.appendingPathComponent(variant.fileName), variant: variant) : nil
        }
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "jinen", jinen: model(.small), fastJinen: model(.xsmall))
        var settings = DefaultSettings.settings
        settings.jinenModel = choice
        engine.apply(settings)
        return engine
    }

    @Test("設定で選んだ大きさの jinen を使い，そのモデルが無ければもう一方を使う．使わない設定と，自動でまだ測っていないときは使わない")
    func resolvesJinenVariant() throws {
        #expect(try engine(models: [.small, .xsmall], choice: .small).resolvedJinenVariant == .small)
        #expect(try engine(models: [.small, .xsmall], choice: .xsmall).resolvedJinenVariant == .xsmall)
        #expect(try engine(models: [.xsmall], choice: .small).resolvedJinenVariant == .xsmall)
        #expect(try engine(models: [.small, .xsmall], choice: .off).resolvedJinenVariant == nil)
        let automatic = try engine(models: [.small, .xsmall], choice: .automatic)
        #expect(automatic.automaticJinenModel == nil)
        #expect(automatic.resolvedJinenVariant == nil)
        #expect(try engine(models: [], choice: .small).resolvedJinenVariant == nil)
    }

    @Test("自動は，合議の 1 歩の p95 が Zenzai だけの 1 歩の p95 ＋ 目安以下ならその大きさにする")
    func automaticStepRule() {
        let margin = DefaultSettings.jinenAutomaticStepMargin
        #expect(AzooKeyConverterEngine.acceptsJinenStep(0.020 + margin, zenzaiStep: 0.020))
        #expect(!AzooKeyConverterEngine.acceptsJinenStep(0.021 + margin, zenzaiStep: 0.020))
        #expect(AzooKeyConverterEngine.p95Seconds((1...20).map { .milliseconds($0) }) == 0.020)
        #expect(AzooKeyConverterEngine.p95Seconds([]) == 0)
    }

    @Test("自動は，起動や Space では測らず，打鍵の合間の 1 歩ずつ測って small・xsmall・使わないを決める", .enabled(if: hasModels))
    func decidesAutomaticVariant() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-fusion-\(UUID().uuidString)")
        let zenzai = try ZenzaiModel.verified(at: URL(fileURLWithPath: try #require(environment["HAJIME_ZENZAI_MODEL"])))
        let jinen = try JinenModel.verified(at: URL(fileURLWithPath: try #require(environment["HAJIME_JINEN_MODEL"])))
        // xsmall は HAJIME_FAST_JINEN_MODEL があれば読む．無ければファイルの無いものを置く(small が遅ければ使わないに決まる)
        let fast = try environment["HAJIME_FAST_JINEN_MODEL"].map { try JinenModel.verified(at: URL(fileURLWithPath: $0), variant: .xsmall) }
            ?? JinenModel(url: directory.appendingPathComponent(JinenModel.Variant.xsmall.fileName), variant: .xsmall)
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "fusion", zenzai: zenzai, jinen: jinen, fastJinen: fast)
        engine.warmUp()
        #expect(engine.automaticJinenModel == nil)
        let session = engine.makeSession()
        session.prepareFusion(for: "しらぬい")
        #expect(engine.automaticJinenModel == nil)
        #expect(!session.hasFusion(for: "しらぬい"))
        var steps = 0
        while engine.automaticJinenModel == nil, steps < 10_000 {
            _ = session.advanceFusion(for: "しらぬい")
            steps += 1
        }
        let decided = try #require(engine.automaticJinenModel)
        // Windows の PC などで，測った 1 歩の p95(ms)と決めた結果を確かめるために出す(入力内容は含まない)
        let times = try #require(engine.automaticJinenStepTimes)
        let fusion = times.fusion.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue)=\(String(format: "%.1f", $0.value * 1000))" }
        print("HAJIME_AUTOMATIC_JINEN \(decided.rawValue) zenzai=\(String(format: "%.1f", times.zenzai * 1000)) \(fusion.joined(separator: " ")) steps=\(steps)")
        switch decided {
        case .small: #expect(engine.resolvedJinenVariant == .small)
        case .xsmall: #expect(engine.resolvedJinenVariant == .xsmall)
        case .off, .automatic: #expect(engine.resolvedJinenVariant == nil)
        }
        // 決めたあとの打鍵の合間の歩は，合議に使う
        if decided != .off {
            while !session.advanceFusion(for: "しらぬい") {}
            #expect(session.hasFusion(for: "しらぬい"))
        }
        session.endComposition()
    }

    private func makeEngine() throws -> AzooKeyConverterEngine {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-fusion-\(UUID().uuidString)")
        let zenzai = try ZenzaiModel.verified(at: URL(fileURLWithPath: try #require(environment["HAJIME_ZENZAI_MODEL"])))
        let jinen = try JinenModel.verified(at: URL(fileURLWithPath: try #require(environment["HAJIME_JINEN_MODEL"])))
        let dictionary = URL(fileURLWithPath: try #require(environment["HAJIME_BUNDLED_DICTIONARY"]), isDirectory: true)
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "fusion", zenzai: zenzai, jinen: jinen, dictionaryDirectory: dictionary)
        // 合議の動きを確かめるので，大きさを決めておく(「自動」だと，GPU の無い CI では使わないに決まる)
        var settings = DefaultSettings.settings
        settings.jinenModel = .small
        engine.apply(settings)
        return engine
    }

    @Test("読みを辞書の語で作れる表記だけを読みにそろえる", .enabled(if: hasModels))
    func alignsOnlyMatchingText() throws {
        let engine = try makeEngine()
        #expect(engine.alignedText("養成を謳っていた", reading: "ようせいをうたっていた") == "養成を謳っていた")
        #expect(engine.alignedText("東京", reading: "あおき") == nil)
    }

    @Test("jinen の候補を読みにそろえ，2 つのモデルの点数で上回れば第 1 候補にする", .enabled(if: hasModels))
    func fusionReplacesFirstCandidate() throws {
        let engine = try makeEngine()
        let session = engine.makeSession()
        session.setLeftContext("入学案内に経営者２世の")
        let reading = "ようせいをうたっていた"
        session.prepareFusion(for: reading)
        #expect(session.hasFusion(for: reading))
        #expect(session.candidates(for: reading).first { $0.readingCount == reading.count }?.text == "養成を謳っていた")
        session.endComposition()
    }

    @Test("合議の結果は，左の文脈が変わったら捨てる", .enabled(if: hasModels))
    func fusionIsDroppedWhenContextChanges() throws {
        let engine = try makeEngine()
        let session = engine.makeSession()
        session.prepareFusion(for: "しらぬい")
        #expect(session.hasFusion(for: "しらぬい"))
        session.setLeftContext("今日は")
        #expect(!session.hasFusion(for: "しらぬい"))
        session.endComposition()
    }

    @Test("打鍵の合間に 1 歩ずつ進めても，一度に求めたのと同じ結果になる", .enabled(if: hasModels))
    func stepwiseMatchesAtOnce() throws {
        let engine = try makeEngine()
        let reading = "しらぬい"
        let atOnce = engine.makeSession()
        atOnce.prepareFusion(for: reading)
        let stepwise = engine.makeSession()
        var steps = 0
        while !stepwise.advanceFusion(for: reading) { steps += 1 }
        #expect(steps > 1)
        #expect(stepwise.candidates(for: reading).map(\.text) == atOnce.candidates(for: reading).map(\.text))
        atOnce.endComposition()
        stepwise.endComposition()
    }
}
