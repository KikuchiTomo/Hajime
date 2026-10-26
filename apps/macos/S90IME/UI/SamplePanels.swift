import S90Application

/// 見本の分岐図．設定の画面の外観のプレビューと，見本の画像(SnapshotRenderer)で使う
enum SamplePanels {
    static let lattice = LatticePanel(columns: [
        .init(text: "私の", isFocused: false, isUncertain: false),
        .init(text: "名前は", isFocused: false, isUncertain: false, isDecided: true),
        .init(text: "中野です", alternatives: ["中のです", "中野です", "仲のです", "那珂のです"], selectedAlternative: 1,
              variants: ["なかのです", "ナカノデス", "ﾅｶﾉﾃﾞｽ"], isFocused: true, isUncertain: true, shorter: "中野で", longer: nil),
    ], position: 1, total: 8)
}
