/// よくある読み違い・言い違い(「ふいんき」→ 雰囲気)．読みがこれに当たれば，正しい語を候補に足し，「もしかして」で示す．
///
/// 一覧ははじめのために書いた．国語辞典で正しい読みが一つに決まっていて，誤った読みが広く知られているものだけを選んだ
public enum Misreadings {
    public struct Entry: Sendable, Equatable {
        /// 誤った読み(ひらがな)
        public var reading: String
        /// 正しい語
        public var word: String
        /// 正しい読み(ひらがな)
        public var correctReading: String
    }

    public static let entries: [Entry] = [
        Entry(reading: "ふいんき", word: "雰囲気", correctReading: "ふんいき"),
        Entry(reading: "しゅみれーしょん", word: "シミュレーション", correctReading: "しみゅれーしょん"),
        Entry(reading: "こみにけーしょん", word: "コミュニケーション", correctReading: "こみゅにけーしょん"),
        Entry(reading: "あぼがど", word: "アボカド", correctReading: "あぼかど"),
        Entry(reading: "ぎぶす", word: "ギプス", correctReading: "ぎぷす"),
        Entry(reading: "ぶるどっく", word: "ブルドッグ", correctReading: "ぶるどっぐ"),
        Entry(reading: "がいしゅつ", word: "既出", correctReading: "きしゅつ"),
        Entry(reading: "しゅつのう", word: "出納", correctReading: "すいとう"),
        Entry(reading: "げんしつ", word: "言質", correctReading: "げんち"),
        Entry(reading: "はったん", word: "発端", correctReading: "ほったん"),
        Entry(reading: "ぞうあく", word: "憎悪", correctReading: "ぞうお"),
        Entry(reading: "たいさい", word: "体裁", correctReading: "ていさい"),
        Entry(reading: "けんあく", word: "嫌悪", correctReading: "けんお"),
        Entry(reading: "きょうない", word: "境内", correctReading: "けいだい"),
        Entry(reading: "ちょくひつ", word: "直筆", correctReading: "じきひつ"),
        Entry(reading: "ふうじょう", word: "風情", correctReading: "ふぜい"),
        Entry(reading: "きじゃく", word: "脆弱", correctReading: "ぜいじゃく"),
        Entry(reading: "ゆうつう", word: "融通", correctReading: "ゆうずう"),
        Entry(reading: "いきじ", word: "意気地", correctReading: "いくじ"),
        Entry(reading: "ぼうろ", word: "暴露", correctReading: "ばくろ"),
        Entry(reading: "すいちょう", word: "吹聴", correctReading: "ふいちょう"),
        Entry(reading: "けんねん", word: "懸念", correctReading: "けねん"),
        Entry(reading: "おうがら", word: "横柄", correctReading: "おうへい"),
        Entry(reading: "あいさい", word: "相殺", correctReading: "そうさい"),
        Entry(reading: "いちにちせんしゅう", word: "一日千秋", correctReading: "いちじつせんしゅう"),
        Entry(reading: "さつな", word: "刹那", correctReading: "せつな"),
        Entry(reading: "うるおぼえ", word: "うろ覚え", correctReading: "うろおぼえ"),
        Entry(reading: "ふしゅう", word: "踏襲", correctReading: "とうしゅう"),
        Entry(reading: "みぞうゆう", word: "未曾有", correctReading: "みぞう"),
        Entry(reading: "こんにちわ", word: "こんにちは", correctReading: "こんにちは"),
        Entry(reading: "こんばんわ", word: "こんばんは", correctReading: "こんばんは"),
    ]

    private static let table = Dictionary(entries.map { ($0.reading, $0) }, uniquingKeysWith: { first, _ in first })

    /// 読み全体がよくある読み違いなら，その項目
    public static func entry(for reading: String) -> Entry? {
        table[reading]
    }

    /// 読みの末尾がよくある読み違いなら，その項目と，読みの中の始まりの位置(文字数)．長いものを先に調べる
    public static func suffixEntry(in reading: String) -> (entry: Entry, start: Int)? {
        let characters = Array(reading)
        for length in stride(from: min(characters.count, 12), through: 3, by: -1) {
            let start = characters.count - length
            if let entry = table[String(characters[start...])] { return (entry, start) }
        }
        return nil
    }
}
