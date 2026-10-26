import Foundation
@testable import S90Domain
import Testing

@Suite("連想の一覧(R-18)")
struct AssociationListTests {
    private let associations = Associations(headword: "美しい", groups: [
        AssociationGroup(label: "見た目", words: ["綺麗", "麗しい", "華麗", "端麗", "秀麗"]),
        AssociationGroup(label: "心", words: ["清らか", "清い"]),
    ])

    @Test("見出しと同じ語と，前のまとまりに出た語を除き，件数の上限までにする．語の残らないまとまりは捨てる")
    func make() throws {
        let groups = [
            AssociationGroup(label: "a", words: ["美しい", "綺麗", "麗しい"]),
            AssociationGroup(label: "b", words: ["綺麗"]),
            AssociationGroup(label: "c", words: ["清らか", "清い", "潔い"]),
        ]
        let made = try #require(Associations.make(headword: "美しい", groups: groups, limit: 4))
        #expect(made.groups == [AssociationGroup(label: "a", words: ["綺麗", "麗しい"]), AssociationGroup(label: "c", words: ["清らか", "清い"])])
        #expect(Associations.make(headword: "美しい", groups: [AssociationGroup(label: "", words: ["美しい"])], limit: 10) == nil)
    }

    @Test("上下で 1 語ずつ，まとまりをまたいで送り，端では反対の端に戻る")
    func move() {
        var list = AssociationList(associations)
        list.move(by: 5)
        #expect(list.selectedWord == "清らか")
        #expect(list.groupIndex == 1)
        list.move(by: 2)
        #expect(list.selectedWord == "綺麗")
        list.move(by: -1)
        #expect(list.selectedWord == "清い")
    }

    @Test("左右でまとまりの先頭に移る")
    func moveGroup() {
        var list = AssociationList(associations)
        list.move(by: 2)
        list.moveGroup(by: 1)
        #expect(list.selectedWord == "清らか")
        list.moveGroup(by: 1)
        #expect(list.selectedWord == "綺麗")
        list.moveGroup(by: -1)
        #expect(list.selectedWord == "清らか")
    }

    @Test("ページはまとまりの中で切り，端を越えたら隣のまとまりに移る")
    func pages() {
        var list = AssociationList(associations)
        #expect(list.page(perPage: 3).words == ["綺麗", "麗しい", "華麗"])
        list.movePage(by: 1, perPage: 3)
        #expect(list.page(perPage: 3).words == ["端麗", "秀麗"])
        #expect(list.selectedWord == "端麗")
        list.movePage(by: 1, perPage: 3)
        #expect(list.selectedWord == "清らか")
        list.movePage(by: -1, perPage: 3)
        #expect(list.selectedWord == "端麗")
    }

    @Test("番号はページの中の位置．範囲の外なら選ばない")
    func selectNumber() {
        var list = AssociationList(associations)
        list.movePage(by: 1, perPage: 3)
        let selected = list.select(number: 2, perPage: 3)
        #expect(selected)
        #expect(list.selectedWord == "秀麗")
        let outside = list.select(number: 3, perPage: 3)
        #expect(!outside)
        #expect(list.selectedWord == "秀麗")
    }

    @Test("まとまりは 2 語以上で，タブと改行を含まず，長さが上限以内")
    func validity() {
        #expect(AssociationGroup(label: "", words: ["a", "b"]).isValid)
        #expect(!AssociationGroup(label: "", words: ["a"]).isValid)
        #expect(!AssociationGroup(label: "x\ty", words: ["a", "b"]).isValid)
        #expect(!AssociationGroup(label: "", words: ["a", "b\nc"]).isValid)
        #expect(!AssociationGroup(label: "", words: ["a", String(repeating: "あ", count: DefaultSettings.maximumAssociationWordLength + 1)]).isValid)
    }

    @Test("連想の辞書の id は UUID の形だけを受け付ける")
    func identity() {
        #expect(AssociationDictionary(id: UUID().uuidString, name: "x", groupCount: 1).hasValidIdentity)
        #expect(!AssociationDictionary(id: "../settings", name: "x", groupCount: 1).hasValidIdentity)
    }
}

@Suite("連想変換のキー(R-18)")
struct AssociationKeyTests {
    private let shiftSpace = KeyEvent(.space, modifiers: .shift)
    private let controlTab = KeyEvent(.tab, modifiers: .control)
    private let shiftUp = KeyEvent(.up, modifiers: .shift)
    private let optionUp = KeyEvent(.up, modifiers: .option)

    @Test("標準では入力中の Shift+Space と変換中の Shift+↑ で連想変換．Ctrl+Tab はアプリのタブの切り替えに残す．変換中の Shift+Space は前の候補のまま")
    func standard() {
        let keymap = KeymapPreset.standard.keymap
        #expect(keymap.command(for: shiftSpace, in: .composing) == .associate)
        #expect(keymap.command(for: shiftUp, in: .converting) == .associate)
        #expect(keymap.command(for: controlTab, in: .composing) == nil)
        #expect(keymap.command(for: controlTab, in: .converting) == nil)
        #expect(keymap.command(for: shiftSpace, in: .converting) == .previousCandidate)
        #expect(keymap.command(for: shiftSpace, in: .idle) == .insertAlternateSpace)
    }

    @Test("どのひな形でも変換中に連想変換のキーがあり，連想変換の行がほかの行に負けない．Ctrl+Tab は使わない")
    func presets() {
        for preset in KeymapPreset.allCases {
            let keymap = preset.keymap
            #expect(!keymap.strokes(for: .associate, in: .converting).isEmpty, "\(preset)")
            #expect(keymap.command(for: controlTab, in: .converting) != .associate, "\(preset)")
            for index in keymap.entries.indices where keymap.entries[index].command == .associate {
                #expect(keymap.overlap(at: index) == nil, "\(preset)")
            }
        }
    }

    private func upgraded(_ keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(4)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    @Test("バージョン 4 で標準のまま保存した表は，今の標準の表にする")
    func upgradesStandard() throws {
        #expect(AssociationKeyUpgrade.previousStandard.command(for: shiftSpace, in: .composing) == .convert)
        #expect(try upgraded(AssociationKeyUpgrade.previousStandard) == KeymapPreset.standard.keymap)
    }

    @Test("変えた表には連想変換のキーを足し(今は Ctrl+Tab でなく Option+↑ や Shift+↑)，利用者の決めたキーは変えない")
    func upgradesCustom() throws {
        var custom = AssociationKeyUpgrade.previousStandard
        custom.entries.append(KeymapEntry(.converting, KeyStroke(.tab, control: true), .nextSegment))
        let keymap = try upgraded(custom)
        #expect(keymap.command(for: shiftSpace, in: .composing) == .convert)
        #expect(keymap.command(for: optionUp, in: .composing) == .associate)
        #expect(keymap.command(for: controlTab, in: .converting) == .nextSegment)
    }

    private func upgraded(fromVersion6 keymap: Keymap) throws -> Keymap {
        var object = try SettingsCoding.object(of: Settings())
        object["keymap"] = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(keymap))
        object[SettingsSchema.versionKey] = .number(6)
        return try SettingsCoding.decode(JSONEncoder().encode(JSONValue.object(object))).keymap
    }

    @Test("バージョン 6 で標準のまま保存した表は，今の標準の表にする(変換中の Tab は文節の移動，連想変換は Shift+↑)")
    func upgradesVersion6Standard() throws {
        let previous = NavigationKeyUpgrade.previousStandard
        #expect(previous.command(for: KeyEvent(.tab), in: .converting) == .nextUncertainSegment)
        #expect(previous.command(for: controlTab, in: .composing) == .associate)
        #expect(try upgraded(fromVersion6: previous) == KeymapPreset.standard.keymap)
    }

    @Test("バージョン 6 の変えた表は，前の標準と同じ行だけを変え，ふさがっていれば代わりのキーにする")
    func upgradesVersion6Custom() throws {
        var custom = NavigationKeyUpgrade.previousStandard
        // 利用者が Shift+↑ を別のコマンドにしていた
        custom.entries.append(KeymapEntry(.converting, KeyStroke(.up, shift: true), .lastCandidate))
        custom.entries.append(KeymapEntry(.converting, KeyStroke(.right, option: true), .lastSegment))
        let keymap = try upgraded(fromVersion6: custom)
        #expect(keymap.command(for: KeyEvent(.tab), in: .converting) == .nextSegment)
        #expect(keymap.command(for: KeyEvent(.tab, modifiers: .shift), in: .converting) == .previousSegment)
        #expect(keymap.command(for: shiftUp, in: .converting) == .lastCandidate)
        #expect(keymap.command(for: optionUp, in: .converting) == .associate)
        #expect(keymap.command(for: controlTab, in: .converting) == nil)
        // 利用者の Option+→ は変えない
        #expect(keymap.command(for: KeyEvent(.right, modifiers: .option), in: .converting) == .lastSegment)
        #expect(keymap.command(for: KeyEvent(.left, modifiers: .option), in: .converting) == .previousUncertainSegment)
    }
}
