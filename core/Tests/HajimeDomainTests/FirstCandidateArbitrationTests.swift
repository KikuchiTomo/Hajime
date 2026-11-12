import HajimeDomain
import Testing

@Suite("2 つのモデルで第 1 候補を決める規則")
struct FirstCandidateArbitrationTests {
    private func scores(_ currentByMain: Double, _ challengerByMain: Double, _ currentByOther: Double, _ challengerByOther: Double)
        -> FirstCandidateArbitration.Scores {
        FirstCandidateArbitration.Scores(currentByMain: currentByMain, challengerByMain: challengerByMain,
                                         currentByOther: currentByOther, challengerByOther: challengerByOther)
    }

    @Test("別のモデルの点数を重み付きで足し，差を超えて上回ったときだけ選ぶ")
    func prefersWhenAboveMargin() {
        // 主のモデル: -1 と -3．別のモデル: -10 と -1．重み 0.5 で -6 と -3.5，差 2.5
        #expect(FirstCandidateArbitration.prefersChallenger(scores(-1, -3, -10, -1), weight: 0.5, margin: 2))
        #expect(!FirstCandidateArbitration.prefersChallenger(scores(-1, -3, -10, -1), weight: 0.5, margin: 3))
    }

    @Test("同じモデルの点数だけでは選び直さない(重み 0 なら主のモデルの差で決まる)")
    func mainModelAlone() {
        #expect(!FirstCandidateArbitration.prefersChallenger(scores(-1, -2, -9, -1), weight: 0, margin: 0))
        #expect(FirstCandidateArbitration.prefersChallenger(scores(-3, -1, -9, -9), weight: 0, margin: 1))
    }

    @Test("点数が数でなければ選ばない")
    func nonFinite() {
        #expect(!FirstCandidateArbitration.prefersChallenger(scores(-.infinity, -1, -1, -1), weight: 0.5, margin: 0))
        #expect(!FirstCandidateArbitration.prefersChallenger(scores(-1, .nan, -1, -1), weight: 0.5, margin: 0))
    }
}
