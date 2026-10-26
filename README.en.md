# s90.tokyo IME

[![CI](https://github.com/KikuchiTomo/s90.tokyo-IME/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/KikuchiTomo/s90.tokyo-IME/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-6-orange.svg)
[![Engine](https://img.shields.io/badge/engine-azooKey%20%2B%20Zenzai-6b4fbb.svg)](https://github.com/azooKey/AzooKeyKanaKanjiConverter)

A Japanese input method for macOS. Kana-kanji conversion uses the [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter) engine with Zenzai, which picks the first candidate from the sentence and the text before the cursor. A Windows version is in progress.

What works today: live conversion, context-aware conversion, correction of English words typed in romaji (`pyてょn`, `pthon` → `python`, undo with Space), a script-variant row above the candidates, a per-segment candidate grid, a configurable ¥ key (default `\`), and half-width symbols in editors and terminals.

The IME itself makes no network connections. The only download is the Zenzai model at install time, verified by SHA-256.

Install on macOS (Xcode 26, XcodeGen and an Apple Development certificate are required): `make install-macos`. On first install, log out and back in, then add "s90.tokyo IME" in System Settings > Keyboard > Input Sources.

Documentation is written in Japanese first. See [docs/README.md](docs/README.md).

License: MIT. Third-party notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
