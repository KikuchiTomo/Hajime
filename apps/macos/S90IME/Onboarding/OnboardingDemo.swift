import Foundation
import S90Application
import S90Domain

/// 初期設定の実演の 1 コマ．入力欄の文字(確定した文字と組み立て中の文字)と，その下に出す窓
struct DemoFrame: Equatable {
    enum Panel: Equatable {
        case lattice(LatticePanel)
        case list(CandidatePanel)
        case note(Note)
    }

    var committed = ""
    var marked = MarkedText.empty
    var panel: Panel?
    /// 入力欄の横に出すモードの札(「あ」「A」)
    var mode: String?
    /// このコマを見せておく時間(秒)
    var duration: TimeInterval
}

/// 初期設定の各ページの実演の台本．選んでいる設定で中身を変える(補正の度合い・ライブ変換・候補の出し方など)．
/// 打っている途中の読みは，本物のローマ字の組み立て(Composition)にキーを 1 つずつ入れて作る
enum DemoScripts {
    private static var keystroke: TimeInterval { DesignTokens.Motion.Onboarding.keystroke / 1000 }
    private static var hold: TimeInterval { DesignTokens.Motion.Onboarding.hold / 1000 }

    static func frames(for page: OnboardingPage, settings: Settings, now: Date = Date()) -> [DemoFrame] {
        switch page {
        case .modeSwitch: modeSwitch(settings)
        case .correction: correction(settings)
        case .theme: theme()
        case .liveConversion: liveConversion(settings)
        case .presentation: presentation(settings)
        case .characters: characters(settings)
        case .features: features(settings, now: now)
        }
    }

    // MARK: - 部品

    /// keys を 1 つずつ打ったときの，組み立て中の読み(打ちかけのローマ字を含む)
    static func readings(of keys: String) -> [String] {
        var composition = Composition()
        return keys.map { key in
            composition.insertRomaji(key)
            return composition.displayReading
        }
    }

    private static func typing(_ keys: String, committed: String = "", mode: String? = nil) -> [DemoFrame] {
        readings(of: keys).map { DemoFrame(committed: committed, marked: MarkedText([.init($0, style: .reading)]), mode: mode, duration: keystroke) }
    }

    private static func converted(_ texts: [(String, MarkedText.Style)], committed: String = "", panel: DemoFrame.Panel? = nil) -> DemoFrame {
        DemoFrame(committed: committed, marked: MarkedText(texts.map { .init($0.0, style: $0.1) }), panel: panel, duration: hold)
    }

    private static func pause(_ frame: DemoFrame?, seconds: TimeInterval) -> [DemoFrame] {
        guard var frame else { return [] }
        frame.duration = seconds
        return [frame]
    }

    // MARK: - ページ

    private static func modeSwitch(_ settings: Settings) -> [DemoFrame] {
        let direct = UIStrings.ModeIndicator.label(for: InputMode.direct)
        let japanese = UIStrings.ModeIndicator.label(for: InputMode.japanese)
        let english = "Mac で"
        var frames = [DemoFrame(mode: direct, duration: hold / 2)]
        frames += english.indices.map { DemoFrame(committed: String(english[...$0]), mode: direct, duration: keystroke) }
        frames.append(DemoFrame(committed: english, mode: japanese, duration: hold / 2))
        frames += typing("nihongo", committed: english, mode: japanese)
        frames.append(converted([("日本語", .converted)], committed: english))
        frames.append(DemoFrame(committed: english + "日本語", duration: hold))
        return frames
    }

    private static func correction(_ settings: Settings) -> [DemoFrame] {
        let keys = "yorosikuonagaisimasu"
        var frames = typing(keys)
        frames += pause(frames.last, seconds: settings.correctionDelay)
        let typed = readings(of: keys).last ?? keys
        guard settings.typoCorrection == .standard else {
            frames.append(converted([("よろしくおながいします", .converted)]))
            return frames
        }
        if settings.correctionSensitivity == .cautious {
            let note = Note(tone: .suggestion, title: "もしかして", subject: "よろしくお願いします", key: "Tab", keyAction: "修正")
            frames.append(converted([("よろしくおながいします", .converted)], panel: .note(note)))
            frames.append(converted([("よろしくお願いします", .converted)]))
        } else {
            let note = Note(tone: .correction, title: "修正", subject: typed, key: "Esc", keyAction: "戻す")
            frames.append(converted([("よろしく", .converted), ("お願い", .correction), ("します", .converted)], panel: .note(note)))
        }
        return frames
    }

    private static func theme() -> [DemoFrame] {
        let lattice = SamplePanels.lattice
        return [converted([("私の", .converted), ("名前は", .converted), ("中野です", .focused)], panel: .lattice(lattice))]
    }

    private static func liveConversion(_ settings: Settings) -> [DemoFrame] {
        let keys = "kyouhaiitenkidesune"
        var frames = typing(keys)
        if settings.liveConversion {
            frames += pause(frames.last, seconds: settings.liveConversionDelay)
            frames.append(converted([("今日はいい天気ですね", .converted)]))
        } else {
            frames += pause(frames.last, seconds: hold / 2)
            frames.append(converted([("今日は", .focused), ("いい", .converted), ("天気ですね", .converted)], panel: .lattice(sentenceLattice(focus: 0))))
        }
        frames.append(DemoFrame(committed: "今日はいい天気ですね", duration: hold / 2))
        return frames
    }

    private static func presentation(_ settings: Settings) -> [DemoFrame] {
        var frames = typing("watasinonamaehanakanodesu")
        frames += pause(frames.last, seconds: hold / 3)
        let focus = switch settings.initialFocus {
        case .start: 0
        case .end, .automatic: 2
        }
        let segments = ["私の", "名前は", "中野です"]
        let marked = segments.enumerated().map { ($0.element, $0.offset == focus ? MarkedText.Style.focused : .converted) }
        switch settings.candidatePresentation {
        case .automatic:
            frames.append(converted(marked, panel: .lattice(nameLattice(focus: focus))))
        case .list:
            let entries = ["私の名前は中野です", "私の名前は中のです", "わたしのなまえはなかのです"]
            let list = CandidatePanel(variants: [], selectedVariant: nil, entries: entries.map { .init(text: $0, annotation: nil) },
                                      selectedEntry: 0, focus: .candidate, position: 1, total: entries.count, note: nil)
            frames.append(converted([(entries[0], .focused)], panel: .list(list)))
        }
        return frames
    }

    private static func characters(_ settings: Settings) -> [DemoFrame] {
        let comma = settings.punctuation.comma, period = settings.punctuation.period
        let text = "\(settings.brackets.open)はい\(settings.brackets.close)\(comma)\(width("10", settings.numberWidth))時\(settings.slash.text)\(width("11", settings.numberWidth))時\(period)"
        return text.indices.map { DemoFrame(committed: String(text[...$0]), duration: keystroke * 2) } + [DemoFrame(committed: text, duration: hold)]
    }

    private static func features(_ settings: Settings, now: Date) -> [DemoFrame] {
        var frames: [DemoFrame] = []
        func show(_ keys: String, reading: String? = nil, entries: [String], heading: AssociationHeading? = nil) {
            frames += reading.map { [DemoFrame(marked: MarkedText([.init($0, style: .reading)]), duration: hold / 2)] } ?? typing(keys)
            var list = CandidatePanel(variants: [], selectedVariant: nil, entries: entries.map { .init(text: $0, annotation: nil) },
                                      selectedEntry: 0, focus: .candidate, position: 1, total: entries.count, note: nil)
            list.association = heading
            frames.append(converted([(entries[0], .focused)], panel: .list(list)))
        }
        if settings.association {
            show("kawaii", entries: ["愛らしい", "可憐", "愛くるしい", "キュート"],
                 heading: AssociationHeading(headword: "可愛い", label: UIStrings.Onboarding.association, group: 1, groupCount: 1))
        }
        if settings.calculation { show("", reading: "1+2*3=", entries: ["7", "1+2*3=7"]) }
        if settings.postalCodeConversion { show("", reading: "100-0001", entries: ["東京都千代田区千代田", "100-0001"]) }
        if settings.dateConversion {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "ja_JP")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = "y年M月d日"
            let long = formatter.string(from: now)
            formatter.dateFormat = "y/MM/dd"
            show("kyou", entries: [long, formatter.string(from: now), "今日"])
        }
        return frames.isEmpty ? [DemoFrame(duration: hold)] : frames
    }

    // MARK: - 見本の分岐図

    private static func sentenceLattice(focus: Int) -> LatticePanel {
        let columns: [(String, [String])] = [("今日は", ["今日は", "京は", "教派"]), ("いい", ["いい", "良い", "言い"]), ("天気ですね", ["天気ですね", "転機ですね"])]
        return LatticePanel(columns: columns.enumerated().map { index, column in
            index == focus
                ? .init(text: column.0, alternatives: column.1, selectedAlternative: 0, isFocused: true, isUncertain: false)
                : .init(text: column.0, isFocused: false, isUncertain: false)
        }, position: 1, total: 3)
    }

    private static func nameLattice(focus: Int) -> LatticePanel {
        let columns: [(String, [String])] = [("私の", ["私の", "渡しの", "わたしの"]), ("名前は", ["名前は", "なまえは"]), ("中野です", ["中野です", "中のです", "仲のです", "那珂のです"])]
        return LatticePanel(columns: columns.enumerated().map { index, column in
            index == focus
                ? .init(text: column.0, alternatives: column.1, selectedAlternative: 0, isFocused: true, isUncertain: index == 2)
                : .init(text: column.0, isFocused: false, isUncertain: index == 2)
        }, position: 1, total: columns[focus].1.count)
    }

    private static func width(_ digits: String, _ width: CharacterWidth) -> String {
        guard width == .fullwidth else { return digits }
        return String(digits.unicodeScalars.map { scalar in
            ("0"..."9").contains(scalar) ? Character(UnicodeScalar(scalar.value + 0xFEE0)!) : Character(scalar)
        })
    }
}
