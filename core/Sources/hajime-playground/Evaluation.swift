import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimePersistence

/// 評価用の文 1 つ．期待する変換は表記の揺れを並べて複数持てる
struct EvaluationCase {
    var reading: String
    var expected: [String]
    var leftContext: String?

    /// 読み<TAB>期待する変換(| で区切って複数)<TAB>左の文脈(任意)．# で始まる行と空の行は読み飛ばす
    static func load(from file: String) throws -> [EvaluationCase] {
        try String(contentsOfFile: file, encoding: .utf8)
            .split(separator: "\n")
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .compactMap { line in
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 2 else { return nil }
                let context = columns.count >= 3 && !columns[2].isEmpty ? columns[2] : nil
                return EvaluationCase(reading: columns[0], expected: columns[1].split(separator: "|").map(String.init), leftContext: context)
            }
    }
}

@MainActor
enum Evaluation {
    /// 正解が入っているかを数える候補の数．語彙の評価で，辞書に語があるのに同じ読みの別の表記が先に出たものを見分けるため
    static let candidateWindow = 10

    /// 評価用の文を変換して，期待どおりになった割合・上位の候補に正解が入った割合・1 回の変換の時間を出す
    static func conversion(cases: [EvaluationCase], engine: AzooKeyConverterEngine) {
        let clock = ContinuousClock()
        var passed = 0
        var listed = 0
        var errorRates: [Double] = []
        var durations: [Duration] = []
        for item in cases {
            // 文ごとに新しいセッションにして，前の文の変換や学習の影響を受けないようにする
            let session = newSession(engine, context: item.leftContext)
            var candidates: [String] = []
            durations.append(clock.measure { candidates = wholeCandidates(session, item.reading) })
            let output = candidates.first ?? item.reading
            let ok = item.expected.contains(output)
            if ok { passed += 1 }
            let rank = candidates.prefix(candidateWindow).firstIndex { item.expected.contains($0) }
            if rank != nil { listed += 1 }
            errorRates.append(minimumCharacterErrorRate(expected: item.expected, output: output))
            let note = ok ? "" : "   期待: \(item.expected.joined(separator: " か "))" + (rank.map { "(\($0 + 1) 番目の候補)" } ?? "")
            print("\(ok ? "○" : rank == nil ? "×" : "△")  \(item.reading)\(contextNote(item))  → \(output)\(note)")
        }
        let sorted = durations.sorted()
        let accuracy = Double(passed) / Double(cases.count) * 100
        let listedRate = Double(listed) / Double(cases.count) * 100
        let meanErrorRate = errorRates.reduce(0, +) / Double(errorRates.count) * 100
        print(String(format: "正解: %d / %d (%.1f%%)  上位 %d 候補: %.1f%%  MinCER: %.2f%%", passed, cases.count, accuracy, candidateWindow, listedRate, meanErrorRate)
              + "  変換の時間 中央値: \(sorted[sorted.count / 2])  最大: \(sorted.last!)")
    }

    /// 期待する変換のうち最も近いものとの文字誤り率(編集距離 ÷ 期待する文の文字数)．AJIMEE-Bench の MinCER と同じ測り方
    static func minimumCharacterErrorRate(expected: [String], output: String) -> Double {
        expected.filter { !$0.isEmpty }
            .map { Double(editDistance(Array($0), Array(output))) / Double($0.count) }
            .min() ?? 0
    }

    /// 文字単位の編集距離(置き換え・削除・挿入をそれぞれ 1 と数える)
    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// 打っている途中の表示を評価する．読みを 1 文字ずつ増やし，各時点で見せる文字が
    /// 最後の変換結果の先頭と食い違った回数(誤った途中表示．「らい」で「雷」など)を数える．かなのまま見せた時点は誤りに数えない
    /// 打っている途中の表示を数える．途中の表示のうち，最後に確定する文と食い違う漢字やカタカナを見せたものを誤りとする．
    /// 末尾がかなのまま食い違うのは，続きを打てば直るので誤りにしない
    static func live(cases: [EvaluationCase], engine: AzooKeyConverterEngine) {
        let rule = LiveConversionRule()
        var steps = 0, wrong = 0, converted = 0
        for item in cases {
            let session = newSession(engine, context: item.leftContext)
            let final = best(session, item.reading)
            var mistakes: [String] = []
            for length in 1..<item.reading.count {
                let prefix = String(item.reading.prefix(length))
                let candidate = session.candidates(for: prefix).first { $0.readingCount == prefix.count }
                let shown = candidate.map { rule.display(of: $0, reading: prefix, settled: false) } ?? prefix
                steps += 1
                if shown == prefix { continue }
                converted += 1
                let common = zip(shown, final).prefix { $0 == $1 }.count
                if shown.dropFirst(common).contains(where: { !isHiragana($0) }) {
                    wrong += 1
                    mistakes.append("\(prefix)→\(shown)")
                }
            }
            if !mistakes.isEmpty { print("\(item.reading) → \(final)  誤った途中表示: \(mistakes.joined(separator: " "))") }
        }
        print("途中の時点: \(steps)  変換して見せた: \(converted)  誤った途中表示: \(wrong)")
    }

    /// 打ち間違いの補正を評価する．1 行は「打ったキー<TAB>直したあとの文(直さないのが正しければ =)」．
    /// 「=」のあとに文を書いたときは，直さずにその文を見せれば正しい(英語の混ざる文．「=pythonがすごい」)．
    /// ライブ変換で打鍵が止まったときと同じに見直し，直した(点線)・示した(「もしかして」)・何もしない，のどれになったかを数える
    /// 打ち間違いの補正を，アプリと同じ道筋(打つ → 止まる → 別の変換器で訂正を求める → 見直す)で測る．
    /// service が無い(Zenzai なし)ときは訂正を求めずに見直す
    /// typingInterval を与えると，その間隔でキーを打ったときと同じに，打鍵の合間(correctionPrefetchDelay 止まったあと)に訂正を前もって求め，
    /// 次のキーで取り消す．打ち終えたあとも，見直すまで(correctionDelay)のあいだ前もって求める．見直しの時間は止まってから correctionDelay たったあとから測る
    static func typo(file: String, engine: AzooKeyConverterEngine, service: ZenzaiTypoService?, typingInterval: Double? = nil) throws {
        let lines = try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        let clock = ContinuousClock()
        var counts: [String: Int] = [:]
        var durations: [Duration] = []
        var keyDurations: [Duration] = []
        /// 打鍵の合間に訂正を前もって求める．seconds たったら取り消す(次のキーが来た)．取り消さないときは見直しで待つ
        func prefetch(_ session: InputSession, for seconds: Double, cancels: Bool) -> Task<Void, Never>? {
            guard let service, seconds > DefaultSettings.correctionPrefetchDelay else { return nil }
            RunLoop.main.run(until: Date().addingTimeInterval(DefaultSettings.correctionPrefetchDelay))
            guard let request = session.prefetchRequest else { return nil }
            let task = Task { await service.prefetch(forKeys: request.keys, leftContext: request.leftContext) }
            RunLoop.main.run(until: Date().addingTimeInterval(seconds - DefaultSettings.correctionPrefetchDelay))
            if cancels { task.cancel() }
            return task
        }
        for line in lines {
            let columns = line.split(separator: "\t").map(String.init)
            guard columns.count == 2 else { continue }
            let store = StaticSettings(DefaultSettings.settings)
            let session = InputSession(converter: engine.makeSession(), lexicon: WordListLexicon(), settings: store, typoService: service)
            for key in columns[0] {
                let keyStart = clock.now
                _ = session.handle(KeyEvent(.character(key)), context: InputContext())
                keyDurations.append(clock.now - keyStart)
                if let typingInterval { _ = prefetch(session, for: typingInterval, cancels: true) }
            }
            var marked = MarkedText.empty
            var note: String?
            let pending = typingInterval.flatMap { _ in prefetch(session, for: DefaultSettings.liveCorrectionDelay, cancels: false) }
            let start = clock.now
            var actions = session.settle(context: InputContext())
            if let service, let request = session.correctionRequest {
                session.provideCorrections(waitFor {
                    await pending?.value
                    return await service.corrections(forKeys: request.keys, leftContext: request.leftContext)
                })
            }
            actions += session.review(context: InputContext())
            durations.append(clock.now - start)
            for action in actions {
                if case .setMarkedText(let text) = action { marked = text }
                if case .showNote(let shown) = action { note = shown.text }
            }
            let applied = marked.segments.contains { $0.style == .correction }
            let suggested = note?.hasPrefix("もしかして") == true
            let outcome: String
            if columns[1].hasPrefix("=") {
                let expected = columns[1].dropFirst()
                outcome = applied ? "誤って直した" : suggested ? "誤って示した"
                    : expected.isEmpty || marked.text == expected ? "正しく直さなかった" : "直さなかったが違う文"
            } else if applied {
                outcome = columns[1].split(separator: "|").contains { marked.text == $0 } ? "正しく直した" : "違う文に直した"
            } else if suggested {
                // 案内には直す語句を含む文節だけが出るので，Tab で直したあとの文で比べる
                let accepted = session.handle(KeyEvent(.tab), context: InputContext()).actions
                    .compactMap { if case .setMarkedText(let text) = $0 { text.text } else { nil } }.last
                outcome = columns[1].split(separator: "|").contains { accepted == String($0) } ? "正しく示した" : "違う文を示した"
            } else if columns[1].split(separator: "|").contains(where: { marked.text == $0 }) {
                // 打ったままの読みでも期待どおりの文になる(「こんにちわ」→「こんにちは」)．直す必要が無い
                outcome = "直さずに正しい文"
            } else {
                outcome = "直せなかった"
            }
            counts[outcome, default: 0] += 1
            print("\(outcome)  \(columns[0]) → \(marked.text)\(note.map { "  [\($0)]" } ?? "")")
        }
        let sorted = durations.sorted()
        print(counts.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "  "))
        print("見直しの時間 中央値: \(sorted[sorted.count / 2])  90%: \(sorted[sorted.count * 9 / 10])  最大: \(sorted.last!)")
        let keys = keyDurations.sorted()
        if !keys.isEmpty {
            print("1 キーの処理の時間 中央値: \(keys[keys.count / 2])  99%: \(keys[keys.count * 99 / 100])  最大: \(keys.last!)")
        }
    }

    /// 訂正の候補ごとの材料を TSV で出す(重みと境目を決めるため)．アプリと同じ道筋(打つ → 止まる → 訂正を求める)で，
    /// 見直すキー(「nn」のあとをな行で読んだところは打ち分けた並び)の候補を出す．service が無ければ表示の変換器で求める．
    /// 列: 文の番号, 期待(= なら直さないのが正しい), 候補のキー, 言語モデルの差(Zenzai の点数 + 手間 - 打ったままの点数), 手間,
    /// 変換のもっともらしさの差, 候補の変換, 正解か．打ったままの並びを言語モデルが読めないときは，ReadingCorrectionRule と同じく最も低い候補と比べる
    static func correctionFeatures(file: String, engine: AzooKeyConverterEngine, service: ZenzaiTypoService?) throws {
        let lines = try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        for (number, line) in lines.enumerated() {
            let columns = line.split(separator: "\t").map(String.init)
            guard columns.count == 2 else { continue }
            let converter = engine.makeSession()
            let session = InputSession(converter: converter, lexicon: WordListLexicon(), settings: StaticSettings(DefaultSettings.settings), typoService: service)
            for key in columns[0] { _ = session.handle(KeyEvent(.character(key)), context: InputContext()) }
            _ = session.settle(context: InputContext())
            guard let request = session.correctionRequest, let keys = request.keys.first else { continue }
            let candidates = service.map { service in waitFor { await service.corrections(forKeys: [keys], leftContext: request.leftContext) }[keys] ?? [] }
                ?? converter.typoCorrections(forKeys: keys)
            guard let original = KeyEditSearch.reading(of: keys) ?? Optional(KeyEditSearch.rawReading(of: keys)),
                let baseScore = candidates.first(where: { $0.keys == keys }).map(\.score) ?? candidates.map({ $0.score + $0.cost }).min() else { continue }
            let base = converter.plausibility(of: original)
            for candidate in candidates where candidate.keys != keys {
                let reading = KanaWidth.hiragana(from: candidate.reading)
                let text = converter.candidates(for: reading).first { $0.readingCount == reading.count }?.text ?? reading
                let correct = !columns[1].hasPrefix("=") && columns[1].split(separator: "|").contains { text == $0 }
                print([String(number), columns[1], candidate.keys, String(format: "%.3f", candidate.score + candidate.cost - baseScore),
                       String(format: "%.3f", candidate.cost), String(format: "%.3f", converter.plausibility(of: reading) - base), text, correct ? "1" : "0"]
                    .joined(separator: "\t"))
            }
        }
    }

    /// 英字入力(自動)で語ごとに英語と日本語を見分けた結果を評価する．1 行は「打ったキー<TAB>入る文<TAB>前の文字列(任意)」．
    /// 打ったキーの空白は Space を押したもの．最後に Enter を押し，入力欄に入った文字(確定した文字とアプリに渡した空白)を比べる
    static func language(file: String, engine: AzooKeyConverterEngine) throws {
        let lines = try String(contentsOfFile: file, encoding: .utf8).split(separator: "\n").filter { !$0.hasPrefix("#") && !$0.isEmpty }
        var settings = DefaultSettings.settings
        settings.inputStyle = .englishAuto
        let lexicon = WordListLexicon()
        var passed = 0
        for line in lines {
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 2 else { continue }
            let session = InputSession(converter: engine.makeSession(), lexicon: lexicon, settings: StaticSettings(settings))
            var text = ""
            var precedingText = columns.count >= 3 && !columns[2].isEmpty ? columns[2] : nil
            func press(_ key: KeyEvent.Key, _ typed: String) {
                let context = InputContext(precedingText: session.isComposing ? nil : (precedingText ?? "") + text)
                let result = session.handle(KeyEvent(key), context: context)
                for action in result.actions { if case .commit(let value) = action { text += value } }
                if !result.handled { text += typed }
            }
            for character in columns[0] {
                press(character == " " ? .space : .character(character), String(character))
            }
            press(.enter, "")
            precedingText = nil
            let ok = text == columns[1]
            if ok { passed += 1 }
            print("\(ok ? "○" : "×")  \(columns[0]) → \(text)\(ok ? "" : "   期待: \(columns[1])")")
        }
        print("正解: \(passed) / \(lines.count)")
    }

    private static func isHiragana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }

    /// アプリと同じく，エンジンの候補に記号・日付・並べ替え(SupplementedConverter)を既定の設定で足したもの
    private static func newSession(_ engine: AzooKeyConverterEngine, context: String?) -> any KanaKanjiConverting {
        let session = SupplementedConverter(engine.makeSession(), settings: StaticSettings(DefaultSettings.settings), calendar: SystemCalendar(clock: { Date() }))
        session.setLeftContext(context)
        return session
    }

    /// 読み全体に対応する第 1 候補．無ければ読みのまま
    private static func best(_ session: any KanaKanjiConverting, _ reading: String) -> String {
        session.candidates(for: reading).first { $0.readingCount == reading.count }?.text ?? reading
    }

    /// 読み全体に対応する候補を，出る順に重なりなく並べたもの
    private static func wholeCandidates(_ session: any KanaKanjiConverting, _ reading: String) -> [String] {
        var seen = Set<String>()
        return session.candidates(for: reading).filter { $0.readingCount == reading.count }.map(\.text).filter { seen.insert($0).inserted }
    }

    private static func contextNote(_ item: EvaluationCase) -> String {
        item.leftContext.map { "(文脈: \($0))" } ?? ""
    }
}

/// 非同期の処理を，メインのランループを回しながら待つ(試す道具の入り口は同期で動くため)
@MainActor
func waitFor<T: Sendable>(_ operation: @escaping @Sendable () async -> T) -> T {
    let box = ResultBox<T>()
    Task.detached { box.value = await operation() }
    while box.value == nil { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    return box.value!
}

private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T?
    var value: T? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
