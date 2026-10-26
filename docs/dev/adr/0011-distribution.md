---
title: "0011 配布の経路"
description: macOS と Windows の配布物をどこで配るか．ストアで配れるかと，そのために要るもの
---

- 状態: 採用
- 日付: 2026-10-27

## 背景

利用者は次の経路で配りたいと考えている．

1. macOS は App Store(Apple Developer Program に参加している)
2. Windows は Microsoft Store(SmartScreen の警告を避けるため．開発者のプログラムにはまだ参加していない)
3. それとは別に，ダウンロードして使えるものを配る

どの経路でも，macOS と Windows はまったく同じ挙動にする．

## 調べたこと(2026-10-27)

### Mac App Store

- App Store Review Guidelines 2.4.5 は，Mac App Store のアプリにサンドボックスを求め，「自己完結した 1 つのアプリのバンドルで，共有の場所にコードやリソースを入れてはならない」とし，Xcode 以外のインストーラーも認めていない．入力メソッドは `/Library/Input Methods` か `~/Library/Input Methods` に置かないと OS が読み込まないので，この決まりに当たる
- ガイドラインには Mac の入力メソッドについての記述が無い(キーボードの拡張の決まり 4.4.1 は iOS のもの)
- 入力メソッドを申請して「UI の無いバックグラウンドのアプリ」として却下された例と，Apple から「できない」と答えられたという開発者の報告がある(Apple Developer Forums の thread 43817)．Apple の担当者の書き込みは無く，確かめられたのは開発者の報告だけ
- サンドボックスに入れた入力メソッドは作れる(このリポジトリの macOS 版もサンドボックスに入れている)．ストアで配れないのは置き場所の決まりのため

### Microsoft Store

- Microsoft Store は MSIX のほかに，MSI・EXE のインストーラーを載せられる．インストーラーそのものは上げず，HTTPS で取れる場所を登録する．黙って入れられること(UAC の確認は出てよい)が要る
- MSI・EXE はストアが署名し直さない．インストーラーと，中のすべての実行ファイル(EXE・DLL)を，Microsoft Trusted Root Program に入った認証局の証明書で Authenticode 署名する必要がある．自己署名の証明書は通らない
- TSF のテキストサービス(入力方式)を MSI で配ってよいかの記述は見つからなかった．審査で確かめる必要がある
- MSIX はアプリの外の場所(すべてのアプリに読み込まれる TSF の DLL の登録)を扱えないので使わない

## 判断

- **ダウンロードして使えるもの**を GitHub の Releases で配る．タグ `macos/vX.Y.Z`・`windows/vX.Y.Z` を付けると `release.yml` が作って置く(docs/dev/RELEASE.md)．今は署名しない
- **macOS** は App Store では配れないとみなし，App Store の代わりに Developer ID で署名して公証した .pkg を Releases で配る．署名と公証は `tools/macos/package.sh` が対応している．CI で行うには証明書と公証の資格情報を GitHub の Secrets に置く必要があり，利用者が設定する
- **Windows** は Microsoft Store に MSI のインストーラーとして載せる．そのためにも，SmartScreen の警告を減らすためにも，MSI と中の EXE・DLL を信頼された証明書で署名する．証明書(Azure Trusted Signing か，認証局の OV・EV の証明書)の用意と Microsoft Store の開発者の登録は利用者が行う
- 署名に使う秘密の値はこのリポジトリのコードとワークフローに書かず，利用者が Secrets に置いたものだけを使う

## 検討したほかの案

| 案 | 採らなかった理由 |
|---|---|
| macOS の入力メソッドをアプリに入れて App Store で配り，初回の起動で `~/Library/Input Methods` に写す | 2.4.5(ii)(iv) の「共有の場所に入れない」「あとからコードを入れない」に当たる |
| Windows を MSIX で配る | TSF の DLL をすべてのアプリに読み込ませる登録が MSIX の中ではできない |
| 署名するまで配らない | 試したい人が手に入れられない．署名していないことと開き方を Releases の説明に書いて配る |

## 結果

- 署名をしていないあいだは，macOS では「このまま開く」，Windows では SmartScreen の「詳細情報」から「実行」が要る．Releases の説明に書く(`tools/release/notes/`)
- macOS と Windows で同じバージョンの機能をそろえる決まりは ADR 0008 のまま
- App Store の判断は，Apple が入力メソッドの扱いを変えたら見直す

参考: [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)，[Apple Developer Forums thread 43817](https://developer.apple.com/forums/thread/43817)，[Distribute your Win32 app through the Microsoft Store](https://learn.microsoft.com/en-us/windows/apps/distribute-through-store/how-to-distribute-your-win32-app-through-microsoft-store)，[MSI・EXE の申請の手引き(Advanced Installer)](https://www.advancedinstaller.com/publish-msi-exe-app-microsoft-store.html)
