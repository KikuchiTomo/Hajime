---
title: はじめ
description: macOS・Windows 向けの日本語IME
layout: hextra-home
---

<div class="hajime-hero">
<div class="hajime-hero__text">

{{< hextra/hero-badge link="https://github.com/KikuchiTomo/Hajime/releases" >}}
  <span>リリース履歴</span>
  {{< icon name="arrow-circle-right" attributes="height=14" >}}
{{< /hextra/hero-badge >}}

<div class="hx:mt-6 hx:mb-6">
{{< hextra/hero-headline >}}
  サクサク入力！&nbsp;<br class="hx:sm:block hx:hidden" /><span class="hajime-gradient-text">高機能日本語IME</span>
{{< /hextra/hero-headline >}}
</div>

<div class="hx:mb-10">
{{< hextra/hero-subtitle >}}
  macOS・Windows 対応&nbsp;<br class="hx:sm:block hx:hidden" />
{{< /hextra/hero-subtitle >}}
</div>

<div class="hajime-hero__buttons">
{{< hajime/download ext="pkg" text="macOS 版をダウンロード" >}}
{{< hajime/download ext="msi" text="Windows 版をダウンロード" style="background: transparent; color: inherit; box-shadow: inset 0 0 0 1px currentColor;" >}}
</div>

<p class="hajime-hero__note">macOS 14 / Windows 10 22H2 (64bit) 以降 <a href="docs/install/">インストールの手順についてはこちら</a></p>

</div>
<div class="hajime-hero__mark" aria-hidden="true">
  <img src="images/hajime-mark.png" alt="" width="320" height="320" />
</div>
</div>

<div class="hx:mt-16"></div>

{{< hajime/features >}}
  {{< hajime/feature
    title="ライブ変換"
    subtitle="スペースキーを押さなくても，自動で漢字に変換します．"
    link="docs/usage/#変換と確定"
    image="images/features/live-conversion.webp"
    alt="テキストエディットで kyouhaiitenkidesune と打ち，「今日はいい天気ですね」と表示されている"
  >}}
  {{< hajime/feature
    title="変換候補をツリー表示"
    subtitle="候補を文節ごとに枝分かれさせて表示します．"
    link="docs/usage/#文節の操作"
    image="images/features/candidate-tree.webp"
    alt="文節ごとに候補が枝分かれした候補ウィンドウ"
  >}}
  {{< hajime/feature
    title="打ち間違いの補正"
    subtitle="入力をしてから一定時間待つと，打ち間違いを入力内容の文脈から自動補正します．"
    link="docs/usage/#打ち間違いの補正"
    image="images/features/typo-correction.webp"
    alt="「ありがぷございます」が「ありがとうございます」に補正され，元に戻すボタンが出ている"
  >}}
  {{< hajime/feature
    title="連想変換"
    subtitle="選んでいる変換対象の語句を関連語句へ変換できます．"
    link="docs/usage/#連想変換"
    image="images/features/association.webp"
    alt="「美しい」の連想として，優・素晴しい・綺麗・美的・可愛いが並んでいる"
  >}}
  {{< hajime/feature
    title="計算・郵便番号・日付"
    subtitle="1+2*3= は 7 に，100-0001 は住所に，きょうは今日の日付等に変換可能です．"
    link="docs/usage/#便利な変換"
    image="images/features/date-conversion.webp"
    alt="「きょう」の候補に 2026/10/30 などの日付が並んでいる"
  >}}
  {{< hajime/feature
    title="外部通信不要"
    subtitle="AI補正などもすべてローカルで実施します．"
    link="docs/privacy/"
  >}}
{{< /hajime/features >}}

<div class="hajime-engine">
  かな漢字変換には <a href="https://github.com/azooKey/AzooKeyKanaKanjiConverter">azooKey</a> のエンジンと，ニューラル言語モデルの Zenzai を使っています．
  このプロジェクトではなく，azooKeyおよびZenzaiプロジェクトを支援していただけると幸いです．
</div>
