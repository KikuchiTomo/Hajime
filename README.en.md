# Hajime

[![macOS](https://img.shields.io/github/v/release/KikuchiTomo/Hajime?filter=*-macos&include_prereleases&sort=semver&display_name=release&label=macOS&logo=apple)](https://github.com/KikuchiTomo/Hajime/releases?q=macos&expanded=true)
[![Windows](https://img.shields.io/github/v/release/KikuchiTomo/Hajime?filter=*-windows&include_prereleases&sort=semver&display_name=release&label=Windows&logo=windows)](https://github.com/KikuchiTomo/Hajime/releases?q=windows&expanded=true)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B%20%7C%20Windows%2010%2B%20%7C%20Linux%20(WIP)-lightgrey.svg)
[![Engine](https://img.shields.io/badge/engine-azooKey%20%2B%20Zenzai-6b4fbb.svg)](https://github.com/azooKey/AzooKeyKanaKanjiConverter)

A Japanese input method for macOS and Windows. Kana-kanji conversion uses the [azooKey](https://github.com/azooKey/AzooKeyKanaKanjiConverter) engine and the Zenzai neural language model.

Hajime is under active development, and its behavior may change.

## Features

| Feature | Description |
|---|---|
| Live conversion | Converts to kanji as you type. |
| Branch map | Candidates branch out per segment, so you can re-pick only the segments you need while seeing the whole sentence. A classic list view is also available. |
| Segment editing | Resize segments by character or by word, split them at word boundaries, or retype a segment in place. |
| Typo correction | Fixes vowel and consonant slips and missed keys from context. When unsure, it suggests a fix instead. Press Esc to restore what you typed. |
| English spelling correction | Fixes English words typed in romaji (`pthon` → `python`). |
| English input mode | Type in English and convert only the words you want into Japanese. |
| Association | Shift+Space shows words with similar or related meanings. |
| Handy conversions | Arithmetic (`1+2*3=`), postal codes to addresses, dates and times, symbols, and emoji. |
| Writing aids | Notes on common usage mistakes and homophones. |
| Handwriting input | Find kanji you cannot read by drawing them. |
| Dictionaries | A user dictionary, plus imported dictionaries with hundreds of thousands of words. |
| Customization | Every key binding can be changed, with Windows, Mac, Emacs, and Vim presets. You can also create your own themes. |
| Per-app behavior | In editors and terminals, symbols stay half-width and commands stay in English. |
| Sync and backup | Sync settings and dictionaries across computers through a folder such as Dropbox, and export settings as JSON. |
| Privacy | Hajime never sends what you type off your computer and makes no network connections. |

## Installation

| OS | Requirements | Download |
|---|---|---|
| macOS | MacOS 14 or later | [Latest release](https://github.com/KikuchiTomo/Hajime/releases?q=macos&expanded=true) (`.pkg`) |
| Windows | Windows 10 22H2 or later (64-bit) | [Latest release](https://github.com/KikuchiTomo/Hajime/releases?q=windows&expanded=true) (`.msi`) |
| Linux (WIP) | | Not yet available |

After installing, sign out once, then add "Hajime" in your OS input source settings.

## License

MIT License ([LICENSE](LICENSE)).

Hajime uses azooKey (MIT) and the Zenzai model (Apache-2.0). Copyright notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and on the About page of the app's settings.

To report a vulnerability, see [SECURITY.md](SECURITY.md).

日本語: [README.md](README.md)
