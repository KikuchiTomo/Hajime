# 探す時間を減らす候補ウィンドウを設計する

s90.tokyo IME の候補ウィンドウで改善の余地が大きいのは，キーの数ではなく，候補を目で探して読む時間である．日本語入力では変換候補を探して選ぶ作業に最も時間がかかり，ピンイン入力でも選択の反応時間が入力時間の36%を占めた．木構造や放射状の表示を IME で評価した査読付き研究は見つからなかった．また，ほかの分野の比較実験でも，既知の項目を選ぶ課題でリストより速いという結果はほとんど出ていない．放射状配置の速度上の利点はマウスやペンでの指示動作に由来するもので，キーボードで選ぶ IME ではほぼ残らない．証拠に照らして採用を勧めるのは次の5点である．候補の位置を読みごとに安定させる分割メニュー型の順位づけ，予測候補を先に出して残りをフェードインさせる ephemeral adaptation，1ページ5〜9件の上限と番号キーによる直接選択，キャレット直下への配置，確信度の低い文節に限った文節格子である．逆に，放射状や木構造の候補表示と，位置を動かすアニメーションは既定の動作にしないほうが良い．放射状の配置は，番号キーと方向の対応を覚えられるという利点に限って，実験用のオプションとして試してみる余地がある．なお，根拠の多くは IME 以外の研究や学位論文から外挿したものである．各提案の強さは本文と末尾の表に示した．

根拠の強さは，調査ノートに合わせて3段階で示す．[強] は再現性の高い古典的知見かレビュー論文，[中] は IME に近い条件の査読付き単一実験，[弱] は学位論文・二次引用か，IME への外挿が大きいものを指す．

## 入力時間の大半は候補を読んで判断する時間に消える

日本語入力の候補提示を直接比べた数少ない研究として，高知工科大学の田村 (2002) がある．縦表示と横表示の2形式，5種類の選択方法を比べ，日本語入力で最も時間がかかるのは変換候補を探して選ぶ作業だと結論した．縦と横の差は認められず，Page Up/Down と数字キーの組み合わせがスペースキー，カーソルキー，マウスより速かった ([高知工科大 田村 2002](https://www.kochi-tech.ac.jp/library/ron/pdf/2002/03/44/a1030283.pdf))．これは学位論文で [弱] だが，中国語でも同じ傾向が出ている．IBM の CHI 2001 の研究は，ピンイン入力の主なボトルネックが同音異義語からの選択と数字キーの打鍵であり，**選択反応時間が入力時間全体の36%を占める**と報告した ([IBM Research](https://research.ibm.com/publications/chinese-input-with-keyboard-and-eye-tracking-an-anatomical-study))．

この時間の重さは，KLM (Keystroke-Level Model) で見積もるとわかりやすい．KLM ではキー押下 K が熟練者で 0.12 秒，平均で 0.28 秒なのに対し，心的準備 M は 1.35 秒とされる ([LMU MMI 演習資料](https://www.medien.ifi.lmu.de/lehre/ws0607/mmi1/mmi-uebung2.pdf))．候補を読んで正誤を判断する作業が M に近い1回の認知操作だとすると，キー4〜10回分の重さがある [強]．したがって，設計の目標は打鍵数の最小化ではなく，判断を要する回数と1回あたりの照合時間の最小化に置くべきである．

テキスト入力の予測候補の研究は，この見積もりを30年にわたって裏づけてきた．Koester & Levine (1994) では，単語予測を使うと全員の打鍵間隔が長くなり，脊髄損傷群は予測なしより遅くなった ([IEEE Xplore](https://ieeexplore.ieee.org/document/331567))．Venkatagiri の研究では，15個の予測を毎キー後に走査させると，キーストロークが約50%減っても通信速度は一字入力と有意差がなかった ([Trnka et al. 2008](https://www.eecis.udel.edu/~mccoy/publications/2008/trnka08at.pdf))．Quinn & Zhai (CHI 2016) は，候補を常に出す条件，出さない条件，確率が閾値を超えたときだけ出す条件を比べた．積極的に出すほど打鍵は減り，参加者にも好まれたが，平均の入力時間は悪化した ([Google Research](https://research.google/pubs/a-costbenefit-study-of-text-entry-suggestion-interaction/)) [中]．好みと実測が逆を向くので，s90.tokyo IME の評価では主観評価に加えて時間の計測が欠かせない．

一方で，予測の質が高ければ見るコストを上回る．Trnka et al. の33名の実験では，高度な予測は予測なしより58.6%速く，実際の削減率を潜在的な削減率で割った利用率は93.6%だった．基本予測では78.2%にとどまった．信頼できないと感じたユーザーは，得が大きそうなときしかリストを見なくなる ([Trnka et al. 2008](https://www.eecis.udel.edu/~mccoy/publications/2008/trnka08at.pdf)) [中]．Gmail の Smart Compose も，確信度が閾値を超えたときに1候補だけを出す設計をとっている ([ar5iv 1906.00080](https://ar5iv.arxiv.org/html/1906.00080))．候補をどれだけ前に出すかは，変換の確信度に応じて変えるのが筋である．

候補数と選択時間の関係にも注意がいる．Hick–Hyman の法則は選択時間が候補数の対数で増えるとするが，これは候補の位置や中身をすでに知っている場合の場合に成り立つ．順序のないリストから語を探すときは1項目ずつ照合するので，時間は線形に増える ([Wikipedia: Hick's law](https://en.wikipedia.org/wiki/Hick%27s_law)) [強]．視覚探索の効率は項目あたりの反応時間の傾きで表され，約25〜30 ms/項目を超えると非効率とされる．物体探索の例では，標的ありで 35 ms/項目，標的なしで 81 ms/項目だった ([Wolfe 2020](https://search.bwh.harvard.edu/new/pubs/Wolfe2020_VisualSearch_annurev-vision.pdf)) [強]．漢字二字熟語では，実在の字に形が似た字を含む非語ほど判断が遅く誤りも多い ([J-STAGE 社会心理学研究](https://www.jstage.jst.go.jp/article/psysoc/44/4/44_4_237/_article)) [中]．保証，保障，補償のような同音異義語は共通の字を持ち，色や形の前注意的な特徴では区別できない．候補を1つ足すごとに，照合の時間がそのまま積み上がると考えるほうが現実に近い．

## 木構造と放射状の表示は，キーボードで選ぶ IME では速さの根拠を持たない

木構造の可視化は，リストより速いという一貫した証拠を持たない．Hyperbolic Tree Browser と Windows のファイルブラウザの比較では課題時間に有意差がなく，被験者はノードのラベルを頼りに移動していた ([UW CSE442 講義資料](https://courses.cs.washington.edu/courses/cse442/21au/lectures/CSE442-Evaluation.pdf))．SpaceTree，hyperbolic browser，MS Explorer を7000ノードの木で比べた実験でも，SpaceTree が優位だったのは既訪問ノードの再訪と全体構造の推定に限られた ([SpaceTree 論文](https://obj.umiacs.umd.edu/spacetree/2002-05.pdf))．SunBurst と Treemap の比較では SunBurst が好まれたものの，性能は著者自身が「比較的同等」と書く程度の差だった ([Stasko InfoVis'00](https://faculty.cc.gatech.edu/~john.stasko/papers/infovis00.pdf))．IME に最も近い結果は fisheye メニューの研究で，既知の項目を選ぶ課題では従来の階層メニューが最も正確で，群を抜いて速かった ([Hornbæk & Hertzum 2007](https://www.kasperhornbaek.dk/papers/TOCHI2007_FisheyeMenus.pdf)) [中]．かな漢字変換の候補選択は，欲しい表記をユーザーが知っている典型的な既知項目課題である．加えて，これらの手法は数千ノードの構造を探索するためのもので，1文節に数個から数十個しかない候補とは規模が合わない．

放射状のパイメニューについては，線形メニューより約15%速くエラーも少ないという結果がある ([OSNews 回顧記事](https://www.osnews.com/story/30371/pie-menus-a-30-year-retrospective/))．しかし理由は，Fitts の法則でいう移動距離が一定になり，ターゲットが大きくなることにある ([UMIACS 抄録](https://sites.umiacs.umd.edu/node/16962))．キーボードで選ぶなら，どの候補も1打で届くので，この利点は消える．キーボードに残る利点は，方向と項目の対応を覚えやすいことだけである．マーキングメニューでは熟練者のマーク選択がメニュー経由の3.5倍速かった ([Autodesk Research](https://research.autodesk.com/app/uploads/2023/03/user-learning-and-performance.pdf_recFBbPwmG7SW9uDe.pdf))．ただしこれは「この項目はいつも右上」という配置が変わらないことが前提で，学習で順位が毎回変わる変換候補とはかみ合わない．実際，円形8分割のメニューで候補を選ぶ日本語入力 Popie の論文は，学習で候補順位が動くため「目的の候補の位置が予測できず，フローメニューの素早い操作を活かせない」と書いている ([Popie 論文](https://www.iplab.cs.tsukuba.ac.jp/paper/journal/daisuke-ipsj2006.pdf)) [中]．

新しい配置には移行期の損失もある．ソフトキーボードにマーキングメニューを組み込んだ Isokoski (CHI 2004) は，モデル上は11〜37%の向上を予測した．しかし現実的な入力課題では当初遅く，20セッション後にようやく同等になった ([Isokoski CHI 2004](https://hci.rwth-aachen.de/materials/conferences/CHI2004/1p423.pdf)) [中]．毎日数千回使う変換操作で，この損失を既定の動作として払わせるわけにはいかない．確率に比例して表示面積を割り当てる Dasher は，視線入力で約25 wpm と画面キーボードの約15 wpm を上回った ([arXiv cs/0204030](https://ar5iv.labs.arxiv.org/html/cs/0204030))．とはいえ，連続的なズームには数百 ms のアニメーションが要り，キーボード入力の速度にも遠く及ばない．Dasher から借りられるのは，確率の高い候補を視覚的に目立たせるという発想だけである．

放射状研究から IME に持ち込める知見は，候補数の上限のほうにある．階層化したマーキングメニューでエラー率10%未満を保てるのは，1段4項目なら4段まで，8項目なら2段までだった ([Zhao & Balakrishnan UIST 2004](https://www.dgp.toronto.edu/~ravin/papers/uist2004_simplemm.pdf))．項目が8を超えると選択精度が大きく落ちる ([Zone & Polygon Menus CHI 2006](https://www.microsoft.com/en-us/research/wp-content/uploads/2016/11/Zone-Polygon-Menus-CHI-2006.pdf)) [中]．これはポインタ操作での上限だが，番号キーで選ぶ場合も，1から9の範囲に収めれば1打で選べる．

## 位置を動かさないことが熟練者の速度を生む

IME の学習機能は，直近に選んだ語を1位に上げるなどして候補順を並べ替える．これは適応メニューの研究で失敗が繰り返し報告されてきた設計と同じ構造を持つ．使用頻度で項目順を動的に並べ替えるメニューでは成績が下がり，ユーザーは方向感覚を失って静的メニューを強く好んだ (Mitchell & Shneiderman 1989，[Gajos et al. 2006 による引用](https://kgajos.seas.harvard.edu/papers/kgajos-avi06.pdf))．適応型の分割メニューも，静的メニューやカスタマイズ可能なメニューより速くなかった ([Findlater & McGrenere 2004](https://www.cs.ubc.ca/labs/edapt/papers/findlater2004.pdf)) [中]．逆に，空間的に安定した配置では熟練者が速くなる．CommandMaps は初心者では差がなかったが，経験者ではメニューやリボンより有意に速かった ([Univ. Manitoba HCI Lab](https://hci.cs.umanitoba.ca/publications/details/improving-command-selection-with-commandmaps))．

安定性と適応を両立させた2つの方式には，直接の実験結果がある．1つは Sears & Shneiderman の分割メニューで，頻出項目だけを上部の数項目に固定する．現場評価で所要時間を17〜58%短縮し，統制実験でもアルファベット順メニューより速く，好まれた．分割部分は4項目以下が推奨されている ([Sears & Shneiderman 1994](https://www.cs.umd.edu/~ben/papers/Sears1994Split.pdf)) [中]．もう1つは Findlater et al. (CHI 2009) の ephemeral adaptation で，予測した項目をメニューを開いた瞬間に出し，他の項目を 500 ms かけてフェードインさせる．48名の実験で，**予測精度79%では静的メニューより速く，50%でも有意には遅くならなかった**．背景色で強調する方式にも勝った ([Findlater et al. 2009](https://www.cs.ubc.ca/labs/edapt/papers/findlater2009.pdf)) [中]．突然の出現が色や輝度の変化とは別の仕組みで注意を引くという知見 ([PMC: abrupt onsets](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC3868916/)) とも合う．

ただし強調の使いすぎには代償がある．StencilMaps と EphemeralMaps の研究では，強調は素早い発見を助けたが，長期的には強調がないほうが成績が良かった．探すのが難しいことが空間記憶の形成を促すためである ([Univ. Manitoba HCI Lab](https://hci.cs.umanitoba.ca/publications/details/stencilmaps-and-ephemeralmaps-spatially-stable-interfaces-that-highlight-co)) [中]．強調は1つの候補に限り，確信度が高いときだけ使うのが良い．なお，これらの研究の大半はマウスで操作するプルダウンメニューを対象にしている．番号キーで選ぶ IME で同じ効果量が出る保証はない．

アニメーションは，この安定性を補うものとしてだけ使える．アニメーション遷移は対象の対応関係を追う助けになり ([Heer & Robertson 2007](https://idl.uw.edu/papers/animated-transitions))，動き始めと終わりで減速する slow-in/slow-out が最も追いやすかった ([Dragicevic et al. 2011](https://cs.au.dk/~elm/pdf/timedistort.pdf))．しかし，これらの遷移は 0.5〜1.0 秒が典型で，打鍵間隔の約 170 ms ([How We Type CHI 2016](https://userinterfaces.aalto.fi/how-we-type/resources/HowWeType_CHI16.pdf)) より1桁長い．候補の並べ替えを動きで見せると，次の打鍵までに終わらない．項目を時間差で動かす staggering は，多物体追跡の成績にほぼ効果がないか逆効果だった ([Chevalier et al. 2014](https://visualcognition.psych.northwestern.edu/publications/ChevalierDragicevicFranconeri2014.pdf)) [中]．WCAG 2.1 SC 2.3.3 は操作で起きる本質的でない動きを無効化できることを求めているが，不透明度の変化と瞬時の出現はこの「モーション」に含まれない ([W3C](https://www.w3.org/WAI/WCAG21/Understanding/animation-from-interactions.html)) [強]．したがって，ephemeral 型のフェードインは位置の移動を伴わないので使えるが，reduced motion の設定がある場合は即時表示に切り替える選択肢を用意しておきたい．

## 視線はキャレットの数文字先までしか届かない

タイピング中の視線は，もともと画面とキーボードを往復している．Feit, Weir & Oulasvirta (CHI 2016) の30名の計測では，文入力中にキーボードを見ていた時間の割合は，タッチタイピストで0.20，非タッチタイピストで0.41だった．タッチタイピストでは，打鍵間隔とキーボードへの視線移動の相関が0.81あった ([How We Type CHI 2016](https://userinterfaces.aalto.fi/how-we-type/resources/HowWeType_CHI16.pdf)) [中]．視線が画面から外れると，熟練者ほど急に遅くなる．候補ウィンドウがキャレットから遠く，大きな視線移動を要する位置にあれば，同じように打鍵が遅くなると考えられる．ピンインの EASE が，数字キーで選ぶと視線が画面から離れることを問題にしたのも同じ理由である ([IBM Research](https://research.ibm.com/publications/chinese-input-with-keyboard-and-eye-tracking-an-anatomical-study))．

置き場所の目安は，日本語読書の知覚範囲から得られる．約12〜13文字とされる ([eScholarship](https://escholarship.org/content/qt9bm7t7kc/qt9bm7t7kc_noSplash_c55f829d1bea8766c8b08cfa633cb596.pdf?t=op2mxn)) ので，第一候補をキャレットの直下，数文字以内に置けば，ほぼ1回の注視で確認できる．周辺視に置いた場合はクラウディングが問題になる．Bouma の法則では，周辺の標的を認識するには，隣の項目が離心率の約0.4〜0.5倍以上離れている必要がある ([Pelli & Tillman 2008](https://www.cns.nyu.edu/~david/courses/perceptionGrad/Readings/Pelli-NatNeurosci2008.pdf)) [強]．ただしこの定数は課題によって変わるという批判もある ([Strasburger 2020](https://journals.sagepub.com/doi/10.1177/2041669520913052))．候補を横に詰めて並べると，隣同士の区別がつきにくくなるおそれがある．縦並びの利点は，向きそのものではなく，1行1候補で語の境界がはっきりし，番号が左端に揃う点にあると考えるのが妥当だろう．並びの向きで選択時間に差がないという田村の結果とも矛盾しない．

日本語の読みでは，サッカードがひらがなより漢字に着地しやすい ([Lancashire repository](https://knowledge.lancashire.ac.uk/id/eprint/22401/)) [中]．同音異義語の候補が末尾の1字だけ違う場合は，共通部分を薄く表示して差分の字を通常の濃さで見せると，照合の対象を実質1字に減らせる可能性がある．この案を検証した研究はないので，[弱] の設計仮説として扱う．

IME の候補ウィンドウを使っているときの視線を計測した研究は，日英とも見つからなかった．この節の提案はすべて，読書とタイピングの知見からの外挿である．

## 文節格子は，確信度の低い文節に絞れば有望な唯一の新奇表示になる

調べた新奇表示の中で IME への転用に最も近いのは，音声認識の訂正 UI である．Parakeet は認識結果を単語コンフュージョンネットワークとして表示し，最上段に最尤の仮説を，各単語の下の列に代替候補を並べる ([Parakeet](https://keithv.com/pub/demoparakeet/))．Ogata & Goto の Speech Repair も，認識結果の各単語を区切り，その下に競合候補を並べて，選ぶだけで誤りを直せるようにした．実験ではほぼすべての認識誤りが訂正された ([Interspeech 2005](https://staff.aist.go.jp/m.goto/PAPER/EUROSPEECH2005ogata.pdf)) [中]．これは日本語の文節ごとの候補をそのまま横に並べた構造で，文節を ←→ で，候補を ↑↓ か数字キーで選ぶ2次元カーソルとして実装できる．現在の IME では注目文節を1つずつ移して候補を開くが，格子なら誤りのある文節を一度に見つけられる．

ただし，格子を常に全文節について出すのは勧められない．音声入力は「どこが誤っているか分からない」ことを前提にするが，IME ではユーザーが入力直後に誤りに気づくことが多い．全文節に候補を並べると，第1節で見た「見るだけでかかるコスト」を毎回払わせることになる．しかも，第一候補の当たる率は文節ごとに大きく違う．1文節の誤りを訂正する選択型インタフェースの試作では，正しい候補が第1位に来る割合は39%，上位6位以内で59%だった ([IPSJ](https://ipsj.ixsq.nii.ac.jp/records/48922/export/bibtex))．確信度の低い文節にだけ下の候補列を出し，残りは1行の変換結果として見せる形が，Quinn & Zhai の閾値条件とも整合する．文節区切りの誤りは格子の形そのものを変えるので，Shift+←→ で区切りを直したら格子を再計算する必要がある．格子 UI で1回の訂正にかかる時間を測った研究も，文節ラティスを編集する IME の評価も見つかっていない．この提案は [中] の類似研究と [弱] の外挿の組み合わせであり，実装したら必ず時間計測で検証したい．

## 提案ごとの採否と根拠の強さ

以下に，s90.tokyo IME の候補ウィンドウ設計に向けた提案を，採否と根拠の強さつきでまとめる．強さの欄は，直接の根拠の質と IME への外挿の大きさを合わせて判断した．

| 提案 | 判断 | 根拠の強さ | 主な根拠 |
|---|---|---|---|
| 確信度に応じて候補の出し方を変える．高ければ1候補をインラインで出し，ウィンドウは開かない | 採用 | 中 | Quinn & Zhai 2016，Trnka et al. 2008，Smart Compose |
| 分割メニュー型の順位づけ．学習で動かすのは第1候補（多くても上位2〜4件）だけにし，残りは読みごとに固定する | 採用 | 中 | Sears & Shneiderman 1994，Mitchell & Shneiderman 1989，Popie 2006 |
| ephemeral adaptation．予測候補を即時に出し，残りを不透明度だけで 100〜500 ms かけてフェードインさせる | 採用（まず試験的に） | 中 | Findlater et al. 2009．マウス操作のメニューからの外挿で，IME での効果量は未知 |
| 1ページの候補数を5〜9件に抑え，番号は1〜9 | 採用 | 弱〜中 | 線形探索のコスト，8方向の精度の上限，Pinyin の top-5 正解率89.7% ([arXiv 1811.04352](https://arxiv.org/pdf/1811.04352))．候補数を変えた統制実験はない |
| 番号キーによる直接選択と Page Up/Down の併用．Space による循環も残す | 採用 | 弱 | 田村 2002，Isokoski 2004 の移行コスト |
| 第一候補をキャレット直下の数文字以内に置き，ウィンドウを遠くに出さない | 採用 | 中 | Feit et al. 2016，日本語の知覚範囲，Bouma の法則 |
| 縦1列1候補を基本にし，候補間の間隔を詰めすぎない | 採用 | 弱 | クラウディング，縦横差なし（田村 2002） |
| 強調は1候補だけに使う | 採用 | 中 | Guided Search，StencilMaps |
| 確信度の低い文節だけに候補列を出す文節格子 | 実験的に採用 | 中（類似研究）／弱（IME） | Parakeet，Speech Repair，IPSJ の第1位39% |
| 同音異義語の共通部分を薄くし，差分の字を見せる | 仮説として試す | 弱 | 漢字類似性の干渉，漢字への着地．直接の検証なし |
| 用例や意味ラベルの表示は，第一候補を外して次候補を見ているときだけにする | 仮説として試す | 弱 | 読む量と照合精度のトレードオフ（推論） |
| 番号キーと方向を対応させた放射状配置．テンキーの1〜9を8方向と中心に見立てる | 既定にはしない．順位を固定した上での実験オプション | 弱 | キーボードでは Fitts 上の利点が消える．順位変動と衝突する（Popie）．移行期の損失（Isokoski） |
| hyperbolic tree，sunburst，fisheye などの木構造表示 | 不採用 | 中 | 既知項目課題で利点なし（Hornbæk & Hertzum 2007，SpaceTree） |
| 確率に比例して候補の大きさを変える Dasher 型表示 | 不採用（強調1つで代替） | 弱 | 配置が毎回変わり，空間の安定性と衝突する |
| 候補位置の移動や並べ替えのアニメーション，時間差での出現 | 不採用 | 中 | 遷移時間が打鍵間隔より1桁長い，staggering は逆効果 |
| 選択ハイライトの移動に 100 ms 前後の slow-in/slow-out を付ける | 任意 | 弱 | Dragicevic et al. 2011．100 ms 未満の遷移の研究はない |
| reduced motion の設定時はフェードも含めて即時表示にし，候補を出さない設定も用意する | 採用 | 強（規範）／中 | WCAG 2.1 SC 2.3.3，Koester & Levine 1994 |
| 自動補正の表示．ローマ字崩れの英単語やキー配列の誤りを直したら，元の綴りを候補に残し，直後の Backspace で元に戻す | 採用 | 弱〜中 | Smart-Restorable Backspace (Arif et al. 2016)，iOS の Backspace による取り消し．Punto Switcher に UX の実証研究はない |

補正の表示は，ほかの項目より根拠が薄い．Punto Switcher や XNeur は辞書で言語らしさを判定してキー配列を自動で切り替えるが，誤検知率や満足度を測った研究は見つからなかった ([XNeur man](https://manpages.org/xneur))．一方，取り消しの操作については実証がある．バックスペースのスワイプで直前の誤り位置まで消し，再スワイプで後続を復元する方式は，従来のバックスペースより入力速度と1文字あたりの操作数を改善した ([Arif et al. CHI 2016](https://vvise.iat.sfu.ca/user/data/papers/smartrestorablebackspace.pdf)) [中]．補正後の語をユーザーがすぐ消して打ち直したことを，その補正を無効にする信号として使う特許もある ([US Patent 5761689](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/5761689))．したがって，補正をかけるかどうかの判定より，補正したことが見えて1打で戻せることを先に作るのが良い．補正した箇所には下線などの静かな印を付け，元の綴りを第2候補に置けば，取り消しは既存の候補選択の操作で済む．

評価の方法については，Cockburn, Gutwin & Greenberg (CHI 2007) のメニュー性能モデルが使える．初心者の視覚探索時間，熟練者の Hick–Hyman 決定時間，両者の間の習熟の遷移を足し合わせたもので，分割メニューや適応型メニューで実測とよく一致した ([Springer Professional](https://www.springerprofessional.de/doi/10.1145/1240624.1240723)) [中]．ポインティング時間を一定のキー時間に置き換えれば，候補の配置案を実装前に比べられる．実装後は，打鍵削減率だけでなく，1変換あたりの時間，第一候補で確定した割合，候補ウィンドウを開いた割合を記録したい．Copilot の調査で体感生産性を最もよく予測したのは補完の受理率だった ([arXiv 2205.06537](https://arxiv.org/pdf/2205.06537)) ので，受理率もあわせて見ると良い．

## Conclusion

候補ウィンドウの新しさは，見た目の形よりも，ユーザーが候補を読まずに済む回数で測るべきだというのが今回の調査の結論である．木構造や放射状の表示が速度で劣るのは，形の問題というより，キーボード上で既知の語を選ぶという課題に合っていないためだ．反対に，地味に見える二つの性質，つまり読みが同じなら候補が同じ位置に来ることと，確信度が高いときには候補を出さないことには，ほかの分野で比較的しっかりした実験の裏づけがある．s90.tokyo IME の差別化は，派手なレイアウトよりもこの二つを徹底するほうが得られやすい．

未知の部分ははっきりしている．IME の候補ウィンドウでの視線計測，1ページの候補数を変えた統制実験，順位の安定性と成績の関係，文節格子の訂正時間は，どれも公開された研究が見つからなかった．s90.tokyo IME は自前の利用ログでこれらを測れる立場にある．分割メニュー型の順位づけと閾値つきの提示を先に入れ，文節格子と放射状配置は比較実験の対象にする順序で進めれば，既存の IME がこれまで答えてこなかった問いに，自分たちのデータで答えを出すことができる．
