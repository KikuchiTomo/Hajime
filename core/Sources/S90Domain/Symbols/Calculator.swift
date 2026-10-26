import Foundation

/// 読みが「1+2*3=」のような式なら，計算した結果を返す．
///
/// 式は自前の再帰下降で読み，文字列をプログラムとして実行しない．使えるのは数・小数・+ − × ÷ ^ とかっこ．
/// 読みの中では記号が全角や「ー」(長音)・「・」(中黒)・「。」(句点)になっていることがあるので，数の間にあればそれぞれ
/// 引き算・割り算・小数点として読む．長すぎる式・0 で割る式・桁があふれる式は計算しない
public enum Calculator {
    /// 式の最大の長さ．長い式で計算に時間をかけない
    static let maximumLength = 64

    /// 末尾が「=」の式なら，式と結果を返す(「1+2*3=」→ ("1+2*3", "7"))
    public static func evaluate(reading: String) -> (expression: String, result: String)? {
        let normalized = normalize(reading)
        guard normalized.count <= maximumLength, normalized.hasSuffix("="), normalized.count >= 4 else { return nil }
        let expression = String(normalized.dropLast())
        // 演算子が 1 つも無い(数だけ)なら計算と言えないので出さない
        guard expression.contains(where: { "+-*/^".contains($0) }), let value = evaluate(expression: expression) else { return nil }
        return (expression, format(value))
    }

    /// 式を計算する．読めない式なら nil
    public static func evaluate(expression: String) -> Double? {
        var parser = Parser(characters: Array(expression))
        guard let value = parser.parseExpression(), parser.index == parser.characters.count, value.isFinite, abs(value) < 1e15 else { return nil }
        return value
    }

    /// 全角・読みの中の記号を，式の記号にそろえる
    static func normalize(_ text: String) -> String {
        let characters = Array(text)
        var result = ""
        for (index, character) in characters.enumerated() {
            let previous = index > 0 ? characters[index - 1] : nil
            let next = index + 1 < characters.count ? characters[index + 1] : nil
            let betweenOperands = (previous.map(isOperandEnd) ?? false) && (next.map(isOperandStart) ?? false)
            switch character {
            case "０"..."９": result.append(Character(UnicodeScalar(character.unicodeScalars.first!.value - 0xFEE0)!))
            case "＋": result.append("+")
            case "－", "−": result.append("-")
            case "ー" where betweenOperands || previous == nil || previous == "(" || previous == "（": result.append("-")
            case "＊", "×": result.append("*")
            case "／", "÷": result.append("/")
            case "・" where betweenOperands: result.append("/")
            case "＾": result.append("^")
            case "（": result.append("(")
            case "）": result.append(")")
            case "＝": result.append("=")
            case "．", "。", "，" where betweenOperands: result.append(character == "，" ? "," : ".")
            case " ", "　": break
            default: result.append(character)
            }
        }
        return result
    }

    private static func isOperandEnd(_ character: Character) -> Bool {
        character.isASCII ? (character.isNumber || character == ")") : ("０"..."９").contains(character) || character == "）"
    }

    private static func isOperandStart(_ character: Character) -> Bool {
        character.isASCII ? (character.isNumber || character == "(") : ("０"..."９").contains(character) || character == "（"
    }

    /// 整数なら小数点を付けず，小数は 10 桁までにして末尾の 0 を除く
    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        var text = String(format: "%.10f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// 式 := 項 (("+"|"-") 項)*，項 := 冪 (("*"|"/") 冪)*，冪 := 単項 ("^" 冪)?，単項 := "-" 単項 | 数 | "(" 式 ")"
    struct Parser {
        let characters: [Character]
        var index = 0
        var depth = 0

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let character = peek, character == "+" || character == "-" {
                index += 1
                guard let right = parseTerm() else { return nil }
                value = character == "+" ? value + right : value - right
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parsePower() else { return nil }
            while let character = peek, character == "*" || character == "/" {
                index += 1
                guard let right = parsePower() else { return nil }
                if character == "/" {
                    guard right != 0 else { return nil }
                    value /= right
                } else {
                    value *= right
                }
            }
            return value
        }

        mutating func parsePower() -> Double? {
            guard let base = parseUnary() else { return nil }
            guard peek == "^" else { return base }
            index += 1
            guard let exponent = parsePower(), abs(exponent) <= 64 else { return nil }
            return pow(base, exponent)
        }

        mutating func parseUnary() -> Double? {
            if peek == "-" {
                index += 1
                return parseUnary().map { -$0 }
            }
            if peek == "(" {
                // 深すぎる入れ子は読まない(再帰が深くなりすぎないように)
                guard depth < 16 else { return nil }
                index += 1
                depth += 1
                guard let value = parseExpression(), peek == ")" else { return nil }
                index += 1
                depth -= 1
                return value
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            let start = index
            var seenDot = false
            while let character = peek, character.isASCII, character.isNumber || (character == "." && !seenDot) || character == "," {
                if character == "." { seenDot = true }
                index += 1
            }
            guard index > start else { return nil }
            return Double(String(characters[start..<index]).replacingOccurrences(of: ",", with: ""))
        }

        var peek: Character? { index < characters.count ? characters[index] : nil }
    }
}
