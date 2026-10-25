# 0006 かな漢字変換に Zenzai を使う

- 状態: 採用
- 日付: 2026-10-26
- 関係する要件: R-01

## 背景

利用者から，変換の第 1 候補の誤りが報告された(「Cloudflareで撮ったドメイン」，「い事に」，「AAA間で」など)．どれも正しい候補は候補一覧の中にあり，第 1 候補の選び方だけが誤っていた．
azooKey のエンジンは，Zenzai(文と左の文脈を見るニューラルかな漢字変換)を切ると，隣り合う語のつながりだけで第 1 候補を決める．

## 測った結果

評価用の文 24 件(`core/Evaluation/conversion-basic.tsv`．報告された例と，同音異義語を文脈で選ぶ例)で比べた．Apple Silicon，Release ビルド．

| | 正解 | 1 回の変換の時間(中央値) | 1 キーの処理時間(p95) |
|---|---|---|---|
| Zenzai なし | 14 / 24 | 32ms | 30ms |
| Zenzai あり | 23 / 24 | 39ms | 34ms |

- その端末で初めてモデルを使ったときだけ，最初の変換に 14 秒かかった．以後はプロセスを起動し直しても 0.14 秒だった
- 「いじにねんかん」は Zenzai ありでも「維持2年間」になる

測り直すときは次を実行する．

```sh
tools/models/fetch_zenzai.sh
swift run --package-path core -c release s90-playground --evaluate core/Evaluation/conversion-basic.tsv --zenzai ../models/zenz-v3.2-small-Q5_K_M.gguf
S90_ZENZAI_MODEL=../models/zenz-v3.2-small-Q5_K_M.gguf swift test --package-path core -c release --filter LatencyProbeTests
```

## 判断

- エンジンの Zenzai の trait を有効にしてビルドする
- モデルは Miwa-Keita/zenz-v3.2-small-gguf の `ggml-model-Q5_K_M.gguf`(Apache-2.0，約 70MB)．Hugging Face のコミットを固定し，SHA-256 をリポジトリ(`ZenzaiModel.swift`)に書く
- モデルはリポジトリに入れない．`tools/models/fetch_zenzai.sh` で取得してハッシュを確かめ，ビルドのときにアプリの中に入れる
- アプリは起動時にモデルの大きさとハッシュを確かめ，合わなければ Zenzai を使わずに動く
- 打ち始めに入力位置の前の文字列(最大 40 字)を左の文脈として渡す．パスワード欄では読まない．中身はログに出さない
- 起動時に一度変換し，最初の変換の待ちを打ち始める前に済ませる
- 推論は同期のまま(1 キーの処理が 50ms 以内に収まったため)

## 検討したほかの案

| 案 | 採らなかった理由 |
|---|---|
| Zenzai を使わず，誤りごとに規則で直す | 誤りの種類が文脈によるもので，規則では際限がない |
| モデルをリポジトリに入れる | 70MB あり，履歴が重くなる．取得とハッシュの確認で同じ版を使える |
| 推論を非同期にする | 今の処理時間では要らない．重いモデルに替えるときに改めて決める |

## 結果

第 1 候補の精度が上がり，左の文脈で変わる変換(「AAAまで」)にも対応できる．
アプリは 70MB 大きくなる．エンジンを読み込むターゲットは C++ との相互運用を有効にする必要がある．
