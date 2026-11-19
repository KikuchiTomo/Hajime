import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 打鍵が止まったあとの処理(止まったときの表示・分岐図の下見)に使う変換を，メインスレッドで待たずに裏で求めておく
/// (InputSession.prepareSettle・prepareWarming)．求めているあいだに来たキーを待たせないための作りで，見せる文と確定する文は変えない
@Suite("打鍵が止まったあとの処理に使う変換を裏で求める")
@MainActor
struct IdlePreparationScenarioTests {
    private func converter() -> FakeConverter {
        FakeConverter([
            "きょう": [("今日", nil), ("京", nil)], "きょうは": [("今日は", nil)], "きょうはあめ": [("今日は雨", nil), ("今日は飴", nil)],
            "きょうん": [("今日ん", nil)], "まけ": [("負け", nil)], "か": [("蚊", nil)], "かん": [("缶", nil)],
        ])
    }

    @Test("止まったときの表示に使う変換は，届くまで裏で求め，メインスレッドでは求めない")
    func settleConversionIsPrefetched() {
        let harness = Harness(converter: converter())
        harness.deferConversions()
        harness.type("kyouhaame")
        #expect(!harness.session.prepareSettle())
        #expect(harness.converter.prefetched == ["きょうはあめ"])
        #expect(harness.converter.requests.isEmpty)
        // 届くまでは何度確かめても同じ(求め直さず，待たない)
        #expect(!harness.session.prepareSettle())
        #expect(harness.converter.requests.isEmpty)
        harness.deliverConversions()
        #expect(harness.session.prepareSettle())
    }

    @Test("裏で求め終えてから止まったときの表示を出しても，待って求めたときと同じ文になる", arguments: ["kyouhaame", "kyou", "make", "kan", "kyoun"])
    func settleAfterPreparationMatchesBlocking(keys: String) {
        func make() -> Harness { Harness(converter: converter(), lexicon: FakeLexicon(words: ["make", "can"])) }
        let prepared = make()
        prepared.deferConversions()
        let blocking = make()
        prepared.type(keys)
        blocking.type(keys)
        for _ in 0..<4 where !prepared.session.prepareSettle() { prepared.deliverConversions() }
        #expect(prepared.session.prepareSettle())
        prepared.settle()
        blocking.settle()
        #expect(prepared.marked == blocking.marked)
        prepared.press(.enter)
        blocking.press(.enter)
        #expect(prepared.committed == blocking.committed)
    }

    @Test("裏で求め終える前に止まったときの表示を出しても，待って求めたときと同じ文になる")
    func settleBeforePreparationMatchesBlocking() {
        let prepared = Harness(converter: converter())
        prepared.deferConversions()
        let blocking = Harness(converter: converter())
        prepared.type("kyouhaame")
        blocking.type("kyouhaame")
        #expect(!prepared.session.prepareSettle())
        prepared.settle()
        blocking.settle()
        #expect(prepared.marked == blocking.marked)
    }

    @Test("英語にも日本語にも読める語を見分けるための変換と読みのもっともらしさも，裏で求める")
    func classificationIsPrefetched() {
        let harness = Harness(converter: converter(), lexicon: FakeLexicon(words: ["make"]))
        harness.deferConversions()
        harness.type("make")
        #expect(!harness.session.prepareSettle())
        #expect(harness.converter.prefetched == ["まけ"])
        #expect(harness.converter.pendingDeferred.contains("p:まけ"))
        harness.deliverConversions()
        #expect(harness.session.prepareSettle())
        let requests = harness.converter.requests.count
        harness.settle()
        // 止まったときの処理は，届いた変換を使う(「まけ」を求め直さない)
        #expect(!harness.converter.requests.dropFirst(requests).contains { $0.reading == "まけ" && $0.typing })
    }

    private func nasalConverter() -> FakeConverter {
        let converter = FakeConverter()
        // 「ん+な行」のほうがもっともらしい読みと，「ん+あ行」のほうがもっともらしい読みを混ぜる
        converter.scores = ["おんな": 5, "んな": 3, "みんな": 6, "はんえい": 7, "んえい": 4, "かんのう": 6, "しんにゅう": 6,
                            "こうしんおねがいします": 8, "こうしんのねがいします": 2]
        return converter
    }

    @Test("「nn」のあとの母音の読みを選び直すための点数も裏で求め，待って選び直したときと同じ読みになる",
          arguments: ["onnna", "hannnei", "minnnanoikenn", "kannnousuru", "sinnnyuu", "kousinnonegaisimasu"])
    func nasalScoresArePrefetched(keys: String) {
        let prepared = Harness(converter: nasalConverter())
        prepared.deferConversions()
        let blocking = Harness(converter: nasalConverter())
        for key in keys {
            prepared.press(.character(key))
            prepared.deliverConversions()
            blocking.press(.character(key))
        }
        for _ in 0..<12 where !prepared.session.prepareSettle() { prepared.deliverConversions() }
        #expect(prepared.session.prepareSettle())
        prepared.settle()
        blocking.settle()
        #expect(prepared.marked == blocking.marked)
        prepared.press(.enter)
        blocking.press(.enter)
        #expect(prepared.committed == blocking.committed)
    }

    @Test("打ち終えた読みの前後を広く見て比べる点数は，届くまで裏で求める")
    func settledNasalScoresWaitForArrival() {
        let harness = Harness(converter: nasalConverter())
        harness.deferConversions()
        for key in "kousinnonegaisimasu" {
            harness.press(.character(key))
            harness.deliverConversions()
        }
        #expect(!harness.session.prepareSettle())
        #expect(harness.converter.pendingDeferred.contains { $0.hasPrefix("p:") })
        for _ in 0..<12 where !harness.session.prepareSettle() { harness.deliverConversions() }
        #expect(harness.session.prepareSettle())
    }

    @Test("表示の読み(か)と見分ける読み(かん)が違うときは，見分ける読みだけを求める(2 つの読みを交互に求めない)")
    func prefetchesOneReadingPerPause() {
        let harness = Harness(converter: converter(), lexicon: FakeLexicon(words: ["can"]))
        harness.deferConversions()
        harness.type("kan")
        #expect(!harness.session.prepareSettle())
        #expect(!harness.session.prepareSettle())
        #expect(Set(harness.converter.prefetched) == ["かん"])
    }

    @Test("変換を裏で求めない作り(届いたときの処理を入れていない)では，今までどおり止まったときの処理の中で求める")
    func blockingSessionNeedsNoPreparation() {
        let harness = Harness(converter: converter())
        harness.type("kyouhaame")
        #expect(harness.session.prepareSettle())
        #expect(harness.session.prepareWarming())
        #expect(harness.converter.prefetched.isEmpty)
    }

    @Test("下見に使う読み全体の変換は，届くまで裏で求める．末尾の「n」は「ん」として求める")
    func warmingConversionIsPrefetched() {
        let harness = Harness(converter: converter())
        harness.deferConversions()
        harness.type("kyoun")
        harness.deliverConversions()
        harness.settle()
        let before = harness.converter.prefetched.count
        #expect(!harness.session.prepareWarming())
        #expect(harness.converter.prefetched.dropFirst(before) == ["きょうん"])
        harness.deliverConversions()
        #expect(harness.session.prepareWarming())
        #expect(!harness.session.latticeWarmingSteps.isEmpty)
    }

    @Test("ローマ字を打ちかけている読みの下見に使う変換も，今までと同じ読みを裏で求める")
    func prefetchesPendingRomajiReading() {
        let harness = Harness(converter: converter())
        harness.deferConversions()
        harness.type("kyouhak")
        harness.deliverConversions()
        harness.settle()
        let requests = harness.converter.requests.count
        #expect(!harness.session.prepareWarming())
        #expect(harness.converter.prefetched.last == "きょうはk")
        // メインスレッドでは求めていない
        #expect(harness.converter.requests.count == requests)
        harness.deliverConversions()
        #expect(harness.session.prepareWarming())
        #expect(!harness.session.latticeWarmingSteps.isEmpty)
    }

    @Test("裏で求め終えてから下見をしても，待って求めて下見をしたときと同じ候補を出す", arguments: ["kyouhaame", "kyouhak", "kyoun"])
    func warmingAfterPreparationMatchesBlocking(keys: String) {
        func make() -> Harness {
            let converter = converter()
            converter.table["きょうはk"] = [("今日はk", nil)]
            return Harness(converter: converter, settings: .listPresentation)
        }
        let prepared = make()
        prepared.deferConversions()
        let blocking = make()
        for harness in [prepared, blocking] { harness.type(keys) }
        for _ in 0..<4 where !prepared.session.prepareSettle() { prepared.deliverConversions() }
        for harness in [prepared, blocking] { harness.settle() }
        for _ in 0..<4 where !prepared.session.prepareWarming() { prepared.deliverConversions() }
        for harness in [prepared, blocking] {
            harness.session.latticeWarmingSteps.forEach { $0() }
            harness.press(.space)
        }
        #expect(prepared.panel?.entries.map(\.text) == blocking.panel?.entries.map(\.text))
        #expect(prepared.marked == blocking.marked)
    }
}
