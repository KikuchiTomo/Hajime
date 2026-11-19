---
title: Code signing policy
description: Code signing policy for the release packages of Hajime IME
---

This page describes how the release packages of Hajime IME are signed.

## Windows

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

## macOS

macOS releases are signed with an Apple Developer ID certificate and notarized by Apple.

## Distribution

Releases are published only on [GitHub Releases](https://github.com/KikuchiTomo/Hajime/releases) and https://haji.men/download/.

## Privacy policy

This program will not transfer any information to other networked systems unless specifically requested by the user or the person installing or operating it.

Hajime IME connects to https://haji.men only when the user selects "更新を確認" (Check for Updates). See the [privacy policy](privacy.md) (in Japanese).
