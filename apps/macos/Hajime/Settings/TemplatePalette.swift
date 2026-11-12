import HajimeApplication
import HajimeDomain
import HajimePersistence
import SwiftUI

/// 単語と変換マクロに書ける書き方のチップ(R-21・R-22．TemplateReference)．RuleListEditor が欄の下に開く．
/// ふだんは上の切り替えでまとまり(短い見出し)を選び，そのチップを並べる(すべて並べると 100 ほどになるため)．
/// 欄で書き方を打ちかけているときは，当たるチップだけをまとまりを問わずに並べる(matches)．
/// チップには今の値を小さく添え，押すと insert に渡す．意味はポインターを載せたときに出す．矢印のキーで隣のチップに移る．
/// 値は 1 秒ごとに求め直す．UUID と乱数は入れるたびに変わるので，開いたときの値を 1 つ出す
struct TemplatePalette: View {
    private let reference: TemplateReference
    /// 変換マクロの {text} と {reading} に入れる語と読み(単語では nil)
    private let sample: (text: String, reading: String)?
    /// 打ちかけの書き方に当たるチップ．絞り込まないときは nil
    private let matches: [TemplateReference.Match]?
    private let focus: FocusState<String?>.Binding
    private let insert: (TemplateReference.Item, TemplateReference.Kind) -> Void

    init(reference: TemplateReference, sample: (text: String, reading: String)? = nil, matches: [TemplateReference.Match]?,
         focus: FocusState<String?>.Binding, insert: @escaping (TemplateReference.Item, TemplateReference.Kind) -> Void) {
        self.reference = reference
        self.sample = sample
        self.matches = matches
        self.focus = focus
        self.insert = insert
    }

    /// 選んでいるまとまり(見出し)．nil なら最初のまとまり
    @State private var selected: String?
    @State private var uuid = UUID().uuidString
    @State private var randomSeed = Int.random(in: 0..<Int(UInt16.max))
    /// ポインターを載せているチップ
    @State private var hovered: String?

    private typealias Space = DesignTokens.Size.Space
    private typealias Part = DesignTokens.Size.Part
    private typealias TextSize = DesignTokens.Size.Text

    var body: some View {
        let group = reference.groups.first { $0.title == selected } ?? reference.groups.first
        let shown = matches ?? group.map { group in group.items.map { TemplateReference.Match(item: $0, kind: group.kind) } } ?? []
        VStack(alignment: .leading, spacing: Space.group) {
            // 打ちかけの書き方で絞り込んでいるあいだは，まとまりを問わずに並べるので切り替えを隠す
            if matches == nil {
                groupSwitch(selected: group?.title)
            }
            if shown.isEmpty {
                Text(UIStrings.RuleList.noMatches)
                    .font(.system(size: TextSize.small))
                    .foregroundStyle(.secondary)
                    .frame(height: Part.tagHeight)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let values = values(at: timeline.date)
                    WrappingStack(spacing: Space.group) {
                        ForEach(shown) { match in
                            chip(match, values: values)
                        }
                    }
                }
                .onMoveCommand { direction in move(direction, in: shown) }
            }
        }
    }

    /// まとまりの切り替え．ページの上の切り替え(登録した単語・取り込んだ辞書)と同じ形を小さくしたもの
    private func groupSwitch(selected title: String?) -> some View {
        Picker("", selection: Binding(get: { title ?? "" }, set: { selected = $0 })) {
            ForEach(reference.groups, id: \.title) { group in
                Text(group.title).tag(group.title)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
    }

    /// 書き方のチップと，今の値．チップと値をひとまとまりで押せるようにする
    private func chip(_ match: TemplateReference.Match, values: TextTemplate.Values) -> some View {
        let item = match.item
        let value = TextTemplate.expand(item.sample, values: values)
        return Button {
            insert(item, match.kind)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Space.inline) {
                Text(item.code)
                    .font(.system(size: TextSize.tag, design: .monospaced))
                    .fixedSize()
                    .padding(.horizontal, Part.tagPaddingX)
                    .frame(height: Part.tagHeight)
                    .background(hovered == item.code ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.quaternary),
                                in: RoundedRectangle(cornerRadius: Part.tagRadius))
                if !value.isEmpty {
                    Text(value)
                        .font(.system(size: TextSize.small, design: item.isCodeValue ? .monospaced : .default))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused(focus, equals: item.code)
        .onHover { hovered = $0 ? item.code : (hovered == item.code ? nil : hovered) }
        .help(item.meaning)
        .accessibilityLabel("\(item.code) \(value)")
        .accessibilityHint(item.meaning)
    }

    /// 矢印のキーで，選んでいるチップの前(左・上)か後ろ(右・下)のチップに移る
    private func move(_ direction: MoveCommandDirection, in shown: [TemplateReference.Match]) {
        guard let current = focus.wrappedValue, let index = shown.firstIndex(where: { $0.item.code == current }) else { return }
        let next = switch direction {
        case .left, .up: index - 1
        case .right, .down: index + 1
        @unknown default: index
        }
        guard shown.indices.contains(next) else { return }
        focus.wrappedValue = shown[next].item.code
    }

    private func values(at date: Date) -> TextTemplate.Values {
        let calendar = SystemCalendar(clock: { date })
        // 呼ぶたびに次の数にする(英数字の乱数が同じ字の繰り返しにならないように)．求め直すたびに同じ並びから始めるので，値は変わらない
        var state = UInt64(randomSeed)
        return TextTemplate.Values(now: calendar.now(), uuid: { uuid }, random: { range in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return range.lowerBound + Int((state >> 33) % UInt64(range.count))
        }, text: sample?.text, reading: sample?.reading)
    }
}

/// 欄のすぐ右に置く，欄と同じ高さの開け閉めのボタン(書き方の「{ }」)．
/// 閉じているときは控えめな背景，開いているときはアクセントの色で示す．押せるのはポインターとキーボード(全体のキーボード操作)の両方
struct FieldAccessoryToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        FieldAccessoryToggle(configuration: configuration)
    }
}

private struct FieldAccessoryToggle: View {
    let configuration: ToggleStyleConfiguration
    @State private var hovered = false

    private typealias Part = DesignTokens.Size.Part

    var body: some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .foregroundStyle(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .padding(.horizontal, Part.fieldPaddingX)
                // 並べた欄の高さに伸ばす(入れ物の HStack が高さを欄に合わせる)
                .frame(maxHeight: .infinity)
                .background(fill, in: RoundedRectangle(cornerRadius: Part.fieldRadius))
                .contentShape(RoundedRectangle(cornerRadius: Part.fieldRadius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        // 読み上げでは，オン・オフのあるボタンとして扱う
        .accessibilityAddTraits(.isToggle)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }

    private var fill: AnyShapeStyle {
        switch (configuration.isOn, hovered) {
        case (true, _): AnyShapeStyle(.tint.quaternary)
        case (false, true): AnyShapeStyle(.tertiary)
        case (false, false): AnyShapeStyle(.quaternary)
        }
    }
}
