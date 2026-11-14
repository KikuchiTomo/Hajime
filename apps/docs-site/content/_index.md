---
title: Hajime IME
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
{{< hajime/download platform="macos" ext="pkg" text="macOS 版をダウンロード" >}}
{{< hajime/download platform="windows" ext="msi" text="Windows 版をダウンロード" style="background: transparent; color: inherit; box-shadow: inset 0 0 0 1px currentColor;" >}}
</div>

<p class="hajime-hero__note">macOS 14 / Windows 10 22H2 (64bit) 以降 <a href="docs/install/">インストールの手順についてはこちら</a></p>

</div>
<div class="hajime-hero__mark" aria-hidden="true">
  <img src="images/hajime-mark.png" alt="" width="320" height="320" />
</div>
</div>

<figure class="hajime-showcase">
  <img src="images/hero.webp" alt="「写真を撮る」の分岐図．文節・文字種・候補・意味が 1 本の線で結ばれ，矢印キーで選択する" width="2400" height="1120" />
</figure>

{{< hajime/features title="主な機能" >}}
  {{< hajime/feature
    title="ライブ変換"
    subtitle="入力と同時に変換し，Enter で確定．"
    link="docs/usage/#変換と確定"
    image="images/features/live-conversion.webp"
    alt="ローマ字の入力が，Space を押さずに「帰りに駅前のカフェに寄って」と変換されている"
  >}}
  {{< hajime/feature
    title="分岐図"
    subtitle="文節・候補・語の意味を 1 本の線で結び，矢印キーだけで選択．"
    link="docs/usage/#文節の操作"
    image="images/features/candidate-tree.webp"
    alt="「私の名前は中野です」の分岐図．文節の上に文字種，下に候補が並ぶ"
  >}}
  {{< hajime/feature
    title="一覧表示"
    subtitle="従来の一覧にも切り替え可能．"
    link="docs/settings/#変換"
    image="images/features/candidate-list.webp"
    alt="「へんかん」の候補の一覧．最上段に文字種が並ぶ"
  >}}
  {{< hajime/feature
    title="入力中の候補と予測"
    subtitle="入力途中の候補と，続きの予測を表示．"
    link="docs/usage/#入力中の候補と予測"
    image="images/features/suggestion-prediction.webp"
    alt="入力中の候補「なんだ」「何だ」と，Tab で確定する予測「エピソード」"
  >}}
  {{< hajime/feature
    title="打ち間違いの補正"
    subtitle="誤入力を文脈から検出して補正．"
    link="docs/usage/#打ち間違いの補正"
    image="images/features/typo-correction.webp"
    alt="「ありがぷございます」が「ありがとうございます」に補正され，Esc で復元できる"
  >}}
  {{< hajime/feature
    title="英単語の判別"
    subtitle="日本語入力のまま英単語を入力可能．"
    link="docs/settings/#英語と日本語"
    image="images/features/english-words.webp"
    alt="日本語入力で打った python が英単語と判定され，「pyてょn」にならない"
  >}}
  {{< hajime/feature
    title="語の意味と使い分け"
    subtitle="意味・用例・同音語を候補の横に表示．"
    link="docs/usage/#語の意味"
    image="images/features/meaning.webp"
    alt="「撮る」の意味と用例，同音語の取る・採る・執る・捕る"
  >}}
  {{< hajime/feature
    title="連想変換"
    subtitle="類義語と関連語を候補から検索．"
    link="docs/usage/#連想変換"
    image="images/features/association.webp"
    alt="「撮る」の連想として，撮影する・写す・収めるが並ぶ"
  >}}
  {{< hajime/feature
    title="計算・郵便番号・日付"
    subtitle="数式は答えに，郵便番号は住所に，「きょう」は日付に変換．"
    link="docs/usage/#便利な変換"
    image="images/features/date-conversion.webp"
    alt="1+2*3= が 7 に，100-0001 が東京都千代田区千代田に，きょうが日付に，21 が ㉑ や二一に変換される"
  >}}
  {{< hajime/feature
    title="絵文字・記号・顔文字"
    subtitle="読み・英語・ショートコードで検索可能なパレット．"
    link="docs/usage/#絵文字と記号のパレット"
    image="images/features/palette.webp"
    alt="顔文字・絵文字・記号のパレットと，それぞれを開くキー"
  >}}
  {{< hajime/feature
    title="手書き入力"
    subtitle="読めない漢字を手書きで検索．"
    link="docs/usage/#手書き入力"
    image="images/features/handwriting.webp"
    alt="手書きの「田」から候補が表示されている"
  >}}
  {{< hajime/feature
    title="テーマ"
    subtitle="10 種のテーマに加え，配色・角丸・書体を自作可能．"
    link="docs/settings/#外観"
    image="images/features/themes.webp"
    alt="和紙・ネオン・北欧・ターミナル・インディゴ・夜のデスクの 6 つのテーマの分岐図"
  >}}
  {{< hajime/feature
    title="アプリごとの入力モード"
    subtitle="日本語と英数をアプリごとに自動で切り替え．"
    link="docs/settings/#除外設定"
    image="images/features/app-modes.webp"
    alt="ターミナルは英数，メモとブラウザは日本語に切り替わる"
  >}}
  {{< hajime/feature
    title="外部通信不要"
    subtitle="変換も補正も端末内で完結．通信は更新の確認時のみ．"
    link="privacy/"
    image="images/features/offline.webp"
    alt="変換・補正・学習を端末内で処理し，外部と通信しない"
  >}}
{{< /hajime/features >}}

{{< hajime/catalog title="そのほかの機能" >}}
  {{< hajime/catalog-group title="入力" >}}
    {{< hajime/catalog-item title="4 つの入力方式" link="docs/settings/#入力" >}}ローマ字・かな・英字・英字(自動)に対応．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="キー配列" link="docs/settings/#入力" >}}US・Dvorak・Colemak などに対応．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="句読点と記号のキー" link="docs/settings/#入力" >}}句読点の種類と，[ ] / ¥ の入力文字を変更可能．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="Shift で英字" link="docs/settings/#入力" >}}Shift で始めた英字は，Space か記号まで英字のまま入力．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="数字のあとのピリオドとハイフン" link="docs/usage/#便利な変換" >}}「3.14」「1,000」「A-1」を切り替えなしで入力．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="テンキーで計算" link="docs/settings/#入力" >}}「12*3」と Enter で，計算結果の 36 が第 1 候補．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="ローマ字と記号の変換表" link="docs/settings/#ローマ字と記号" >}}「wyi」→「ゐ」，「->」→「→」などの変換を追加可能．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="変換" >}}
    {{< hajime/catalog-item title="文節の操作" link="docs/usage/#文節の操作" >}}区切りを 1 文字単位・単語単位で変更し，文節ごとに再入力．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="候補を表に展開" link="docs/usage/#候補を表に展開" >}}Option+↓ で 36 個の候補を一覧．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="Esc で元に戻す" link="docs/usage/#変換と確定" >}}候補と区切りの変更を 8 回まで取り消し．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="確定の取り消し" link="docs/usage/#確定の取り消し" >}}確定直後の Control+Backspace で，確定前の変換に復帰．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="誤りやすい文節へ移動" link="docs/usage/#変換と確定" >}}Option+→ で，誤変換の可能性が高い文節へ移動．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="前後の文脈で並べ替え" link="docs/settings/#変換" >}}「Pythonでプログラムをかこう」では，「加工」より「書こう」を優先．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="再変換" link="docs/usage/#再変換" >}}確定した文字を選択して Control+Shift+R で再変換．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="文字種の変換" link="docs/usage/#変換と確定" >}}F6〜F10 で，ひらがな・カタカナ・全角英数・半角英数に変換．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="数字の表記" link="docs/settings/#変換" >}}21 を ㉑・二一・弐拾壱・ⅩⅩⅠ に変換．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="校正支援" link="docs/settings/#変換" >}}ら抜き言葉・さ入れ言葉・二重敬語・重言に，本来の形を併記．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="送り仮名" link="docs/settings/#変換" >}}本則と許容から選択．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="学習" link="docs/settings/#変換" >}}選んだ語を優先し，不要な学習は Control+Backspace で削除．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="予測の管理" link="docs/usage/#入力中の候補と予測" >}}不要な予測を非表示にし，確定直後の Backspace で補完前の読みに復帰．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="Zenzai モデル" link="docs/settings/#変換" >}}精度優先・速度優先・併用から選択．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="補正" >}}
    {{< hajime/catalog-item title="キーの二重入力" link="docs/settings/#補正" >}}「koonnnitiha」を「こんにちは」に補正．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="読み違い" link="docs/settings/#補正" >}}「ふいんき」から「雰囲気」に変換．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="うろ覚えのカタカナ語" link="docs/settings/#補正" >}}「しゅみれーしょん」から「シミュレーション」に変換．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="発音どおりに綴った英単語" link="docs/settings/#補正" >}}「ふぉと」から「photo」に変換．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="手の位置のずれ(試験的)" link="docs/settings/#補正" >}}1 キー横にずれて入力した文を補正．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="修正しない語句と置き換え" link="docs/settings/#補正" >}}補正の除外と，「pthon」→「Python3」のような置き換えを登録．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="英語と日本語" >}}
    {{< hajime/catalog-item title="外来語の英字表記" link="docs/settings/#英語と日本語" >}}約 13 万語を収録．「れっどはっと」から Red Hat に変換．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="直前の単語で判別" link="docs/settings/#英語と日本語" >}}「make」のように英語にも日本語にも読める語を，直前の単語から判別．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="英語にする単語・日本語にする単語" link="docs/settings/#英語と日本語" >}}常に英語で入力する単語と，常に日本語に変換する単語を登録．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="辞書・マクロ・コマンド" >}}
    {{< hajime/catalog-item title="ユーザー辞書" link="docs/settings/#ユーザー辞書と辞書の取り込み" >}}10,000 単語まで登録可能．「gh」→ GitHub のような英字の読みにも対応．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="日付や乱数を入れる単語" link="docs/settings/#単語と変換マクロに書ける書き方" >}}{date} や {uuid} で，変換時の日付や UUID を挿入．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="辞書の取り込み" link="docs/settings/#ユーザー辞書と辞書の取り込み" >}}SKK 辞書やほかの IME の辞書を取り込み，アプリや文脈ごとに使い分け．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="専門用語の辞書" link="docs/settings/#専門用語の辞書" >}}医学・法律・情報技術などを分野ごとに選択．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="変換マクロ" link="docs/settings/#コマンドと変換マクロ" >}}語を【東京】・ルビ・Markdown の太字などの形に整形．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="コマンド" link="docs/settings/#コマンドと変換マクロ" >}}登録した読みから，アプリ・Web ページ・ファイルを起動．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="設定と更新" >}}
    {{< hajime/catalog-item title="キー設定" link="docs/settings/#キー設定" >}}全キーを変更可能．標準・Windows 風・Mac 風・ATOK 風・Emacs 風・Vim 風のひな形を用意．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="同期とバックアップ" link="docs/settings/#同期とバックアップ" >}}Dropbox・Google Drive・iCloud Drive などのフォルダで，設定と辞書を同期．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="初期設定" >}}初回起動時に，入力モードの切り替え・ライブ変換・外観などを選択．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="更新を確認" link="docs/install/" >}}新バージョンの変更点を確認して，そのまま更新．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
{{< /hajime/catalog >}}
