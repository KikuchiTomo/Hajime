import HajimeApplication
import HajimeDomain
import SwiftUI

/// 初期設定の画面．左に実演の舞台，右にページ(題・説明・選択肢)と進み具合
struct OnboardingView: View {
    private typealias Size = DesignTokens.Size.Onboarding
    private typealias Opacity = DesignTokens.Opacity.Onboarding

    @ObservedObject var model: OnboardingModel

    static var size: CGSize { CGSize(width: Size.width, height: Size.height) }

    var body: some View {
        HStack(spacing: 0) {
            stage
                .frame(width: Size.stageWidth)
            VStack(alignment: .leading, spacing: Size.cardGap) {
                header
                ScrollView {
                    content
                        .padding(.vertical, Size.cardGap / 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 窓が低くて入らないときは，スクロールできることが分かるようにする
                .scrollIndicators(.automatic)
                footer
            }
            .padding(Size.padding)
        }
        // タイトルバーの下まで広げる(窓の大きさは OnboardingWindowController が決める)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .animation(.easeInOut(duration: DesignTokens.Motion.Onboarding.page / 1000), value: model.page)
    }

    // MARK: - 実演の舞台

    private var stage: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)
            // アクセントカラーと補正の色を，左上と右下からにじませる
            RadialGradient(colors: [Color.accentColor.opacity(Opacity.stageGlow), .clear], center: .topLeading,
                           startRadius: 0, endRadius: Size.height * 0.8)
            RadialGradient(colors: [Color(nsColor: .systemPink).opacity(Opacity.stageGlowSecondary), .clear], center: .bottomTrailing,
                           startRadius: 0, endRadius: Size.height * 0.7)
            OnboardingStage(page: model.page, settings: model.draft, spotlight: model.spotlight)
                .id(model.page)
                .transition(.opacity)
            if let spotlight = model.spotlight {
                SpotlightCaption(spotlight: spotlight)
                    .id(spotlight)
                    .transition(.asymmetric(insertion: .offset(y: Size.cardGap * 2).combined(with: .opacity), removal: .opacity))
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(Size.stagePadding)
            }
        }
        .animation(.spring(response: DesignTokens.Motion.Onboarding.page / 1000 * 1.6, dampingFraction: 0.82), value: model.spotlight)
        .ignoresSafeArea()
        .clipped()
    }

    // MARK: - 見出し

    private var header: some View {
        let index = (OnboardingPage.allCases.firstIndex(of: model.page) ?? 0) + 1
        return VStack(alignment: .leading, spacing: Size.cardGap / 2) {
            Text(UIStrings.Onboarding.step(index, of: OnboardingPage.allCases.count))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
            Text(model.page.title)
                .font(.largeTitle.weight(.bold))
            Text(model.page.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .id(model.page)
    }

    // MARK: - ページごとの選択肢

    @ViewBuilder private var content: some View {
        switch model.page {
        case .modeSwitch: modeSwitch
        case .appModes: appModes
        case .correction: correction
        case .theme: theme
        case .liveConversion: liveConversion
        case .presentation: presentation
        case .characters: characters
        case .features: features
        case .extras: extras
        }
    }

    private var modeSwitch: some View {
        VStack(spacing: Size.cardGap) {
            ForEach(ModeSwitchStyle.allCases, id: \.self) { style in
                OptionCard(title: UIStrings.Onboarding.label(for: style), detail: UIStrings.Onboarding.detail(for: style),
                           recommended: style == ModeSwitchStyle.recommended, selected: model.modeSwitchStyle == style) {
                    model.modeSwitchStyle = style
                }
            }
        }
    }

    /// 除外設定で選べる，アプリを切り替えたときのモード．ここでは紹介だけで，選ぶのは設定の画面
    private var appModes: some View {
        VStack(spacing: Size.cardGap) {
            ForEach([AppProfile.imeOff, .imeOn, .remembersMode], id: \.self) { profile in
                InfoCard(mark: Self.mark(for: profile), title: UIStrings.Settings.label(for: profile),
                         detail: UIStrings.Onboarding.appModeDetail(for: profile))
            }
        }
    }

    /// カードの札．モードの札と同じ文字(A・あ)を枠に入れて見せる．記憶は両方を並べる
    private static func mark(for profile: AppProfile) -> String {
        switch profile {
        case .imeOff: UIStrings.ModeIndicator.label(for: InputMode.direct)
        case .imeOn: UIStrings.ModeIndicator.label(for: InputMode.japanese)
        default: UIStrings.ModeIndicator.label(for: InputMode.direct) + UIStrings.ModeIndicator.label(for: InputMode.japanese)
        }
    }

    private var correction: some View {
        VStack(spacing: Size.cardGap) {
            ForEach(CorrectionSensitivity.allCases, id: \.self) { sensitivity in
                OptionCard(title: UIStrings.More.label(for: sensitivity), detail: UIStrings.Onboarding.detail(for: sensitivity),
                           recommended: sensitivity == .standard,
                           selected: model.draft.typoCorrection == .standard && model.draft.correctionSensitivity == sensitivity) {
                    model.draft.typoCorrection = .standard
                    model.draft.correctionSensitivity = sensitivity
                }
            }
            OptionCard(title: UIStrings.Onboarding.correctionOff, detail: nil, recommended: false, selected: model.draft.typoCorrection == .off) {
                model.draft.typoCorrection = .off
            }
        }
    }

    private var theme: some View {
        let themes = ThemePreference.allCases.filter { $0 != .native }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: (Size.width - Size.stageWidth - Size.padding * 2) / 3 - Size.cardGap), spacing: Size.cardGap)],
                         spacing: Size.cardGap) {
            ForEach(themes, id: \.self) { preference in
                ThemeTile(preference: preference, selected: model.draft.theme == preference && model.draft.customThemeID == nil) {
                    model.draft.theme = preference
                    model.draft.customThemeID = nil
                }
            }
        }
    }

    private var liveConversion: some View {
        VStack(spacing: Size.cardGap) {
            OptionCard(title: UIStrings.Onboarding.liveOn, detail: nil, recommended: true, selected: model.draft.liveConversion) {
                model.draft.liveConversion = true
            }
            OptionCard(title: UIStrings.Onboarding.liveOff, detail: nil, recommended: false, selected: !model.draft.liveConversion) {
                model.draft.liveConversion = false
            }
            SecondsSlider(title: UIStrings.Onboarding.liveDelay, value: model.binding(\.liveConversionDelay),
                          range: DefaultSettings.liveConversionDelayRange)
                .padding(.top, Size.cardGap / 2)
                .disabled(!model.draft.liveConversion)
        }
    }

    private var presentation: some View {
        VStack(alignment: .leading, spacing: Size.cardGap) {
            ForEach(CandidatePresentation.allCases, id: \.self) { presentation in
                OptionCard(title: UIStrings.Choice.label(for: presentation), detail: UIStrings.Onboarding.detail(for: presentation),
                           recommended: presentation == .automatic, selected: model.draft.candidatePresentation == presentation) {
                    model.draft.candidatePresentation = presentation
                }
            }
            LabeledContent(UIStrings.Onboarding.initialFocus) {
                Picker(UIStrings.Onboarding.initialFocus, selection: model.binding(\.initialFocus)) {
                    ForEach(InitialFocus.allCases, id: \.self) { focus in
                        Text(UIStrings.Choice.label(for: focus) + (focus == .start ? " (\(UIStrings.Onboarding.recommended))" : "")).tag(focus)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            .padding(.top, Size.cardGap / 2)
        }
    }

    private var characters: some View {
        VStack(spacing: Size.cardGap) {
            CharacterRow(title: UIStrings.Settings.punctuation, selection: model.binding(\.punctuation), label: UIStrings.Settings.label(for:))
            CharacterRow(title: UIStrings.Settings.brackets, selection: model.binding(\.brackets), label: UIStrings.Settings.label(for:))
            CharacterRow(title: UIStrings.Settings.slash, selection: model.binding(\.slash), label: UIStrings.Settings.label(for:))
            CharacterRow(title: UIStrings.Choice.yenKey, selection: model.binding(\.yenKey), label: UIStrings.Choice.label(for:))
            CharacterRow(title: UIStrings.Settings.spaceWidth, selection: model.binding(\.spaceWidth), label: UIStrings.Settings.label(for:))
            CharacterRow(title: UIStrings.Settings.numberWidth, selection: model.binding(\.numberWidth), label: UIStrings.Settings.label(for:))
            CharacterRow(title: UIStrings.More.alphabetWidth, selection: model.binding(\.alphabetWidth), label: UIStrings.Settings.label(for:))
        }
    }

    private var features: some View { spotlightRows(on: .features) }

    /// 既定ではオフの機能．ここでオンにでき，あとから設定の画面でも変えられる
    private var extras: some View { spotlightRows(on: .extras) }

    /// 機能の一覧．項目にポインタを置くと，左の舞台にその機能の実演と説明を出す(説明は舞台に出すので，項目は名前とスイッチだけ)
    private func spotlightRows(on page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: Size.cardGap) {
            ForEach(OnboardingSpotlight.items(on: page)) { item in
                SpotlightRow(item: item, isOn: model.binding(item.setting), highlighted: model.spotlight == item) {
                    model.spotlight = item
                }
            }
            Label(UIStrings.Onboarding.spotlightHint, systemImage: "cursorarrow.rays")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, Size.cardGap / 2)
        }
    }

    // MARK: - 足元

    private var footer: some View {
        HStack(spacing: Size.cardGap) {
            HStack(spacing: Size.dotGap) {
                ForEach(OnboardingPage.allCases) { page in
                    Circle()
                        .fill(page == model.page ? Color.accentColor : Color.secondary.opacity(Opacity.cardSelected * 3))
                        .frame(width: Size.dotSize, height: Size.dotSize)
                }
            }
            Spacer()
            Button(UIStrings.Onboarding.skip) { model.skip() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            if !model.isFirst {
                Button(UIStrings.Onboarding.back) { model.back() }
                    .controlSize(.large)
            }
            Button(model.isLast ? UIStrings.Onboarding.finish : UIStrings.Onboarding.next) {
                if model.isLast { model.finish() } else { model.next() }
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// 選択肢のカード．選んだカードはアクセントカラーの縁と地，推奨の選択肢には札を付ける
private struct OptionCard: View {
    private typealias Size = DesignTokens.Size.Onboarding
    private typealias Opacity = DesignTokens.Opacity.Onboarding

    let title: String
    let detail: String?
    let recommended: Bool
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: Size.cardGap) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: Size.cardGap / 3) {
                    HStack(spacing: Size.cardGap / 2) {
                        Text(title).font(.headline)
                        if recommended { RecommendedBadge() }
                    }
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(Size.cardPadding)
            .background(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(Opacity.cardSelected) : Color.primary.opacity(Opacity.cardIdle)))
            .overlay(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 「推奨」の札
private struct RecommendedBadge: View {
    private typealias Size = DesignTokens.Size.Onboarding

    var body: some View {
        Text(UIStrings.Onboarding.recommended)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, Size.cardPadding / 2)
            .padding(.vertical, Size.dotGap / 3)
            .background(RoundedRectangle(cornerRadius: Size.badgeRadius, style: .continuous).fill(Color.accentColor))
    }
}

/// テーマのカード．そのテーマの地・選択・補正の色を小さく並べた見本と名前
private struct ThemeTile: View {
    private typealias Size = DesignTokens.Size.Onboarding
    private typealias Opacity = DesignTokens.Opacity.Onboarding

    let preference: ThemePreference
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = ResolvedTheme.resolve(preference, appearance: NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua))
        Button(action: action) {
            VStack(alignment: .leading, spacing: Size.cardGap / 2) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: Size.cardRadius / 2, style: .continuous).fill(Color(nsColor: theme.surface))
                    VStack(alignment: .leading, spacing: Size.dotGap) {
                        Capsule().fill(Color(nsColor: theme.selection)).frame(width: Size.cardPadding * 4, height: Size.dotSize * 1.6)
                        Capsule().fill(Color(nsColor: theme.text).opacity(0.7)).frame(width: Size.cardPadding * 3, height: Size.dotSize / 1.5)
                        Capsule().fill(Color(nsColor: theme.correction)).frame(width: Size.cardPadding * 2, height: Size.dotSize / 2)
                    }
                    .padding(Size.cardPadding / 1.5)
                }
                .frame(height: Size.fieldHeight * 1.3)
                .overlay(RoundedRectangle(cornerRadius: Size.cardRadius / 2, style: .continuous).strokeBorder(Color(nsColor: theme.frame).opacity(0.6), lineWidth: 1))
                HStack(spacing: Size.cardGap / 2) {
                    Text(UIStrings.Choice.label(for: preference)).font(.callout.weight(.medium))
                    if preference == .automatic { RecommendedBadge() }
                }
            }
            .padding(Size.cardPadding / 1.5)
            .background(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(Opacity.cardSelected) : Color.primary.opacity(Opacity.cardIdle)))
            .overlay(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// 入力する文字の 1 行．名前と，選択肢のメニュー
private struct CharacterRow<Value: Hashable & CaseIterable>: View where Value.AllCases: RandomAccessCollection {
    private typealias Size = DesignTokens.Size.Onboarding
    private typealias Opacity = DesignTokens.Opacity.Onboarding

    let title: String
    let selection: Binding<Value>
    let label: (Value) -> String

    var body: some View {
        HStack {
            Text(title).font(.callout)
            Spacer()
            Picker(title, selection: selection) {
                ForEach(Array(Value.allCases), id: \.self) { Text(label($0)).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, Size.cardPadding)
        .padding(.vertical, Size.cardPadding / 2)
        .background(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous).fill(Color.primary.opacity(Opacity.cardIdle)))
    }
}

/// 説明だけのカード．入力モードの札と名前と説明を並べる
private struct InfoCard: View {
    private typealias Size = DesignTokens.Size.Onboarding
    private typealias Opacity = DesignTokens.Opacity.Onboarding

    let mark: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Size.cardGap) {
            Text(mark)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .lineLimit(1)
                .fixedSize()
                // 3 つの札の幅をそろえる(記憶の札は A とあの 2 文字)
                .frame(width: Size.infoSymbolWidth * 2, height: Size.infoSymbolWidth)
                .overlay(RoundedRectangle(cornerRadius: Size.cardRadius / 2, style: .continuous).stroke(Color.accentColor, lineWidth: 1.5))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Size.cardGap / 3) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Size.cardPadding)
        .background(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous).fill(Color.primary.opacity(Opacity.cardIdle)))
        .accessibilityElement(children: .combine)
    }
}

/// 機能の一覧の 1 行．アイコン・名前・スイッチ．ポインタを置くか押すと，左の舞台にその機能を見せる
private struct SpotlightRow: View {
    private typealias Size = DesignTokens.Size.Onboarding
    private typealias Opacity = DesignTokens.Opacity.Onboarding

    let item: OnboardingSpotlight
    let isOn: Binding<Bool>
    let highlighted: Bool
    let focus: () -> Void

    var body: some View {
        HStack(spacing: Size.cardGap) {
            Image(systemName: item.symbol)
                .font(.title3)
                .foregroundStyle(highlighted ? Color.accentColor : Color.secondary)
                .frame(width: Size.infoSymbolWidth)
                .accessibilityHidden(true)
            Text(item.title).font(.headline)
            Spacer(minLength: Size.cardGap)
            Toggle(item.title, isOn: isOn).labelsHidden().toggleStyle(.switch)
        }
        .padding(.horizontal, Size.cardPadding)
        .padding(.vertical, Size.cardPadding * 0.7)
        .background(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous)
            .fill(highlighted ? Color.accentColor.opacity(Opacity.cardSelected) : Color.primary.opacity(Opacity.cardIdle)))
        .overlay(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous)
            .strokeBorder(highlighted ? Color.accentColor : Color.clear, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous))
        .onHover { inside in if inside { focus() } }
        .onTapGesture(perform: focus)
        .animation(.easeOut(duration: DesignTokens.Motion.Onboarding.page / 1000), value: highlighted)
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.detail)
    }
}

/// 舞台の下に出す，見せている機能の説明の札．項目を移るたびに下から浮かび上がる
private struct SpotlightCaption: View {
    private typealias Size = DesignTokens.Size.Onboarding

    let spotlight: OnboardingSpotlight

    var body: some View {
        HStack(alignment: .top, spacing: Size.cardGap) {
            Image(systemName: spotlight.symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: Size.fieldHeight, height: Size.fieldHeight)
                .background(Circle().fill(Color.accentColor))
                .symbolEffect(.bounce, value: spotlight)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Size.cardGap / 3) {
                Text(spotlight.title).font(.headline)
                Text(spotlight.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Size.cardPadding)
        .background(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous).fill(.regularMaterial))
        .overlay(RoundedRectangle(cornerRadius: Size.cardRadius, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
