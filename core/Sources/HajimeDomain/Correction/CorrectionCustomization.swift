/// 利用者が足した，英単語の置き換えの決まり(「teh」→「the」)．打った英字の並びがこれに当たれば，綴りの辞書より先に使う
public struct CorrectionRule: Sendable, Equatable, Codable, Hashable {
    /// 打った英字(小文字で照らし合わせる)
    public var typed: String
    /// 直した語
    public var word: String

    public init(typed: String, word: String) {
        self.typed = typed
        self.word = word
    }

    /// 打った英字は DefaultSettings.correctionRuleTypedLength の文字数の英字，直した語は 1 文字から上限まで
    public var isValid: Bool {
        DefaultSettings.correctionRuleTypedLength.contains(typed.count) && typed.allSatisfy { $0.isASCII && $0.isLetter }
            && (1...DefaultSettings.maximumCorrectionRuleWordLength).contains(word.count)
    }
}

/// 打ち間違いの補正のうち，利用者が決められること(R-02)
public struct CorrectionCustomization: Sendable, Equatable, Codable {
    /// 英単語の綴りを直す(「pthon」→「python」)
    public var english = true
    /// 日本語の打ち間違いを直す(「kyounotenkihayoudesune」→「今日の天気は良いですね」)
    public var japanese = true
    /// 同じキーを続けて 2 回打った誤りを直す(「koonnnitiha」→「こんにちは」)
    public var repeatedKeys = true
    /// 直さない語．打った英字か読みにこれを含むときは直さない
    public var exceptions: [String] = []
    /// 利用者が足した置き換えの決まり
    public var rules: [CorrectionRule] = []

    public init() {}

    /// 打った英字か読みが，直さない語を含むか
    public func isException(keys: String?, reading: String) -> Bool {
        exceptions.contains { exception in
            !exception.isEmpty && ((keys?.lowercased().contains(exception.lowercased()) ?? false) || reading.contains(exception))
        }
    }

    /// 打った英字に当たる置き換えの決まり
    public func rule(for keys: String) -> CorrectionRule? {
        rules.last { $0.typed.lowercased() == keys.lowercased() }
    }

    private enum CodingKeys: String, CodingKey { case english, japanese, repeatedKeys, exceptions, rules }

    /// 足した項目や読めない値は既定のままにする．一覧は 1 つずつ読み，崩れたものだけを捨てる
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        english = (try? container.decodeIfPresent(Bool.self, forKey: .english)) ?? true
        japanese = (try? container.decodeIfPresent(Bool.self, forKey: .japanese)) ?? true
        repeatedKeys = (try? container.decodeIfPresent(Bool.self, forKey: .repeatedKeys)) ?? true
        exceptions = ((try? container.decodeIfPresent([String].self, forKey: .exceptions)) ?? [])
            .filter { !$0.isEmpty && $0.count <= 64 }
        rules = ((try? container.decodeIfPresent([LossyRule].self, forKey: .rules)) ?? []).compactMap(\.rule).filter(\.isValid)
    }

    private struct LossyRule: Decodable {
        var rule: CorrectionRule?
        init(from decoder: any Decoder) throws { rule = try? CorrectionRule(from: decoder) }
    }
}
