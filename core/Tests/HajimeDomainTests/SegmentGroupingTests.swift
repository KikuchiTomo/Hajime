import Testing
@testable import HajimeDomain

@Suite("分岐図のまとまり")
struct SegmentGroupingTests {
    @Test("文節の数が上限までなら分けない．区切らない設定(0)でも分けない")
    func single() {
        let texts = ["私の", "名前は", "中野です"]
        #expect(SegmentGrouping.groups(texts: texts, size: 8) == [0..<3])
        #expect(SegmentGrouping.groups(texts: texts, size: 3) == [0..<3])
        #expect(SegmentGrouping.groups(texts: Array(repeating: "あ", count: 20), size: 0) == [0..<20])
        #expect(SegmentGrouping.groups(texts: [], size: 8).isEmpty)
    }

    @Test("上限を超えたら，上限の数ずつに分ける")
    func byCount() {
        let texts = Array(repeating: "あ", count: 10)
        #expect(SegmentGrouping.groups(texts: texts, size: 4) == [0..<4, 4..<8, 8..<10])
        #expect(SegmentGrouping.group(containing: 5, texts: texts, size: 4) == 4..<8)
        #expect(SegmentGrouping.group(containing: 9, texts: texts, size: 4) == 8..<10)
    }

    @Test("後ろ半分に句点や読点で終わる文節があれば，そこで切る．句点を読点より優先する")
    func atPunctuation() {
        // 上限 4．3 番目が読点で終わるので，3 つで切る
        #expect(SegmentGrouping.groups(texts: ["今日は", "天気が", "良いので、", "公園まで", "散歩に", "出かけた"], size: 4) == [0..<3, 3..<6])
        // 読点(2 番目)と句点(4 番目)の両方があれば句点で切る
        #expect(SegmentGrouping.groups(texts: ["はい、", "そう、", "思い", "ます。", "では", "また"], size: 4) == [0..<4, 4..<6])
        // 前半の読点では切らない(短いまとまりを作りすぎない)
        #expect(SegmentGrouping.groups(texts: ["はい、", "今日は", "天気が", "良い", "ので", "出かけた"], size: 4) == [0..<4, 4..<6])
    }
}
