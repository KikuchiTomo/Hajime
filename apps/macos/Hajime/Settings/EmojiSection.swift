import AppKit
import HajimeApplication
import HajimeDomain
import SwiftUI

/// 変換のページの「絵文字」．2 種類の変換は項目名の横の候補の見本で見分け，
/// 位置・数・名前は変えるとその場で下の候補の窓の見本が変わる(説明の文は置かない)
struct EmojiSection: View {
    @ObservedObject var model: SettingsModel
    /// タグの左の端をそろえる名前の幅(2 つの切り替えの長いほう．見出しで区切った別のまとまりの見本とはそろえない)
    var titleWidth = ExampleToggle.titleWidth([UIStrings.Settings.emojiConversion, UIStrings.Settings.emojiWordConversion])

    var body: some View {
        Section(UIStrings.Settings.emojiSection) {
            ExampleToggle(model: model, title: UIStrings.Settings.emojiConversion, keyPath: \.emojiConversion,
                          example: UIStrings.Settings.emojiConversionExample, titleWidth: titleWidth)
            ExampleToggle(model: model, title: UIStrings.Settings.emojiWordConversion, keyPath: \.emojiWordConversion,
                          example: UIStrings.Settings.emojiWordConversionExample, titleWidth: titleWidth)
            Group {
                ResettableStepper(model: model, title: UIStrings.Settings.emojiCandidatePosition, keyPath: \.emojiCandidatePosition, range: DefaultSettings.emojiCandidatePositionRange,
                                  value: UIStrings.Settings.emojiCandidatePositionValue(model.settings.emojiCandidatePosition))
                ResettableStepper(model: model, title: UIStrings.Settings.emojiCandidateCount, keyPath: \.emojiCandidateCount, range: DefaultSettings.emojiCandidateCountRange,
                                  value: "\(model.settings.emojiCandidateCount)")
                // 見本は最後の行(名前の表示)のすぐ下に，項目の名前と同じ左の端から置く(足元の行を出さない小さな窓)．
                // 同じ行に入れて区切りの線を引かず，項目との間は section の余白にする
                VStack(alignment: .leading, spacing: DesignTokens.Size.Space.section) {
                    ResettableToggle(model: model, title: UIStrings.Settings.showsEmojiNames, keyPath: \.showsEmojiNames)
                    if let panel = SamplePanels.emojiPlacement(model.settings.emojiPlacement, convertsWholeReading: model.settings.emojiConversion,
                                                               candidatesPerPage: model.settings.listCandidatesPerPage, showsNames: model.settings.showsEmojiNames) {
                        CandidatePreview(choice: ThemeChoice(model.settings), fontSize: model.settings.candidateFontSize, panel: panel)
                    }
                }
            }
            .disabled(model.settings.emojiPlacement == nil)
        }
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
