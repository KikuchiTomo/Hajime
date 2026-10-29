---
title: "0012 Linux 版の組み立て"
description: Linux 版を Windows 版と同じく，入力の枠組みの薄い口と別のプロセスのエンジンに分けて作る
---

- 状態: 提案
- 日付: 2026-10-27

## 背景

macOS 版と Windows 版のあとに Linux 版を作る．Linux の日本語入力は，入力の枠組み(Fcitx 5 か IBus)の上で動く．
どちらもデスクトップ環境ごとに使われ方が違い，Wayland では入力メソッドの窓を好きな位置に出せない．
macOS 版・Windows 版と同じ機能を，同じ挙動で使えるようにする(ADR 0008・0011)．

## 判断

- **エンジンは Windows と同じく別のプロセスにする**．`hajime-engine-host`(Swift)を Linux でも作り，入力の状態・候補・補正はすべて core(`EngineService`)で行う．枠組みの口は，キーを渡して結果を画面に出すだけにする
- **通信は Unix ドメインソケット**にする．メッセージの形(`protocol/`，長さ付きの JSON)は Windows の名前付きパイプと同じにし，送り方だけを替える．ソケットは `$XDG_RUNTIME_DIR/haji.men/engine.sock`(本人だけが読み書きできる場所)に置き，つないできた相手が同じユーザーかを `SO_PEERCRED` で確かめる(Windows の「同じセッション」に当たる)
- **最初の口は Fcitx 5 のアドオン**(C++)にする．日本語の利用者が多く，Wayland でも入力欄の位置に候補を出す仕組み(classicui・kimpanel)がある．IBus の口はそのあとで足す
- **候補の出し方**は，最初は枠組みの候補の一覧(一覧の表示)を使う．分岐図は枠組みの外に窓を出す必要があるので，X11 では別のプロセスの窓で描き，Wayland では枠組みの UI の口(Fcitx 5 の UI アドオン)で描けるかを試してから決める
- **設定の画面**は，Windows の設定の画面と同じく設定の目録(`protocol/settings-catalog.json`)から作る．GTK 4 で作るか，Windows と共通の Rust の UI にするかは，作り始めるときに決める
- **配布**は Flatpak ではなく，distro のパッケージ(.deb・.rpm)にする．入力の枠組みのアドオンは決まった場所(`/usr/lib/fcitx5`)に置く必要があり，サンドボックスの中からは入れられないため

## 準備として行うこと

1. core を Linux でビルドしてテストを通す(Swift の公式の Linux のツールチェーン)．CI に `core-linux` を足す
2. `HajimeIPC` に Unix ドメインソケットの送り方を足し，Windows の `EnginePipeServer` と共通の部分(要求をセッションに渡す処理)を分ける
3. `hajime-engine-host` の置き場所(`HostPaths`)を Linux の XDG の場所にする(設定は `$XDG_CONFIG_HOME/haji.men/IME`，学習データは `$XDG_DATA_HOME/haji.men/IME`)
4. Fcitx 5 のアドオンを `apps/linux/fcitx5` に作る．C++ の薄い口(`src/`)と，エンジンと話す Rust の橋渡し(`bridge/`．Windows と同じ `ipc` を使う静的ライブラリ)に分ける．C++ は JSON もソケットも扱わない
   - エンジンは候補の指示(`UiCommand`)を，Windows の候補ウィンドウと同じ形で `candidate-window.sock` に送る(`CandidateWindowLink` を Windows と共通にした)．アドオンがそれを受け取り，Fcitx 5 の候補の一覧と案内(上下の補助の文)に出す．分岐図は，選んでいる文節の候補と種類を一覧にする
   - キーはエンジンの返事を待ってから受け取るかを決める(上限は `timing.ENGINE_STALL_MILLISECONDS`)．Windows のように遅れた返事を後から当てる仕組みは，まだ入れていない
   - まだ無いもの: マウスで候補を選ぶ，再変換，モードの札，手書き，設定の画面，配布のパッケージ
5. Rust の手元側(`apps/windows/crates/ipc`)のつなぎ方を差し替えられるようにし，Unix ドメインソケットでもつなぐ(`ipc::unix`)．Windows と Linux で要求の送り方と挨拶を共通にする．つなぐ前に，ソケットのフォルダが本人のもので，ほかの人が読み書きできないことを確かめる

## 準備で分かった Linux の残り

- Linux の Foundation(swift-corelibs-foundation)は Shift_JIS と EUC-JP を読めない．取り込む辞書のうち，この 2 つの符号化のファイルはまだ読めない(UTF-8・UTF-16 は読める)．JIS X 0208 の対応表を持って自分で読むか，ICU の変換を使うかを決める
- 英単語の辞書(macOS の NSSpellChecker・Windows のスペルチェッカーに当たるもの)が無い．Hunspell などを使うかを決める

## 検討したほかの案

| 案 | 採らなかった理由 |
|---|---|
| エンジンを枠組みのアドオンの中で動かす | Fcitx 5 のプロセスに Swift のランタイムと数百 MB のモデルを読み込むことになり，不具合が入力全体を止める．Windows と作りが分かれる |
| IBus を先に作る | GNOME では標準だが，IBus の候補の窓は形を変えにくく，分岐図を描く口が無い |
| Flatpak で配る | 入力の枠組みのアドオンをサンドボックスの外の決まった場所に置けない |

## 結果

core と通信の形は 3 つの OS で共通になり，Linux で書くのは枠組みの口と送り方だけになる．
Wayland で分岐図をどう出すかは，Fcitx 5 の UI の口を試してから決める(この ADR を更新する)．
