/// うろ覚えで読みを少し違えて打った語(「しゅみれーしょん」→ シミュレーション，「こみにけーしょん」→ コミュニケーション，
/// 「ぶるどっく」→ ブルドッグ)を見つけるための，読みの組み替え．
///
/// Misreadings は一つずつ書いた一覧で，ここは一覧に無い語のための決まり．外来語の言い違いに多い形だけを試す
/// - 小さい「ゃゅょ」の位置の取り違え(しゅみ ↔ しみゅ)
/// - 小さい「ゅ」の抜け(こみに → こみゅに)と，余分な「ゅ」
/// - 濁点・半濁点の取り違え(ぶるどっく → ぶるどっぐ，ぎぶす → ぎぷす，あぼがど → あぼかど)
/// - 長音の抜け・余分な長音(こんぴゅーた ↔ こんぴゅーたー)
/// どれが正しい語かは呼び出し側が辞書で確かめる(SupplementedConverter)
public enum LooseReadings {
    private static let smallY: Set<Character> = ["ゃ", "ゅ", "ょ"]
    /// 小さい「ゃゅょ」を付けられる，い段のかな
    private static let iRow: Set<Character> = Set("きしちにひみりぎじぢびぴ")

    /// 読みを 1 か所だけ組み替えた読み．元の読みと同じものと重なりは除く．多すぎないよう DefaultSettings.maximumLooseReadingVariants まで
    public static func variants(of reading: String) -> [String] {
        let characters = Array(reading)
        guard characters.count >= DefaultSettings.minimumLooseReadingLength, characters.count <= DefaultSettings.maximumLooseReadingLength else { return [] }
        var seen: Set<String> = [reading]
        var result: [String] = []
        func add(_ variant: [Character]) {
            let text = String(variant)
            if seen.insert(text).inserted { result.append(text) }
        }
        for index in characters.indices {
            let current = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let afterNext = index + 2 < characters.count ? characters[index + 2] : nil
            // しゅみ → しみゅ: 小さいかなを次のい段のかなのあとへ
            if iRow.contains(current), let small = next, smallY.contains(small), let target = afterNext, iRow.contains(target) {
                add(Array(characters[..<index]) + [current, target, small] + Array(characters[(index + 3)...]))
            }
            // しみゅ → しゅみ: 小さいかなを前のい段のかなのあとへ
            if iRow.contains(current), let target = next, iRow.contains(target), let small = afterNext, smallY.contains(small) {
                add(Array(characters[..<index]) + [current, small, target] + Array(characters[(index + 3)...]))
            }
            // こみに → こみゅに: い段のかなのあとに「ゅ」を補う(次が小さいかなでないとき)
            if iRow.contains(current), next.map({ !smallY.contains($0) && $0 != "ぇ" }) ?? false {
                add(Array(characters[...index]) + ["ゅ"] + Array(characters[(index + 1)...]))
            }
            // 余分な小さいかなを除く
            if smallY.contains(current), index > 0 {
                add(Array(characters[..<index]) + Array(characters[(index + 1)...]))
            }
            // 濁点・半濁点の取り違え
            for voiced in voicingAlternatives(of: current) {
                var replaced = characters
                replaced[index] = voiced
                add(replaced)
            }
            // 長音の抜けと余分な長音
            if current == "ー" {
                add(Array(characters[..<index]) + Array(characters[(index + 1)...]))
            }
        }
        if characters.last != "ー" { add(characters + ["ー"]) }
        return Array(result.prefix(DefaultSettings.maximumLooseReadingVariants))
    }

    /// 清音・濁音・半濁音を入れ替えた字(か → が，ぶ → ふ・ぷ)
    static func voicingAlternatives(of character: Character) -> [Character] {
        for group in voicingGroups where group.contains(character) {
            return group.filter { $0 != character }
        }
        return []
    }

    private static let voicingGroups: [[Character]] = {
        let plain = Array("かきくけこさしすせそたちつてと"), voiced = Array("がぎぐげござじずぜぞだぢづでど")
        var groups = zip(plain, voiced).map { [$0, $1] }
        for (h, b, p) in zip(Array("はひふへほ"), zip(Array("ばびぶべぼ"), Array("ぱぴぷぺぽ"))).map({ ($0, $1.0, $1.1) }) {
            groups.append([h, b, p])
        }
        // ぢ・づは じ・ず と取り違えるのがふつうで，ち・つ と取り違えることは少ないので除く
        return groups.filter { !$0.contains("ぢ") && !$0.contains("づ") }
    }()
}
