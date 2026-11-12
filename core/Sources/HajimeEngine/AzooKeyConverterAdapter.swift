import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary
import HajimeApplication
import HajimeDomain

/// 渡された辞書のディレクトリが辞書として読めない(louds/charID.chid が無い)
public enum DictionaryDirectoryError: Error, Equatable {
    case notFound
}

/// 辞書と学習データを持つ変換エンジン．アプリ全体で 1 つ作り，入力欄ごとのセッションを渡す．
///
/// azooKey の型はこのモジュールの外に出さない(docs/dev/ARCHITECTURE.md)．
@MainActor
public final class AzooKeyConverterEngine {
    private let converter: KanaKanjiConverter
    private let memoryDirectory: URL
    private let versionString: String
    /// 精度を優先するモデル(small)と，速さを優先するモデル(xsmall)．どちらも確かめ済み．無ければ nil
    private let accurateZenzai: ZenzaiModel?
    private let fastZenzai: ZenzaiModel?
    /// 設定で選んだモデルの使い方(apply(_:) で入れ替える)
    private var zenzaiChoice = ZenzaiModelChoice.accurate
    /// 変換に効く設定(学習・日付・絵文字)．apply(_:) で入れ替える
    private var learningType: LearningType = .inputAndOutput
    /// 絵文字の辞書は読み込みが重いので，一度だけ作って使い回す
    private lazy var emojiReplacer = TextReplacer.withDefaultEmojiDictionary()
    private var usesEmoji = true
    private var userDictionary: [UserDictionaryEntry] = []
    /// 取り込んだ辞書から引いた語(R-16)．ユーザー辞書と合わせて動的な辞書としてエンジンに渡す
    private var auxiliaryWords: [AuxiliaryWord] = []
    /// Zenzai を使った変換にかかった時間の移動平均(秒)．まだ測っていなければ nil
    private var zenzaiCost: Double?
    /// 合議に使う別のモデル(jinen)の small と xsmall．確かめ済み．どちらも無ければ合議しない
    private let jinenModels: [JinenModel.Variant: JinenModel]
    /// 設定で選んだ jinen のモデル(apply(_:) で入れ替える)
    private var jinenChoice = JinenModelChoice.automatic
    /// 「自動」で決めた結果(small・xsmall・使わない)．起動のあと，打鍵の合間に 1 歩ずつ測って決める(advanceAutomaticJinenDecision)．まだ決めていなければ nil
    private var automaticJinenChoice: JinenModelChoice?
    /// 「自動」を決める測定の途中の状態．測っていなければ nil
    private var automaticJinenProbe: AutomaticJinenProbe?
    /// 「自動」を決めたときに測った 1 歩の p95(秒)．Zenzai だけと，試した jinen の大きさごと．テストで値を出すために持つ
    private(set) var automaticJinenStepTimes: (zenzai: Double, fusion: [JinenModel.Variant: Double])?
    /// 今読んでいる jinen の推論の文脈と，その大きさ．大きさを変えたら読み直す(メモリを抑えるため 1 つだけ持つ)
    private var jinenRunner: (variant: JinenModel.Variant, runner: ExperimentalJinen)?
    /// 読めなかった大きさ．読み直さない
    private var failedJinenVariants: Set<JinenModel.Variant> = []
    /// 合議 1 回(jinen の変換・読みにそろえる・採点)にかかった時間の移動平均(秒)
    private var fusionCost: Double?
    private var fusionCount = 0
    private var lastFusionTime: ContinuousClock.Instant?

    /// - Parameters:
    ///   - memoryDirectory: 学習データとユーザー辞書を置くディレクトリ．本人だけが読み書きできる権限で作る
    ///   - versionString: エンジンに渡すアプリのバージョンの文字列
    ///   - zenzai: 確かめ済みの Zenzai のモデル(small)．nil なら Zenzai を使わない
    ///   - fastZenzai: 確かめ済みの速さを優先する Zenzai のモデル(xsmall)．nil なら設定にかかわらず zenzai だけを使う
    ///   - dictionaryDirectory: かな漢字変換の辞書(louds/・cb/・p/・mm.binary を持つディレクトリ)．nil なら azooKey に同梱の辞書を使う
    ///   - jinen: 確かめ済みの jinen のモデル(small)．jinen と fastJinen の両方が nil なら合議しない(ADR 0016 の案 2)
    ///   - fastJinen: 確かめ済みの jinen のモデル(xsmall)
    public init(memoryDirectory: URL, versionString: String, zenzai: ZenzaiModel? = nil, fastZenzai: ZenzaiModel? = nil,
                jinen: JinenModel? = nil, fastJinen: JinenModel? = nil, dictionaryDirectory: URL? = nil) throws {
        // 辞書の場所を誤ると，エンジンは何も言わずに語の無い状態で動き，変換がほぼすべて読みのままになる．作る前に止める
        if let dictionaryDirectory {
            let charID = dictionaryDirectory.appendingPathComponent("louds/charID.chid", isDirectory: false)
            guard FileManager.default.fileExists(atPath: charID.path) else { throw DictionaryDirectoryError.notFound }
        }
        try FileManager.default.createDirectory(
            at: memoryDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.memoryDirectory = memoryDirectory
        self.versionString = versionString
        self.accurateZenzai = zenzai
        self.fastZenzai = fastZenzai
        self.jinenModels = [jinen, fastJinen].compactMap { $0 }.reduce(into: [:]) { $0[$1.variant] = $1 }
        self.converter = dictionaryDirectory.map { KanaKanjiConverter(dicdataStore: DicdataStore(dictionaryURL: $0)) } ?? KanaKanjiConverter.withDefaultDictionary()
    }

    /// 読みに合う絵文字(EmojiLooking)．肌の色などを変えた形は除く．パレットの表を持たない作り(Linux)で使う．
    /// azooKey の絵文字の辞書は，どの絵文字にも絵文字の形を選ぶ印(U+FE0F)を後ろに付けている(「😀」の後ろにも付き，
    /// 「🖐」には 2 つ付く)．同じ絵文字のエンジンの辞書の語と重なって見えたり，確定した文字に余計な印が入ったりしないよう，
    /// 要らない印を除く．azooKey の絵文字の辞書は名前を持たないので，文節の語(word)とは照らし合わせない
    public func emoji(for reading: String, word: EmojiWord, limit: Int) -> [String] {
        var seen = Set<String>()
        return emojiReplacer.getSearchResult(query: reading, target: [.emoji], ignoreNonBaseEmoji: true)
            .map { Self.withoutExtraEmojiStyle($0.text) }
            .filter { seen.insert($0).inserted }
            .prefix(max(limit, 0)).map { $0 }
    }

    /// 名前は持たない(パレットの表に名前がある)
    public func name(of emoji: String) -> String? { nil }

    /// 選んだ絵文字は覚えない(覚えるのはパレットの表を使うとき)
    public func didCommit(_ emoji: String, reading: String) {}

    /// 絵文字の形で描く字(Emoji_Presentation)のあとの U+FE0F と，続けて重なった U+FE0F を除く
    static func withoutExtraEmojiStyle(_ text: String) -> String {
        let style: Unicode.Scalar = "\u{FE0F}"
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar == style, let previous = scalars.last, previous == style || previous.properties.isEmojiPresentation { continue }
            scalars.append(scalar)
        }
        return String(scalars)
    }

    /// 入力欄ひとつぶんの変換．検証木の採点(CandidateScoring)と合議(CandidateFusing)も同じものが受け持つ
    public func makeSession() -> any KanaKanjiConverting & CandidateScoring & CandidateFusing {
        // 読みのもっともらしさを測る変換は，表示する変換と状態を混ぜないよう別のセッションで行う
        AzooKeyConverterSession(engine: self, sessionID: converter.createSession(), scoringSessionID: converter.createSession(),
                                typingSessionID: converter.createSession(), restSessionID: converter.createSession())
    }

    /// 最初の変換で Zenzai のモデルの準備が走るので，起動時に一度変換しておく．入力内容は使わない
    /// 入力中の表示で Zenzai を使わないか．Zenzai の変換が 1 キーの時間に収まらない環境(GPU の無い Windows など)だけ true
    var skipsZenzaiWhileTyping: Bool {
        !waitsForModels && Self.exceedsTypingBudget(zenzaiCost)
    }

    /// 評価の道具で，時間による切り替え(入力中の表示で Zenzai を使わない・採点と合議を Space で待たない)をすべてやめ，
    /// 言語モデルの結果を必ず待つ(マシンの負荷で評価の結果が変わらないように)．アプリでは使わない
    public var waitsForModels = false

    /// Zenzai を使った変換の時間を覚える(打鍵が止まったときや Space の変換も測り，速い環境に戻ったら入力中にも使う)
    func recordZenzaiCost(_ duration: Duration) {
        zenzaiCost = Self.smoothedCost(zenzaiCost, adding: duration)
    }

    nonisolated static func smoothedCost(_ current: Double?, adding duration: Duration) -> Double {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        guard let current else { return seconds }
        return current + (seconds - current) * DefaultSettings.zenzaiCostSmoothing
    }

    nonisolated static func exceedsTypingBudget(_ cost: Double?) -> Bool {
        (cost ?? 0) > DefaultSettings.zenzaiTypingBudget
    }

    /// 1 回の採点(検証木)で評価するトークンの数の上限．採点にかかった時間で増減し，1 回が DefaultSettings.candidateScoringBudget に
    /// 収まるようにする(GPU の無い Windows やほかの処理で混んでいるときは少なくなり，採点する候補が減る)
    public private(set) var candidateTreeTokenLimit = DefaultSettings.candidateTreeTokenLimit
    /// 評価の道具で，採点の時間によらず決まった数にするとき(負荷で結果が変わらないように)．アプリでは使わない
    public var fixedCandidateTreeTokenLimit: Int? {
        didSet { if let fixedCandidateTreeTokenLimit { candidateTreeTokenLimit = fixedCandidateTreeTokenLimit } }
    }

    /// 検証木の採点 1 回(プロンプトを評価し直す時間を含む)の時間の移動平均(秒)．まだ測っていなければ nil
    private var scoringCallCost: Double?
    /// 採点した回数．最初の 1 回は GPU の準備の時間を含むので，時間の平均に入れない
    private var scoringCallCount = 0
    /// 最後に採点した時刻．遅い環境とみなしたあとも，ときどき採点して速さを測り直すのに使う
    private var lastScoringTime: ContinuousClock.Instant?

    func recordScoringCallCost(_ duration: Duration) {
        scoringCallCount += 1
        lastScoringTime = .now
        guard scoringCallCount > 1 else { return }
        scoringCallCost = Self.smoothedCost(scoringCallCost, adding: duration)
    }

    /// 採点が遅い環境か．採点 1 回の時間の移動平均が DefaultSettings.candidateScoringSlowThreshold を超えたら，
    /// 打鍵の合間に前もって求めた点数だけを使う(Space で待たせない)．
    /// 最後の採点から DefaultSettings.candidateScoringProbeInterval たったら，次の 1 回は採点して速さを測り直す(混んでいたあと速さが戻るように)．
    /// 評価の道具でトークンの数を決めているときは，結果を負荷で変えないよう遅いとみなさない
    var prefersPrecomputedScores: Bool {
        guard !waitsForModels, fixedCandidateTreeTokenLimit == nil, (scoringCallCost ?? 0) > DefaultSettings.candidateScoringSlowThreshold else { return false }
        guard let lastScoringTime else { return true }
        return ContinuousClock.now - lastScoringTime < .seconds(DefaultSettings.candidateScoringProbeInterval)
    }

    /// 検証木で採点した時間を覚え，次の採点で評価するトークンの数の上限を決め直す．
    /// プロンプトを評価し直した回は，時間をトークンの数で按分し，木のぶんの時間だけで決める(プロンプトは同じ読みなら次は評価し直さない)
    func recordScoringCost(_ duration: Duration, treeTokens: Int, promptTokens: Int) {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        let treeSeconds = seconds * Double(treeTokens) / Double(max(treeTokens + promptTokens, 1))
        guard fixedCandidateTreeTokenLimit == nil else { return }
        candidateTreeTokenLimit = Self.nextCandidateTreeTokenLimit(current: candidateTreeTokenLimit, tokens: treeTokens, seconds: treeSeconds)
    }

    /// 目安を超えたら，時間がトークンの数に比例するとみて目安に収まる数まで減らす．上限近くまで使って目安より十分速く済んだら少し増やす．
    /// 1 トークンあたりの平均の時間で決めると，推論 1 回の決まった時間のぶん小さな木ほど割高に見え，上限が下がり続けるので使わない
    nonisolated static func nextCandidateTreeTokenLimit(current: Int, tokens: Int, seconds: Double) -> Int {
        let budget = DefaultSettings.candidateScoringBudget
        if seconds > budget {
            let affordable = Int(Double(max(tokens, 1)) * budget / seconds)
            return max(DefaultSettings.minimumCandidateTreeTokens, min(current, affordable))
        }
        if tokens * 10 >= current * 9, seconds < budget * DefaultSettings.candidateTreeGrowthMargin {
            return min(DefaultSettings.candidateTreeTokenLimit, Int(Double(current) * DefaultSettings.candidateTreeGrowth))
        }
        return current
    }

    /// jinen のモデルを「自動」にしたときに決めた結果(small・xsmall・使わない)．まだ決めていなければ nil．設定の画面に出す
    public var automaticJinenModel: JinenModelChoice? {
        automaticJinenChoice
    }

    /// 合議に使う jinen の大きさ．設定で選んだもの(「自動」なら測って決めたもの)．そのモデルが無ければもう一方．
    /// 使わない設定のとき，どちらのモデルも無いとき，「自動」でまだ決めていないか使わないと決めたときは nil
    public var resolvedJinenVariant: JinenModel.Variant? {
        let preferred: JinenModel.Variant
        switch jinenChoice {
        case .off: return nil
        case .small: preferred = .small
        case .xsmall: preferred = .xsmall
        case .automatic:
            switch automaticJinenChoice {
            case .small: preferred = .small
            case .xsmall: preferred = .xsmall
            case .automatic, .off, nil: return nil
            }
        }
        let other: JinenModel.Variant = preferred == .small ? .xsmall : .small
        return [preferred, other].first { jinenModels[$0] != nil && !failedJinenVariants.contains($0) }
    }

    /// 合議に使う jinen．使わないとき，モデルが無いとき，Zenzai を使わないとき，読めなかったとき，「自動」でまだ決めていないときは nil
    var jinen: ExperimentalJinen? {
        guard usesZenzai, jinenChoice != .off, !jinenModels.isEmpty else { return nil }
        guard let variant = resolvedJinenVariant else { return nil }
        return jinenRunner(variant)
    }

    /// その大きさの jinen を読む(前に読んだものと大きさが違えば，前のものを捨ててから読む)．読めなければ nil
    private func jinenRunner(_ variant: JinenModel.Variant) -> ExperimentalJinen? {
        if let jinenRunner, jinenRunner.variant == variant { return jinenRunner.runner }
        jinenRunner = nil
        guard let model = jinenModels[variant], !failedJinenVariants.contains(variant) else { return nil }
        do {
            let runner = try ExperimentalJinen(modelURL: model.url)
            jinenRunner = (variant, runner)
            return runner
        } catch {
            failedJinenVariants.insert(variant)
            return nil
        }
    }

    /// 「自動」の jinen を決める測定を 1 歩進める．打鍵の合間の手順(AzooKeyConverterSession.advanceFusion)から呼び，起動や Space では進めない．
    /// 打鍵の合間の 1 歩の時間で決める(次のキーはそのとき動いている 1 歩を待つため)．決まった読み(入力内容は使わない)で，
    /// Zenzai だけの 1 歩(分岐図の文節ごとの変換)と，合議の 1 歩(jinen の 1 トークン・読みにそろえる・Zenzai の採点・jinen の採点)を測り，
    /// 合議の 1 歩の p95 が Zenzai だけの 1 歩の p95 ＋ DefaultSettings.jinenAutomaticStepMargin 以下なら，その大きさにする．
    /// small から試し，超えれば xsmall，それも超えれば使わない．GPU の無い PC でも速ければ small になる．
    /// 測ることが無ければ(決め終えた，「自動」でない，モデルが無い)何もせず true，1 歩進めたら false
    func advanceAutomaticJinenDecision() -> Bool {
        guard jinenChoice == .automatic, automaticJinenChoice == nil, !jinenModels.isEmpty else { return true }
        guard usesZenzai else {
            automaticJinenChoice = .off
            return true
        }
        let probe = automaticJinenProbe ?? AutomaticJinenProbe(session: makeProbeSession(), readings: Self.automaticJinenReadings, warmUpReading: Self.warmUpReading,
                                                                variants: [.small, .xsmall].filter { jinenModels[$0] != nil })
        automaticJinenProbe = probe
        guard let unit = probe.units.first else { return finishAutomaticJinenDecision(.off) }
        let clock = ContinuousClock()
        switch unit {
        case .sentence(let reading):
            probe.units.removeFirst()
            let clauses = probe.session.clausesForMeasurement(reading).map(AutomaticJinenProbe.Unit.clause)
            probe.units.insert(contentsOf: clauses, at: 0)
        case .clause(let reading):
            probe.units.removeFirst()
            probe.zenzaiTimes.append(clock.measure { probe.session.convertForMeasurement(reading) })
        case .begin(let variant):
            probe.units.removeFirst()
            probe.begin(variant)
        case .fusion(let reading, let counted):
            guard let variant = probe.variant, let runner = jinenRunner(variant) else {
                // 読めなければ，この大きさは使えないものとして次を試す
                probe.units.removeAll {
                    if case .fusion = $0 { return true }
                    return false
                }
                return false
            }
            var finished = false
            let time = clock.measure { finished = probe.session.advanceFusion(for: reading, using: runner) }
            if counted { probe.fusionTimes.append(time) }
            if finished { probe.units.removeFirst() }
        case .judge(let variant):
            probe.units.removeFirst()
            let zenzaiStep = Self.p95Seconds(probe.zenzaiTimes)
            let step = probe.fusionTimes.isEmpty ? .infinity : Self.p95Seconds(probe.fusionTimes)
            automaticJinenStepTimes = (zenzaiStep, (automaticJinenStepTimes?.fusion ?? [:]).merging([variant: step]) { $1 })
            if Self.acceptsJinenStep(step, zenzaiStep: zenzaiStep) {
                _ = finishAutomaticJinenDecision(variant == .small ? .small : .xsmall)
            } else if probe.variants.isEmpty {
                jinenRunner = nil
                _ = finishAutomaticJinenDecision(.off)
            } else {
                probe.planNextVariant()
            }
        }
        return false
    }

    private func finishAutomaticJinenDecision(_ choice: JinenModelChoice) -> Bool {
        automaticJinenChoice = choice
        automaticJinenProbe?.session.endComposition()
        automaticJinenProbe = nil
        return true
    }

    /// 「自動」を測るための変換のセッション(入力に使うセッションと状態を混ぜない)
    private func makeProbeSession() -> AzooKeyConverterSession {
        AzooKeyConverterSession(engine: self, sessionID: converter.createSession(), scoringSessionID: converter.createSession(),
                                typingSessionID: converter.createSession(), restSessionID: converter.createSession())
    }

    /// 合議の 1 歩の p95 が，Zenzai だけの 1 歩の p95 ＋ DefaultSettings.jinenAutomaticStepMargin 以下か(「自動」でその大きさを使うか)
    nonisolated static func acceptsJinenStep(_ step: Double, zenzaiStep: Double) -> Bool {
        step <= zenzaiStep + DefaultSettings.jinenAutomaticStepMargin
    }

    /// 「自動」を決めるときに変換する読み(入力内容は使わない)
    private static let automaticJinenReadings = ["あしたのかいぎにしゅっせきします", "みんなのいけんをはんえいする", "でんしゃがおくれている"]

    nonisolated static func p95Seconds(_ durations: [Duration]) -> Double {
        guard !durations.isEmpty else { return 0 }
        let sorted = durations.sorted()
        let value = sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))]
        return Double(value.components.seconds) + Double(value.components.attoseconds) / 1e18
    }

    /// 言語モデルを CPU で推論する環境か(Windows の llama.cpp は CPU の DLL だけを入れている)
    static var infersOnCPU: Bool {
        #if os(Windows)
        true
        #else
        false
        #endif
    }

    /// 合議の 1 歩(推論 1 回など)にかかった時間を覚える
    func recordFusionStepCost(_ duration: Duration) {
        fusionCount += 1
        lastFusionTime = .now
        // 最初の数歩はモデルの準備を含むので数えない
        guard fusionCount > 3 else { return }
        fusionCost = Self.smoothedCost(fusionCost, adding: duration)
    }

    /// 合議が遅い環境か．1 歩の時間の移動平均が DefaultSettings.fusionSlowStepThreshold を超えたら，打鍵の合間に前もって求めた結果だけを使い，
    /// Space では求めない．最後の合議から DefaultSettings.candidateScoringProbeInterval たったら，次は Space でも求めて速さを測り直す
    var prefersPrecomputedFusion: Bool {
        // 評価の道具でトークンの数を決めているときは，結果を負荷で変えないよう遅いとみなさない(prefersPrecomputedScores と同じ)
        guard !waitsForModels, fixedCandidateTreeTokenLimit == nil else { return false }
        // CPU で推論する環境(Windows)では，Space で合議を待たない
        if Self.infersOnCPU { return true }
        guard (fusionCost ?? 0) > DefaultSettings.fusionSlowStepThreshold else { return false }
        guard let lastFusionTime else { return true }
        return ContinuousClock.now - lastFusionTime < .seconds(DefaultSettings.candidateScoringProbeInterval)
    }

    /// jinen だけで読みを変換する(評価の道具が 1 文の時間を測るのに使う)．使う大きさは設定の jinenModel で決まる．使えなければ nil
    public func jinenConversion(reading: String, leftContext: String?) -> String? {
        jinen?.convert(reading: reading, leftContext: leftContext ?? "", maximumLeftContextLength: DefaultSettings.maximumLeftContextLength)?.text
    }

    /// 表記を読みにそろえられるか(評価の道具用)．そろえた表記を返す．そろえられなければ nil
    public func alignedText(_ text: String, reading: String) -> String? {
        let session = makeSession()
        defer { session.endComposition() }
        return (session as? AzooKeyConverterSession)?.alignedText(text, reading: reading)
    }

    public func warmUp() {
        // 「自動」の jinen は起動では決めない．起動の直後のキーを待たせないよう，打鍵の合間に 1 歩ずつ測る(advanceAutomaticJinenDecision)
        let session = makeSession()
        _ = session.candidates(for: Self.warmUpReading)
        session.endComposition()
        // 最初の変換はモデルの準備の時間を含むので，Zenzai の時間として数えない
        zenzaiCost = nil
    }

    private static let warmUpReading = "きょうはいいてんきです"

    /// 学習データをファイルに書き出す．入力欄からフォーカスが外れたときなどに呼ぶ
    public func flushLearning() {
        guard learningType == .inputAndOutput else { return }
        restoreLearningConfig(converter)
        converter.stopComposition()
        converter.commitUpdateLearningData()
    }

    /// azooKey は学習の設定を変換器に 1 つだけ持ち，変換を求めるたびにその要求の設定で上書きする．学習を使わない要求
    /// (plausibility・語の区切り・辞書の候補)のあとに学習を書くと，「学習しない」設定のまま捨てられ，ファイルにも書き出されない
    /// (確定した語が次の変換で上に来ない)．学習を書く・忘れる・書き出す前に，今の学習の設定で 1 文字の軽い要求を通して設定を戻す
    fileprivate func restoreLearningConfig(_ converter: KanaKanjiConverter) {
        var composing = ComposingText()
        composing.insertAtCursorPosition(Self.learningConfigReading, inputStyle: .direct)
        var options = options(leftContext: nil, usesZenzai: false, candidateCount: 1)
        options.textReplacer = .empty
        options.specialCandidateProviders = []
        options.typoCorrectionMode = .disabled
        _ = converter.requestCandidates(composing, options: options)
    }

    private static let learningConfigReading = "あ"

    /// 学んだことをすべて消す
    public func resetLearning() {
        converter.resetMemory()
    }

    /// 変換に効く設定を入れる．設定が変わるたびに呼ぶ
    public func apply(_ settings: Settings) {
        learningType = switch settings.learning {
        case .enabled: .inputAndOutput
        case .readOnly: .onlyOutput
        case .disabled: .nothing
        }
        usesEmoji = settings.emojiConversion
        jinenChoice = settings.jinenModel
        if jinenChoice != .automatic, let probe = automaticJinenProbe {
            // 「自動」でなくなったら測るのをやめる(「自動」に戻したら初めから測る)
            probe.session.endComposition()
            automaticJinenProbe = nil
        }
        if settings.zenzaiModel != zenzaiChoice {
            zenzaiChoice = settings.zenzaiModel
            // 測った時間は前のモデルのものなので，選び直したモデルで測り直す
            zenzaiCost = nil
            candidateTreeTokenLimit = DefaultSettings.candidateTreeTokenLimit
            scoringCallCost = nil
            scoringCallCount = 0
            lastScoringTime = nil
        }
        // かなにならない読み(「gh」)と，入れる時に中身を決める語(TextTemplate)は，文の中の語として渡さない．
        // SupplementedConverter が読み全体の一致で候補に出す
        let entries = settings.userDictionary
            .filter { $0.isValid && $0.hasKanaReading && !(settings.dynamicDictionary && TextTemplate.containsPlaceholder($0.word)) }
            .prefix(DefaultSettings.maximumUserDictionaryEntries)
        if Array(entries) != userDictionary {
            userDictionary = Array(entries)
            importDynamicUserDictionary()
        }
    }

    /// 取り込んだ辞書から引いた語を入れ替える．変わったら true
    fileprivate func setAuxiliaryWords(_ words: [AuxiliaryWord]) -> Bool {
        guard words != auxiliaryWords else { return false }
        auxiliaryWords = words
        importDynamicUserDictionary()
        return true
    }

    /// ユーザー辞書と取り込んだ辞書の語を，動的な辞書としてエンジンに渡す．
    /// 短縮よみの語は文の中の語にしない(SupplementedConverter が読み全体の一致で候補に出す)
    private func importDynamicUserDictionary() {
        let user = userDictionary.filter(\.wordClass.joinsSentences).map {
            DicdataElement(word: $0.word, ruby: KanaWidth.katakana(from: $0.lookupReading ?? $0.reading), cid: Self.partOfSpeechID(for: $0.wordClass),
                           mid: MIDData.一般.mid, value: DefaultSettings.userDictionaryWordCost)
        }
        let imported = auxiliaryWords.filter(\.word.wordClass.joinsSentences).map {
            DicdataElement(word: $0.word.word, ruby: KanaWidth.katakana(from: $0.word.reading), cid: Self.partOfSpeechID(for: $0.word.wordClass),
                           mid: MIDData.一般.mid, value: DefaultSettings.importedWordCost + $0.costOffset)
        }
        converter.importDynamicUserDictionary(user + imported)
    }

    /// 品詞に当たる変換エンジンの品詞の ID．名前の無い ID は本体の辞書の語の ID(サ変名詞は「勉強」，形容動詞は「綺麗」，
    /// 副詞は「迚も」，感動詞は「ああ」)に合わせた．短縮よみは文の中の語にしないので使わない
    public nonisolated static func partOfSpeechID(for wordClass: WordClass) -> Int {
        switch wordClass {
        case .noun, .abbreviation: CIDData.一般名詞.cid
        case .properNoun: CIDData.固有名詞.cid
        case .personName: CIDData.人名一般.cid
        case .surname: CIDData.人名姓.cid
        case .givenName: CIDData.人名名.cid
        case .organization: CIDData.固有名詞組織.cid
        case .place: CIDData.地名一般.cid
        case .symbol: CIDData.記号.cid
        case .suruNoun: 1283
        case .adjectivalNoun: 1287
        case .adverb: 1281
        case .interjection: 3
        }
    }

    fileprivate func withSession<Result>(_ id: KanaKanjiConverter.ConversionSessionID, _ body: (KanaKanjiConverter) -> Result) -> Result? {
        try? converter.withSession(id) { body(converter) }
    }

    fileprivate func removeSession(_ id: KanaKanjiConverter.ConversionSessionID) {
        converter.removeSession(id)
    }

    public var usesZenzai: Bool { zenzai != nil }

    /// 打鍵が止まったときと変換(Space)に使うモデル．速さを優先するときだけ xsmall
    var zenzai: ZenzaiModel? {
        switch zenzaiChoice {
        case .fast: fastZenzai ?? accurateZenzai
        case .accurate, .combined: accurateZenzai ?? fastZenzai
        }
    }

    /// 打っている間の表示に別に使うモデル．併用のときの xsmall．nil なら打っている間も zenzai を使う
    var typingZenzai: ZenzaiModel? {
        guard zenzaiChoice == .combined, accurateZenzai != nil else { return nil }
        return fastZenzai
    }

    private func zenzaiMode(leftContext: String?, rightContext: String?, model: ZenzaiModel?) -> ConvertRequestOptions.ZenzaiMode {
        guard let zenzai = model else { return .off }
        return .on(
            weight: zenzai.url,
            inferenceLimit: DefaultSettings.zenzaiInferenceLimit,
            personalizationMode: nil,
            versionDependentMode: .v3(.init(
                leftSideContext: leftContext,
                rightSideContext: rightContext,
                maxLeftSideContextLength: DefaultSettings.maximumLeftContextLength,
                maxRightSideContextLength: DefaultSettings.maximumRightContextLength
            ))
        )
    }

    /// - Parameter usesTypingModel: 打っている間の表示を求めるとき true．併用なら xsmall で求める
    /// - Parameter rightContext: 読みの後ろにある文字．検証木で文節を採点するときだけ渡す(変換には使わない)
    fileprivate func options(leftContext: String?, rightContext: String? = nil, usesZenzai: Bool = true, usesTypingModel: Bool = false,
                             candidateCount: Int = DefaultSettings.engineCandidateCount) -> ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: candidateCount,
            requireJapanesePrediction: .disabled,
            requireEnglishPrediction: .disabled,
            keyboardLanguage: .ja_JP,
            englishCandidateInRoman2KanaInput: false,
            fullWidthRomanCandidate: false,
            halfWidthKanaCandidate: false,
            learningType: learningType,
            memoryDirectoryURL: memoryDirectory,
            sharedContainerURL: memoryDirectory,
            textReplacer: usesEmoji ? emojiReplacer : .empty,
            // 和暦と西暦の読み替え(「れいわ8ねん」→「2026年」)や数の桁区切りは azooKey が出す．
            // 「きょう」→ 日付の候補は SupplementedConverter が出す(設定の dateConversion)
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            zenzaiMode: usesZenzai ? zenzaiMode(leftContext: leftContext, rightContext: rightContext, model: usesTypingModel ? typingZenzai ?? zenzai : zenzai) : .off,
            metadata: .init(versionString: versionString)
        )
    }
}

extension AzooKeyConverterEngine: EmojiLooking {}

/// 入力欄ひとつぶんの変換の状態．
@MainActor
final class AzooKeyConverterSession: KanaKanjiConverting, CandidateScoring, CandidateFusing {
    private struct Result {
        var all: [HajimeDomain.Candidate]
        var clauses: [HajimeDomain.Candidate]
    }

    private let engine: AzooKeyConverterEngine
    private let sessionID: KanaKanjiConverter.ConversionSessionID
    private let scoringSessionID: KanaKanjiConverter.ConversionSessionID
    /// Zenzai が遅い環境で，打鍵が止まる前の表示を Zenzai なしで求めるセッション．azooKey は前の読みからの差分で変換するので，
    /// Zenzai を使う変換(止まったとき・Space)と同じセッションで交互に求めると，差分が使えず毎回一から変換して遅くなる
    private let typingSessionID: KanaKanjiConverter.ConversionSessionID
    /// 打っている文の続きでない読み(分岐図の文節より後ろの残りの読み・Backspace で戻った読み)を Zenzai で求めるセッション．
    /// 同じセッションで求めると，打っている文の差分の変換の状態が捨てられ，次の打鍵で文を一から変換し直して遅くなる
    private let restSessionID: KanaKanjiConverter.ConversionSessionID
    private var plausibilityCache: [String: Double] = [:]
    private var predictionCache: [String: [HajimeDomain.Candidate]] = [:]
    private var dictionaryCache: [String: [HajimeDomain.Candidate]] = [:]
    private var segmentCandidateCache: [String: [HajimeDomain.Candidate]] = [:]
    private var segmentationCache: [String: [HajimeDomain.Candidate.Word]] = [:]
    /// 検証木の点数(scores)．読み・前後の文字・表記をつないだものがキー．左の文脈が変わったときと入力を終えたときに捨てる
    private var scoreCache: [String: [Double?]] = [:]
    /// 合議の結果(prepareFusion)．読みがキー．重ねる候補と，それを第 1 候補にするか．左の文脈が変わったときと入力を終えたときに捨てる
    private var fusionCache: [String: Fusion] = [:]
    /// 返した候補をエンジンの候補に戻すための表．Candidate の id はこの表のキーで，入力を確定するまで使い回さない
    private var engineCandidates: [Int: KanaKanjiConverterModule.Candidate] = [:]
    private var nextID = 0
    private var cache: [String: Result] = [:]
    /// 打鍵が止まる前の表示を求めているか(setTyping)．Zenzai が遅い環境では，そのあいだ Zenzai を使わない
    private var typing = false
    /// 前に変換を求めた読み．続きの読みなら azooKey の差分の変換を使える
    private var lastRequested: String?
    /// 入力中の表示のセッション(typingSessionID)で前に変換を求めた読み
    private var lastTypingRequested: String?
    /// 残りの読みのセッション(restSessionID)で前に変換を求めた読み
    private var lastRestRequested: String?
    /// 入力中の表示を Zenzai なしで求めた最後の読み．打鍵の合間に Zenzai で求めておく(performDeferredConversion)
    private var deferredReading: String?
    /// 入力位置の前にある文字列(左の文脈)．Zenzai が変換の手がかりに使う
    private var leftContext: String?
    /// 学習を使わずに変換しているか(suspendLearningUntilEnd)．入力を終えると戻す
    private var learningSuspended = false
    /// 今の入力で確定して学んだ候補．入力を終えたら lastCommitted に移す
    private var committedInComposition: [KanaKanjiConverterModule.Candidate] = []
    /// 最後に終えた入力で確定して学んだ候補(最後の学習を取り消すときに使う)
    private var lastCommitted: [KanaKanjiConverterModule.Candidate] = []
    /// 今の入力で確定を伝えられたか(学ばなかったときも)．入力を終えたら，この入力を最後の確定にする
    private var committedAnyInComposition = false
    /// 最後に終えた入力で返した候補(engineCandidates)．確定を取り消したときに戻し，同じ候補のまま確定し直せるようにする
    private var lastEngineCandidates: [Int: KanaKanjiConverterModule.Candidate] = [:]

    init(engine: AzooKeyConverterEngine, sessionID: KanaKanjiConverter.ConversionSessionID, scoringSessionID: KanaKanjiConverter.ConversionSessionID,
         typingSessionID: KanaKanjiConverter.ConversionSessionID, restSessionID: KanaKanjiConverter.ConversionSessionID) {
        self.engine = engine
        self.sessionID = sessionID
        self.scoringSessionID = scoringSessionID
        self.typingSessionID = typingSessionID
        self.restSessionID = restSessionID
    }

    deinit {
        // deinit はどのスレッドで動くか決まっていないので，エンジンへの操作はメインアクターに頼む．
        // isolated deinit は Swift 6.2 からで，CI の Swift 6.1 では使えない
        let engine = engine
        let sessionIDs = [sessionID, scoringSessionID, typingSessionID, restSessionID]
        Task { @MainActor in sessionIDs.forEach(engine.removeSession) }
    }

    func candidates(for reading: String) -> [HajimeDomain.Candidate] {
        let all = request(reading)?.all ?? []
        // 合議の結果は，打鍵が止まったあとの変換(Space など)にだけ重ねる
        guard !typing, let fusion = fusionCache[reading], let candidate = fusion.candidate else { return all }
        var result = all.filter { $0.text != candidate.text }
        result.insert(candidate, at: fusion.first ? 0 : min(1, result.count))
        return result
    }

    func setTyping(_ typing: Bool) {
        self.typing = typing
    }

    var hasDeferredConversion: Bool {
        deferredReading.map { cache[$0] == nil } ?? false
    }

    /// Zenzai を使うセッションで求める．前に Zenzai で求めた読みの続きなら差分で進むので，1 打鍵分の時間で済む
    func performDeferredConversion() {
        guard let reading = deferredReading else { return }
        deferredReading = nil
        let wasTyping = typing
        typing = false
        defer { typing = wasTyping }
        _ = request(reading)
    }

    func clauseCandidates(for reading: String) -> [HajimeDomain.Candidate] {
        request(reading)?.clauses ?? []
    }

    func segmentCandidates(for reading: String) -> [HajimeDomain.Candidate] {
        guard !reading.isEmpty else { return [] }
        if let cached = segmentCandidateCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        // ライブ変換の状態を捨てないよう採点用の変換器で求める．文脈が無いので Zenzai は使わない
        var options = engine.options(leftContext: nil, usesZenzai: false)
        options.typoCorrectionMode = .disabled
        if learningSuspended { options.learningType = .nothing }
        let results = engine.withSession(scoringSessionID) { converter -> [KanaKanjiConverterModule.Candidate] in
            converter.stopComposition()
            defer { converter.stopComposition() }
            let result = converter.requestCandidates(composing, options: options)
            return result.mainResults + result.firstClauseResults
        } ?? []
        var seen = Set<String>()
        let candidates = results.filter { seen.insert($0.text).inserted }.map { register($0, readingLength: reading.count) }
        segmentCandidateCache[reading] = candidates
        return candidates
    }

    func dictionaryCandidates(for reading: String) -> [HajimeDomain.Candidate] {
        guard !reading.isEmpty else { return [] }
        if let cached = dictionaryCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        var options = engine.options(leftContext: nil, usesZenzai: false, candidateCount: DefaultSettings.headWordAlternativeCount * 2)
        options.typoCorrectionMode = .disabled
        options.learningType = .nothing
        let results = engine.withSession(scoringSessionID) { converter -> [KanaKanjiConverterModule.Candidate] in
            converter.stopComposition()
            defer { converter.stopComposition() }
            return converter.requestCandidates(composing, options: options).mainResults
        } ?? []
        var seen = Set<String>()
        let candidates = results.filter { seen.insert($0.text).inserted }.map { register($0, readingLength: reading.count) }
        dictionaryCache[reading] = candidates
        return candidates
    }

    func predictions(for reading: String) -> [HajimeDomain.Candidate] {
        guard !reading.isEmpty else { return [] }
        if let cached = predictionCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        // 予測は Zenzai を使わない軽い変換で求める(打つたびに求めるため)．表示の変換と状態を混ぜないよう，採点用の変換器で求める
        var options = engine.options(leftContext: leftContext, usesZenzai: false, candidateCount: DefaultSettings.suggestionCount)
        options.requireJapanesePrediction = .manualMix
        options.typoCorrectionMode = .disabled
        let results = engine.withSession(scoringSessionID) { converter -> [KanaKanjiConverterModule.Candidate] in
            converter.stopComposition()
            defer { converter.stopComposition() }
            return converter.requestCandidates(composing, options: options).predictionResults
        } ?? []
        var seen = Set<String>()
        let predictions = results.filter { seen.insert($0.text).inserted }.prefix(DefaultSettings.suggestionCount).map { candidate in
            // 予測は打った読み全体を置き換える
            let id = nextID
            nextID += 1
            engineCandidates[id] = candidate
            var prediction = HajimeDomain.Candidate(text: candidate.text, readingCount: reading.count, origin: .engine(id: id))
            prediction.isLearned = !candidate.data.isEmpty && candidate.data.allSatisfy { $0.metadata.contains(.isLearned) }
            return prediction
        }
        predictionCache[reading] = Array(predictions)
        return Array(predictions)
    }

    func plausibility(of reading: String) -> Double {
        guard !reading.isEmpty else { return -.infinity }
        if let cached = plausibilityCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        // 点数だけを使うので，Zenzai・絵文字・特別な候補・打ち間違いの補正を使わず，候補も 1 つだけ求める
        var options = engine.options(leftContext: nil, usesZenzai: false, candidateCount: 1)
        options.textReplacer = .empty
        options.specialCandidateProviders = []
        options.typoCorrectionMode = .disabled
        options.learningType = .nothing
        let best = engine.withSession(scoringSessionID) { converter in
            converter.requestCandidates(composing, options: options).mainResults
                .first { Self.readingCount($0.composingCount, readingLength: reading.count) == reading.count }
                .map { Double($0.value) }
        }
        let score = (best ?? nil) ?? -.infinity
        plausibilityCache[reading] = score
        return score
    }

    func segmentationWords(for reading: String) -> [HajimeDomain.Candidate.Word] {
        guard !reading.isEmpty else { return [] }
        if let cached = segmentationCache[reading] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        // 語の区切りだけを使うので，Zenzai・絵文字・特別な候補・打ち間違いの補正を使わない(plausibility と同じ軽い変換)
        var options = engine.options(leftContext: nil, usesZenzai: false, candidateCount: 1)
        options.textReplacer = .empty
        options.specialCandidateProviders = []
        options.typoCorrectionMode = .disabled
        options.learningType = .nothing
        let data = engine.withSession(scoringSessionID) { converter -> [DicdataElement]? in
            converter.stopComposition()
            return converter.requestCandidates(composing, options: options).mainResults
                .first { Self.readingCount($0.composingCount, readingLength: reading.count) == reading.count }?.data
        }
        let words = Self.words(of: (data ?? nil) ?? [])
        segmentationCache[reading] = words
        return words
    }

    /// 語の品詞の ID と読みから，文節に分けるための印と，崩れた候補を見分けるための印を付ける．名詞の ID は azooKey の CIDData(一般名詞 1285〜数 1295)の並びの範囲
    private static func words(of data: [DicdataElement]) -> [HajimeDomain.Candidate.Word] {
        data.map { element in
            .init(text: element.word, readingCount: element.ruby.count, startsWithParticle: CIDData.isJoshi(cid: element.lcid),
                  endsWithParticle: CIDData.isJoshi(cid: element.rcid), startsWithNoun: nounIDs.contains(element.lcid),
                  startsWithPredicate: predicateIDs.contains { $0.contains(element.lcid) },
                  startsWithConjunctiveParticle: conjunctiveParticleIDs.contains(element.lcid),
                  endsWithSentenceFinalParticle: sentenceFinalParticleIDs.contains(element.rcid),
                  isFunctionWord: functionWordIDs.contains(element.lcid) && functionWordIDs.contains(element.rcid),
                  isCommonNoun: element.lcid == CIDData.一般名詞.cid,
                  endsWithSokuon: element.ruby.last.map("ッっ".contains) ?? false)
        }
    }

    /// 変換で語にならず，かなのまま残った部分の位置(読みの文字数の範囲)．助詞・助動詞(かなで書くのがふつうの語)は除く．
    /// かなの単位の訂正(KanaEditSearch)を試す場所に使う．隣どうしの部分はつなげる(「そう」「ゆう」→「そうゆう」)
    nonisolated static func unconvertedSpans(of data: [DicdataElement], minimumLength: Int = DefaultSettings.minimumUnconvertedSpanLength) -> [Range<Int>] {
        var spans: [Range<Int>] = []
        var position = 0
        for element in data {
            let length = element.ruby.count
            defer { position += length }
            let isFunctionWord = functionWordIDs.contains(element.lcid)
            guard !isFunctionWord, element.word == KanaWidth.hiragana(from: element.ruby) else { continue }
            if let last = spans.last, last.upperBound == position {
                spans[spans.count - 1] = last.lowerBound..<(position + length)
            } else {
                spans.append(position..<(position + length))
            }
        }
        return spans.filter { $0.count >= minimumLength }
    }

    /// 助詞(147〜368)と助動詞(369〜554)．かなで書くのがふつうなので，かなのまま残っても語にならなかったとはみなさない
    private nonisolated static let functionWordIDs = 147...554

    private static let nounIDs = 1280...1316
    /// 名詞のほかの自立語の品詞の ID の範囲．azooKey の品詞の ID は品詞の名前の順に並ぶ．hajime-playground --words で語ごとの ID を見て確かめた
    /// (形容詞 19・20・35・43，接続詞 555，動詞 619・772・817，副詞 1281・1282，連体詞 1315)．助詞は 147〜368，助動詞は 369〜554
    private static let predicateIDs: [ClosedRange<Int>] = [10...146, 555...1279, 1280...1284, 1315...1315]
    /// 助詞のうち，終助詞(ね 279・よ 288・わ 291)と接続助詞(て 307・で 308・ので 316・ば 318)の範囲．同じく語ごとの ID を見て決めた
    private static let sentenceFinalParticleIDs = 263...295
    private static let conjunctiveParticleIDs = 296...330

    func typoCorrections(forKeys keys: String) -> [ReadingCorrection] {
        guard engine.usesZenzai, !keys.isEmpty else { return [] }
        var composing = ComposingText()
        composing.insertAtCursorPosition(keys, inputStyle: .roman2kana)
        let options = engine.options(leftContext: leftContext)
        let config = ExperimentalTypoCorrectionConfig(
            beamSize: DefaultSettings.typoCorrectionBeamSize, topK: DefaultSettings.typoCorrectionTopK, nBest: DefaultSettings.typoCorrectionCandidateCount)
        // 訂正は表示する変換と状態を混ぜないよう，求めたあとに変換の状態を捨てる
        lastRequested = nil
        let corrections = engine.withSession(sessionID) { converter -> [ZenzaiTypoCandidate] in
            defer { converter.stopComposition() }
            return converter.experimentalRequestTypoCorrection(
                leftSideContext: leftContext ?? "", composingText: composing, options: options, inputStyle: .roman2kana, config: config)
        } ?? []
        let beam = corrections.map {
            ReadingCorrection(keys: $0.correctedInput, reading: $0.convertedText, score: Double($0.score), cost: Double($0.channelCost))
        }
        // Zenzai の探索が拾わない誤り(かなの書き誤りなど)を，1 か所の打ち間違いを全部試して補う
        let edits = KeyEditSearch.corrections(of: keys, plausibility: plausibility(of:), languageModel: languageModelScores(forKeys:))
        return KeyEditSearch.withPlausibility(KeyEditSearch.merge(beam, edits), typedKeys: keys, plausibility: plausibility(of:))
    }

    func languageModelScores(forKeys keys: [String]) -> [Double?] {
        guard engine.usesZenzai, !keys.isEmpty else { return keys.map { _ in nil } }
        let inputs = keys.map { key -> ComposingText in
            var composing = ComposingText()
            composing.insertAtCursorPosition(key, inputStyle: .roman2kana)
            return composing
        }
        let options = engine.options(leftContext: leftContext)
        lastRequested = nil
        let scores = engine.withSession(sessionID) { converter -> [Float?] in
            defer { converter.stopComposition() }
            return converter.experimentalScoreTypoInputs(leftSideContext: leftContext ?? "", inputs: inputs, options: options, inputStyle: .roman2kana)
        } ?? keys.map { _ in nil }
        return scores.map { $0.map(Double.init) }
    }

    /// 表記を Zenzai の検証木で採点する．前の文節の文字は左の文脈に続け，後ろの文節の文字は右の文脈にする．
    /// 採点は変換の状態を変えないので，採点用のセッションで行う．同じ問いは入力を終えるまで覚えておく
    /// (打鍵の合間に前もって求め，Space で使うため)
    func scores(of texts: [String], reading: String, before: String, after: String) -> [Double?] {
        guard engine.usesZenzai, !texts.isEmpty, !reading.isEmpty else { return texts.map { _ in nil } }
        let key = Self.scoreKey(texts, reading: reading, before: before, after: after)
        if let cached = scoreCache[key] { return cached }
        let left = (leftContext ?? "") + before
        let options = engine.options(leftContext: left.isEmpty ? nil : left, rightContext: after.isEmpty ? nil : after)
        let started = ContinuousClock.now
        let result = engine.withSession(scoringSessionID) { converter in
            converter.experimentalScoreCandidates(texts, convertTarget: reading, options: options,
                                                  maximumTreeTokens: engine.candidateTreeTokenLimit,
                                                  maximumCandidates: DefaultSettings.candidateTreeCandidateLimit)
        }
        if let result {
            engine.recordScoringCallCost(ContinuousClock.now - started)
            // 1 つも木に入らなかったときは，上限を使い切ったとみなす(速ければ上限を増やし，長い表記も入るようにする)
            engine.recordScoringCost(ContinuousClock.now - started,
                                     treeTokens: result.evaluatedTokens > 0 ? result.evaluatedTokens : engine.candidateTreeTokenLimit,
                                     promptTokens: result.decodedPromptTokens)
        }
        let scores = result.map { $0.scores.map { $0.map(Double.init) } } ?? texts.map { _ in nil }
        scoreCache[key] = scores
        return scores
    }

    func cachedScores(of texts: [String], reading: String, before: String, after: String) -> [Double?]? {
        scoreCache[Self.scoreKey(texts, reading: reading, before: before, after: after)]
    }

    var prefersPrecomputedScores: Bool { engine.prefersPrecomputedScores }

    /// 合議の結果．candidate は重ねる候補(読みにそろえた別のモデルの候補．重ねるものが無ければ nil)
    private struct Fusion {
        var candidate: HajimeDomain.Candidate?
        var first: Bool
    }

    /// 途中まで進めた合議．読みが変わったら捨てて始め直す
    private struct FusionJob {
        enum Stage {
            /// jinen で 1 トークンずつ変換している
            case generating(ExperimentalJinen.ConversionProgress)
            /// jinen の表記を読みにそろえる
            case aligning(String)
            /// 今の第 1 候補と，読みにそろえた jinen の候補を Zenzai で採点する
            case scoringMain(HajimeDomain.Candidate)
            /// 同じ 2 つを jinen で採点し，2 つのモデルの点数で比べる(1 歩を短くするため，Zenzai の採点と分ける)
            case scoringOther(HajimeDomain.Candidate, main: [Double?])
        }

        var reading: String
        var current: HajimeDomain.Candidate
        var stage: Stage
    }

    private var fusionJob: FusionJob?

    /// 読み全体を jinen でも変換し，読みにそろえてから，今の第 1 候補(Zenzai)と比べる．
    /// 2 つのモデルの点数(FirstCandidateArbitration)で上回れば第 1 候補に，そうでなければ 2 番目に重ねる
    /// Space で求めるときは，「自動」の測定を進めない(Space を待たせない)
    func prepareFusion(for reading: String) {
        guard let jinen = engine.jinen else { return }
        while !advanceRecordingCost(reading, jinen: jinen) {}
    }

    /// 打鍵の合間の 1 歩．「自動」をまだ決めていなければ，その測定を 1 歩進める．決めたあとは合議を 1 歩(推論 1 回か，読みにそろえる 1 回か，
    /// 採点 1 回)進める．結果を覚え終えたら(重ねるものが無いときも) true
    func advanceFusion(for reading: String) -> Bool {
        guard engine.advanceAutomaticJinenDecision() else { return false }
        guard let jinen = engine.jinen else { return true }
        return advanceRecordingCost(reading, jinen: jinen)
    }

    private func advanceRecordingCost(_ reading: String, jinen: ExperimentalJinen) -> Bool {
        guard !reading.isEmpty, fusionCache[reading] == nil else { return true }
        let started = ContinuousClock.now
        defer { engine.recordFusionStepCost(ContinuousClock.now - started) }
        return advanceFusion(for: reading, using: jinen)
    }

    /// 合議を 1 歩進める(かかった時間は覚えない．「自動」の測定でも使う)．結果を覚え終えたら true
    func advanceFusion(for reading: String, using jinen: ExperimentalJinen) -> Bool {
        guard !reading.isEmpty, fusionCache[reading] == nil else { return true }
        guard var job = fusionJob, job.reading == reading else {
            fusionJob = startFusion(reading, jinen: jinen)
            return fusionJob == nil
        }
        let left = leftContext ?? ""
        switch job.stage {
        case .generating(var progress):
            jinen.advance(&progress)
            switch progress.state {
            case .running:
                job.stage = .generating(progress)
            case .finished(let conversion?):
                job.stage = .aligning(conversion.text)
            case .finished(nil), .failed:
                return finishFusion(reading, Fusion(candidate: nil, first: false))
            }
        case .aligning(let text):
            guard let challenger = align(text, reading: reading), challenger.text != job.current.text else {
                return finishFusion(reading, Fusion(candidate: nil, first: false))
            }
            job.stage = .scoringMain(challenger)
        case .scoringMain(let challenger):
            let texts = [job.current.text, challenger.text]
            // 比べる 2 つの表記は必ず採点する．打鍵の合間の採点の上限(時間で増減する)ではなく，合議の上限を使う
            let options = engine.options(leftContext: left.isEmpty ? nil : left)
            let main = engine.withSession(scoringSessionID) { converter in
                converter.experimentalScoreCandidates(texts, convertTarget: reading, options: options,
                                                      maximumTreeTokens: DefaultSettings.fusionScoringTokenLimit, maximumCandidates: texts.count)
            }?.scores.map { $0.map(Double.init) } ?? [nil, nil]
            job.stage = .scoringOther(challenger, main: main)
        case .scoringOther(let challenger, let main):
            let texts = [job.current.text, challenger.text]
            let other = jinen.score(texts, reading: reading, leftContext: left, maximumLeftContextLength: DefaultSettings.maximumLeftContextLength)
            var first = false
            if let currentByMain = main[0], let challengerByMain = main[1], let currentByOther = other[0], let challengerByOther = other[1] {
                let scores = FirstCandidateArbitration.Scores(currentByMain: currentByMain, challengerByMain: challengerByMain,
                                                              currentByOther: Double(currentByOther), challengerByOther: Double(challengerByOther))
                first = FirstCandidateArbitration.prefersChallenger(scores, weight: DefaultSettings.fusionOtherModelWeight, margin: DefaultSettings.fusionMargin)
            }
            return finishFusion(reading, Fusion(candidate: challenger, first: first))
        }
        fusionJob = job
        return false
    }

    /// 合議を始める．今の第 1 候補(Space と同じ問い)を求め，jinen のプロンプトを作る．始められなければ結果なしで終える
    private func startFusion(_ reading: String, jinen: ExperimentalJinen) -> FusionJob? {
        let wasTyping = typing
        typing = false
        defer { typing = wasTyping }
        guard let current = request(reading)?.all.first(where: { $0.readingCount == reading.count }),
              let progress = jinen.beginConversion(reading: reading, leftContext: leftContext ?? "",
                                                   maximumLeftContextLength: DefaultSettings.maximumLeftContextLength) else {
            _ = finishFusion(reading, Fusion(candidate: nil, first: false))
            return nil
        }
        return FusionJob(reading: reading, current: current, stage: .generating(progress))
    }

    private func finishFusion(_ reading: String, _ fusion: Fusion) -> Bool {
        fusionCache[reading] = fusion
        fusionJob = nil
        return true
    }

    /// 文を変換し(打っているあいだに求め終えるので，「自動」の測定では数えない)，第 1 候補の語を文節(自立語＋付属語)にまとめた読みを返す．
    /// Zenzai だけのときの打鍵の合間の 1 歩の多くは，分岐図の文節ごとの候補を求めること(LatticeBuilder.warmingSteps)なので，その読みで測る
    func clausesForMeasurement(_ reading: String) -> [String] {
        let wasTyping = typing
        typing = false
        defer { typing = wasTyping }
        guard let sentence = request(reading)?.all.first(where: { $0.readingCount == reading.count }) else { return [] }
        var lengths: [Int] = []
        for word in sentence.words {
            if word.isFunctionWord, !lengths.isEmpty { lengths[lengths.count - 1] += word.readingCount } else { lengths.append(word.readingCount) }
        }
        var start = 0
        return lengths.compactMap { length in
            defer { start += length }
            let slice = String(reading.dropFirst(start).prefix(length))
            return slice.isEmpty ? nil : slice
        }
    }

    /// 読みを打鍵が止まったときと同じ問いで変換する(「自動」の測定で，Zenzai だけの 1 歩を測る)
    func convertForMeasurement(_ reading: String) {
        let wasTyping = typing
        typing = false
        defer { typing = wasTyping }
        _ = request(reading)
    }

    /// 合議の途中の結果を捨てる(「自動」の測定で，別の大きさの jinen を試す前に呼ぶ)
    func resetFusion() {
        fusionCache = [:]
        fusionJob = nil
    }

    /// 表記を読みにそろえられるか(評価の道具が，合議で別のモデルの候補が落ちた理由を調べるのに使う)．そろえた表記を返す
    func alignedText(_ text: String, reading: String) -> String? {
        align(text, reading: reading)?.text
    }

    func hasFusion(for reading: String) -> Bool {
        fusionCache[reading] != nil
    }

    var prefersPrecomputedFusion: Bool { engine.prefersPrecomputedFusion }

    /// 別のモデルの表記を，辞書の語の読みで読み全体を作れるかで確かめ(読みにそろえる)，作れればエンジンの候補にする．
    /// 別のモデルは NFKC の表記を出すので，そのままで作れないときは，読みにある全角の記号を全角に戻して試す
    private func align(_ text: String, reading: String) -> HajimeDomain.Candidate? {
        var options = engine.options(leftContext: nil, usesZenzai: false)
        options.typoCorrectionMode = .disabled
        if learningSuspended { options.learningType = .nothing }
        for attempt in Self.alignmentAttempts(text, reading: reading) {
            let aligned = engine.withSession(scoringSessionID) { converter in
                converter.experimentalAlignText(attempt, reading: reading, options: options)
            } ?? nil
            if let aligned { return register(aligned, readingLength: reading.count) }
        }
        return nil
    }

    /// 読みにそろえるときに試す表記．そのままの表記と，読みにある全角の記号(「（」「？」など)に当たる半角の記号を全角に戻した表記
    static func alignmentAttempts(_ text: String, reading: String) -> [String] {
        let fullWidth = Set(reading.unicodeScalars.filter { (0xFF01 ... 0xFF5E).contains($0.value) })
        guard !fullWidth.isEmpty else { return [text] }
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if (0x21 ... 0x7E).contains(scalar.value), let wide = Unicode.Scalar(scalar.value + 0xFEE0), fullWidth.contains(wide) {
                scalars.append(wide)
            } else {
                scalars.append(scalar)
            }
        }
        let restored = String(scalars)
        return restored == text ? [text] : [text, restored]
    }

    /// 点数を覚えるキー．読み・前後の文字・表記を，読みや表記に出ない文字でつなぐ
    private static func scoreKey(_ texts: [String], reading: String, before: String, after: String) -> String {
        ([reading, before, after] + texts).joined(separator: "\u{0}")
    }

    func setLeftContext(_ text: String?) {
        guard text != leftContext else { return }
        leftContext = text
        cache = [:]
        scoreCache = [:]
        fusionCache = [:]
    }

    func didCommit(_ candidate: HajimeDomain.Candidate) {
        committedAnyInComposition = true
        guard case .engine(let id) = candidate.origin, let engineCandidate = engineCandidates[id] else {
            // つないだ候補は，元の語(エンジンの候補)を学ぶ
            learn(candidate.learnedParts.compactMap { part in
                if case .engine(let id) = part.origin { engineCandidates[id] } else { nil }
            })
            return
        }
        let learns = !learningSuspended
        if learns { restoreLearningConfig() }
        _ = engine.withSession(sessionID) { converter in
            converter.setCompletedData(engineCandidate)
            if learns { converter.updateLearningData(engineCandidate) }
        }
        if learns { committedInComposition.append(engineCandidate) }
        // 確定すると学習で順位が変わるので，同じ読みでも求め直す
        cache = [:]
    }

    private func learn(_ parts: [KanaKanjiConverterModule.Candidate]) {
        guard !parts.isEmpty, !learningSuspended else { return }
        restoreLearningConfig()
        _ = engine.withSession(sessionID) { converter in parts.forEach(converter.updateLearningData) }
        committedInComposition.append(contentsOf: parts)
        cache = [:]
    }

    /// 学習の設定を戻す(AzooKeyConverterEngine.restoreLearningConfig)．表示の変換の状態を捨てないよう，採点用の変換器で行う
    private func restoreLearningConfig() {
        _ = engine.withSession(scoringSessionID) { converter in
            converter.stopComposition()
            defer { converter.stopComposition() }
            engine.restoreLearningConfig(converter)
        }
    }

    func forget(_ candidate: HajimeDomain.Candidate) {
        guard case .engine(let id) = candidate.origin, let engineCandidate = engineCandidates[id] else { return }
        restoreLearningConfig()
        _ = engine.withSession(sessionID) { $0.forgetMemory(engineCandidate) }
        cache = [:]
    }

    func forget(_ candidate: HajimeDomain.Candidate, readingRange range: Range<Int>) {
        guard case .engine(let id) = candidate.origin, var engineCandidate = engineCandidates[id] else { return }
        restoreLearningConfig()
        // 読みの range に掛かる語だけを残す(語の読みはカタカナで，字の数はひらがなの読みと同じ)
        var start = 0
        engineCandidate.data = engineCandidate.data.filter { element in
            defer { start += element.ruby.count }
            return start < range.upperBound && start + element.ruby.count > range.lowerBound
        }
        guard !engineCandidate.data.isEmpty else { return }
        _ = engine.withSession(sessionID) { $0.forgetMemory(engineCandidate) }
        cache = [:]
    }

    func forgetLastCommit() -> Bool {
        guard !lastCommitted.isEmpty else { return false }
        let targets = lastCommitted
        lastCommitted = []
        _ = engine.withSession(sessionID) { converter in targets.forEach(converter.forgetMemory) }
        cache = [:]
        return true
    }

    func reopenLastCommit() {
        engineCandidates.merge(lastEngineCandidates) { current, _ in current }
    }

    func suspendLearningUntilEnd() {
        guard !learningSuspended else { return }
        learningSuspended = true
        // 学習を使った結果を使い回さないよう，前の結果を捨てて一から変換する
        cache = [:]
        lastRequested = nil
        lastTypingRequested = nil
        lastRestRequested = nil
        deferredReading = nil
    }

    /// 取り込んだ辞書の語が変わったら，前の結果は使えないので捨て，次は差分ではなく一から変換する
    func setAuxiliaryWords(_ words: [AuxiliaryWord]) {
        guard engine.setAuxiliaryWords(words) else { return }
        cache = [:]
        segmentCandidateCache = [:]
        lastRequested = nil
        lastTypingRequested = nil
        lastRestRequested = nil
        deferredReading = nil
    }

    func endComposition() {
        lastRequested = nil
        lastTypingRequested = nil
        lastRestRequested = nil
        deferredReading = nil
        learningSuspended = false
        // 学ばなかった入力(学習を使わない変換)も最後の確定にし，その前の入力の学習を取り消さないようにする
        if committedAnyInComposition { lastCommitted = committedInComposition }
        committedAnyInComposition = false
        committedInComposition = []
        // 候補の id は使い回さないので，前の入力の候補を残しても別の候補と取り違えない
        if !engineCandidates.isEmpty { lastEngineCandidates = engineCandidates }
        _ = engine.withSession(sessionID) { $0.stopComposition() }
        _ = engine.withSession(scoringSessionID) { $0.stopComposition() }
        _ = engine.withSession(typingSessionID) { $0.stopComposition() }
        _ = engine.withSession(restSessionID) { $0.stopComposition() }
        plausibilityCache = [:]
        predictionCache = [:]
        dictionaryCache = [:]
        segmentationCache = [:]
        segmentCandidateCache = [:]
        scoreCache = [:]
        fusionCache = [:]
        engineCandidates = [:]
        cache = [:]
    }

    private func request(_ reading: String) -> Result? {
        guard !reading.isEmpty else { return nil }
        // 併用のときは，打鍵が止まる前の表示を速いモデル(xsmall)で求める．
        // そうでなく Zenzai が遅い環境では，打鍵が止まる前の表示を Zenzai なしで求める．
        // どちらの結果も止まったときに求め直すので，止まったときの結果とは別のキーで覚える(止まったときの結果があればそれを使う)
        let usesTypingModel = typing && engine.typingZenzai != nil
        let skipsZenzai = typing && !usesTypingModel && engine.usesZenzai && engine.skipsZenzaiWhileTyping
        // ライブ変換の表示と候補一覧で同じ読みを続けて求めることが多いので，結果を使い回す
        if let cached = cache[reading] { return cached }
        let key = skipsZenzai || usesTypingModel ? Self.typingCacheKey(reading) : reading
        if let cached = cache[key] { return cached }
        var composing = ComposingText()
        composing.insertAtCursorPosition(reading, inputStyle: .direct)
        var options = engine.options(leftContext: leftContext, usesZenzai: !skipsZenzai, usesTypingModel: usesTypingModel)
        if learningSuspended { options.learningType = .nothing }
        // azooKey は前に求めた読みからの差分で変換を進める．前の読みの続きでない読み(文節ごとの残りの読みなど)を
        // そのまま渡すと前の結果が混ざる(「ひとだ」→「非とだ」)ので，続きでなければ状態を捨ててから求める
        let stream = stream(for: reading, separatesTyping: skipsZenzai || usesTypingModel)
        let previous = switch stream {
        case .typing: lastTypingRequested
        case .sentence: lastRequested
        case .rest: lastRestRequested
        }
        let continues = previous.map(reading.hasPrefix) ?? false
        let session = switch stream {
        case .typing: typingSessionID
        case .sentence: sessionID
        case .rest: restSessionID
        }
        let started = ContinuousClock.now
        guard let result = engine.withSession(session, { converter in
            if !continues { converter.stopComposition() }
            return converter.requestCandidates(composing, options: options)
        }) else {
            return nil
        }
        switch stream {
        case .typing:
            lastTypingRequested = reading
            deferredReading = reading
        case .sentence:
            lastRequested = reading
        case .rest:
            lastRestRequested = reading
        }
        if stream != .typing, engine.usesZenzai { engine.recordZenzaiCost(ContinuousClock.now - started) }
        var seen = Set<String>()
        var all: [HajimeDomain.Candidate] = []
        for candidate in result.mainResults + result.firstClauseResults where seen.insert(candidate.text).inserted {
            all.append(register(candidate, readingLength: reading.count))
        }
        var clauseSeen = Set<String>()
        var clauses: [HajimeDomain.Candidate] = []
        for candidate in result.firstClauseResults where clauseSeen.insert(candidate.text).inserted {
            clauses.append(register(candidate, readingLength: reading.count))
        }
        let value = Result(all: all, clauses: clauses)
        cache[key] = value
        return value
    }

    /// 変換を求めるセッションの流れ
    private enum Stream {
        /// 打鍵が止まる前の表示(Zenzai なしか，併用のときの速いモデル)
        case typing
        /// 打っている文．前の読みの続きを差分で変換する
        case sentence
        /// 打っている文の続きでない読み
        case rest
    }

    private func stream(for reading: String, separatesTyping: Bool) -> Stream {
        if separatesTyping { return .typing }
        return lastRequested.map(reading.hasPrefix) ?? true ? .sentence : .rest
    }

    /// 打鍵が止まる前に求めた表示(Zenzai なしか，併用のときの速いモデル)を覚えるキー(読みの前に読みには出ない文字を付ける)
    nonisolated static func typingCacheKey(_ reading: String) -> String {
        "\u{0}" + reading
    }

    private func register(_ candidate: KanaKanjiConverterModule.Candidate, readingLength: Int) -> HajimeDomain.Candidate {
        let id = nextID
        nextID += 1
        engineCandidates[id] = candidate
        return HajimeDomain.Candidate(
            text: candidate.text,
            readingCount: Self.readingCount(candidate.composingCount, readingLength: readingLength),
            origin: .engine(id: id),
            score: Double(candidate.value),
            trailingWord: candidate.data.last.map { .init(readingCount: $0.ruby.count, textCount: $0.word.count) },
            words: Self.words(of: candidate.data)
        )
    }

    /// 入力を .direct で渡しているので，入力の数と読みの文字数は同じになる
    nonisolated static func readingCount(_ count: ComposingCount, readingLength: Int) -> Int {
        switch count {
        case .inputCount(let value), .surfaceCount(let value):
            return min(value, readingLength)
        case .composite(let lhs, let rhs):
            return min(readingCount(lhs, readingLength: readingLength) + readingCount(rhs, readingLength: readingLength), readingLength)
        }
    }
}
