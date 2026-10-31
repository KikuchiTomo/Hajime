/// 登録する語の読みを，引くときの読み(ひらがな)にそろえる．
///
/// 読みはひらがな・カタカナのほか，ローマ字や英字でも書ける(「gh」→ GitHub，「toyota」→ トヨタ)．
/// ローマ字入力で打ったキーは読みになってから引くので，ローマ字の読みは打ったときと同じ決まりでかなにする
/// (「toyota」は「とよた」，「gh」はかなにならないので「gh」のまま)．他の IME の辞書(Google 日本語入力・Microsoft IME)の
/// 書き出しにも英字の読みがあるので，取り込むときも同じにそろえる
public enum ReadingNormalization {
    /// そろえた読み．読みに使えない文字があれば nil
    public static func normalized(_ reading: String) -> String? {
        let trimmed = String(reading.drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
        guard !trimmed.isEmpty else { return nil }
        let kana = KanaWidth.hiragana(from: trimmed)
        if kana.unicodeScalars.allSatisfy(isKanaReading) { return kana }
        // 英字・数字・長音の「-」だけの読みは，ローマ字として打ったときの読みにする
        let lowered = trimmed.lowercased()
        guard lowered.unicodeScalars.allSatisfy(isRomajiReading), lowered.contains(where: \.isLetter) else { return nil }
        let reading = KeyEditSearch.rawReading(of: lowered)
        return reading.isEmpty ? nil : reading
    }

    /// 引くときの読みとして形が正しいか(ひらがな・長音と，かなにならずに残った英小文字・数字)
    public static func isNormalizedReading(_ reading: String) -> Bool {
        !reading.isEmpty && reading.unicodeScalars.allSatisfy { isKanaReading($0) || isRomajiReading($0) && !("A"..."Z").contains($0) }
    }

    private static func isKanaReading(_ scalar: Unicode.Scalar) -> Bool {
        (0x3041...0x3096).contains(scalar.value) || scalar == "ー"
    }

    private static func isRomajiReading(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
    }
}
