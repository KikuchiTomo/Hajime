import AppKit
import HajimeApplication
import HajimeDomain
import SwiftUI

/// 変換のページの「絵文字」．2 種類の変換は項目名の横の候補の見本で見分け，
/// 位置・数・名前は変えるとその場で下の候補の窓の見本が変わる(説明の文は置かない)
struct EmojiSection: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        Section(UIStrings.Settings.emojiSection) {
            exampleToggle(UIStrings.Settings.emojiConversion, keyPath: \.emojiConversion, example: UIStrings.Settings.emojiConversionExample)
            exampleToggle(UIStrings.Settings.emojiWordConversion, keyPath: \.emojiWordConversion, example: UIStrings.Settings.emojiWordConversionExample)
            Group {
                ResettableStepper(model: model, title: UIStrings.Settings.emojiCandidatePosition, keyPath: \.emojiCandidatePosition, range: DefaultSettings.emojiCandidatePositionRange,
                                  value: UIStrings.Settings.emojiCandidatePositionValue(model.settings.emojiCandidatePosition))
                ResettableStepper(model: model, title: UIStrings.Settings.emojiCandidateCount, keyPath: \.emojiCandidateCount, range: DefaultSettings.emojiCandidateCountRange,
                                  value: "\(model.settings.emojiCandidateCount)")
                // 見本は最後の行(名前の表示)のすぐ下に，項目の名前と同じ左の端から置く(足元の行を出さない小さな窓)．
                // 同じ行に入れて区切りの線を引かず，項目との間は section の余白にする
                VStack(alignment: .leading, spacing: DesignTokens.Size.Space.section) {
                    ResettableToggle(model: model, title: UIStrings.Settings.showsEmojiNames, keyPath: \.showsEmojiNames)
                    if let panel = SamplePanels.emojiPlacement(model.settings) {
                        CandidatePreview(choice: ThemeChoice(model.settings), fontSize: model.settings.candidateFontSize, panel: panel)
                    }
                }
            }
            .disabled(model.settings.emojiPlacement == nil)
        }
    }

    /// 2 つの切り替えの名前のうち長いほうの幅(Form の名前と同じ本文の書体で測る)．タグの左の端をそろえる．
    /// 名前の欄は最小の幅として使うので，測り方の差で名前が欠けることはない
    private var titleWidth: CGFloat {
        let font = NSFont.preferredFont(forTextStyle: .body)
        return [UIStrings.Settings.emojiConversion, UIStrings.Settings.emojiWordConversion]
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width.rounded(.up) }
            .max() ?? 0
    }

    /// オン・オフの項目．名前の横に，その設定で出る候補の見本(「びーる → 🍺」)をタグの形で添える．
    /// タグは 2 つの名前の長いほうのあとから書き出し，行ごとの左の端をそろえる
    private func exampleToggle(_ title: String, keyPath: WritableKeyPath<HajimeDomain.Settings, Bool>,
                               example: (reading: String, candidate: String)) -> some View {
        ResettableRow(model: model, keyPath: keyPath) {
            Toggle(isOn: model.binding(keyPath)) {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Size.Space.group) {
                    Text(title).frame(minWidth: titleWidth, alignment: .leading)
                    CandidateExample(reading: example.reading, candidate: example.candidate)
                }
            }
        }
    }
}

/// 読みと，その読みで出る候補を並べたタグ(「ねこが → 🐈が」)
struct CandidateExample: View {
    let reading: String
    let candidate: String

    var body: some View {
        HStack(spacing: DesignTokens.Size.Space.inline) {
            Text(reading).foregroundStyle(.secondary)
            Image(systemName: "arrow.right").foregroundStyle(.tertiary).imageScale(.small)
            Text(candidate)
        }
        .font(.callout)
        .padding(.horizontal, DesignTokens.Size.Settings.previewChipPaddingX)
        .padding(.vertical, DesignTokens.Size.Settings.previewChipPaddingY)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: DesignTokens.Size.Settings.previewChipRadius))
        .accessibilityElement(children: .combine)
    }
}

/// 候補の一覧の見本(足元の行を出さない)．テーマ・文字の大きさ・中身を変えると，その場で描き直す(欄が狭ければ同じ比で縮める)
struct CandidatePreview: NSViewRepresentable {
    let choice: ThemeChoice
    let fontSize: Double
    let panel: CandidatePanel

    func makeNSView(context: Context) -> ScaledPreview<CandidateView> {
        let view = CandidateView()
        view.fillsSurface = true
        view.showsFooter = false
        return ScaledPreview(content: view)
    }

    func updateNSView(_ view: ScaledPreview<CandidateView>, context: Context) {
        view.content.theme = ResolvedTheme.resolve(choice, appearance: view.effectiveAppearance)
        view.content.fontSize = CGFloat(fontSize)
        view.content.panel = panel
        view.natural = view.content.fittingSize(for: panel)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: ScaledPreview<CandidateView>, context: Context) -> CGSize? {
        ScaledPreview<CandidateView>.size(natural: view.content.fittingSize(for: panel), proposal: proposal)
    }
}
