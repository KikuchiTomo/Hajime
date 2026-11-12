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
                ResettableRow(model: model, keyPath: \.emojiCandidatePosition) {
                    Stepper(value: model.binding(\.emojiCandidatePosition), in: DefaultSettings.emojiCandidatePositionRange) {
                        LabeledContent(UIStrings.Settings.emojiCandidatePosition,
                                       value: UIStrings.Settings.emojiCandidatePositionValue(model.settings.emojiCandidatePosition))
                    }
                }
                ResettableRow(model: model, keyPath: \.emojiCandidateCount) {
                    Stepper(value: model.binding(\.emojiCandidateCount), in: DefaultSettings.emojiCandidateCountRange) {
                        LabeledContent(UIStrings.Settings.emojiCandidateCount, value: "\(model.settings.emojiCandidateCount)")
                    }
                }
                ResettableToggle(model: model, title: UIStrings.Settings.showsEmojiNames, keyPath: \.showsEmojiNames)
            }
            .disabled(model.settings.emojiPlacement == nil)
            if let panel = SamplePanels.emojiPlacement(model.settings) {
                CandidatePreview(choice: ThemeChoice(model.settings), fontSize: model.settings.candidateFontSize, panel: panel)
                    .padding(DesignTokens.Size.Settings.previewPadding)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// オン・オフの項目．名前の横に，その設定で出る候補の見本(「びーる → 🍺」)を札の形で添える
    private func exampleToggle(_ title: String, keyPath: WritableKeyPath<HajimeDomain.Settings, Bool>,
                               example: (reading: String, candidate: String)) -> some View {
        ResettableRow(model: model, keyPath: keyPath) {
            Toggle(isOn: model.binding(keyPath)) {
                HStack(spacing: DesignTokens.Size.Space.sm) {
                    Text(title)
                    CandidateExample(reading: example.reading, candidate: example.candidate)
                }
            }
        }
    }
}

/// 読みと，その読みで出る候補を並べた札(「ねこが → 🐈が」)
struct CandidateExample: View {
    let reading: String
    let candidate: String

    var body: some View {
        HStack(spacing: DesignTokens.Size.Space.xs) {
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

/// 候補の一覧の見本．テーマ・文字の大きさ・中身を変えると，その場で描き直す(欄が狭ければ同じ比で縮める)
struct CandidatePreview: NSViewRepresentable {
    let choice: ThemeChoice
    let fontSize: Double
    let panel: CandidatePanel

    func makeNSView(context: Context) -> ScaledPreview<CandidateView> {
        let view = CandidateView()
        view.fillsSurface = true
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
