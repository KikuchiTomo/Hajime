import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeTestSupport
import Testing

/// 同梱の辞書で，促音を含む読みを Zenzai を使わずに変換し，文節の区切り・文節の第 1 候補・2〜5 番目の候補が崩れないことを確かめる．
/// Zenzai を使わない変換は，分岐図の文節の候補と，一覧の 2 番目から後ろに混ぜる候補に出る．辞書の語(促音で切った交ぜ書きの「はっ声」，
/// 名詞の「ッ」)や，活用の切れ端と漢字をつないだ候補(はっ再・じゅっ分・シュッ派つ．BrokenSpellings で除く)が上位に出ると，
/// 「はッ制したとかないのか」のような候補になる．
/// 辞書が要るので，環境変数 HAJIME_BUNDLED_DICTIONARY があるときだけ動かす(make test-zenzai)．Zenzai を使う確かめは，HAJIME_ZENZAI_MODEL もあるときだけ
@Suite("同梱の辞書の促音の語", .serialized, .enabled(if: ProcessInfo.processInfo.environment["HAJIME_BUNDLED_DICTIONARY"] != nil))
@MainActor
struct BundledDictionaryQualityTests {
    /// 読みと，Zenzai を使わない分岐図の文節(「｜」で区切る)．同梱の辞書を v0.5.1 と v0.5.2 にしたときの結果で，v0.2.0 から変わっていない
    private nonisolated static let segmentCases: [(reading: String, segments: String)] = [
        ("はっせいしたとかないのか", "発生したと｜かない｜のか"),
        ("はっぴょうした", "発表した"),
        ("いっしょにいく", "一緒に｜行く"),
        ("ろっぴゃくえん", "600円"),
        ("じゅっぷん", "10分"),
        ("はっけんした", "発見した"),
        ("せっていした", "設定した"),
        ("けっていした", "決定した"),
        ("がっこうにいく", "学校に｜行く"),
        ("ざっしをかう", "雑誌を｜買う"),
        ("きっぷをかった", "切符を｜買った"),
        ("いっぽんのえんぴつ", "1本の｜鉛筆"),
        ("はっさいのこども", "8歳の｜子供"),
        ("ちょっとまって", "ちょっと｜待って"),
        ("みっかかん", "3日間"),
        ("よっかめ", "4日目"),
        ("にっきをかく", "日記を｜書く"),
        ("ほっかいどうにいった", "北海道に｜行った"),
        ("せっかくだから", "せっかくだから"),
        ("しっぱいした", "失敗した"),
        ("はったつした", "発達した"),
        ("てっていてきに", "徹底的に"),
        ("じっけんのけっか", "実験の｜結果"),
        ("あっとうてきなしょうり", "圧倒的な｜勝利"),
        ("はっちゅうした", "発注した"),
        ("ひっこしをした", "引っ越しを｜した"),
        ("もっとはやく", "もっと早く"),
        ("きってをはる", "切手を｜貼る"),
        ("さっきょくした", "作曲した"),
        ("はっきりいって", "はっきり言って"),
        ("けっこんしき", "結婚式"),
    ]

    /// 辞書から除いた，促音で切った交ぜ書き(元の語の頭の漢字を読みのかなにした書き方)．どれも変換の候補の上位に出ない．
    /// v0.5.1 で足した辞書の語を，v0.5.2 で azooKey の辞書の語(てっ底・やっ介・ひっ算・まっ赤)を除いた．
    /// v0.5.3 で送りがなを落とした 1 字の名詞(待 の まち・考 の かんがえ)を除いた
    private nonisolated static let removedSpellings: [(reading: String, spellings: [String])] = [
        ("はっせい", ["はっ声", "はっ生", "ハッ声", "ハッ生"]),
        ("はっちゅう", ["はっ注", "ハッ注"]),
        ("けったい", ["けっ滞", "ケッ滞"]),
        ("はっかい", ["はっ会", "ハッ会"]),
        ("あっせい", ["アッ制"]),
        ("せっせい", ["セッ制", "セッ生"]),
        ("てってい", ["てっ底"]),
        ("やっかい", ["やっ介"]),
        ("ひっさん", ["ひっ算"]),
        ("まっか", ["まっ赤"]),
        ("まち", ["待"]),
        ("かんがえ", ["考"]),
    ]

    /// 辞書に残した，新聞の交ぜ書き(常用漢字になる前の表外字をかなにした書き方)．候補に出る
    private nonisolated static let keptSpellings: [(reading: String, spelling: String)] = [
        ("うっけつ", "うっ血"),
        ("ぼっぱつ", "ぼっ発"),
    ]

    /// 直す前に，分岐図の文節か一覧の 2〜5 番目に崩れた候補が出ていた読み(1 文字のカタカナの 落ち着けヨ・ソの・窓ヲ・発生スる，
    /// 拍の途中の字種の切り替えの フッた・ザッしを・テっきり，小さいかなの位置の 良ッた・打ァ・蛇ぁ・偽ゅー)
    private nonisolated static let brokenCases = [
        "おちつけよ", "ゆうびんきょくはとしょかんのとなりにある", "まいとしたくさんのじこがはっせいする", "かのじょはそのはなをとてもだいじにしている",
        "まどをあけてもかまわないでしょうか", "じこげんいんはまだはっきりしていない", "ちゅうこしゃにしてはこのねだんはややたかい",
        "なんにちもつづけてあめがふった", "ざっしをよむ", "てっきりそうだとおもった", "いまばっはをきいてるとこなんだ",
        "とむがいったことほんとうにしんじるの", "あしたはげつようだぁまじゆううつ", "じゃぁいくのはやめときましょう", "ぎゅーしてほしい",
        "とっきょをとる", "ねぇたのむからしんじてくれよ",
    ]

    /// 読みが促音で終わる数(はっ → 8・ろっ → 6)に，助数詞でない漢字の語をつないだ書き方．直す前は，はっせいし のほかは
    /// 分岐図の文節か一覧の 2〜5 番目に出ていた．はっせいし は，利用者が「8｜精子」と分かれた候補を見た読み
    private nonisolated static let numberCases: [(reading: String, spellings: [String])] = [
        ("はっせいし", ["8精子"]), ("はっせいしたとかないのか", ["8精子"]), ("ろっけん", ["6権", "6券", "6圏", "6犬", "6研", "6拳"]),
        ("はっちゅう", ["8中"]), ("はっこつ", ["8骨"]), ("ろっきん", ["6筋", "6金"]),
    ]

    /// 漢字と促音で終わる活用の形(良っ・行っ)に漢字の語をつないだ書き方．直す前は いっぷん の文節の 3・5 番目に出ていた
    private nonisolated static let sokuonStemCases: [(reading: String, spellings: [String])] = [
        ("いっぷん", ["良っ分", "好っ分", "善っ分", "行っ分"]), ("いっしょに", ["良っ所に", "良っ書に"]),
    ]

    /// 数と助数詞の書き方．数のあとの語の決まりで除かず，一覧の上位 5 に出る
    private nonisolated static let counterCases: [(reading: String, text: String)] = [
        ("はっぽん", "8本"), ("いっぷん", "1分"), ("じゅっかい", "10回"), ("ろっぽん", "6本"), ("ろっけん", "6件"), ("はっさい", "8歳"),
        // v0.5.3 で足した助数詞の音の変わる読み(匹 の ピキ・ビキ)
        ("ろっぴき", "6匹"), ("よんびき", "四匹"),
    ]

    /// 語末で前のかなの母音を伸ばす書き方．拍の途中の字種の切り替えとして除かず，一覧の上位 5 に出る
    private nonisolated static let elongationCases: [(reading: String, text: String)] = [
        ("だいじょうぶだよぉ", "大丈夫だよォ"), ("どうしてるかなぁ", "どうしてるかなァ"), ("そうだねぇ", "そうだねェ"),
    ]

    /// 2〜5 番目の候補に出てはいけない書き方のうち，決まり(BrokenSpellings)と別に書いた形．頭のかなを促音で切ってつないだ漢字(じゅっ分・はっ再)，
    /// ひらがなやカタカナのあとのカタカナの「ッ」に漢字が続くもの(はッ制・シュッ派つ・ハッ中)
    private static let brokenPatterns = ["[ぁ-ゖ]ッ", "[ァ-ヺ]ッ[一-鿿]", "^[ぁ-ゖァ-ヺ]{1,2}[っッ][一-鿿]"].map { try! Regex($0) }

    private static let engine: AzooKeyConverterEngine? = makeEngine(zenzai: false)
    /// Zenzai を使うエンジン(環境変数 HAJIME_ZENZAI_MODEL があるときだけ)
    private static let zenzaiEngine: AzooKeyConverterEngine? = makeEngine(zenzai: true)

    private static func makeEngine(zenzai: Bool) -> AzooKeyConverterEngine? {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["HAJIME_BUNDLED_DICTIONARY"] else { return nil }
        let model = zenzai ? environment["HAJIME_ZENZAI_MODEL"].flatMap { try? ZenzaiModel.verified(at: URL(fileURLWithPath: $0)) } : nil
        if zenzai, model == nil { return nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-dictionary-quality-\(UUID().uuidString)")
        return try? AzooKeyConverterEngine(memoryDirectory: directory, versionString: "dictionary-quality", zenzai: model,
                                           dictionaryDirectory: URL(fileURLWithPath: path, isDirectory: true))
    }

    /// 読みを打って Space を押し，打鍵の合間に求める候補も求めたあとの，分岐図の文節の文字・文節ごとの候補・一覧の候補を返す．
    /// 文節ごとの候補は，→ で注目を移しながら集める
    private func convert(_ reading: String, presentation: CandidatePresentation, zenzai: Bool = false) throws
        -> (columns: [String], alternatives: [[String]], entries: [String]) {
        let engine = try #require(zenzai ? Self.zenzaiEngine : Self.engine)
        var settings = DefaultSettings.settings
        settings.candidatePresentation = presentation
        settings.typoCorrection = .off
        // アプリと同じく，エンジンの候補に足す候補と除く候補の決まり(SupplementedConverter)と，検証木の採点を通す
        let engineSession = engine.makeSession()
        let store = FakeSettings(settings)
        let session = InputSession(converter: SupplementedConverter(engineSession, settings: store, calendar: FakeCalendar()), lexicon: FakeLexicon(),
                                   settings: store, scorer: engineSession)
        let keys = try #require(KanaRomanizer.keys(for: reading))
        for key in keys { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
        var columns: [String] = []
        var alternatives: [[String]] = []
        var entries: [String] = []
        func press(_ event: KeyEvent) {
            var actions = session.handle(event, context: InputContext()).actions
            for step in session.followUps(context: InputContext()) { actions += step() }
            var focused: [String]?
            for action in actions {
                switch action {
                case .showLattice(let panel):
                    if columns.isEmpty { columns = panel.columns.map(\.text) }
                    focused = panel.columns.first(where: \.isFocused)?.alternatives
                case .showCandidates(let panel):
                    entries = panel.entries.map(\.text)
                default:
                    break
                }
            }
            if let focused { alternatives.append(focused) }
        }
        press(KeyEvent(.space))
        if presentation == .automatic {
            for _ in columns.dropFirst() { press(KeyEvent(.right)) }
        }
        return (columns, alternatives, entries)
    }

    /// 2〜5 番目の候補のうち，促音で切った書き方のもの
    /// 2〜5 番目の候補のうち，崩れた書き方のもの(決まりと，それと別に書いた形)
    private func broken(in candidates: [String]) -> [String] {
        candidates.dropFirst().prefix(4).filter { text in
            Self.brokenPatterns.contains { text.contains($0) }
                || BrokenSpellings.isBroken(Candidate(text: text, readingCount: text.count, origin: .combined))
        }
    }

    @Test("Zenzai を使わない分岐図の文節の区切りと第 1 候補が崩れない", arguments: segmentCases)
    func segments(reading: String, segments: String) throws {
        #expect(try convert(reading, presentation: .automatic).columns.joined(separator: "｜") == segments)
    }

    @Test("辞書から除いた交ぜ書きが，読み全体の候補の上位 15 に出ない", arguments: removedSpellings)
    func removedSpellingsStayOut(reading: String, spellings: [String]) throws {
        let engine = try #require(Self.engine)
        let candidates = engine.makeSession().candidates(for: reading).filter { $0.readingCount == reading.count }.prefix(15).map(\.text)
        #expect(Set(candidates).isDisjoint(with: spellings), "候補: \(candidates)")
    }

    @Test("辞書に残した新聞の交ぜ書きは，読み全体の候補の上位 15 に出る", arguments: keptSpellings)
    func keptSpellingsStayIn(reading: String, spelling: String) throws {
        let engine = try #require(Self.engine)
        let candidates = engine.makeSession().candidates(for: reading).filter { $0.readingCount == reading.count }.prefix(15).map(\.text)
        #expect(candidates.contains(spelling), "候補: \(candidates)")
    }

    @Test("分岐図の文節ごとの候補と一覧の 2〜5 番目に，崩れた書き方(はッ制・じゅっ分・出発スる・自ャ)が出ない",
          arguments: segmentCases.map(\.reading) + brokenCases)
    func noBrokenCandidates(reading: String) throws {
        let automatic = try convert(reading, presentation: .automatic)
        #expect(automatic.alternatives.count == automatic.columns.count)
        for alternatives in automatic.alternatives {
            #expect(broken(in: alternatives).isEmpty, "文節の候補: \(alternatives.prefix(5))")
        }
        let list = try convert(reading, presentation: .list)
        #expect(broken(in: list.entries).isEmpty, "一覧の候補: \(list.entries.prefix(5))")
    }

    @Test("読みが促音で終わる数に助数詞でない語をつないだ書き方(8精子・6権・8中)は，文節と一覧の 2〜5 番目に出ない", arguments: numberCases)
    func noNumberBeforeNonCounter(reading: String, spellings: [String]) throws {
        try expectNoSpellings(reading: reading, spellings: spellings, zenzai: false)
    }

    @Test("Zenzai を使っても，読みが促音で終わる数に助数詞でない語をつないだ書き方は，文節と一覧の 2〜5 番目に出ない",
          .enabled(if: ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil), arguments: numberCases)
    func noNumberBeforeNonCounterWithZenzai(reading: String, spellings: [String]) throws {
        try #require(Self.zenzaiEngine != nil, "HAJIME_ZENZAI_MODEL のモデルが無い")
        try expectNoSpellings(reading: reading, spellings: spellings, zenzai: true)
    }

    private func expectNoSpellings(reading: String, spellings: [String], zenzai: Bool) throws {
        let automatic = try convert(reading, presentation: .automatic, zenzai: zenzai)
        let list = try convert(reading, presentation: .list, zenzai: zenzai)
        for candidates in automatic.alternatives + [list.entries] {
            let found = candidates.dropFirst().prefix(4).filter { text in spellings.contains { text.hasPrefix($0) } }
            #expect(found.isEmpty, "候補: \(candidates.prefix(5))")
        }
    }

    @Test("促音で終わる活用の形に漢字の語をつないだ書き方(良っ分・良っ所に)は，文節と一覧の 2〜5 番目に出ない", arguments: sokuonStemCases)
    func noKanjiAfterSokuonStem(reading: String, spellings: [String]) throws {
        try expectNoSpellings(reading: reading, spellings: spellings, zenzai: false)
        if Self.zenzaiEngine != nil {
            try expectNoSpellings(reading: reading, spellings: spellings, zenzai: true)
        }
        // 1分 は第 1 候補のまま
        #expect(try convert(reading, presentation: .list).entries.first == (reading == "いっぷん" ? "1分" : "一緒に"))
    }

    @Test("数と助数詞(8本・1分・10回・6本・6件・8歳・6匹・四匹)は除かず，一覧の上位 5 に出る", arguments: counterCases)
    func keepsCounters(reading: String, text: String) throws {
        let list = try convert(reading, presentation: .list)
        #expect(list.entries.prefix(5).contains(text), "一覧の候補: \(list.entries.prefix(5))")
    }

    @Test("語末で母音を伸ばす書き方(大丈夫だよォ・どうしてるかなァ・そうだねェ)は除かず，一覧の上位 5 に出る", arguments: elongationCases)
    func keepsElongation(reading: String, text: String) throws {
        let list = try convert(reading, presentation: .list)
        #expect(list.entries.prefix(5).contains(text), "一覧の候補: \(list.entries.prefix(5))")
    }

    @Test("Zenzai を使っても，崩れた書き方(シュッ派つ・ハッ中・はっ駐・出発スる)は文節と一覧の 2〜5 番目に出ない",
          .enabled(if: ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil), arguments: segmentCases.map(\.reading) + brokenCases)
    func noRemovedCandidatesWithZenzai(reading: String) throws {
        try #require(Self.zenzaiEngine != nil, "HAJIME_ZENZAI_MODEL のモデルが無い")
        let automatic = try convert(reading, presentation: .automatic, zenzai: true)
        let list = try convert(reading, presentation: .list, zenzai: true)
        for candidates in automatic.alternatives + [list.entries] {
            #expect(broken(in: candidates).isEmpty, "候補: \(candidates.prefix(5))")
        }
    }
}
