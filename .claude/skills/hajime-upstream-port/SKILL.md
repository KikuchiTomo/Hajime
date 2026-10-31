---
name: hajime-upstream-port
description: azooKey の fork(../upstream/ の AzooKeyKanaKanjiConverter・azooKey-Desktop・azooKey-Windows)からコードや変更を Hajime に持ち込む・参考にする・エンジンの revision を上げるときの手順．ライセンスの表示，差分の読み方，このリポジトリの層への書き直し方を含む．「azooKey から持ってくる」「upstream を取り込む」「エンジンを更新」「azooKey-Desktop ではどうしているか」と言われたときは必ず使う．Use whenever porting, syncing or referencing code from the azooKey forks.
---

# azooKey からの持ち込み

方針は `docs/dev/UPSTREAM.md` と `docs/dev/adr/0001-monorepo-and-forks.md`．

## 前提

- fork はこのワークツリーの外，`../upstream/<名前>` にある．origin が fork，upstream が元のリポジトリ
- いずれも MIT License．持ち込んだコードには元の著作権表示を残す

## エンジン(AzooKeyKanaKanjiConverter)を更新する

1. `git -C ../upstream/AzooKeyKanaKanjiConverter fetch upstream`
2. `core/Package.swift` に固定している revision から `upstream/main` までの `git log` と差分を読む．公開 API の変更と，辞書・モデルのファイルの変更を書き出す
3. fork の `main` に merge して push する．Hajime 独自の変更がある場合は競合を解き，独自の変更の一覧(fork の `HAJIME_CHANGES.md`)を更新する
4. `core/Package.swift` の revision を上げ，`HajimeEngine` のアダプタを直す．azooKey の型の変更はアダプタの中で吸収し，`HajimeApplication` に波及させない
5. `make test`．変換の結果が変わったテストは，エンジンの改善なのか退行なのかを PR に書く

## アプリのコード(azooKey-Desktop・azooKey-Windows)を持ち込む

コミットをそのまま当てない．構成が違うため(ADR 0001)．

1. 持ち込みたい振る舞いを 1 文で書く(例: 「ターミナルで候補ウィンドウの位置を補正する」)
2. 元のコードを読み，判断の部分と OS の API を呼ぶ部分に分ける
3. 判断の部分は `hajime-architecture` の置き場所の決め方に従って core に書き直す．テストを先に書く
4. OS の API を呼ぶ部分だけをアダプタに移す
5. 元のコードをほぼそのまま移したファイルには，先頭に次のコメントを付ける

```swift
// このファイルは azooKey-Desktop の <パス>(<コミットの短い SHA>)をもとにしている．
// Copyright (c) 2025 Miwa Keita, MIT License. 全文は THIRD_PARTY_NOTICES.md
```

6. `THIRD_PARTY_NOTICES.md` に元のリポジトリが載っていることを確かめる
7. PR に，元のコミットの URL，持ち込んだ振る舞い，持ち込まなかった部分とその理由を書く

## 持ち込まないもの

- azooKey のブランドの名前・アイコン・文言
- 通信する機能(いい感じ変換など)を，オプトインと送る内容の表示なしに持ち込むこと(`hajime-security`)
- 1 つのクラスに責務が集まった形(`azooKeyMacInputController` など)．振る舞いだけを持ち込む
