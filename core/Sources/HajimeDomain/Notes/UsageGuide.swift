/// 変換の候補に添える使い分けと誤用の注釈(R-08)．同音異義語は同梱の辞書(UsageDictionary)を先に使い，
/// 辞書に無い語はこのリポジトリで書いた組で補う．誤用の文はすべてこのリポジトリで書いたもの．
///
/// - 同音異義語: 同じ読みで意味の違う語の使い分け(「撮る」写真や動画を写す，など)．既定で出す
/// - 誤用: 本来とは違う形で広まっている言い回し(「汚名挽回」→「汚名返上」「名誉挽回」)．既定では出さない
/// 同音異義語の使い分けの注釈．候補の窓は語・意味・ほかの語を描き分ける(語を強く，意味を控えめに，ほかの語を札に)
public struct HomophoneNote: Sendable, Equatable {
    /// 選んでいる候補に当たる語(「撮る」)
    public var word: String
    /// その語の意味(句点を除く)
    public var meaning: String
    /// 使い方の例(「写真を撮る」．かぎ括弧を除く)．無ければ nil
    public var example: String?
    /// 同じ読みのほかの語(「取る」「採る」)
    public var others: [String]

    public init(word: String, meaning: String, example: String? = nil, others: [String]) {
        self.word = word
        self.meaning = meaning
        self.example = example
        self.others = others
    }

    /// 1 行の文にしたもの(読み上げなど)．「撮る: 撮影する。例「写真を撮る」　ほかに 取る・採る」
    public var text: String {
        let example = example.map { "。例「\($0)」" } ?? ""
        return "\(word): \(meaning)\(example)　ほかに \(others.joined(separator: "・"))"
    }
}

extension HomophoneNote: CustomStringConvertible, CustomDebugStringConvertible {
    // 語は入力内容なので，ログには数だけを出す
    public var description: String { "HomophoneNote(others: \(others.count))" }
    public var debugDescription: String { description }
}

public enum UsageGuide {
    public struct Homophone: Sendable, Equatable {
        public var word: String
        public var meaning: String
        public var example: String?

        /// 語の漢字の部分(送り仮名を除いたもの)．「撮る」→「撮」，「清算」→「清算」
        var stem: String { String(word.prefix { !$0.isHiragana }) }

        /// 文節がこの語か．送り仮名のある語は，漢字の部分のあとが送り仮名(ひらがな)か文節の終わりのときだけ当てはめる
        /// (「撮った」は当てはめ，「取引」は当てはめない)
        func matches(_ text: String) -> Bool {
            guard text.hasPrefix(stem) else { return false }
            guard stem != word else { return true }
            return text.dropFirst(stem.count).first.map(\.isHiragana) ?? true
        }
    }

    struct Group: Sendable, Equatable {
        /// 組に共通する読みの先頭(「とる」の組は「と」)．文節の読みがこれで始まるときだけ当てはめる
        var reading: String
        var words: [Homophone]
    }

    /// 文節の候補に当てはまる同音異義語の使い分け．同梱の辞書(dictionary)を先に引き，無ければこのリポジトリで書いた組を引く．
    /// 当てはまらなければ nil．
    /// 活用した形(「撮った」)にも当てはまるよう，語の漢字の部分(「撮」)が候補にあり，文節の読みが組の読み(「と」)で始まるものを探す．
    /// 例: 「撮った」(読み「とった」)→「撮る」写真や動画を写す，ほかに「取る」「採る」「執る」「捕る」
    public static func homophoneNote(for text: String, reading: String, dictionary: UsageDictionary? = nil) -> HomophoneNote? {
        if let note = dictionary?.note(for: text, reading: reading) { return note }
        for group in homophoneGroups where reading.hasPrefix(group.reading) {
            guard let hit = group.words.first(where: { $0.matches(text) }) else { continue }
            return HomophoneNote(word: hit.word, meaning: hit.meaning, example: hit.example, others: group.words.filter { $0.word != hit.word }.map(\.word))
        }
        return nil
    }

    /// 候補の文字列に誤用の言い回しが含まれていれば，その注釈．含まれていなければ nil
    public static func misuseNote(for text: String) -> String? {
        misuses.first { text.contains($0.phrase) }.map { "「\($0.phrase)」は\($0.note)" }
    }

    private static func group(_ reading: String, _ entries: [(String, String)]) -> Group {
        Group(reading: reading, words: entries.map { Homophone(word: $0.0, meaning: $0.1) })
    }

    /// 同じ読みの語の組
    static let homophoneGroups: [Group] = [
        group("せいさん", [("清算", "貸し借りを整理してけりをつける"), ("精算", "料金などを細かく計算し直す"), ("成算", "うまくいく見込み")]),
        group("たいしょう", [("対象", "働きかけや関心が向かう相手"), ("対照", "比べ合わせる・違いが際立つ"), ("対称", "つり合いがとれている")]),
        group("ほしょう", [("保証", "間違いがないと請け合う"), ("保障", "権利や安全を守る"), ("補償", "損害を償う")]),
        group("こうえん", [("講演", "大勢の前で話をする"), ("公演", "劇や音楽を人前で演じる"), ("後援", "活動を後ろから支える")]),
        group("かいとう", [("回答", "問いや要求に答える"), ("解答", "問題を解いて答えを出す")]),
        group("しゅうせい", [("修正", "誤りや不足を直す"), ("修整", "写真や画像を手直しする")]),
        group("たいけい", [("体系", "全体をまとめた仕組み"), ("体型", "体の形"), ("大系", "ある分野をまとめた書物")]),
        group("きかい", [("機会", "何かをするのにちょうどよいとき"), ("機械", "動力で動く装置"), ("器械", "動力を使わない道具・器具")]),
        group("じき", [("時期", "何かを行う期間"), ("時機", "ちょうどよい機会"), ("時季", "季節・シーズン")]),
        group("かんしん", [("関心", "興味を持つこと"), ("感心", "心を動かされてほめる"), ("歓心", "相手が喜ぶ気持ち")]),
        group("ついきゅう", [("追求", "目的のものを追い求める"), ("追究", "深く調べて明らかにする"), ("追及", "責任や欠点を問いただす")]),
        group("いし", [("意思", "考えや思い"), ("意志", "成し遂げようとする強い気持ち")]),
        group("どうし", [("同士", "仲間・同じ種類のもの"), ("同志", "同じ志を持つ人")]),
        group("いがい", [("以外", "それを除いたほか"), ("意外", "思いがけない")]),
        group("と", [("撮る", "写真や動画を写す"), ("取る", "手に持つ・手に入れる"), ("採る", "選び出す・集める"), ("執る", "役目や事務を行う"), ("捕る", "動物などをつかまえる")]),
        group("あ", [("会う", "人と顔を合わせる"), ("合う", "一致する・調和する"), ("遭う", "好ましくない出来事に出くわす")]),
        group("はか", [("図る", "計画する・工夫する"), ("計る", "時間や数を数える"), ("測る", "長さ・高さ・深さを調べる"), ("量る", "重さや容積を調べる"), ("諮る", "意見を求める"), ("謀る", "よくないことをたくらむ")]),
        group("あつ", [("暑い", "気温が高い"), ("熱い", "物の温度が高い・感情が高ぶる"), ("厚い", "厚みがある・心がこもっている")]),
        group("か", [("変える", "状態や内容を変化させる"), ("替える", "新しいものと取り替える"), ("換える", "ほかのものと交換する"), ("代える", "ほかのものに役目をさせる")]),
        group("おさ", [("収める", "中に入れる・成果を得る"), ("納める", "税や品物を渡す"), ("治める", "国を統治する・争いを鎮める"), ("修める", "学問や技を身につける")]),
        group("つと", [("努める", "力を尽くす"), ("勤める", "職場で働く"), ("務める", "役目を受け持つ")]),
        group("あ", [("開ける", "閉じたものを開く"), ("明ける", "夜や期間が終わる"), ("空ける", "中身をなくして空にする")]),
        group("うつ", [("写す", "書き写す・写真に撮る"), ("映す", "鏡や画面に映し出す"), ("移す", "場所や状態を変える")]),
        group("き", [("聞く", "音を耳で受け取る・尋ねる"), ("聴く", "注意して耳を傾ける"), ("効く", "効果が表れる"), ("利く", "機能が働く")]),
        group("のぼ", [("上る", "上の方へ移る"), ("登る", "高い所へ自分の力で行く"), ("昇る", "太陽が上がる・地位が上がる")]),
        group("さ", [("指す", "指し示す"), ("差す", "傘を差す・光が差す"), ("刺す", "とがったもので突く"), ("挿す", "細いものを差し込む")]),
        group("た", [("建つ", "建物ができる"), ("絶つ", "つながりを切る・なくす"), ("断つ", "切り離す・やめる"), ("発つ", "出発する")]),
        group("かた", [("固い", "しっかりして動かない"), ("硬い", "物の質がかたい・こわばっている"), ("堅い", "中身が詰まって確かだ")]),
        group("おく", [("送る", "届ける・見送る"), ("贈る", "気持ちを込めて人に与える")]),
    ]

    struct Misuse: Sendable, Equatable {
        var phrase: String
        var note: String
    }

    /// 誤用とされる言い回しと注釈
    static let misuses: [Misuse] = [
        Misuse(phrase: "汚名挽回", note: "「汚名返上」か「名誉挽回」が本来の形です"),
        Misuse(phrase: "取り付く暇もない", note: "「取り付く島もない」が本来の形です"),
        Misuse(phrase: "熱にうなされる", note: "「熱に浮かされる」が本来の形です"),
        Misuse(phrase: "怒り心頭に達する", note: "「怒り心頭に発する」が本来の形です"),
        Misuse(phrase: "上や下への", note: "「上を下への」が本来の形です"),
        Misuse(phrase: "舌の先の乾かぬうち", note: "「舌の根の乾かぬうち」が本来の形です"),
        Misuse(phrase: "一つ返事", note: "快く引き受ける意味なら「二つ返事」です"),
        Misuse(phrase: "雪辱を晴らす", note: "「雪辱を果たす」か「屈辱を晴らす」が本来の形です"),
        Misuse(phrase: "二の舞を踏む", note: "「二の舞を演じる」か「二の足を踏む」が本来の形です"),
        Misuse(phrase: "白羽の矢が当たる", note: "「白羽の矢が立つ」が本来の形です"),
        Misuse(phrase: "押しも押されぬ", note: "「押しも押されもせぬ」が本来の形です"),
        Misuse(phrase: "足元をすくわれる", note: "「足をすくわれる」が本来の形です"),
        Misuse(phrase: "采配を振るう", note: "「采配を振る」が本来の形です"),
        Misuse(phrase: "物議を呼ぶ", note: "「物議を醸す」が本来の形です"),
        Misuse(phrase: "公算が強い", note: "「公算が大きい」が本来の形です"),
        Misuse(phrase: "寸暇を惜しまず", note: "「寸暇を惜しんで」が本来の形です"),
        Misuse(phrase: "古式豊か", note: "「古式ゆかしく」が本来の形です"),
        Misuse(phrase: "過半数を超える", note: "「過半数に達する」か「半数を超える」が本来の形です"),
        Misuse(phrase: "後で後悔", note: "「後悔」だけで意味が通ります(意味の重複)"),
        Misuse(phrase: "頭痛が痛い", note: "「頭が痛い」か「頭痛がする」です(意味の重複)"),
        Misuse(phrase: "役不足", note: "本来は「力量に比べて役目が軽すぎる」意味です．力が足りない意味なら「力不足」"),
        Misuse(phrase: "確信犯", note: "本来は「信念に基づいて正しいと信じて行う犯罪」の意味です"),
        Misuse(phrase: "的を得る", note: "「的を射る」が本来の形とされます"),
    ]
}

extension Character {
    fileprivate var isHiragana: Bool {
        unicodeScalars.allSatisfy { (0x3041...0x309F).contains($0.value) }
    }
}
