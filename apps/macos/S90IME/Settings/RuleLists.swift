import S90Domain
import S90Persistence
import SwiftUI

/// 左が重ならない決まりの一覧(補正の置き換え・直さない語・ローマ字)の扱い．RuleListEditor に設定の一覧をつなぐ
struct RuleListSpec<Rule> {
    let list: WritableKeyPath<S90Domain.Settings, [Rule]>
    let key: (Rule) -> String
    let value: (Rule) -> String
    /// 入力欄の値から決まりを作る(前後の空白を除き，形をそろえる)
    let make: (_ key: String, _ value: String) -> Rule
    let isValid: (Rule) -> Bool
    let limit: Int
    let invalidMessage: String
    /// ファイルに書き出し・読み込みするときの一覧
    let file: RuleList

    static var correctionRules: RuleListSpec<CorrectionRule> {
        RuleListSpec<CorrectionRule>(
            list: \.correction.rules, key: \.typed, value: \.word, make: RuleListEditing.correctionRule(typed:word:), isValid: \.isValid,
            limit: DefaultSettings.maximumCorrectionRules, invalidMessage: UIStrings.Features.invalidRule, file: .correctionRules)
    }

    static var exceptions: RuleListSpec<String> {
        RuleListSpec<String>(
            list: \.correction.exceptions, key: { $0 }, value: { _ in "" }, make: { key, _ in key }, isValid: RuleListEditing.isValidException,
            limit: DefaultSettings.maximumCorrectionRules, invalidMessage: UIStrings.Features.invalidException, file: .exceptions)
    }

    /// いつも英語にする語・いつも日本語にする語(英語と日本語)
    static func languageWords(_ language: WordLanguage) -> RuleListSpec<String> {
        RuleListSpec<String>(
            list: language == .english ? \.wordLanguage.englishWords : \.wordLanguage.japaneseWords, key: { $0 }, value: { _ in "" },
            make: { key, _ in RuleList.languageWord(key) }, isValid: WordLanguageSettings.isValidWord, limit: DefaultSettings.maximumWordLanguageEntries,
            invalidMessage: UIStrings.Features.invalidWord, file: language == .english ? .englishWords : .japaneseWords)
    }

    static var romaji: RuleListSpec<RomajiRule> {
        RuleListSpec<RomajiRule>(
            list: \.customRomaji, key: \.keys, value: \.kana, make: RuleListEditing.romajiRule(keys:kana:), isValid: \.isValid,
            limit: DefaultSettings.maximumRomajiRules, invalidMessage: UIStrings.Settings.invalidRomaji, file: .romaji)
    }
}

extension RuleListEditor {
    /// 設定の一覧をそのまま編集する．足す・書き換える・消す・読み込む・書き出すをすべて spec の決まりで行う
    init<Rule>(model: SettingsModel, spec: RuleListSpec<Rule>, labels: Labels) {
        let rules = model.settings[keyPath: spec.list]
        func upsert(_ rule: Rule, replacing old: String?, in settings: inout S90Domain.Settings) -> Bool {
            RuleListEditing.upsert(rule, key: spec.key, isValid: spec.isValid, limit: spec.limit, replacing: old, in: &settings[keyPath: spec.list])
        }
        self.init(
            labels: labels,
            items: rules.map { RuleItem(id: spec.key($0), key: spec.key($0), value: spec.value($0)) },
            problem: { key, value in spec.isValid(spec.make(key, value)) ? nil : spec.invalidMessage },
            save: { key, value, editing in
                model.editRules(failure: UIStrings.RuleList.full) { upsert(spec.make(key, value), replacing: editing?.key, in: &$0) }
            },
            remove: { items in
                let keys = Set(items.map(\.key))
                model.update { $0[keyPath: spec.list].removeAll { keys.contains(spec.key($0)) } }
            },
            importFile: { model.importRuleList(spec.file) },
            exportFile: { model.exportRuleList(spec.file) }
        )
    }
}
