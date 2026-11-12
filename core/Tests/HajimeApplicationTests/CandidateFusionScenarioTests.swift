import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 別のモデルとの合議(ADR 0016 の案 2)．Space で第 1 候補を決める前に合議を求め，遅い環境では打鍵の合間に求めた結果だけを使う
@MainActor
@Suite("別のモデルとの合議")
struct CandidateFusionScenarioTests {
    /// 「あめ」1 文節．Zenzai の変換の候補は 雨・亜目
    private func converter() -> FakeConverter {
        FakeConverter(["あめ": [("雨", nil), ("亜目", nil)]], clauses: ["あめ": [("雨", 2), ("飴", 2)]])
    }

    private var listSettings: Settings {
        var settings = DefaultSettings.settings
        settings.candidatePresentation = .list
        settings.listSegmentAlternatives = false
        return settings
    }

    @Test("Space で合議を求め，上回った別のモデルの候補を第 1 候補にする")
    func spaceUsesFusion() {
        let fake = converter()
        let fuser = FakeCandidateFuser(converter: fake, results: ["あめ": ("飴", true)])
        let harness = Harness(converter: fake, fusing: fuser)
        harness.type("ame")
        harness.press(.space)
        #expect(fuser.prepared == ["あめ"])
        #expect(harness.lattice?.columns.map(\.text) == ["飴"])
    }

    @Test("一覧では，上回らなかった別のモデルの候補を 2 番目に置く")
    func listPlacesSecond() {
        let fake = converter()
        let fuser = FakeCandidateFuser(converter: fake, results: ["あめ": ("飴", false)])
        let harness = Harness(converter: fake, settings: listSettings, fusing: fuser)
        harness.type("ame")
        harness.press(.space)
        #expect(harness.panel?.entries.prefix(2).map(\.text) == ["雨", "飴"])
    }

    @Test("設定でオフなら合議しない")
    func settingOff() {
        let fake = converter()
        let fuser = FakeCandidateFuser(converter: fake, results: ["あめ": ("飴", true)])
        var settings = DefaultSettings.settings
        settings.jinenModel = .off
        let harness = Harness(converter: fake, settings: settings, fusing: fuser)
        harness.type("ame")
        harness.settle()
        harness.session.latticeWarmingSteps.forEach { $0() }
        harness.press(.space)
        #expect(fuser.prepared.isEmpty)
        #expect(fuser.steps.isEmpty)
        #expect(harness.lattice?.columns.map(\.text) == ["雨"])
    }

    @Test("合議が遅い環境では Space で待たず，打鍵の合間に求め終えた結果だけを使う")
    func slowEnvironmentUsesPrecomputed() {
        let fake = converter()
        let fuser = FakeCandidateFuser(converter: fake, results: ["あめ": ("飴", true)])
        fuser.prefersPrecomputedFusion = true
        let cold = Harness(converter: fake, fusing: fuser)
        cold.type("ame")
        cold.press(.space)
        #expect(fuser.prepared.isEmpty)
        #expect(cold.lattice?.columns.map(\.text) == ["雨"])

        let warmed = Harness(converter: fake, fusing: fuser)
        warmed.type("ame")
        warmed.settle()
        warmed.session.latticeWarmingSteps.forEach { $0() }
        warmed.press(.space)
        #expect(fuser.prepared.isEmpty)
        #expect(warmed.lattice?.columns.map(\.text) == ["飴"])
    }

    @Test("打鍵の合間の手順は，合議を分岐図の下見より先に 1 歩ずつ進める")
    func warmingAdvancesFusionFirst() {
        let fake = converter()
        let fuser = FakeCandidateFuser(converter: fake, results: [:], stepsToFinish: 2)
        let harness = Harness(converter: fake, fusing: fuser)
        harness.type("ame")
        harness.settle()
        let steps = harness.session.latticeWarmingSteps
        steps.first?()
        #expect(fuser.steps["あめ"] == 1)
        #expect(!fuser.hasFusion(for: "あめ"))
        steps.dropFirst().forEach { $0() }
        #expect(fuser.hasFusion(for: "あめ"))
        #expect(fuser.steps["あめ"] == 2)
    }
}
