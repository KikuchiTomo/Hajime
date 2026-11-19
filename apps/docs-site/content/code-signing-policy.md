---
title: コード署名ポリシー
description: Hajime IME の配布物のコード署名の方針(Code signing policy)
---

Hajime IME の配布物のコード署名の方針です．English: [Code signing policy](#code-signing-policy)

## Windows 版

Windows 版は現在未署名です．[SignPath Foundation](https://signpath.org) の OSS 向けのコード署名を申請し，承認後は次のとおり署名します．

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org)

| 項目 | 内容 |
|---|---|
| 署名の対象 | インストーラー(`.msi`)と，このリポジトリのソースコードからビルドした Hajime IME の実行ファイル・DLL |
| 署名しないもの | 同梱する第三者のライブラリ(Swift のランタイム，ICU，llama.cpp) |
| ビルド | バージョンのタグから，GitHub Actions の[公開のワークフロー](https://github.com/KikuchiTomo/Hajime/blob/main/.github/workflows/release.yml)が GitHub ホストのランナーで実行 |
| 署名の提出 | GitHub Actions がビルドした配布物のみ．開発者の PC でビルドしたものは提出しません |
| 承認 | リリースごとに承認者が手動で承認 |
| 秘密鍵 | SignPath の HSM で管理．開発者は保持しません |

### 役割

| 役割 | 担当 |
|---|---|
| Committers and reviewers | [KikuchiTomo](https://github.com/KikuchiTomo) |
| Approvers | [KikuchiTomo](https://github.com/KikuchiTomo) |

## macOS 版

macOS 版は，Apple の Developer ID の証明書で署名し，Apple の公証を受けています．

## 配布場所

配布物は [GitHub の Releases](https://github.com/KikuchiTomo/Hajime/releases) と https://haji.men/download/ でのみ公開します．

## プライバシー

Hajime IME は，利用者が「更新を確認」を選択した場合を除き，通信しません．詳細は[プライバシーポリシー](privacy.md)をご覧ください．

## Code signing policy

### Windows

The Windows installer is currently unsigned. Once our application to the [SignPath Foundation](https://signpath.org) program for open source projects is approved, Windows releases will be signed as follows.

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org)

| Item | Policy |
|---|---|
| Signed files | The installer (`.msi`) and the Hajime IME executables and DLLs built from the source code in this repository |
| Not signed | Bundled third-party libraries (Swift runtime, ICU, llama.cpp) |
| Build | Built from a version tag by the [public workflow](https://github.com/KikuchiTomo/Hajime/blob/main/.github/workflows/release.yml) on GitHub-hosted runners of GitHub Actions |
| Submission | Only artifacts built by GitHub Actions are submitted for signing. Binaries built on a developer's PC are never submitted |
| Approval | An approver manually approves the signing request of every release |
| Private key | Kept in the HSM of SignPath. The project does not hold it |

### Team roles

| Role | Members |
|---|---|
| Committers and reviewers | [KikuchiTomo](https://github.com/KikuchiTomo) |
| Approvers | [KikuchiTomo](https://github.com/KikuchiTomo) |

### macOS

macOS releases are signed with an Apple Developer ID certificate and notarized by Apple.

### Distribution

Releases are published only on [GitHub Releases](https://github.com/KikuchiTomo/Hajime/releases) and https://haji.men/download/.

### Privacy policy

This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it. Hajime IME connects to https://haji.men only when the user selects "更新を確認" (Check for Updates). See the [privacy policy](privacy.md) (in Japanese).
