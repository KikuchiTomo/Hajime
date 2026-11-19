---
title: Code signing policy
description: Code signing policy for the release packages of Hajime IME
---

This page describes how the release packages of Hajime IME are built and signed.

## Windows

The Windows installer is currently unsigned, so Windows shows a SmartScreen warning when the installer is opened. Windows releases will be signed with an open source code signing certificate issued by [Certum](https://www.certum.eu) as follows.

| Item | Policy |
|---|---|
| Signed files | The installer (`.msi`) and every executable and DLL in it that is not already signed by its publisher |
| Publisher | The name on the signature starts with "Open Source Developer", followed by the name of the maintainer |
| Signing | Done by the same public workflow that builds the release. Binaries built on a developer's PC are never signed |
| Private key | Kept in the cloud service of Certum. The project does not hold it |
| Timestamp | Every signature has a timestamp, so it stays valid after the certificate expires |

## macOS

macOS releases are signed with an Apple Developer ID certificate and notarized by Apple.

## Build

| Item | Policy |
|---|---|
| Build | Built from a version tag by the [public workflow](https://github.com/KikuchiTomo/Hajime/blob/main/.github/workflows/release.yml) on GitHub-hosted runners of GitHub Actions |
| Integrity | `SHA256SUMS.txt`, published with every release, lists the SHA-256 hash of each release package |

## Distribution

Releases are published only on [GitHub Releases](https://github.com/KikuchiTomo/Hajime/releases) and https://haji.men/download/.

## Privacy policy

Hajime IME connects to https://haji.men only when the user selects "更新を確認" (Check for Updates). It does not send anything the user types over the network. See the [privacy policy](privacy.en.md).
