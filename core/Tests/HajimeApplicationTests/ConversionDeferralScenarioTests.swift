import HajimeApplication
import HajimeDomain
import HajimeTestSupport
import Testing

/// 打っているあいだの変換を裏で求め，キーの処理では待たない(InputSession.setConversionArrivalHandler)．
/// キーにはすぐ応え，変換は届いたときに出し直す．待って求めたときと同じ文になることを確かめる
@Suite("打鍵を待たせずに変換する")
@MainActor
struct ConversionDeferralScenarioTests {
    private func converter() -> FakeConverter {
        let converter = FakeConverter([
            "きょ": [("巨", nil)], "きょう": [("今日", nil), ("京", nil)], "きょうは": [("今日は", nil)], "きょうはあ": [("今日はあ", nil)],
            "きょうはあめ": [("今日は雨", nil), ("今日は飴", nil)],
        ])
        return converter
    }

    @Test("まだ求めていない読みでは，前に見せた文にあとから打ったかなを足してすぐ見せ，届いたら変換した文に出し直す")
    func showsPreviousTextUntilArrival() {
        let harness = Harness(converter: converter())
        harness.deferConversions()
        harness.type("kyou")
        // 何も届いていないあいだは読みのまま
        #expect(harness.marked.text == "きょう")
        #expect(harness.session.awaitsConversion)
        harness.deliverConversions()
        #expect(harness.marked.text == "今日")
        #expect(!harness.session.awaitsConversion)
        harness.type("ha")
        // 「きょうは」はまだ届いていない．前に見せた「今日」に「は」を足して見せる
        #expect(harness.marked.text == "今日は")
        harness.type("ame")
        #expect(harness.marked.text == "今日はあめ")
        harness.deliverConversions()
        #expect(harness.marked.text == "今日は雨")
    }

    @Test("キーの処理では変換を求めない．求めるのは届けるときと，待ってよい操作(確定)のときだけ")
    func keysDoNotConvert() {
        let harness = Harness(converter: converter())
        harness.deferConversions()
        harness.type("kyouhaame")
        #expect(harness.converter.requests.isEmpty)
        harness.press(.enter)
        #expect(harness.committed == "今日は雨")
    }

    @Test("届く前に確定しても，待って求めたときと同じ文になる")
    func commitBeforeArrivalMatchesBlocking() {
        let deferred = Harness(converter: converter())
        deferred.deferConversions()
        let blocking = Harness(converter: converter())
        for harness in [deferred, blocking] {
            harness.type("kyouhaame")
            harness.press(.enter)
        }
        #expect(deferred.committed == blocking.committed)
        #expect(deferred.committed == "今日は雨")
    }

    @Test("届く前に Space を押すと，待って求めた変換で候補を出す")
    func convertBeforeArrival() {
        let deferred = Harness(converter: converter(), settings: .listPresentation)
        deferred.deferConversions()
        let blocking = Harness(converter: converter(), settings: .listPresentation)
        for harness in [deferred, blocking] {
            harness.type("kyouhaame")
            harness.press(.space)
        }
        #expect(deferred.panel?.entries.map(\.text) == blocking.panel?.entries.map(\.text))
        #expect(deferred.marked.text == blocking.marked.text)
    }

    @Test("打鍵が止まったときは，届いていなくても待って求めた変換を見せる")
    func settleWaits() {
        let harness = Harness(converter: converter())
        harness.deferConversions()
        harness.type("kyouhaame")
        #expect(harness.marked.text == "きょうはあめ")
        harness.settle()
        #expect(harness.marked.text == "今日は雨")
    }

    @Test("届いたときに読みが変わっていたら，届いた変換を今の読みの先頭に使う")
    func lateArrivalAnchorsPrefix() {
        let harness = Harness(converter: converter())
        harness.deferConversions()
        harness.type("kyouha")
        harness.deliverConversions()
        #expect(harness.marked.text == "今日は")
        harness.type("a")
        #expect(harness.marked.text == "今日はあ")
        harness.type("me")
        // 「きょうはあ」を届ける前に打ち進めた．届いても，今の読み「きょうはあめ」はまだ無いので前の文に足したまま
        #expect(harness.marked.text == "今日はあめ")
    }

    @Test("変換を待っているあいだ，入力中の候補のウィンドウは前に出したまま消さない")
    func keepsSuggestionWindowWhileAwaiting() {
        var settings = DefaultSettings.settings
        settings.suggestionDisplay = .always
        settings.liveConversion = false
        let harness = Harness(converter: converter(), settings: settings)
        harness.deferConversions()
        harness.type("kyou")
        harness.deliverConversions()
        #expect(harness.panel?.entries.map(\.text) == ["今日", "京"])
        harness.type("ha")
        // 「きょうは」の候補はまだ届いていない．前の候補を出したままにする
        #expect(harness.panel?.entries.map(\.text) == ["今日", "京"])
        harness.deliverConversions()
        #expect(harness.panel == nil || harness.panel?.entries.map(\.text) == ["今日は"])
    }

    @Test("入力を終えたあとに届いた前の入力の変換では，何も出さない")
    func arrivalAfterCommitDoesNothing() {
        let harness = Harness(converter: converter())
        harness.deferConversions()
        harness.type("kyou")
        harness.press(.enter)
        let committed = harness.committed
        harness.deliverConversions()
        #expect(harness.marked.text.isEmpty)
        #expect(harness.committed == committed)
    }

    @Test("「nn」のあとの母音の読みは，点数を待たずに打ち進めても，待って決めたときと同じ読みになる",
          arguments: ["hannnei", "onnna", "minnnanoikenn", "kannnousuru", "sinnnyuu"])
    func nasalReadingMatchesBlocking(keys: String) {
        func make() -> Harness {
            let converter = FakeConverter()
            // 「ん+な行」のほうがもっともらしい読みと，「ん+あ行」のほうがもっともらしい読みを混ぜる
            converter.scores = ["おんな": 5, "んな": 3, "みんな": 6, "はんえい": 7, "んえい": 4, "かんのう": 6, "しんにゅう": 6]
            return Harness(converter: converter)
        }
        let deferred = make()
        deferred.deferConversions()
        let blocking = make()
        for key in keys {
            deferred.press(.character(key))
            blocking.press(.character(key))
            // 次のキーの前に届くことも，届かないこともある．届かないまま打ち進めても同じになることを確かめるので届けない
        }
        deferred.press(.enter)
        blocking.press(.enter)
        #expect(deferred.committed == blocking.committed)
    }

    @Test("読みを待って決める前でも，届けば同じ読みになる")
    func nasalReadingAfterArrival() {
        func make() -> Harness {
            let converter = FakeConverter()
            converter.scores = ["おんな": 5, "んな": 3]
            return Harness(converter: converter)
        }
        let deferred = make()
        deferred.deferConversions()
        let blocking = make()
        for key in "onnna" {
            deferred.press(.character(key))
            deferred.deliverConversions()
            blocking.press(.character(key))
        }
        #expect(deferred.marked.text == blocking.marked.text)
    }

    @Test("ローマ字として読める英単語の見分け(読みのもっともらしさを使う)も，待たずに打ち進めて同じ結果になる",
          arguments: ["gitwotukau", "reactwotukau", "kyouhaame", "makewotukau"])
    func englishWordMatchesBlocking(keys: String) {
        func make() -> Harness {
            let converter = FakeConverter(["きょうはあめ": [("今日は雨", nil)], "をつかう": [("を使う", nil)], "ぎtをつかう": [("ぎtを使う", nil)]])
            converter.scores = ["をつかう": -2, "ぎtをつかう": -30, "れあctをつかう": -40, "まけをつかう": -6]
            return Harness(converter: converter, lexicon: FakeLexicon(words: ["git", "react", "make", "two"]))
        }
        let deferred = make()
        deferred.deferConversions()
        let blocking = make()
        for key in keys {
            deferred.press(.character(key))
            blocking.press(.character(key))
        }
        deferred.press(.enter)
        blocking.press(.enter)
        #expect(deferred.committed == blocking.committed)
    }
}

extension ConversionDeferralScenarioTests {
    @Test("予測する読みを決める変換を待っているあいだは予測を求めず，届いたあとに求めて出す")
    func predictionWaitsForConversion() {
        let converter = FakeConverter(["きょう": [("今日", nil), ("京", nil)]])
        converter.predictionTexts["きょう"] = ["今日は", "教室"]
        var settings = DefaultSettings.settings
        settings.predictionDisplay = .always
        let harness = Harness(converter: converter, settings: settings)
        harness.deferConversions()
        harness.type("kyou")
        // 変換が届く前は，予測を求める手順が無い
        #expect(harness.session.followUps(context: harness.context).isEmpty)
        #expect(harness.prediction == nil)
        harness.deliverConversions()
        #expect(harness.session.needsFollowUpsAfterArrival)
        harness.followUp()
        #expect(harness.prediction != nil)
    }
}
