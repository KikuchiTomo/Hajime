import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeTestSupport
import Testing

/// 同梱の辞書で，促音を含む読みを Zenzai を使わずに変換し，文節の区切り・文節の第 1 候補・2〜5 番目の候補が崩れないことを確かめる．
/// Zenzai を使わない変換は，分岐図の文節の候補と，一覧の 2 番目から後ろに混ぜる候補に出る．辞書の語(促音で切った交ぜ書きの「はっ声」，
/// 名詞の「ッ」)や，活用の切れ端と漢字をつないだ候補(はっ再・じゅっ分・シュッ派つ．SokuonFragments で除く)が上位に出ると，
/// 「はッ制したとかないのか」のような候補になる．
/// 辞書が要るので，環境変数 HAJIME_BUNDLED_DICTIONARY があるときだけ動かす(make test-zenzai)．Zenzai を使う確かめは，HAJIME_ZENZAI_MODEL もあるときだけ
@Suite("同梱の辞書の促音の語", .serialized, .enabled(if: ProcessInfo.processInfo.environment["HAJIME_BUNDLED_DICTIONARY"] != nil))
@MainActor
struct BundledDictionaryQualityTests {
    /// 読みと，Zenzai を使わない分岐図の文節(「｜」で区切る)．同梱の辞書を v0.5.1 にしたときの結果で，v0.2.0 から変わっていない
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

    /// 辞書から除いた，促音で切った交ぜ書き(元の語の頭の漢字を読みのかなにした書き方)．どれも変換の候補の上位に出ない
    private nonisolated static let removedSpellings: [(reading: String, spellings: [String])] = [
        ("はっせい", ["はっ声", "はっ生", "ハッ声", "ハッ生"]),
        ("はっちゅう", ["はっ注", "ハッ注"]),
        ("けったい", ["けっ滞", "ケッ滞"]),
        ("はっかい", ["はっ会", "ハッ会"]),
        ("あっせい", ["アッ制"]),
        ("せっせい", ["セッ制", "セッ生"]),
    ]

    /// 2〜5 番目の候補に出てはいけない書き方(SokuonFragments)．ひらがなのあとのカタカナの促音(はッ制・きッぷ)，カタカナの促音のあとの漢字
    /// (イッ所・ハッ中)，頭のかなを促音で切ってつないだ漢字(じゅっ分・はっ再)
    private static let brokenPatterns = ["[ぁ-ゖ]ッ", "ッ[一-鿿]", "^[ぁ-ゖァ-ヺ]{1,2}[っッ][一-鿿]"].map { try! Regex($0) }
    /// どの位置にも出してはいけない書き方(SokuonFragments で除く)．ひらがなのあとのカタカナの「ッ」(はッ制)，カタカナか漢字の「ッ」の
    /// 切れ端に漢字をつないだもの(シュッ派つ・ハッ中・良ッ書)，頭のかなを促音で切ってつないだ漢字(じゅっ分・はっ駐)
    private static let removedPatterns = ["[ぁ-ゖ]ッ", "[ァ-ヺ一-鿿]ッ[一-鿿]", "^[ぁ-ゖァ-ヺ]{1,2}[っッ][一-鿿]"].map { try! Regex($0) }

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
    private func broken(in candidates: [String]) -> [String] {
        candidates.dropFirst().prefix(4).filter { text in Self.brokenPatterns.contains { text.contains($0) } }
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

    @Test("分岐図の文節ごとの候補と一覧の 2〜5 番目に，促音で切った書き方(はッ制・じゅっ分・いッ所)が出ない", arguments: segmentCases.map(\.reading))
    func noBrokenCandidates(reading: String) throws {
        let automatic = try convert(reading, presentation: .automatic)
        #expect(automatic.alternatives.count == automatic.columns.count)
        for alternatives in automatic.alternatives {
            #expect(broken(in: alternatives).isEmpty, "文節の候補: \(alternatives.prefix(5))")
        }
        let list = try convert(reading, presentation: .list)
        #expect(broken(in: list.entries).isEmpty, "一覧の候補: \(list.entries.prefix(5))")
    }

    @Test("Zenzai を使っても，促音の切れ端をつないだ候補(シュッ派つ・ハッ中・はっ駐)は文節と一覧の 2 番目から後ろに出ない",
          .enabled(if: ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil), arguments: segmentCases.map(\.reading))
    func noRemovedCandidatesWithZenzai(reading: String) throws {
        try #require(Self.zenzaiEngine != nil, "HAJIME_ZENZAI_MODEL のモデルが無い")
        let automatic = try convert(reading, presentation: .automatic, zenzai: true)
        let list = try convert(reading, presentation: .list, zenzai: true)
        for candidates in automatic.alternatives + [list.entries] {
            let removed = candidates.dropFirst().filter { text in Self.removedPatterns.contains { text.contains($0) } }
            #expect(removed.isEmpty, "候補: \(candidates)")
        }
    }
}
