import HajimeApplication

import HajimeDomain

/// 見本の分岐図と候補の一覧．設定の画面の外観のプレビューと，見本の画像(SnapshotRenderer)で使う
enum SamplePanels {
    static let list = CandidatePanel(
        variants: ScriptVariant.allCases.map { .init(label: $0.label, isAvailable: true) },
        selectedVariant: nil,
        entries: ["変換", "返還", "偏官", "へんかん", "ヘンカン"].map { .init(text: $0, annotation: nil) },
        selectedEntry: 1, focus: .candidate, position: 2, total: 12, note: nil
    )

    static let lattice = LatticePanel(columns: [
        .init(text: "私の", isFocused: false, isUncertain: false),
        .init(text: "名前は", isFocused: false, isUncertain: false, isDecided: true),
        .init(text: "中野です", alternatives: ["中のです", "中野です", "仲のです", "那珂のです"], selectedAlternative: 1,
              variants: ["なかのです", "ナカノデス", "ﾅｶﾉﾃﾞｽ"], isFocused: true, isUncertain: true, shorter: "中野で", longer: nil),
    ], position: 1, total: 8)
}
