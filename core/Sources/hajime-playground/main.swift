import Foundation
import HajimeDomain

// 入力メソッドとして入れずに，ターミナルで変換を試し，精度を測る道具(make try)．composition root のひとつ．
//
// 使い方:
//   hajime-playground [--zenzai <モデル>]                         ローマ字を打って結果を見る
//   hajime-playground --evaluate <TSV> [--zenzai <モデル>]        評価用の文の正解の割合と変換の時間
//   hajime-playground --evaluate-live <TSV> [--zenzai <モデル>]   打っている途中の表示の誤り
//   hajime-playground --evaluate-typo <TSV> [--zenzai <モデル>]   打ち間違いの補正(直した・示した・直さなかった)
//   hajime-playground --evaluate-language <TSV> [--zenzai <モデル>] 英字入力(自動)で英語と日本語を見分けた結果
//   hajime-playground --typo-candidates <キー> [--zenzai <モデル>] 打ったキーの訂正の候補と点数
//   hajime-playground --correction-features <TSV> [--zenzai <モデル>] 訂正の候補ごとの材料(重みと境目を決めるため)
//   hajime-playground --split <読み,読み,…>                      文節を区切るときに区切れる位置
//   hajime-playground --plausibility <読み,読み,…>               読みの変換のもっともらしさと時間
//   hajime-playground --words <読み,読み,…>                      読みを変換したときの語の並び
//
// どの使い方でも --dictionary <ディレクトリ> を付けると，azooKey に同梱の辞書の代わりにその辞書で変換する(辞書を作り直して比べるため)

MainActor.assumeIsolated {
    let arguments = Arguments()
    do {
        let playground = try PlaygroundEngine(zenzaiPath: arguments.value(of: "--zenzai"), dictionaryPath: arguments.value(of: "--dictionary"))
        defer { playground.removeMemory() }
        print("Zenzai: \(playground.engine.usesZenzai ? "あり" : "なし")")
        if let file = arguments.value(of: "--evaluate") {
            Evaluation.conversion(cases: try EvaluationCase.load(from: file), engine: playground.engine)
        } else if let file = arguments.value(of: "--evaluate-live") {
            Evaluation.live(cases: try EvaluationCase.load(from: file), engine: playground.engine)
        } else if let file = arguments.value(of: "--evaluate-typo") {
            try Evaluation.typo(file: file, engine: playground.engine, service: playground.typoService)
        } else if let file = arguments.value(of: "--evaluate-language") {
            try Evaluation.language(file: file, engine: playground.engine)
        } else if let file = arguments.value(of: "--correction-features") {
            try Evaluation.correctionFeatures(file: file, engine: playground.engine, service: playground.typoService)
        } else if let readings = arguments.value(of: "--words") {
            // 読みを変換したときの語の並び(文節の区切りと，先頭の語の候補を作るのに使う)
            let session = playground.engine.makeSession()
            for reading in readings.split(separator: ",").map(String.init) {
                print(reading, "→", session.segmentationWords(for: reading).map { "\($0.text)(\($0.readingCount))" }.joined(separator: " | "))
            }
        } else if let readings = arguments.value(of: "--split") {
            // 文節を区切る(⇧↓)ときに区切れる位置
            let session = playground.engine.makeSession()
            let clock = ContinuousClock()
            for reading in readings.split(separator: ",").map(String.init) {
                var split = SegmentSplitter.Split(positions: [], pieces: [])
                let time = clock.measure {
                    let shown = session.segmentationWords(for: reading).map(\.text).joined()
                    split = SegmentSplitter.split(
                        shown: shown, reading: reading,
                        candidates: { part in session.dictionaryCandidates(for: part).filter { $0.readingCount == part.count }.map(\.text) },
                        words: session.segmentationWords(for:))
                }
                print(reading, "→", split.pieces.joined(separator: "｜"), " (\(time))")
            }
        } else if let readings = arguments.value(of: "--plausibility") {
            // 読みごとの変換のもっともらしさと，求めるのにかかる時間
            let session = playground.engine.makeSession()
            let clock = ContinuousClock()
            for reading in readings.split(separator: ",").map(String.init) {
                var score = 0.0
                let time = clock.measure { score = session.plausibility(of: reading) }
                print(String(format: "%8.2f  %@  ", score, reading), time)
            }
        } else if let keys = arguments.value(of: "--typo-candidates") {
            // 打ったキーに対する訂正の候補と点数(補正の手間を調べるため)
            let session = playground.engine.makeSession()
            for correction in session.typoCorrections(forKeys: keys).prefix(40) {
                let reading = KanaWidth.hiragana(from: correction.reading)
                print(String(format: "%7.2f  手間 %5.2f  変換 %7.2f  %@  %@", correction.score, correction.cost, session.plausibility(of: reading),
                             correction.keys, correction.reading))
            }
        } else {
            Interactive.run(engine: playground.engine)
        }
    } catch {
        print("起動できませんでした: \(error)")
        exit(1)
    }
}
