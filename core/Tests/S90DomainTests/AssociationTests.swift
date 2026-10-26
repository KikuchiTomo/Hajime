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

    @Test("標準では入力中の Shift+Space と Ctrl+Tab，変換中の Ctrl+Tab で連想変換．変換中の Shift+Space は前の候補のまま")
    func standard() {
        let keymap = KeymapPreset.standard.keymap
        #expect(keymap.command(for: shiftSpace, in: .composing) == .associate)
        #expect(keymap.command(for: controlTab, in: .composing) == .associate)
        #expect(keymap.command(for: controlTab, in: .converting) == .associate)
        #expect(keymap.command(for: shiftSpace, in: .converting) == .previousCandidate)
        #expect(keymap.command(for: shiftSpace, in: .idle) == .insertAlternateSpace)
    }

    @Test("どのひな形でも Ctrl+Tab で連想変換になり，連想変換の行がほかの行に負けない")
    func presets() {
        for preset in KeymapPreset.allCases {
            let keymap = preset.keymap
            #expect(keymap.command(for: controlTab, in: .composing) == .associate, "\(preset)")
            #expect(keymap.command(for: controlTab, in: .converting) == .associate, "\(preset)")
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

    @Test("変えた表には，空いていれば Ctrl+Tab だけを足し，利用者の決めたキーは変えない")
    func upgradesCustom() throws {
        var custom = AssociationKeyUpgrade.previousStandard
        custom.entries.append(KeymapEntry(.converting, KeyStroke(.tab, control: true), .nextSegment))
        let keymap = try upgraded(custom)
        #expect(keymap.command(for: shiftSpace, in: .composing) == .convert)
        #expect(keymap.command(for: controlTab, in: .composing) == .associate)
        #expect(keymap.command(for: controlTab, in: .converting) == .nextSegment)
    }
}
