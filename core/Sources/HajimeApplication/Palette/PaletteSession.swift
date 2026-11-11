import Foundation
import HajimeDomain

/// 開いているパレットの状態(R-25)．キーとマウスの操作を受け，窓に出す内容(PalettePanel)と入れる文字を決める．
///
/// - 文字のキーは探す欄に入る．ローマ字はかなにして，打ったままの英数字とかなの両方で探す(漢字には変換しない)
/// - 矢印でマス目を動き，Tab と ⇧Tab でまとまりを移り，⌃Tab で絵文字と記号を切り替える(PaletteKeymap)
/// - Enter で選んでいる文字を入れる．⇧Enter は閉じずに続けて入れる．⌥Enter で肌の色の帯を開く
/// - Esc は肌の色の帯を閉じ，探す語を消し，最後にパレットを閉じる
/// - マス目の並びは表の順で変えない．ピン留めとよく使う文字はその上に写しとして出し，よく使う文字は開いたときだけ作り直す
///   (開いているあいだに並びが変わると，覚えた位置で選べなくなるため)
@MainActor
final class PaletteSession {
    /// 操作の結果
    enum Outcome: Equatable {
        /// 表示を出し直す
        case render
        /// 文字を入れる．keepsOpen なら開いたまま表示を出し直す
        case insert(String, keepsOpen: Bool)
        case close
        /// パレットを閉じ，キーは入力先のアプリに渡す(⌘ との組み合わせ)
        case closeAndPassThrough
        /// 何もしない
        case none
    }

    /// 探す欄に打ったキー．かなにする前の形で持ち，打つたびに初めから組み立て直す(一度に消せるように)
    private enum TypedKey {
        case romaji(Character)
        case kana(String)
        case literal(Character)
    }

    private struct Row {
        var section: Int
        var start: Int
        var count: Int
    }

    private let services: PaletteServices
    private let settings: any SettingsReading
    private let keyNames: KeyNameStyle
    private let makeComposition: () -> Composition
    private(set) var kind: PaletteItem.Kind
    /// 探す欄の表示を，日本語入力(かな)と英数入力(打ったまま)のどちらで出すか
    var inputMode: InputMode
    private var keys: [TypedKey] = []
    private var query = PaletteSearch.Query(typed: "")
    private var display = ""
    private var pinnedItems: [PaletteItem] = []
    private var frequentItems: [PaletteItem] = []
    private var sections: [PaletteSection] = []
    private var rows: [Row] = []
    private var selection: PalettePanel.Position?
    private var firstRow = 0
    /// 肌の色の帯．forDefault なら既定の肌の色を選ぶ帯，そうでなければ選んでいる絵文字の帯
    private var picker: (forDefault: Bool, selected: Int)?

    init(kind: PaletteItem.Kind, inputMode: InputMode, services: PaletteServices, settings: any SettingsReading, keyNames: KeyNameStyle,
         makeComposition: @escaping () -> Composition) {
        self.kind = kind
        self.inputMode = inputMode
        self.services = services
        self.settings = settings
        self.keyNames = keyNames
        self.makeComposition = makeComposition
        refreshShortcuts()
        rebuild()
    }

    private var index: PaletteIndex? { services.catalog.index }
    private var columns: Int { settings.current.paletteColumns }
    private var visibleRows: Int { settings.current.paletteRows }

    // MARK: - キー

    func handle(_ event: KeyEvent) -> Outcome {
        if let command = PaletteKeymap.command(for: event) {
            return perform(command)
        }
        if event.modifiers.contains(.command) { return .closeAndPassThrough }
        if picker != nil { picker = nil }
        // ⌃・⌥ との組み合わせは文字として打たない(表に無い組み合わせは何もしない)
        guard !event.modifiers.contains(.control), !event.modifiers.contains(.option) else { return .none }
        switch event.key {
        case .character(let character):
            return type(character, keyLabel: event.keyLabel, shift: event.modifiers.contains(.shift))
        case .space:
            // 英語の名前は語を空白で区切るので，打ち始めたあとの空白は探す語に入れる
            guard !keys.isEmpty else { return .none }
            return type(" ", keyLabel: nil, shift: false)
        default:
            return .none
        }
    }

    private func type(_ character: Character, keyLabel: String?, shift: Bool) -> Outcome {
        guard keys.count < DefaultSettings.maximumPaletteQueryLength else { return .none }
        let style = settings.current.inputStyle
        if inputMode == .japanese, style == .kana, let keyLabel, let kana = KanaLayout.text(forKey: keyLabel, shift: shift, settings: settings.current) {
            keys.append(.kana(kana))
        } else if character.isASCII, character.isLetter || character == "-" {
            keys.append(.romaji(Character(character.lowercased())))
        } else {
            keys.append(.literal(character))
        }
        updateQuery()
        // 「:bow:」のように閉じたショートコードがそのまま当たれば，選ばずに入れる
        if character == ":", let pattern = query.shortcodePattern, !pattern.isEmpty, query.typed.count > 2,
           let item = index?.catalog.items.first(where: { $0.shortcodes.contains(pattern.lowercased()) }) {
            return insert(item, keepsOpen: false)
        }
        rebuild()
        return .render
    }

    private func perform(_ command: PaletteCommand) -> Outcome {
        if let current = picker {
            switch command {
            case .moveLeft:
                picker?.selected = max(current.selected - 1, 0)
                return .render
            case .moveRight:
                picker?.selected = min(current.selected + 1, SkinTone.allCases.count - 1)
                return .render
            case .insert, .insertAndContinue:
                return choose(SkinTone.allCases[current.selected], keepsOpen: command == .insertAndContinue)
            case .cancel, .skinTone:
                picker = nil
                return .render
            default:
                picker = nil
            }
        }
        switch command {
        case .insert, .insertAndContinue:
            guard let item = selectedItem else { return .none }
            return insert(item, keepsOpen: command == .insertAndContinue)
        case .moveUp: return move { position in self.vertical(from: position, by: -1) }
        case .moveDown: return move { position in self.vertical(from: position, by: 1) }
        case .moveLeft: return move(horizontal(-1))
        case .moveRight: return move(horizontal(1))
        case .pageUp: return move { position in self.vertical(from: position, by: -self.visibleRows) }
        case .pageDown: return move { position in self.vertical(from: position, by: self.visibleRows) }
        case .first:
            return move { _ in self.rows.isEmpty ? nil : PalettePanel.Position(row: 0, column: 0) }
        case .last:
            return move { _ in self.rows.last.map { PalettePanel.Position(row: self.rows.count - 1, column: $0.count - 1) } }
        case .nextSection: return moveToSection(offset: 1)
        case .previousSection: return moveToSection(offset: -1)
        case .switchKind:
            switchKind(to: kind == .emoji ? .symbol : .emoji)
            return .render
        case .skinTone:
            guard let item = selectedItem, item.hasSkinTones else { return .none }
            let tone = services.usage.usage.effectiveSkinTone(for: item.text)
            picker = (false, SkinTone.allCases.firstIndex(of: tone) ?? 0)
            return .render
        case .pin:
            togglePin()
            return .render
        case .deleteBackward:
            guard !keys.isEmpty else { return .none }
            keys.removeLast()
            updateQuery()
            rebuild()
            return .render
        case .cancel:
            guard keys.isEmpty else {
                keys = []
                updateQuery()
                rebuild()
                return .render
            }
            return .close
        }
    }

    // MARK: - マウス

    func perform(_ target: PaletteTarget) -> Outcome {
        switch target {
        case .cell(let position):
            guard let item = item(at: position) else { return .none }
            selection = position
            picker = nil
            return insert(item, keepsOpen: false)
        case .hover(let position):
            guard item(at: position) != nil, selection != position else { return .none }
            selection = position
            return .render
        case .tab(let section):
            guard let target = sections.firstIndex(where: { $0.kind == section }) else { return .none }
            return moveToSection(target)
        case .mode(let kind):
            guard kind != self.kind else { return .none }
            switchKind(to: kind)
            return .render
        case .scroll(let delta):
            let scrolled = min(max(firstRow + delta, 0), maximumFirstRow)
            guard scrolled != firstRow else { return .none }
            firstRow = scrolled
            return .render
        case .skinTone(let tone):
            guard picker != nil else { return .none }
            return choose(tone, keepsOpen: false)
        case .skinToneButton:
            picker = picker?.forDefault == true ? nil : (true, SkinTone.allCases.firstIndex(of: services.usage.usage.defaultSkinTone) ?? 0)
            return .render
        case .pin:
            togglePin()
            return .render
        case .close:
            return .close
        }
    }

    // MARK: - 入れる

    private func insert(_ item: PaletteItem, keepsOpen: Bool, tone: SkinTone? = nil) -> Outcome {
        let tone = tone ?? services.usage.usage.effectiveSkinTone(for: item.text)
        let text = item.text(skinTone: tone)
        let searched = query.isEmpty ? nil : query
        let records = settings.current.paletteRecordsHistory
        let now = services.now()
        let kind = self.kind
        services.usage.update { usage in
            if records { usage.record(item.text, query: searched, at: now) }
            usage.lastKind = kind
        }
        picker = nil
        let keeps = keepsOpen || !settings.current.paletteClosesAfterInsert
        if keeps, query.shortcodePattern != nil, query.typed.hasSuffix(":") {
            // 閉じたショートコードで入れたら，続けて次のショートコードを打てるよう探す欄を空ける
            keys = []
            updateQuery()
            rebuild()
        }
        return .insert(text, keepsOpen: keeps)
    }

    /// 肌の色の帯で選んだ．絵文字の帯なら，その肌の色を覚えて入れる．既定の帯なら既定にする
    private func choose(_ tone: SkinTone, keepsOpen: Bool) -> Outcome {
        guard let current = picker else { return .none }
        picker = nil
        if current.forDefault {
            services.usage.update { $0.defaultSkinTone = tone }
            return .render
        }
        guard let item = selectedItem else { return .render }
        let text = item.text
        services.usage.update { $0.setSkinTone(tone, for: text) }
        return insert(item, keepsOpen: keepsOpen, tone: tone)
    }

    private func togglePin() {
        guard let item = selectedItem else { return }
        let text = item.text
        services.usage.update { usage in
            if usage.isPinned(text) { usage.unpin(text) } else { usage.pin(text) }
        }
        refreshShortcuts(refreshingFrequent: false)
        rebuild(keepingSelection: true)
    }

    // MARK: - 中身

    private var selectedItem: PaletteItem? { selection.flatMap(item(at:)) }

    private func item(at position: PalettePanel.Position) -> PaletteItem? {
        guard rows.indices.contains(position.row), position.column >= 0, position.column < rows[position.row].count else { return nil }
        let row = rows[position.row]
        return sections[row.section].items[row.start + position.column]
    }

    private func switchKind(to kind: PaletteItem.Kind) {
        self.kind = kind
        picker = nil
        rebuild()
    }

    /// ピン留めとよく使う文字を作る．よく使う文字は開いたときだけ作り直す
    private func refreshShortcuts(refreshingFrequent: Bool = true) {
        guard let catalog = index?.catalog else { return }
        let usage = services.usage.usage
        pinnedItems = usage.pinned.compactMap(catalog.item(for:))
        guard refreshingFrequent else { return }
        frequentItems = []
        let count = settings.current.paletteFrequentRows * columns
        guard settings.current.paletteRecordsHistory, count > 0 else { return }
        let now = services.now()
        let pinned = Set(usage.pinned)
        var row: [String] = []
        services.usage.update { row = $0.refreshFrequentRow(count: count, at: now, excluding: pinned) }
        frequentItems = row.compactMap(catalog.item(for:))
    }

    private func updateQuery() {
        var composition = makeComposition()
        var typed = ""
        for key in keys {
            switch key {
            case .romaji(let character):
                composition.insertRomaji(character)
                typed.append(character)
            case .kana(let kana):
                composition.insertKana(kana)
            case .literal(let character):
                composition.insertLiteral(String(character))
                typed.append(character)
            }
        }
        // かなになった部分だけを読みとして探す(英語の綴りをローマ字として読んだもの「sみぇ」は読みにしない)
        let isKana = !composition.kana.isEmpty && composition.kana.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || $0 == "ー" }
        query = PaletteSearch.Query(typed: typed, kana: isKana ? composition.kana : "")
        // 英数入力・ショートコード・かなにならない綴りは打ったままを見せる
        let showsTyped = inputMode == .direct || typed.hasPrefix(":") || (!composition.kana.isEmpty && !isKana)
        display = showsTyped && !typed.isEmpty ? typed : composition.displayReading
    }

    /// まとまりとマス目の行を作り直す
    private func rebuild(keepingSelection: Bool = false) {
        let previous = keepingSelection ? selection : nil
        if let index {
            if query.isEmpty {
                sections = [PaletteSection(kind: .pinned, items: pinnedItems), PaletteSection(kind: .frequent, items: frequentItems)]
                    + index.catalog.categories.filter { $0.kind == kind }.map { PaletteSection(kind: .category($0), items: index.catalog.items(in: $0)) }
            } else {
                let usage = services.usage.usage
                let ranking = PaletteSearch.Ranking(
                    usage: settings.current.paletteRecordsHistory ? usage.scores(at: services.now()) : [:],
                    learned: settings.current.paletteRecordsHistory ? usage.learnedChoices(for: query) : [],
                    pinned: Set(usage.pinned), preferredKind: kind)
                sections = [PaletteSection(kind: .results, items: index.search.search(query, ranking: ranking))]
            }
            sections.removeAll { $0.items.isEmpty }
        } else {
            sections = []
        }
        rows = []
        for (sectionIndex, section) in sections.enumerated() {
            for start in stride(from: 0, to: section.items.count, by: columns) {
                rows.append(Row(section: sectionIndex, start: start, count: min(columns, section.items.count - start)))
            }
        }
        if let previous, item(at: previous) != nil {
            selection = previous
        } else {
            selection = rows.isEmpty ? nil : PalettePanel.Position(row: 0, column: 0)
            firstRow = 0
        }
        firstRow = min(firstRow, maximumFirstRow)
        ensureVisible()
    }

    // MARK: - 動く

    private var maximumFirstRow: Int { max(rows.count - visibleRows, 0) }

    private func move(_ next: (PalettePanel.Position) -> PalettePanel.Position?) -> Outcome {
        guard let current = selection, let target = next(current), target != current else { return .none }
        selection = target
        ensureVisible()
        return .render
    }

    private func horizontal(_ step: Int) -> (PalettePanel.Position) -> PalettePanel.Position? {
        { position in
            let column = position.column + step
            if column >= 0, column < self.rows[position.row].count { return PalettePanel.Position(row: position.row, column: column) }
            let row = position.row + step
            guard self.rows.indices.contains(row) else { return nil }
            return PalettePanel.Position(row: row, column: step > 0 ? 0 : self.rows[row].count - 1)
        }
    }

    private func vertical(from position: PalettePanel.Position, by step: Int) -> PalettePanel.Position? {
        guard !rows.isEmpty else { return nil }
        let row = min(max(position.row + step, 0), rows.count - 1)
        return PalettePanel.Position(row: row, column: min(position.column, rows[row].count - 1))
    }

    /// 次か前のまとまりへ移る．前へ移るときは，まとまりの途中にいればそのまとまりの頭へ移る
    private func moveToSection(offset: Int) -> Outcome {
        guard !sections.isEmpty, query.isEmpty else { return .none }
        let current = selection.map { rows[$0.row].section } ?? 0
        if offset < 0, let selection, let head = rows.firstIndex(where: { $0.section == current }), selection != PalettePanel.Position(row: head, column: 0) {
            return moveToSection(current)
        }
        return moveToSection((current + offset + sections.count) % sections.count)
    }

    /// まとまりの先頭のマスを選び，まとまりが窓の上から始まるようにスクロールする
    private func moveToSection(_ sectionIndex: Int) -> Outcome {
        guard let row = rows.firstIndex(where: { $0.section == sectionIndex }) else { return .none }
        selection = PalettePanel.Position(row: row, column: 0)
        firstRow = min(row, maximumFirstRow)
        picker = nil
        return .render
    }

    private func ensureVisible() {
        guard let row = selection?.row else { return }
        if row < firstRow { firstRow = row }
        if row >= firstRow + visibleRows { firstRow = row - visibleRows + 1 }
        firstRow = min(max(firstRow, 0), maximumFirstRow)
    }

    // MARK: - 表示

    func panel() -> PalettePanel {
        let usage = services.usage.usage
        let pinned = Set(usage.pinned)
        let cellText: (PaletteItem) -> String = { $0.text(skinTone: usage.effectiveSkinTone(for: $0.text)) }
        let visible = rows.indices.dropFirst(firstRow).prefix(visibleRows)
        let panelRows = visible.map { index in
            let row = rows[index]
            let section = sections[row.section]
            let cells = section.items[row.start..<(row.start + row.count)].map {
                PalettePanel.Cell(text: cellText($0), name: Self.spokenName(of: $0), isPinned: pinned.contains($0.text))
            }
            return PalettePanel.Row(index: index, cells: cells, startsSection: row.start == 0, sectionTitle: section.title)
        }
        let currentSection = selection.map { rows[$0.row].section } ?? (rows.indices.contains(firstRow) ? rows[firstRow].section : nil)
        let tabs = query.isEmpty ? sections.enumerated().map { offset, section in
            PalettePanel.Tab(section: section.kind, title: section.title, symbol: Self.symbol(of: section.kind), isSelected: offset == currentSection)
        } : []
        let heading: String
        if !query.isEmpty {
            heading = PaletteStrings.results + "　" + PaletteStrings.resultCount(sections.first?.items.count ?? 0)
        } else {
            heading = rows.indices.contains(firstRow) ? sections[rows[firstRow].section].title : ""
        }
        let message: String? = index == nil ? PaletteStrings.loading : (rows.isEmpty && !query.isEmpty ? PaletteStrings.notFound : nil)
        let selected = selectedItem
        return PalettePanel(
            modes: PaletteItem.Kind.allCases.map { PalettePanel.Mode(kind: $0, title: PaletteStrings.title(of: $0), isSelected: $0 == kind) },
            query: display,
            placeholder: kind == .emoji ? PaletteStrings.emojiPlaceholder : PaletteStrings.symbolPlaceholder,
            tabs: tabs, heading: heading, rows: panelRows, rowCount: rows.count, firstRow: firstRow,
            columns: columns, visibleRows: visibleRows, selection: selection,
            preview: settings.current.paletteShowsPreview ? selected.map { preview(of: $0, text: cellText($0), pinned: pinned.contains($0.text)) } : nil,
            showsPreview: settings.current.paletteShowsPreview,
            skinTone: usage.defaultSkinTone,
            skinTonePicker: picker.map { current in
                let sample = current.forDefault ? nil : selected
                return PalettePanel.SkinTonePicker(options: SkinTone.allCases.map { tone in
                    sample.map { $0.text(skinTone: tone) } ?? Self.defaultToneSample(tone)
                }, selected: current.selected)
            },
            message: message,
            hints: hints(for: selected))
    }

    private func preview(of item: PaletteItem, text: String, pinned: Bool) -> PalettePanel.Preview {
        let readings = ([item.nameReading] + item.readings).filter { !$0.isEmpty }
        var unique: [String] = []
        for reading in readings where !unique.contains(reading) { unique.append(reading) }
        return PalettePanel.Preview(
            text: text, japaneseName: item.japaneseName, englishName: item.englishName,
            shortcodes: item.shortcodes.map { ":\($0):" },
            readings: Array(unique.prefix(DefaultSettings.palettePreviewReadings)),
            codePoints: text.unicodeScalars.map { "U+" + String($0.value, radix: 16, uppercase: true) }.joined(separator: " "),
            isPinned: pinned)
    }

    private func hints(for selected: PaletteItem?) -> [PalettePanel.Hint] {
        var commands: [(PaletteCommand, String)] = [(.insert, PaletteStrings.insert), (.nextSection, PaletteStrings.category),
                                                    (.switchKind, PaletteStrings.switchKind), (.insertAndContinue, PaletteStrings.insertAndContinue)]
        if selected?.hasSkinTones == true { commands.append((.skinTone, PaletteStrings.skinTone)) }
        commands += [(.pin, PaletteStrings.pin), (.cancel, PaletteStrings.close)]
        if !query.isEmpty { commands.removeAll { $0.0 == .nextSection } }
        return commands.compactMap { command, action in
            PaletteKeymap.stroke(for: command).map { PalettePanel.Hint(key: $0.label(style: keyNames), action: action) }
        }
    }

    /// 読み上げに使う名前．日本語の名前が無ければ英語の名前，それも無ければ文字そのもの
    private static func spokenName(of item: PaletteItem) -> String {
        [item.japaneseName, item.englishName].first { !$0.isEmpty } ?? item.text
    }

    private static func symbol(of section: PaletteSection.Kind) -> String {
        switch section {
        case .pinned: PaletteStrings.pinnedSymbol
        case .frequent: PaletteStrings.frequentSymbol
        case .category(let category): category.symbol
        case .results: PaletteStrings.resultsSymbol
        }
    }

    /// 既定の肌の色を選ぶ帯に見せる絵文字
    private static func defaultToneSample(_ tone: SkinTone) -> String {
        PaletteStrings.skinToneSample.text(skinTone: tone)
    }
}
