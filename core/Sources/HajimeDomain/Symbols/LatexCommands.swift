/// 読みから引く LaTeX のコマンドの表．数式を書くときに，ギリシャ文字や記号の読み(「らむだ」)から
/// コマンド(「\lambda」)を候補に出す．ふだんの文でよく使う語(「かける」「いじょう」)の読みは入れない．
/// 設定(latexConversion)でオンにしたときだけ使い，記号と同じく第 1 候補は変えずに差し込む
public enum LatexCommands {
    /// 読みに当たるコマンド．無ければ空
    public static func commands(for reading: String) -> [String] {
        table[reading] ?? []
    }

    static let table: [String: [String]] = {
        let entries: [(String, String)] = [
            // ギリシャ文字(小文字のあとに大文字や異体字)
            ("あるふぁ", "\\alpha"), ("べーた", "\\beta"), ("がんま", "\\gamma \\Gamma"), ("でるた", "\\delta \\Delta"),
            ("いぷしろん", "\\epsilon \\varepsilon"), ("ぜーた", "\\zeta"), ("いーた", "\\eta"), ("しーた", "\\theta \\Theta \\vartheta"),
            ("いおた", "\\iota"), ("かっぱ", "\\kappa"), ("らむだ", "\\lambda \\Lambda"), ("みゅー", "\\mu"), ("にゅー", "\\nu"),
            ("くしー", "\\xi \\Xi"), ("ぐざい", "\\xi \\Xi"), ("ぱい", "\\pi \\Pi"), ("ろー", "\\rho \\varrho"),
            ("しぐま", "\\sigma \\Sigma"), ("たう", "\\tau"), ("うぷしろん", "\\upsilon \\Upsilon"), ("ふぁい", "\\phi \\varphi \\Phi"),
            ("かい", "\\chi"), ("ぷさい", "\\psi \\Psi"), ("ぷしー", "\\psi \\Psi"), ("おめが", "\\omega \\Omega"),
            // 大きな演算子と式の形
            ("せきぶん", "\\int \\iint \\oint"), ("にじゅうせきぶん", "\\iint"), ("しゅうかいせきぶん", "\\oint"),
            ("そうわ", "\\sum"), ("しぐまきごう", "\\sum"), ("そうじょう", "\\prod"), ("きょくげん", "\\lim"),
            ("ぶんすう", "\\frac{}{}"), ("るーと", "\\sqrt{}"), ("へいほうこん", "\\sqrt{}"),
            ("びぶん", "\\frac{d}{dx} \\partial"), ("へんびぶん", "\\partial"), ("なぶら", "\\nabla"),
            ("むげんだい", "\\infty"),
            // 関係と演算
            ("ほぼひとしい", "\\approx"), ("にあいこーる", "\\approx \\simeq"), ("のっといこーる", "\\neq"), ("ひとしくない", "\\neq"),
            ("しょうなりいこーる", "\\leq"), ("だいなりいこーる", "\\geq"), ("ごうどう", "\\equiv"), ("ひれい", "\\propto"),
            ("ぷらすまいなす", "\\pm"), ("まいなすぷらす", "\\mp"), ("ないせき", "\\cdot"), ("がいせき", "\\times"),
            ("ちょっこう", "\\perp"),
            // 論理と集合
            ("ぞくする", "\\in"), ("ぶぶんしゅうごう", "\\subset \\subseteq"), ("わしゅうごう", "\\cup"), ("せきしゅうごう", "\\cap"),
            ("くうしゅうごう", "\\emptyset"), ("にんいの", "\\forall"), ("そんざいする", "\\exists"),
            ("ひつようじゅうぶん", "\\Leftrightarrow"),
            // 関数
            ("さいん", "\\sin"), ("こさいん", "\\cos"), ("たんじぇんと", "\\tan"), ("たいすう", "\\log \\ln"), ("しぜんたいすう", "\\ln"),
            ("しすう", "\\exp"),
            // 飾り
            ("べくとる", "\\vec{} \\boldsymbol{}"),
        ]
        var table: [String: [String]] = [:]
        for (reading, commands) in entries {
            table[reading, default: []] += commands.split(separator: " ").map(String.init)
        }
        return table
    }()
}
