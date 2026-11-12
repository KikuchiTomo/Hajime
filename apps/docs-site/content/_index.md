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
  <img src="images/hero.webp" alt="テキストエディットで「写真を撮る」と入力し，分岐図の候補の「撮る」の横に，意味・使い方の例・同音語が表示されている" width="1400" height="672" />
</figure>

{{< hajime/features title="主な機能" >}}
  {{< hajime/feature
    title="ライブ変換"
    subtitle="スペースキーを押さなくても，入力しながら漢字に変換します．Enter で確定します．"
    link="docs/usage/#変換と確定"
    image="images/features/live-conversion.webp"
    alt="テキストエディットで kyouhaiitenkidesune と打ち，「今日はいい天気ですね」と表示されている"
  >}}
  {{< hajime/feature
    title="変換候補をツリー表示"
    subtitle="候補を文節ごとに枝分かれさせて表示します．文全体を見ながら，直したい文節の候補だけを選び直せます．"
    link="docs/usage/#文節の操作"
    image="images/features/candidate-tree.webp"
    alt="文節ごとに候補が枝分かれした候補ウィンドウ"
  >}}
  {{< hajime/feature
    title="一覧の表示"
    subtitle="候補を縦に並べる一覧の表示にも切り替えられます．上の行で，カタカナや全角英数などの文字種をすぐに選べます．"
    link="docs/settings/#変換"
    image="images/features/candidate-list.webp"
    alt="「へんかん」の候補が一覧で並び，上の行にそのまま・カタカナ・全角英数などの文字種が並んでいる"
  >}}
  {{< hajime/feature
    title="入力中の候補と予測"
    subtitle="入力しながら変換の候補を表示し，続く語句も予測します．「えぴ」まで打てば，Tab で「エピソード」と確定できます．"
    link="docs/usage/#入力中の候補と予測"
    image="images/features/suggestion-prediction.webp"
    alt="入力中の候補の窓に「なんだ」「何だ」「なんだ？」が並び，予測の窓に「エピソード」と Tab のキーが表示されている"
  >}}
  {{< hajime/feature
    title="打ち間違いの補正"
    subtitle="入力を止めると，打ち間違いを文脈から判断して補正します．確信が持てないときは「もしかして」で知らせ，Esc で入力どおりに戻せます．"
    link="docs/usage/#打ち間違いの補正"
    image="images/features/typo-correction.webp"
    alt="「ありがぷございます」が「ありがとうございます」に補正され，元に戻すボタンが出ている"
  >}}
  {{< hajime/feature
    title="英単語は英単語のまま"
    subtitle="日本語入力のまま python と打っても「pyてょn」にならず，python に補正します．GitHub や ChatGPT のような語も，切り替えずに入力できます．"
    link="docs/settings/#英語と日本語"
    image="images/features/english-words.webp"
    alt="補正の候補として python が選ばれ，入力のままの「pyてょn」と Python が並んでいる"
  >}}
  {{< hajime/feature
    title="語の意味と使い分け"
    subtitle="選んでいる語の意味と使い方の例を，候補の横に表示します．同じ読みのほかの語も並ぶので，「撮る」と「取る」の使い分けに迷いません．"
    link="docs/usage/#語の意味"
    image="images/features/meaning.webp"
    alt="「撮る」を選ぶと，写真や動画を写す・映画やテレビ番組などを撮影するという意味と例文，同音語の取る・採る・執る・捕るが表示されている"
  >}}
  {{< hajime/feature
    title="連想変換"
    subtitle="選んでいる語を，似た意味の語や関連する語に変換できます．"
    link="docs/usage/#連想変換"
    image="images/features/association.webp"
    alt="「美しい」の連想として，優・素晴しい・綺麗・美的・可愛いが並んでいる"
  >}}
  {{< hajime/feature
    title="計算・郵便番号・日付"
    subtitle="1+2*3= は 7 に，100-0001 は住所に，きょうは今日の日付に変換します．21 を ㉑ や二一にもできます．"
    link="docs/usage/#便利な変換"
    image="images/features/date-conversion.webp"
    alt="「きょう」の候補に 2026/10/30 などの日付が並んでいる"
  >}}
  {{< hajime/feature
    title="絵文字・記号・顔文字のパレット"
    subtitle="Control+Option+E で絵文字，K で記号，F で顔文字のパレットを開きます(Windows は Ctrl+Alt)．「おじぎ」のような読みや英語，:bow: のようなショートコードで探せます．"
    link="docs/usage/#絵文字と記号のパレット"
    image="images/features/palette.webp"
    alt="絵文字・顔文字・記号の 3 つのパレットが並び，それぞれの下に選んでいる文字の名前と読みが表示されている"
  >}}
  {{< hajime/feature
    title="手書き入力"
    subtitle="読みがわからない漢字は，書いて探せます．設定でオンにすると，Control+Option+H(Windows は Ctrl+Alt+H)で手書きの画面を開きます．"
    link="docs/usage/#手書き入力"
    image="images/features/handwriting.webp"
    alt="手書きの画面に「田」と書かれ，候補に田と H が並んでいる"
  >}}
  {{< hajime/feature
    title="候補ウィンドウのテーマ"
    subtitle="和紙・北欧・ネオン・端末など，8 つのテーマから選べます．色・角の丸み・枝の形・書体を決めたカスタムテーマも作れます．"
    link="docs/settings/#外観"
    image="images/features/themes.webp"
    alt="和紙・ネオン・北欧・端末の 4 つのテーマで描いた候補ウィンドウ"
  >}}
  {{< hajime/feature
    title="アプリごとの入力モード"
    subtitle="アプリを切り替えたときに IME をオンにするかオフにするかを，アプリごとに決められます．"
    link="docs/settings/#除外設定"
    image="images/features/app-modes.webp"
    alt="初期設定のアプリごとの入力モードの画面．IME をオフ，IME をオン，IME のオンオフを記憶を説明している"
  >}}
  {{< hajime/feature
    title="外部通信不要"
    subtitle="AI による補正なども，すべてこのパソコンの中で処理します．通信するのは「更新を確認」を押したときだけです．"
    link="privacy/"
  >}}
{{< /hajime/features >}}

{{< hajime/catalog title="そのほかの機能" >}}
  {{< hajime/catalog-group title="入力" >}}
    {{< hajime/catalog-item title="4 つの入力方式" link="docs/settings/#入力" >}}ローマ字入力・かな入力・英字入力・英字入力(自動)から選べます．英字入力(自動)では，日本語にできる語を判別して変換します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="キー配列" link="docs/settings/#入力" >}}US・Dvorak・Colemak などのキー配列に合わせて入力します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="句読点と記号のキー" link="docs/settings/#入力" >}}句読点を「、。」「，．」などから選べます．[ ] / ¥ のキーで入る文字も変えられます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="Shift で英字" link="docs/settings/#入力" >}}Shift を押して打った英字を，Space か記号まで英字のまま入力します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="数字のあとのピリオドとハイフン" link="docs/usage/#便利な変換" >}}「3.14」「1,000」「A-1」を，そのまま入力できます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="テンキーで計算" link="docs/settings/#入力" >}}テンキーで「12*3」と打って Enter を押すと，計算の結果の 36 を先頭の候補にします．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="ローマ字と記号の変換表" link="docs/settings/#ローマ字と記号" >}}ローマ字の組み合わせ(「wyi」→「ゐ」)や，「->」→「→」のような記号の変換を追加できます．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="変換" >}}
    {{< hajime/catalog-item title="文節の操作" link="docs/usage/#文節の操作" >}}文節の区切りを 1 文字ずつや単語の切れ目で調整し，その文節だけを入力し直せます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="Esc で元に戻す" link="docs/usage/#変換と確定" >}}直前に変えた候補や文節の区切りを，8 回まで元に戻せます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="誤りやすい文節へ移動" link="docs/usage/#変換と確定" >}}Option+→ で，誤変換の可能性が高い文節へ移動します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="前後の文脈で並べ替え" link="docs/settings/#変換" >}}「Pythonでプログラムをかこう」なら「加工」より「書こう」を先に表示します．Zenzai が 2 番目以降の候補を文に合う順に並べます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="再変換" link="docs/usage/#再変換" >}}確定した文字を選んで Control+Shift+R を押すと，読みに戻して変換し直します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="文字種の変換" link="docs/usage/#変換と確定" >}}F6〜F10 で，ひらがな・カタカナ・全角英数・半角英数に変換します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="数字の書き方" link="docs/settings/#変換" >}}21 を ㉑・二一・弐拾壱・ⅩⅩⅠ のように，丸数字・漢数字・ローマ数字に変換します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="校正支援" link="docs/settings/#変換" >}}ら抜き言葉・さ入れ言葉・二重敬語・重言に，本来の形を添えます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="送り仮名" link="docs/settings/#変換" >}}送り仮名を本則・許容から選べます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="学習" link="docs/settings/#変換" >}}選んだ語を覚えて，次から先に表示します．Control+Backspace で学習から削除できます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="予測の管理" link="docs/usage/#入力中の候補と予測" >}}表示してほしくない予測を登録できます．予測を確定した直後の Backspace で，補う前の読みに戻せます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="Zenzai のモデル" link="docs/settings/#変換" >}}精度を優先・速さを優先・併用から選べます．併用では，打っているあいだは小さなモデルで速く表示します．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="補正" >}}
    {{< hajime/catalog-item title="同じキーの重なり" link="docs/settings/#補正" >}}「koonnnitiha」を「こんにちは」に補正します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="読み違い" link="docs/settings/#補正" >}}「ふいんき」を変換すると「雰囲気」を示します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="うろ覚えのカタカナ語" link="docs/settings/#補正" >}}「しゅみれーしょん」を変換すると「シミュレーション」を候補に表示します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="発音どおりに綴った英単語" link="docs/settings/#補正" >}}「ふぉと」を変換すると「photo」を候補に表示します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="手の位置のずれ(試験的)" link="docs/settings/#補正" >}}手が 1 キー横にずれたまま打った文を補正します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="修正しない語句と置き換え" link="docs/settings/#補正" >}}補正しない語句を登録できます．「pthon」→「Python3」のような置き換えも登録できます．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="英語と日本語" >}}
    {{< hajime/catalog-item title="外来語の英字表記" link="docs/settings/#英語と日本語" >}}約 13 万語の英字表記を収録しています．「れっどはっと」で Red Hat，「にゅーらる」で neural を表示します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="前の単語で判別" link="docs/settings/#英語と日本語" >}}「make」のように英語にも日本語にも読める語を，前の単語に合わせて判別します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="英語にする単語・日本語にする単語" link="docs/settings/#英語と日本語" >}}常に英語にする単語と，常に日本語にする単語を登録できます．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="辞書・マクロ・コマンド" >}}
    {{< hajime/catalog-item title="ユーザー辞書" link="docs/settings/#ユーザー辞書と辞書の取り込み" >}}10,000 語まで登録できます．読みは英字でも登録でき，「gh」で GitHub と入力できます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="日付や乱数を入れる単語" link="docs/settings/#変換マクロと単語に書ける書き方" >}}単語に {date} や {uuid} のように書くと，変換したときの日付や UUID を入れます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="辞書の取り込み" link="docs/settings/#ユーザー辞書と辞書の取り込み" >}}SKK 辞書や，ほかの IME で書き出した辞書を読み込めます．数十万語の辞書も使え，アプリや文脈ごとに使い分けられます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="変換マクロ" link="docs/settings/#コマンドと変換マクロ" >}}選んでいる語を【東京】・ルビ・Markdown の太字などの形に整えます．形は自由に追加でき，設定の画面で試せます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="コマンド" link="docs/settings/#コマンドと変換マクロ" >}}登録した読みを変換すると，候補からアプリ・Web ページ・ファイルを開けます．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
  {{< hajime/catalog-group title="設定と更新" >}}
    {{< hajime/catalog-item title="キー設定" link="docs/settings/#キー設定" >}}すべてのキーを変更できます．ひな形は標準・Windows 風・Mac 風・ATOK 風・Emacs 風・Vim 風から選べます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="同期とバックアップ" link="docs/settings/#同期とバックアップ" >}}Dropbox・Google Drive・iCloud Drive などのフォルダを指定すると，設定と辞書を複数のパソコンで同期します．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="初期設定" >}}初めて使うときに，英数とかなの切り替え・ライブ変換・外観などを順に選べます．{{< /hajime/catalog-item >}}
    {{< hajime/catalog-item title="更新を確認" link="docs/install/" >}}新しいバージョンの変更点を見てから，そのまま更新できます．ログアウトや再起動は要りません．{{< /hajime/catalog-item >}}
  {{< /hajime/catalog-group >}}
{{< /hajime/catalog >}}

<div class="hajime-engine">
  かな漢字変換には <a href="https://github.com/azooKey/AzooKeyKanaKanjiConverter">azooKey</a> のエンジンと，ニューラル言語モデルの Zenzai を使っています．
  このプロジェクトではなく，azooKeyおよびZenzaiプロジェクトを支援していただけると幸いです．
</div>
