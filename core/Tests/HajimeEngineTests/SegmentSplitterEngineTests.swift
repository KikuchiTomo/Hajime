import Foundation
import HajimeDomain
import HajimeEngine
import Testing

/// 文節を区切る位置(⇧↓)を，本物の変換器(Zenzai なし)で確かめる
@Suite("文節を区切る位置(本物のエンジン)")
@MainActor
struct SegmentSplitterEngineTests {
    @Test("語の切れ目だけで切る．1 文字ごとや語の途中では切らない", arguments: [
        ("それはもんだいがあるとおもう", "それ｜は｜問題｜が｜ある｜と｜思う"),
        ("もんだいがある", "問題｜が｜ある"),
        ("いちどろぐあうとして", "一度｜ログアウト｜して"),
        ("てんきですね", "天気｜です｜ね"),
        ("あるとおもう", "ある｜と｜思う"),
        ("わたしはがくせいです", "私｜は｜学生｜です"),
        ("ほんをよんでください", "本｜を｜読んで｜ください"),
        ("おちゃをのむ", "お茶｜を｜飲む"),
        ("うんてんめんきょ", "運転｜免許"),
        ("わからないです", "わからないです"),
        ("かいて", "書いて"),
    ])
    func splitsAtWords(reading: String, expected: String) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hajime-split-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try AzooKeyConverterEngine(memoryDirectory: directory, versionString: "split").makeSession()
        let shown = session.segmentationWords(for: reading).map(\.text).joined()
        let split = SegmentSplitter.split(
            shown: shown, reading: reading,
            candidates: { part in session.dictionaryCandidates(for: part).filter { $0.readingCount == part.count }.map(\.text) },
            words: session.segmentationWords(for:))
        #expect(split.pieces.joined(separator: "｜") == expected)
    }
}
