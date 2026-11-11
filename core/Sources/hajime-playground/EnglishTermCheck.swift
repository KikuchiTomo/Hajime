import Foundation
import HajimeApplication
import HajimeDomain
import HajimeEngine
import HajimePersistence

/// 英語の語の辞書(R-24)の語ごとに，小文字で打ったときの読みと候補の先頭を出す．
/// 読みがかなになり切り，英語の語が第 1 候補になる語は，その読みを日本語として打つ人がいないかを見て選ぶ(「meta」→ メタ は入れない)
@MainActor
enum EnglishTermCheck {
    /// リポジトリの頭から見た同梱の辞書
    static let bundledURL = URL(fileURLWithPath: "data/english").appendingPathComponent(DefaultSettings.bundledEnglishTermFileName)

    /// 1 行に「語・読み・語の並び・もっともらしさ・候補の先頭 3 つ・英語の語が第 1 候補か」をタブで区切って出す
    static func run(file: String, engine: AzooKeyConverterEngine) throws {
        let store = StaticSettings(DefaultSettings.settings)
        let terms = EnglishTerms(bundled: EnglishTermFile(url: URL(fileURLWithPath: file)), settings: store)
        let converter = SupplementedConverter(engine.makeSession(), settings: store, calendar: SystemCalendar(clock: { Date() }), englishTerms: terms)
        let session = engine.makeSession()
        let text = try String(contentsOfFile: file, encoding: .utf8)
        for line in text.split(whereSeparator: \.isNewline) where !line.hasPrefix("#") {
            let term = String(line)
            guard EnglishTermDictionary.isValidTerm(term), let reading = ReadingNormalization.normalized(term.lowercased()) else { continue }
            let words = session.segmentationWords(for: reading).map { "\($0.text)(\($0.readingCount))" }.joined(separator: "|")
            let candidates = converter.listCandidates(for: reading).prefix(3).map(\.text)
            let first = candidates.first == term ? "first" : "-"
            print([term, reading, words, String(format: "%.1f", session.plausibility(of: reading)), candidates.joined(separator: " "), first]
                .joined(separator: "\t"))
        }
    }
}
