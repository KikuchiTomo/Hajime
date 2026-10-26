import Foundation
import S90Domain
import S90Persistence
import Testing

@Suite("設定の書き出しと読み込み")
struct SettingsTransferTests {
    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("s90-\(name)-\(UUID().uuidString)")
    }

    @Test("辞書・テーマ・キーの割り当てを含めて書き出し，読み戻すと同じになる")
    func roundTrip() throws {
        var settings = Settings()
        settings.userDictionary = [UserDictionaryEntry(reading: "えすきゅー", word: "s90")]
        settings.keymap.entries.append(KeymapEntry(.converting, KeyStroke(.character("j"), control: true), .nextCandidate))
        let theme = CustomTheme(id: "a", name: "夕焼け", base: .automatic, surface: HexColor("#202020")!, text: HexColor("#FFFFFF")!,
                                textMuted: HexColor("#AAAAAA")!, selection: HexColor("#FF6600")!, selectionText: HexColor("#000000")!,
                                correction: HexColor("#FF0066")!, line: HexColor("#555555")!)
        settings.customThemes = [theme]
        settings.customThemeID = "a"
        settings.listCandidatesPerPage = 7
        let url = temporaryURL("settings.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try SettingsTransfer.write(settings, to: url)
        #expect(try SettingsTransfer.read(from: url) == settings)
    }

    @Test("JSON のオブジェクトでないファイルは断る")
    func rejectsNonSettings() throws {
        let url = temporaryURL("array.json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("[1, 2]".utf8).write(to: url)
        #expect(throws: SettingsTransfer.TransferError.notSettings) { try SettingsTransfer.read(from: url) }
    }

    @Test("範囲の外の値と壊れたテーマは既定にし，ほかの項目は読む")
    func clampsValues() throws {
        let url = temporaryURL("broken.json")
        defer { try? FileManager.default.removeItem(at: url) }
        let json = #"{"listCandidatesPerPage": 40, "liveConversionDelay": -3, "customThemes": [{"id": "x", "name": ""}], "customThemeID": "x", "punctuation": "commaPeriod"}"#
        try Data(json.utf8).write(to: url)
        let settings = try SettingsTransfer.read(from: url)
        #expect(settings.listCandidatesPerPage == 9)
        #expect(settings.liveConversionDelay == DefaultSettings.liveConversionDelayRange.lowerBound)
        #expect(settings.customThemes.isEmpty)
        #expect(settings.customThemeID == nil)
        #expect(settings.punctuation == .commaPeriod)
    }

    @Test("除外設定を CSV で書き出し，読み戻すと同じになる")
    func profileRulesRoundTrip() throws {
        let rules = [ProfileRule(applicationPrefix: "com.apple.Terminal", profile: .terminal), ProfileRule(applicationPrefix: "com.example.Game", profile: .direct)]
        let url = temporaryURL("rules.csv")
        defer { try? FileManager.default.removeItem(at: url) }
        try ProfileRuleFile.write(rules, to: url)
        #expect(try ProfileRuleFile.read(from: url) == rules)
    }
}
