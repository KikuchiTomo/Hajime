import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimeTestSupport
import Testing

/// 評価用の文(core/Evaluation)を本物の Zenzai と同梱の辞書で変換し，第 1 候補が期待どおりになった文の数が下限を下回らないことを確かめる．
/// 辞書・モデル・変換の処理を変えて正解率が下がったら落とす(正解率を上げたら下限も上げる)．
/// モデルと辞書が要るので，環境変数 HAJIME_ZENZAI_MODEL(small)と HAJIME_BUNDLED_DICTIONARY があるときだけ動かす(make test-zenzai)
private let hasModelAndDictionary = ProcessInfo.processInfo.environment["HAJIME_ZENZAI_MODEL"] != nil
    && ProcessInfo.processInfo.environment["HAJIME_BUNDLED_DICTIONARY"] != nil

@Suite("評価用の文の正解率(Zenzai)", .serialized, .enabled(if: hasModelAndDictionary))
@MainActor
struct ConversionAccuracyTests {

    /// 評価用の文の 1 行．期待する変換は書き方の揺れを含めて複数
    private struct Case {
        var reading: String
        var expected: [String]
        var leftContext: String?
    }

    private static let evaluationDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Evaluation", isDirectory: true)

    private func cases(_ name: String) throws -> [Case] {
        let text = try String(contentsOf: Self.evaluationDirectory.appendingPathComponent(name), encoding: .utf8)
        return text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard columns.count >= 2 else { return nil }
            return Case(reading: columns[0], expected: columns[1].split(separator: "|").map(String.init),
                        leftContext: columns.count >= 3 && !columns[2].isEmpty ? columns[2] : nil)
        }
    }

    /// 期待どおりの第 1 候補になった文の数と，外れた文(読みと出た変換)
    private func evaluate(_ name: String) throws -> (passed: Int, total: Int, misses: [String]) {
        let environment = ProcessInfo.processInfo.environment
        let model = try ZenzaiModel.verified(at: URL(fileURLWithPath: try #require(environment["HAJIME_ZENZAI_MODEL"])))
        let dictionary = URL(fileURLWithPath: try #require(environment["HAJIME_BUNDLED_DICTIONARY"]), isDirectory: true)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-accuracy-\(UUID().uuidString)")
        let engine = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "accuracy", zenzai: model, dictionaryDirectory: dictionary)
        let items = try cases(name)
        var passed = 0
        var misses: [String] = []
        for item in items {
            // 文ごとに新しいセッションにして，前の文の変換の影響を受けないようにする(hajime-playground --evaluate と同じ)
            let settings = FakeSettings()
            let session = SupplementedConverter(engine.makeSession(), settings: settings, calendar: FakeCalendar())
            session.setLeftContext(item.leftContext)
            let output = session.candidates(for: item.reading).first { $0.readingCount == item.reading.count }?.text ?? item.reading
            if item.expected.contains(output) {
                passed += 1
            } else {
                misses.append("\(item.reading) → \(output)")
            }
        }
        return (passed, items.count, misses)
    }

    @Test("評価用の文の第 1 候補が期待どおりになった数が下限を下回らない", arguments: [("conversion-basic.tsv", 27), ("conversion-everyday.tsv", 125)])
    func accuracy(name: String, minimum: Int) throws {
        let result = try evaluate(name)
        print("HAJIME_ACCURACY \(name) \(result.passed)/\(result.total)")
        #expect(result.passed >= minimum, "\(name) の正解が下限 \(minimum) を下回った: \(result.passed)/\(result.total)．外れた文: \(result.misses)")
    }
}
