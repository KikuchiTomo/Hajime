import Foundation
import Testing
@testable import S90Domain

/// Windows の設定の画面(Rust)が読む，設定の項目の名前と値の範囲・上限の写し(protocol/settings-catalog.json)．
/// 範囲と上限は DefaultSettings だけに書き，Rust には写しを渡す．写しが古くなればこのテストが落ちる．
/// 既定値は写さず，画面がエンジンに頼んで読む(readSettingsFields)．作り直すときは `make settings-catalog`
@Suite("設定の範囲の写し")
struct SettingsCatalogTests {
    private static let writeKey = "S90_WRITE_SETTINGS_CATALOG"

    private static var url: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("protocol/settings-catalog.json")
    }

    private static func range(_ range: ClosedRange<Double>) -> JSONValue {
        .array([.number(range.lowerBound), .number(range.upperBound)])
    }

    private static func range(_ range: ClosedRange<Int>) -> JSONValue {
        .array([.number(Double(range.lowerBound)), .number(Double(range.upperBound))])
    }

    private static func limit(_ value: Int) -> JSONValue { .number(Double(value)) }

    static func catalog() throws -> JSONValue {
        .object([
            "fields": .array(Settings.fieldNames.sorted().map(JSONValue.string)),
            "ranges": .object([
                "candidatesPerPage": range(DefaultSettings.candidatesPerPageRange),
                "liveConversionDelay": range(DefaultSettings.liveConversionDelayRange),
                "correctionDelay": range(DefaultSettings.correctionDelayRange),
                "modeIndicatorDuration": range(DefaultSettings.modeIndicatorDurationRange),
                "candidateFontSize": range(DefaultSettings.candidateFontSizeRange),
                "customThemeCornerRadius": range(DefaultSettings.customThemeCornerRadiusRange),
                "associationLimit": range(DefaultSettings.associationLimitRange),
            ]),
            "associationLimitStep": .number(Double(DefaultSettings.associationLimitStep)),
            "secondsStep": .number(DefaultSettings.secondsStep),
            "limits": .object([
                "settingsFileBytes": limit(DefaultSettings.maximumSettingsFileBytes),
                "usageFileBytes": limit(DefaultSettings.maximumUsageFileBytes),
                "ruleListFileBytes": limit(DefaultSettings.maximumRuleListFileBytes),
                "userDictionaryFileBytes": limit(DefaultSettings.maximumUserDictionaryFileBytes),
                "profileRuleFileBytes": limit(DefaultSettings.maximumProfileRuleFileBytes),
                "romajiKeysLength": limit(DefaultSettings.maximumRomajiKeysLength),
                "romajiKanaLength": limit(DefaultSettings.maximumRomajiKanaLength),
                "romajiRules": limit(DefaultSettings.maximumRomajiRules),
                "symbolRules": limit(DefaultSettings.maximumSymbolRules),
                "correctionRules": limit(DefaultSettings.maximumCorrectionRules),
                "exceptionLength": limit(DefaultSettings.maximumExceptionLength),
                "wordLanguageEntries": limit(DefaultSettings.maximumWordLanguageEntries),
                "wordLanguageWordLength": limit(DefaultSettings.maximumWordLanguageWordLength),
                "userDictionaryEntries": limit(DefaultSettings.maximumUserDictionaryEntries),
                "userDictionaryReadingLength": limit(DefaultSettings.maximumUserDictionaryReadingLength),
                "userDictionaryWordLength": limit(DefaultSettings.maximumUserDictionaryWordLength),
                "profileRules": limit(DefaultSettings.maximumProfileRules),
                "applicationIdentifierLength": limit(DefaultSettings.maximumApplicationIdentifierLength),
                "customThemes": limit(DefaultSettings.maximumCustomThemes),
                "themeNameLength": limit(DefaultSettings.maximumThemeNameLength),
                "importedDictionaries": limit(DefaultSettings.maximumImportedDictionaries),
                "associationDictionaries": limit(DefaultSettings.maximumAssociationDictionaries),
                "keymapEntries": limit(DefaultSettings.maximumKeymapEntries),
                "correctionRuleTypedMinimum": limit(DefaultSettings.correctionRuleTypedLength.lowerBound),
                "correctionRuleTypedMaximum": limit(DefaultSettings.correctionRuleTypedLength.upperBound),
                "correctionRuleWordLength": limit(DefaultSettings.maximumCorrectionRuleWordLength),
                "symbolSequenceMinimum": limit(DefaultSettings.symbolSequenceInputLength.lowerBound),
                "symbolInputLength": limit(DefaultSettings.symbolSequenceInputLength.upperBound),
                "symbolOutputLength": limit(DefaultSettings.maximumSymbolOutputLength),
            ]),
            "timing": .object([
                "responseTimeout": .number(DefaultSettings.settingsAppResponseTimeout),
                "reconnectInterval": .number(DefaultSettings.settingsAppReconnectInterval),
                "fileTimeout": .number(DefaultSettings.settingsAppFileTimeout),
            ]),
            // 書き出すファイルの既定の名前(一覧の値は protocol の RuleList と同じ名前)
            "exportFileNames": .object(Dictionary(uniqueKeysWithValues: RuleList.allCases.map { ($0.rawValue, JSONValue.string($0.exportFileName)) })),
        ])
    }

    static func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(catalog()) + Data("\n".utf8)
    }

    @Test("写しが Settings と DefaultSettings に合う")
    func matchesDefaults() throws {
        let expected = try Self.encoded()
        if ProcessInfo.processInfo.environment[Self.writeKey] == "1" {
            try expected.write(to: Self.url)
        }
        let actual = try Data(contentsOf: Self.url)
        #expect(actual == expected, "protocol/settings-catalog.json が古い．make settings-catalog で作り直す")
    }
}
