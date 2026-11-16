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
  <img src="images/hero.webp" alt="「写真を撮る」の変換候補のツリー表示．文節・文字種・候補・意味を矢印キーで選択可能" width="2400" height="1120" />
</figure>

{{< hajime/features title="主な機能" >}}
  {{< hajime/feature
    title="ライブ変換"
    subtitle="入力と同時に変換"
    link="docs/usage/#変換と確定"
    image="images/features/live-conversion.webp"
  >}}
  {{< hajime/feature
    title="変換候補のツリー表示"
    subtitle="変換に関わる操作がツリー表示されます"
    link="docs/usage/#文節の操作"
    image="images/features/candidate-tree.webp"
  >}}
  {{< hajime/feature
    title="一覧表示"
    subtitle="通常のIMEと同等の表示形式にも対応"
    link="docs/settings/#変換"
    image="images/features/candidate-list.webp"
  >}}
  {{< hajime/feature
    title="入力予測"
    subtitle="AIによる入力予測を提示"
    link="docs/usage/#入力中の候補と予測"
    image="images/features/suggestion-prediction.webp"
  >}}
  {{< hajime/feature
    title="打ち間違い補正"
    subtitle="誤入力を文脈から検討して自動的に補正"
    link="docs/usage/#打ち間違いの補正"
    image="images/features/typo-correction.webp"
  >}}
  {{< hajime/feature
    title="英単語の判別"
    subtitle="日本語入力のまま英単語を入力可能"
    link="docs/settings/#英語と日本語"
    image="images/features/english-words.webp"
  >}}
  {{< hajime/feature
    title="意味の表示"
    subtitle="意味や用例を変換候補と同時に表示"
    link="docs/usage/#語の意味"
    image="images/features/meaning.webp"
  >}}
  {{< hajime/feature
    title="連想変換"
    subtitle="単語の言い換えなどを提示"
    link="docs/usage/#連想変換"
    image="images/features/association.webp"
  >}}
  {{< hajime/feature
    title="計算・郵便番号・日付"
    subtitle="数式計算や郵便番号から住所への変換・日付の変換などに対応"
    link="docs/usage/#便利な変換"
    image="images/features/date-conversion.webp"
  >}}
  {{< hajime/feature
    title="絵文字・記号・顔文字"
    subtitle="絵文字や記号を提示するパレットを搭載"
    link="docs/usage/#絵文字と記号のパレット"
    image="images/features/palette.webp"
  >}}
  {{< hajime/feature
    title="手書き入力"
    subtitle="読めない漢字を手書きで検索"
    link="docs/usage/#手書き入力"
    image="images/features/handwriting.webp"
  >}}
  {{< hajime/feature
    title="テーマ"
    subtitle="既存テーマの他にカスタムテーマも作成可能"
    link="docs/settings/#外観"
    image="images/features/themes.webp"
  >}}
  {{< hajime/feature
    title="入力モード"
    subtitle="フォーカスしているアプリを認識しで自動でIME切り替えを設定可能"
    link="docs/settings/#除外設定"
    image="images/features/app-modes.webp"
  >}}
  {{< hajime/feature
    title="外部通信不要"
    subtitle="AIモデルはローカルモデルを使用するため外部への通信は不要です"
    link="privacy/"
    image="images/features/offline.webp"
  >}}
{{< /hajime/features >}}

{{< hajime/catalog title="そのほかの機能" >}}
  {{< hajime/catalog-group title="入力" >}}
    {{< hajime/catalog-item title="入力方式" image="images/catalog/input-styles.webp" link="docs/settings/#入力" >}}ローマ字・かな・英字・英字(自動)に対応{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="キー配列" image="images/catalog/key-layouts.webp" link="docs/settings/#入力" >}}US・Dvorak・Colemak その他OSが搭載する配列に対応．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="句読点・記号キー" image="images/catalog/punctuation.webp" link="docs/settings/#入力" >}}句読点の種類などを変更可能．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="Shift で英字入力" image="images/catalog/shift-english.webp" link="docs/settings/#入力" >}}シフト入力で自動で英語入力可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="数字と記号" image="images/catalog/number-punctuation.webp" link="docs/usage/#便利な変換" >}}数字の後にピリオドを入力するとそのまま英字入力可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="テンキーで計算" image="images/catalog/numpad-calc.webp" link="docs/settings/#入力" >}}テンキーで入力した場合は自動で計算に対応します{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="ローマ字や記号変換のユーザ定義" image="images/catalog/romaji-table.webp" link="docs/settings/#ローマ字と記号" >}}ユーザ定義の変換を追加可能{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="変換" >}}
    {{< hajime/catalog-item title="変換文節の調節" image="images/catalog/segments.webp" link="docs/usage/#文節の操作" >}}区切り位置をユーザが変更可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="一覧表示" image="images/catalog/grid.webp" link="docs/usage/#候補を表に展開" >}}候補を一覧表示可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="変換巻き戻し" image="images/catalog/undo.webp" link="docs/usage/#変換と確定" >}}候補と区切りの変更を 8 回まで取り消し可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="確定取り消し" image="images/catalog/undo-commit.webp" link="docs/usage/#確定の取り消し" >}}確定直後に行う操作で確定前の変換に復帰可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="誤用語句" image="images/catalog/uncertain.webp" link="docs/usage/#変換と確定" >}}誤変換の可能性が高い文節をAIが判断して一発で移動可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="AIによる変換文脈補正" image="images/catalog/context.webp" link="docs/settings/#変換" >}}「Pythonでプログラムをかこう」などの例において「加工」より「書こう」を優先{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="再変換" image="images/catalog/reconvert.webp" link="docs/usage/#再変換" >}}確定した文字を選択して Control+Shift+R で再変換可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="ひらがな・カタカナへの変換" image="images/catalog/script-keys.webp" link="docs/usage/#変換と確定" >}}ファンクションキーでひらがな・カタカナ・半角カタカナ・全角英数・半角英数へ一括変換{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="数字の表記" image="images/catalog/number-forms.webp" link="docs/settings/#変換" >}}21 を ㉑・二一・弐拾壱・ⅩⅩⅠ に変換可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="校正支援" image="images/catalog/proofreading.webp" link="docs/settings/#変換" >}}ら抜き言葉・さ入れ言葉・二重敬語・重言に提案を表示{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="送り仮名" image="images/catalog/okurigana.webp" link="docs/settings/#変換" >}}本則と許容のどちらかを選択可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="学習" image="images/catalog/learning.webp" link="docs/settings/#変換" >}}古典的な学習機能も搭載．気に入らない学習内容はその場で Control+Backspace で削除可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="予測の管理" image="images/catalog/prediction-manage.webp" link="docs/usage/#入力中の候補と予測" >}}不要な予測を非表示にし，確定直後の Backspace で補完前の読みに復帰可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="AI モデル" image="images/catalog/zenzai.webp" link="docs/settings/#変換" >}} Zenzai/Jinenモデルを搭載．従来のエンジンと複数のAIエンジンで同時推論することで正確性を向上{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="補正" >}}
    {{< hajime/catalog-item title="二重入力" image="images/catalog/double-key.webp" link="docs/settings/#補正" >}}「koonnnitiha」などの打ち間違いを「こんにちは」に補正可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="読み違い" image="images/catalog/misreading.webp" link="docs/settings/#補正" >}}「ふいんき」から「雰囲気」に変換可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="日本語発音から英単語変換" image="images/catalog/phonetic.webp" link="docs/settings/#補正" >}}「ふぉと」などを「photo」に変換可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="入力位置ずれ補正機能 (試験的)" image="images/catalog/hand-shift.webp" link="docs/settings/#補正" >}}1 キー横にずれて入力した文を補正可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="補正除外と置き換え機能" image="images/catalog/exclusions.webp" link="docs/settings/#補正" >}}補正の除外と「pthon」→「Python3」のような置き換えを登録可能{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="英語と日本語" >}}
    {{< hajime/catalog-item title="外来語の英字表記" image="images/catalog/loanwords.webp" link="docs/settings/#英語と日本語" >}}約 13 万語を収録！「れっどはっと」から Red Hat に変換可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="直前の入力単語から変換予測" image="images/catalog/previous-word.webp" link="docs/settings/#英語と日本語" >}}make/負け のように英語/日本語のどちらにも変換可能な文字を直前の単語から指定可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="英語にする単語・日本語にする単語登録" image="images/catalog/english-japanese-words.webp" link="docs/settings/#英語と日本語" >}}常に英語で入力する単語と，常に日本語に変換する単語を登録可能{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="辞書・マクロ・コマンド" >}}
    {{< hajime/catalog-item title="ユーザー辞書" image="images/catalog/user-dictionary.webp" link="docs/settings/#ユーザー辞書と辞書の取り込み" >}}10,000 単語まで登録可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="動的ユーザ辞書" image="images/catalog/placeholders.webp" link="docs/settings/#単語と変換マクロに書ける書き方" >}}特定のフォーマットによって動的に変化する変換内容を登録可能．{date} や {uuid} で，変換時の日付や UUID を挿入できます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="辞書の取り込み" image="images/catalog/import.webp" link="docs/settings/#ユーザー辞書と辞書の取り込み" >}}SKK 辞書やほかの IME の辞書を取り込み，アプリや文脈ごとに使い分けを搭載{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="専門用語の辞書" image="images/catalog/technical-terms.webp" link="docs/settings/#専門用語の辞書" >}}医学・法律・情報技術などを分野ごとに選択可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="変換マクロ" image="images/catalog/macros.webp" link="docs/settings/#コマンドと変換マクロ" >}}【東京】・ルビ・Markdown の太字などの形に整形マクロを指定可能{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="コマンド" image="images/catalog/commands.webp" link="docs/settings/#コマンドと変換マクロ" >}}登録した読みから，アプリ・Web ページ・ファイルを起動可能{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="設定と更新" >}}
    {{< hajime/catalog-item title="キー設定" image="images/catalog/keymap.webp" link="docs/settings/#キー設定" >}}全てのキーバインドをカスタマイズ可能．標準・Windows 風・Mac 風・ATOK 風・Emacs 風・Vim 風のプリセットを用意{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="同期とバックアップ" image="images/catalog/sync.webp" link="docs/settings/#同期とバックアップ" >}}Dropbox・Google Drive・iCloud Drive などのフォルダで，設定と辞書を同期．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
{{< /hajime/catalog >}}
