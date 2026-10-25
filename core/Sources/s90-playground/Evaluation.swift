import Foundation
import S90Application
import S90Domain
import S90Engine

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
    /// 評価用の文を変換して，期待どおりになった割合と 1 回の変換の時間を出す
    static func conversion(cases: [EvaluationCase], engine: AzooKeyConverterEngine) {
        let clock = ContinuousClock()
        var passed = 0
        var durations: [Duration] = []
        for item in cases {
            // 文ごとに新しいセッションにして，前の文の変換や学習の影響を受けないようにする
            let session = newSession(engine, context: item.leftContext)
            var output = ""
            durations.append(clock.measure { output = best(session, item.reading) })
            let ok = item.expected.contains(output)
            if ok { passed += 1 }
            print("\(ok ? "○" : "×")  \(item.reading)\(contextNote(item))  → \(output)\(ok ? "" : "   期待: \(item.expected.joined(separator: " か "))")")
        }
        let sorted = durations.sorted()
        print("正解: \(passed) / \(cases.count)  変換の時間 中央値: \(sorted[sorted.count / 2])  最大: \(sorted.last!)")
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

    private static func isHiragana(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }

    private static func newSession(_ engine: AzooKeyConverterEngine, context: String?) -> any KanaKanjiConverting {
        let session = engine.makeSession()
        session.setLeftContext(context)
        return session
    }

    /// 読み全体に対応する第 1 候補．無ければ読みのまま
    private static func best(_ session: any KanaKanjiConverting, _ reading: String) -> String {
        session.candidates(for: reading).first { $0.readingCount == reading.count }?.text ?? reading
    }

    private static func contextNote(_ item: EvaluationCase) -> String {
        item.leftContext.map { "(文脈: \($0))" } ?? ""
    }
}
