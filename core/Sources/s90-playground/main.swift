import Foundation

// 入力メソッドとして入れずに，ターミナルで変換を試し，精度を測る道具(make try)．composition root のひとつ．
//
// 使い方:
//   s90-playground [--zenzai <モデル>]                         ローマ字を打って結果を見る
//   s90-playground --evaluate <TSV> [--zenzai <モデル>]        評価用の文の正解の割合と変換の時間
//   s90-playground --evaluate-live <TSV> [--zenzai <モデル>]   打っている途中の表示の誤り

MainActor.assumeIsolated {
    let arguments = Arguments()
    do {
        let playground = try PlaygroundEngine(zenzaiPath: arguments.value(of: "--zenzai"))
        defer { playground.removeMemory() }
        print("Zenzai: \(playground.engine.usesZenzai ? "あり" : "なし")")
        if let file = arguments.value(of: "--evaluate") {
            Evaluation.conversion(cases: try EvaluationCase.load(from: file), engine: playground.engine)
        } else if let file = arguments.value(of: "--evaluate-live") {
            Evaluation.live(cases: try EvaluationCase.load(from: file), engine: playground.engine)
        } else {
            Interactive.run(engine: playground.engine)
        }
    } catch {
        print("起動できませんでした: \(error)")
        exit(1)
    }
}
