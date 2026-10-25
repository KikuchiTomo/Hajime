# 0001 製品は新しいリポジトリで作り，azooKey は fork を参照する

- 状態: 採用
- 日付: 2026-10-25

## 背景

azooKey から分かれて独自に進める．macOS と Windows の両方を作り，あとでほかの OS にも広げる．azooKey 側のエンジンの改善は取り込みたい．

## 判断

- 製品は新しい公開リポジトリ `KikuchiTomo/s90.tokyo-IME` で作る．GitHub の fork にはしない
- `AzooKeyKanaKanjiConverter`，`azooKey-Desktop`，`azooKey-Windows` は fork を作り，参照元として使う
- 変換エンジンは fork を SwiftPM の依存として revision で固定して使う
- アプリのコードは fork からこのリポジトリに移しながら，`docs/dev/ARCHITECTURE.md` の層に合わせて作り直す

## 検討したほかの案

| 案 | 採らなかった理由 |
|---|---|
| azooKey-Desktop の fork をそのまま製品のリポジトリにする | macOS 専用の構成のまま Windows を足すことになる．GitHub の fork は検索や PR の既定の宛先が元のリポジトリになり，独自に進めるには向かない |
| エンジンのソースをこのリポジトリにコピーする | azooKey の改善を取り込むたびに手で差分を当てることになる |
| git submodule で fork を入れる | SwiftPM の依存で足りる．submodule は clone の手順を増やす |

## 結果

macOS と Windows のコードを 1 つのリポジトリで同時に変えられる．エンジンの更新は fork の merge と revision の更新で済む．
アプリの層は azooKey-Desktop と形が変わるので，azooKey-Desktop の変更はコミット単位では取り込めず，読んで書き直すことになる．
