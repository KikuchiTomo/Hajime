/// 校正支援(R-08)．候補の文に，ら抜き言葉・さ入れ言葉・二重敬語・重言があれば，本来の形を添える．
///
/// 文は直さない(言い方は利用者が決める)．分岐図で選んでいる候補の下に注釈として出すだけにする．
/// 語の並びはすべてこのリポジトリで選んだ．よく使う動詞と言い回しに絞り，正しい文に注釈を付けないことを優先する
public enum Proofreading {
    /// 候補の文に当てはまる最初の注釈．無ければ nil
    public static func note(for text: String) -> String? {
        raNuki(text) ?? saIre(text) ?? phrase(doubleHonorifics, kind: "二重敬語", in: text) ?? phrase(redundancies, kind: "重言", in: text)
    }

    /// ら抜き言葉: 一段動詞・カ変動詞の可能の形から「ら」が抜けたもの(見れる → 見られる)．
    /// 「見れば」は仮定の形で正しいので，「れ」のあとが「ば」のものは除く
    private static func raNuki(_ text: String) -> String? {
        for stem in ichidanStems {
            var searchRange = text.startIndex..<text.endIndex
            while let range = text.range(of: stem + "れ", range: searchRange) {
                let rest = text[range.upperBound...]
                if let ending = raNukiEndings.first(where: { rest.hasPrefix($0) }) {
                    let wrong = stem + "れ" + ending
                    return "「\(wrong)」はら抜き言葉です。「\(stem)られ\(ending)」が本来の形です。"
                }
                searchRange = range.upperBound..<text.endIndex
            }
        }
        return nil
    }

    /// さ入れ言葉: 五段動詞の使役に余分な「さ」が入ったもの(読まさせて → 読ませて)
    private static func saIre(_ text: String) -> String? {
        for stem in godanNegativeStems where text.contains(stem + "させ") {
            return "「\(stem)させ」はさ入れ言葉です。「\(stem)せ」が本来の形です。"
        }
        return nil
    }

    private static func phrase(_ entries: [(wrong: String, right: String)], kind: String, in text: String) -> String? {
        entries.first { text.contains($0.wrong) }.map { "「\($0.wrong)」は\(kind)です。「\($0.right)」で足ります。" }
    }

    /// 一段動詞とカ変動詞の，「られる」の前の形
    static let ichidanStems = [
        "見", "来", "出", "寝", "着", "居", "似", "煮", "干",
        "食べ", "起き", "考え", "決め", "信じ", "感じ", "覚え", "投げ", "開け", "閉め", "降り", "借り", "生き", "落ち", "伸び", "浴び",
        "止め", "辞め", "始め", "教え", "答え", "変え", "越え", "超え", "捨て", "建て", "育て", "比べ", "調べ", "並べ", "述べ", "混ぜ",
        "受け", "付け", "続け", "避け", "負け", "助け", "見せ", "任せ", "乗せ", "載せ", "寄せ", "出かけ", "片付け", "見つけ",
    ]

    /// ら抜き言葉の「れ」に続く形
    static let raNukiEndings = ["る", "ない", "ます", "ません", "た", "て", "なかった", "そう"]

    /// 五段動詞の，「せる」の前の形(ない形の語幹)
    static let godanNegativeStems = [
        "書か", "読ま", "行か", "休ま", "帰ら", "言わ", "待た", "話さ", "歌わ", "使わ", "作ら", "送ら", "頑張ら", "知ら", "取ら",
        "撮ら", "選ば", "遊ば", "飲ま", "聞か", "働か", "思わ", "買わ", "会わ", "持た", "立た", "座ら", "走ら", "泳が", "急が",
    ]

    /// 二重敬語(尊敬語に「れる・られる」や「お〜になる」を重ねたもの)
    static let doubleHonorifics: [(wrong: String, right: String)] = [
        ("おっしゃられ", "おっしゃ"), ("お見えになられ", "お見えにな"), ("ご覧になられ", "ご覧にな"), ("お越しになられ", "お越しにな"),
        ("お帰りになられ", "お帰りにな"), ("召し上がられ", "召し上が"), ("お召し上がりにな", "召し上が"), ("お読みになられ", "お読みにな"),
        ("お書きになられ", "お書きにな"), ("いらっしゃられ", "いらっしゃ"),
    ]

    /// 重言(同じ意味の語を重ねたもの)．「後で後悔」「頭痛が痛い」などは誤用の注釈(UsageGuide.misuses)が受け持つ
    static let redundancies: [(wrong: String, right: String)] = [
        ("一番最初", "最初"), ("一番最後", "最後"), ("違和感を感じ", "違和感を覚え"), ("必ず必要", "必要"), ("馬から落馬", "落馬"),
        ("元旦の朝", "元旦"), ("被害を被", "被害を受け"), ("犯罪を犯", "罪を犯"), ("今現在", "現在"), ("まず最初に", "最初に"),
        ("日本に来日", "来日"), ("射程距離", "射程"), ("製造メーカー", "メーカー"), ("返事を返", "返事をす"), ("思いがけないハプニング", "ハプニング"), ("最後の切り札", "切り札"),
    ]
}
