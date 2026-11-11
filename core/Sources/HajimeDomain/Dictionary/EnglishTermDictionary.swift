/// 英語の語の辞書(R-24)．API・OpenAI・GitHub のように書き方の決まった英語の語を，打った英字で引く．
///
/// ローマ字入力で英語の語を小文字で打つと，ローマ字として読める並びはかなになり(「api」→ あぴ，「openai」→ おぺない)，
/// 読めない並びは英字のまま残る(「github」→ ぎてゅb，「aws」→ あws)．どちらの読みからも語を引けるよう，
/// 語ごとに，打つ英字(語を小文字にしたもの)と，その英字を打ったときの読みの両方で引けるようにしておく．
/// 読みはユーザー辞書の英字の読みと同じ決まりでそろえる(ReadingNormalization)
public struct EnglishTermDictionary: Sendable, Equatable {
    /// 打つ英字(小文字)ごとの語．並びは足した順
    private var byKeys: [String: [String]] = [:]
    /// 英字を打ったときの読みごとの語．読みが打った英字のままの語(「python」を英単語として確定させたもの)は byKeys で引く
    private var byReading: [String: [String]] = [:]

    /// 語を並べた文字列．1 行に 1 語で，前後の空白は除く．「#」で始まる行と，語にならない行は飛ばす
    public init(text: String) {
        self.init(terms: text.split(whereSeparator: \.isNewline).lazy
            .map { String($0.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed()) }
            .filter { !$0.hasPrefix("#") })
    }

    /// 語にならないものは飛ばす．同じ語は 1 つにする
    public init(terms: some Sequence<String>) {
        for term in terms where Self.isValidTerm(term) {
            let keys = term.lowercased()
            guard !(byKeys[keys]?.contains(term) ?? false) else { continue }
            byKeys[keys, default: []].append(term)
            if let reading = ReadingNormalization.normalized(keys), reading != keys {
                byReading[reading, default: []].append(term)
            }
        }
    }

    /// この辞書の語のあとに other の語を足した辞書．同じ英字の語はこの辞書の語を先にする(利用者が足した語を同梱の語より先に出す)
    public func merging(_ other: EnglishTermDictionary) -> EnglishTermDictionary {
        var merged = self
        for (keys, terms) in other.byKeys {
            merged.byKeys[keys, default: []] += terms.filter { !(byKeys[keys]?.contains($0) ?? false) }
        }
        for (reading, terms) in other.byReading {
            merged.byReading[reading, default: []] += terms.filter { !(byReading[reading]?.contains($0) ?? false) }
        }
        return merged
    }

    public var isEmpty: Bool { byKeys.isEmpty }

    /// 語の数
    public var count: Int { byKeys.values.reduce(0) { $0 + $1.count } }

    /// 語として足せるか．英字だけで，長さが DefaultSettings.englishTermLengthRange に収まるもの
    public static func isValidTerm(_ term: String) -> Bool {
        DefaultSettings.englishTermLengthRange.contains(term.count) && term.unicodeScalars.allSatisfy(isLetter)
    }

    /// 打った英字(大文字小文字は問わない)の語
    public func terms(forKeys keys: String) -> [String] {
        byKeys[keys.lowercased()] ?? []
    }

    /// 読み全体が辞書の語になるときの語．読みは英字を打ったときの読み(「あぴ」「ぎてゅb」)か，
    /// 小文字で打った英字のまま確定させた読み(「github」)．大文字を含む読み(Shift で打った「Api」)は打ったとおりにするので引かない．
    /// - Parameter includesRomajiReadings: 英字を打ったときの読みでも引くか．かな入力では読みを英字で打っていないので引かない
    public func terms(forReading reading: String, includesRomajiReadings: Bool = true) -> [String] {
        var found = includesRomajiReadings ? byReading[reading] ?? [] : []
        if reading.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) }) {
            found += (byKeys[reading] ?? []).filter { !found.contains($0) }
        }
        return found
    }

    /// 文字列の中の小文字の英字の並び(前後が英数字でないもの)のうち，辞書の語になるものを語の書き方にした文字列．
    /// 書き方を変えるところが無ければ nil．英単語として確定させた英字(「githubを使う」)を「GitHubを使う」にする．
    /// 大文字小文字を変えるだけなので，文字数は変わらない
    public func applyingTerms(to text: String) -> String? {
        var result = ""
        var run = ""
        var changed = false
        func flush() {
            if !run.isEmpty, run.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) }), let term = byKeys[run]?.first, term != run {
                result += term
                changed = true
            } else {
                result += run
            }
            run = ""
        }
        for character in text {
            if character.isASCII, character.isLetter || character.isNumber {
                run.append(character)
            } else {
                flush()
                result.append(character)
            }
        }
        flush()
        return changed ? result : nil
    }

    private static func isLetter(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar)
    }
}

extension EnglishTermDictionary: CustomStringConvertible, CustomDebugStringConvertible {
    // 利用者の足した語を含むので，ログには数だけを出す
    public var description: String { "EnglishTermDictionary(count: \(count))" }
    public var debugDescription: String { description }
}
