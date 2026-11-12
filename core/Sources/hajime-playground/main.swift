import Foundation
import HajimeDomain
import HajimeEngine

// 入力メソッドとして入れずに，ターミナルで変換を試し，精度を測る道具(make try)．composition root のひとつ．
//
// 使い方:
//   hajime-playground [--zenzai <モデル>]                         ローマ字を打って結果を見る
//   hajime-playground --evaluate <TSV> [--zenzai <モデル>]        評価用の文の正解の割合と変換の時間
//   hajime-playground --dump-candidates <TSV> [--zenzai <モデル>] [--score]
//                                                                文ごとの候補(上位 20)と時間を JSON Lines で出す(tools/evaluation/complementarity.py が読む)．
//                                                                --score を付けると，Zenzai を使わない変換の候補も合わせて検証木で採点した点数も出す
//   hajime-playground --bench-scoring <TSV> --zenzai <モデル> [--repeat 5] 検証木の採点 1 回の時間(文ごとに繰り返した最小と中央値)
//   hajime-playground --bench-jinen <TSV> --zenzai <モデル> --jinen <Jinen モデル> [--jinen-variant xsmall] jinen だけで 1 文を変換した時間と正解の数
//   hajime-playground --evaluate-live <TSV> [--zenzai <モデル>]   打っている途中の表示の誤り
//   hajime-playground --evaluate-operations <TSV> [--presentation automatic,segmentList,list] [--shard k/n] [--warm-before-space] [--zenzai <モデル>]
//                                                                期待する文に着くまでの操作(↓ ← → ⇧← ⇧→)の数と，着いた割合．
//                                                                --no-reranking を付けると候補を検証木の点数で並べ替えない(設定の candidateReranking を切る)
//   hajime-playground --evaluate-typo <TSV> [--zenzai <モデル>] [--typing-interval <秒>]
//                                                                打ち間違いの補正(直した・示した・直さなかった)．
//                                                                --typing-interval を付けると，その間隔で打ったときのように打鍵の合間に訂正を前もって求める
//   hajime-playground --evaluate-language <TSV> [--zenzai <モデル>] 英字入力(自動)で英語と日本語を見分けた結果
//   hajime-playground --typo-candidates <キー> [--zenzai <モデル>] 打ったキーの訂正の候補と点数
//   hajime-playground --correction-features <TSV> [--zenzai <モデル>] 訂正の候補ごとの材料(重みと境目を決めるため)
//   hajime-playground --split <読み,読み,…>                      文節を区切るときに区切れる位置
//   hajime-playground --plausibility <読み,読み,…>               読みの変換のもっともらしさと時間
//   hajime-playground --panels <読み,読み,…> [--zenzai <モデル>] 読みを打ったときに候補の窓(入力中の候補の窓・分岐図・文節ごとの一覧・文全体の一覧)に出る候補．
//                                                                絵文字に印を付け，1 ページに見える数で区切る．--no-reranking で検証木の並べ替えを，
//                                                                --no-context で文節の候補の前後の文脈での並べ替えを切る
//   hajime-playground --words <読み,読み,…>                      読みを変換したときの語の並び
//   hajime-playground --english-terms <ファイル>                  英語の語の辞書(R-24)の語ごとの読み・語の並び・もっともらしさ・候補の先頭
//   hajime-playground --startup <同梱の辞書> [--zenzai <モデル>] [--zenzai-fast <xsmall のモデル>] [--jinen <small>] [--jinen-fast <xsmall>]
//                                                                起動(モデルと辞書の確認・エンジン・warmUp)から最初の変換までの時間
//
// どの使い方でも --dictionary <ディレクトリ> を付けると，azooKey に同梱の辞書の代わりにその辞書で変換する(辞書を作り直して比べるため)
// --tree-tokens <数> を付けると，検証木の採点で評価するトークンの数をその数に決める(アプリは採点の時間で増減させる．評価の結果を負荷で変えないため)
// --zenzai-variant xsmall を付けると，--zenzai に渡したモデルを zenz-v3.2-xsmall として確かめて使う．
// --zenzai-fast <xsmall のモデル> と --zenzai-model accurate|fast|combined で，設定の「Zenzai モデル」を試す
// --jinen <Jinen モデル> [--jinen-variant small|xsmall] で，別のモデル(jinen)との合議を試す(ADR 0016 の案 2)．--evaluate と --evaluate-operations で使う
// --wait-for-models を付けると，時間による切り替え(入力中に Zenzai を使わない・採点と合議を Space で待たない)をやめ，結果を必ず待つ
// --dictionary の辞書に専門用語の辞書(terms.tsv．R-29)があれば，アプリと同じく既定の設定(すべての分野)で使う．--no-terms を付けると使わない
// 絵文字の候補は，アプリと同じくパレットの表(data/palette/palette.tsv)から引く．--emoji-source azookey で azooKey の絵文字の辞書から引き(Linux と同じ)，
// --evaluate-operations と --panels では --no-emoji・--emoji-position <何番目>・--emoji-count <数> で絵文字の設定を変える

MainActor.assumeIsolated {
    let arguments = Arguments()
    if let dictionary = arguments.value(of: "--startup") {
        do {
            try StartupProbe.run(zenzaiPath: arguments.value(of: "--zenzai"), fastZenzaiPath: arguments.value(of: "--zenzai-fast"),
                                 jinenPath: arguments.value(of: "--jinen"), fastJinenPath: arguments.value(of: "--jinen-fast"), dictionaryPath: dictionary)
        } catch {
            print("起動できませんでした: \(error)")
            exit(1)
        }
        return
    }
    do {
        let playground = try PlaygroundEngine(zenzaiPath: arguments.value(of: "--zenzai"),
                                              zenzaiVariant: arguments.value(of: "--zenzai-variant").flatMap(ZenzaiModel.Variant.init(rawValue:)) ?? .small,
                                              fastZenzaiPath: arguments.value(of: "--zenzai-fast"),
                                              zenzaiChoice: arguments.value(of: "--zenzai-model").flatMap(ZenzaiModelChoice.init(rawValue:)),
                                              jinenPath: arguments.value(of: "--jinen"),
                                              jinenVariant: arguments.value(of: "--jinen-variant").flatMap(JinenModel.Variant.init(rawValue:)) ?? .small,
                                              dictionaryPath: arguments.value(of: "--dictionary"),
                                              usesTerms: !CommandLine.arguments.contains("--no-terms"))
        defer { playground.removeMemory() }
        // 時間による切り替えをやめ，言語モデル(Zenzai・jinen)の結果を必ず待つ(負荷で評価の結果が変わらないように)
        if CommandLine.arguments.contains("--wait-for-models") { playground.engine.waitsForModels = true }
        // 検証木の採点で評価するトークンの数を決まった数にする(ほかの処理の負荷で並べ替えの結果が変わらないように)
        if let tokens = arguments.value(of: "--tree-tokens").flatMap(Int.init) { playground.engine.fixedCandidateTreeTokenLimit = tokens }
        print("Zenzai: \(playground.engine.usesZenzai ? "あり" : "なし")")
        if playground.usesFusion { print("合議: jinen") }
        // 読み<TAB>表記 の行ごとに，表記を読みにそろえられるかを出す(合議で別のモデルの候補が落ちた理由を調べる)
        if let file = arguments.value(of: "--align-check") {
            for line in try String(contentsOfFile: file, encoding: .utf8).split(whereSeparator: \.isNewline) {
                let columns = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
                guard columns.count >= 2 else { continue }
                print("\(playground.engine.alignedText(columns[1], reading: columns[0]) ?? "×")\t\(columns[1])")
            }
            return
        }
        print("専門用語の辞書: \(playground.terms == nil ? "なし" : "あり")")
        if let file = arguments.value(of: "--evaluate") {
            Evaluation.conversion(cases: try EvaluationCase.load(from: file), engine: playground.engine, terms: playground.terms,
                                  fusion: playground.usesFusion)
        } else if let file = arguments.value(of: "--evaluate-operations") {
            let presentations = (arguments.value(of: "--presentation") ?? CandidatePresentation.allCases.map(\.rawValue).joined(separator: ","))
                .split(separator: ",").compactMap { CandidatePresentation(rawValue: String($0)) }
            // --shard k/n で n 個に分けた k 番目(0 から)だけを測る．分けて並べて動かし，結果をつなげる(1 文に数秒かかるため)
            var cases = try EvaluationCase.load(from: file)
            if let shard = arguments.value(of: "--shard")?.split(separator: "/").compactMap({ Int($0) }), shard.count == 2, shard[1] > 0 {
                cases = cases.enumerated().filter { $0.offset % shard[1] == shard[0] }.map(\.element)
            }
            OperationEvaluation.run(cases: cases, engine: playground.engine, presentations: presentations,
                                    warmsBeforeSpace: CommandLine.arguments.contains("--warm-before-space"),
                                    reranking: !CommandLine.arguments.contains("--no-reranking"),
                                    emoji: PlaygroundEmoji.lookup(engine: playground.engine, arguments: arguments)) { PlaygroundEmoji.adjust(&$0, arguments: arguments) }
        } else if let file = arguments.value(of: "--bench-jinen") {
            Evaluation.benchJinen(cases: try EvaluationCase.load(from: file), engine: playground.engine)
        } else if let file = arguments.value(of: "--bench-scoring") {
            Evaluation.benchScoring(cases: try EvaluationCase.load(from: file), engine: playground.engine,
                                    repeats: arguments.value(of: "--repeat").flatMap(Int.init) ?? 5)
        } else if let file = arguments.value(of: "--dump-candidates") {
            Evaluation.dump(cases: try EvaluationCase.load(from: file), engine: playground.engine, scores: CommandLine.arguments.contains("--score"))
        } else if let file = arguments.value(of: "--evaluate-live") {
            Evaluation.live(cases: try EvaluationCase.load(from: file), engine: playground.engine)
        } else if let file = arguments.value(of: "--evaluate-typo") {
            try Evaluation.typo(file: file, engine: playground.engine, service: playground.typoService,
                                typingInterval: arguments.value(of: "--typing-interval").flatMap(Double.init))
        } else if let file = arguments.value(of: "--evaluate-language") {
            try Evaluation.language(file: file, engine: playground.engine)
        } else if let file = arguments.value(of: "--correction-features") {
            try Evaluation.correctionFeatures(file: file, engine: playground.engine, service: playground.typoService)
        } else if let file = arguments.value(of: "--english-terms") {
            // 英語の語の辞書の語を打ったときの読みと候補．日本語の語を打った人に英語の語が先に出ないか確かめる(make english-terms)
            try EnglishTermCheck.run(file: file, engine: playground.engine)
        } else if let readings = arguments.value(of: "--panels") {
            PanelDump.run(readings: readings.split(separator: ",").map(String.init), engine: playground.engine,
                          emoji: PlaygroundEmoji.lookup(engine: playground.engine, arguments: arguments)) { settings in
                if CommandLine.arguments.contains("--no-reranking") { settings.candidateReranking = false }
                if CommandLine.arguments.contains("--no-context") { settings.contextualSegmentCandidates = false }
                PlaygroundEmoji.adjust(&settings, arguments: arguments)
            }
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
            Interactive.run(engine: playground.engine, emoji: PlaygroundEmoji.lookup(engine: playground.engine, arguments: arguments))
        }
    } catch {
        print("起動できませんでした: \(error)")
        exit(1)
    }
}
