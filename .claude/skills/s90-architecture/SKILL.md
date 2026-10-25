---
name: s90-architecture
description: s90.tokyo IME のコードの置き場所・層・依存の向き・SOLID/DRY の決まりに従って設計と実装を進める．新しい型・ファイル・モジュール・ディレクトリを作るとき，機能を実装するとき，既存コードを移す・分割する・リファクタリングするとき，azooKey からコードを持ち込むときは必ず使う．「どこに書くか」「どの層か」を少しでも判断する場面なら，明示されていなくても使うこと．Use for any design, placement, layering, dependency, refactor or new-feature work in this repository.
---

# s90.tokyo IME のアーキテクチャに従う

決まりの本体は `docs/dev/ARCHITECTURE.md` と `docs/dev/GUIDELINES.md` にある．このスキルは，それを作業の手順に落としたもの．決まりそのものを変えたいときは，コードより先に文書と ADR を変える(`docs/dev/adr/README.md`)．

## 作業を始める前に

1. `docs/dev/ARCHITECTURE.md` を読む(毎回．層の名前と依存の向きを取り違えないため)
2. 関係する要件の ID を `docs/specs/REQUIREMENTS.md` から探す．無ければ，要件を足すべきかを利用者に確かめる
3. 下の「置き場所の決め方」で置き場所を決め，作るファイルの一覧を先に示してから書き始める

## 置き場所の決め方

上から順に当てはめ，最初に当てはまったところに置く．

| 問い | はい のとき |
|---|---|
| OS の API(AppKit，InputMethodKit，Win32，TSF)を呼ぶか | `apps/macos/` か `apps/windows/` のアダプタ |
| ファイル・時刻・変換エンジン・ネットワークに触れるか | `S90Application/Ports/` に protocol，実装は `S90Engine` か `S90Persistence` |
| 状態を進める・複数のポートを組み合わせるか | `S90Application` のユースケース |
| 値から値を計算するだけか | `S90Domain` |

アダプタに `if` が増えてきたら，その判断は core に移すべきもののことが多い．macOS と Windows で同じ判断が要るなら core の仕事．

## 依存の向き

```
apps / s90-engine-host / S90Engine / S90Persistence → S90Application → S90Domain
```

- 内側から外側を import しない．`S90Domain` は Foundation の値の型以外を import しない
- azooKey の型(`KanaKanjiConverterModule` など)は `S90Engine` の外に出さない．出したくなったら Domain に自前の型を作り，アダプタで写す
- 具象の組み立ては composition root(`apps/macos/S90IME/CompositionRoot.swift`，`core/Sources/s90-engine-host/main.swift`)だけ

書いたあとで `python3 -I .claude/skills/s90-architecture/scripts/check_layers.py` を実行し，import の向きを確かめる．

## SOLID と DRY をこのリポジトリでどう守るか

抽象的な原則を，ここで実際に起きる形に置き換えたもの．詳しい例は `references/principles.md`．

- 単一責任: 入力メソッドのコントローラ・`InputSession`・候補ウィンドウに，変換・表示・設定の読み込みを同居させない．1 つの型が変わる理由は 1 つ
- 開放閉鎖: 入力方式(ローマ字・かな・EN)やプロファイルを足すときに既存の `switch` を書き換えて回らずに済むよう，方式ごとの振る舞いは protocol の実装として足す．ただし網羅したい列挙(`ScriptVariant` など)は enum のままにする
- リスコフ: Fake とアダプタは本物と同じ事前条件・事後条件を守る．Fake だけ例外を投げない，などの差を作らない
- インターフェース分離: ポートは使う側の都合で小さく切る．`SettingsStore` に辞書の操作を足さない
- 依存性逆転: ユースケースはポートの protocol だけを知る
- DRY: 同じ「判断」を 2 か所に書かない．同じに見えるコードでも，変わる理由が違うなら無理にまとめない(例: macOS と Windows のキーコードの表は別物)
- 値の直書きをしない．色と寸法は `design/tokens/`，既定値は `DefaultSettings.swift`

## 新しい機能を足すときの順序

1. Domain の型と，その単体テスト
2. Application のユースケースと，キーの列から `ClientAction` の列を確かめるシナリオのテスト(`InputSessionScenarioTests`)
3. 必要ならポートと実装
4. 最後に各 OS のアダプタ

アダプタから書き始めると，判断がアダプタに入り込む．

## やめておくこと

- シングルトン，`static var` の共有状態，`NotificationCenter` を使った層をまたぐ通知
- 汎用の `Utils` / `Helpers` / `Manager` という名前のファイル．責務を名前にする
- 先回りの抽象化．実装が 1 つしかなく，差し替える予定も無い protocol は作らない(ポートは例外．テストで差し替えるため)

## 終わる前の確認

- [ ] 作ったファイルが ARCHITECTURE.md のディレクトリの説明と食い違っていない
- [ ] `check_layers.py` が通る
- [ ] Domain と Application の変更にテストがある
- [ ] 構成を変えたなら ARCHITECTURE.md を更新し，判断を変えたなら ADR を足した
- [ ] 入力内容・ファイル・通信に触れたなら `s90-security` スキルの確認をした
