import Testing
@testable import S90Domain

@Suite("ターミナルの行の状態")
struct CommandLineStateTests {
    @Test("コマンドの名前で始まればコマンドの行，そうでなければ文の行")
    func firstWord() {
        var command = CommandLineState()
        let isCommand = command.didTypeFirstWord("git")
        #expect(isCommand)
        #expect(command.passesThrough)
        var text = CommandLineState()
        let isTextCommand = text.didTypeFirstWord("kyouha")
        #expect(!isTextCommand)
        #expect(text.region == .text)
    }

    @Test("引用符の中は日本語にし，閉じる引用符でコマンドの行に戻る")
    func quotes() {
        var state = CommandLineState()
        _ = state.didTypeFirstWord("git")
        state.didPass("\"")
        #expect(state.region == .quoted("\""))
        state.didPass("'")
        #expect(state.region == .quoted("\""))
        state.didPass("\"")
        #expect(state.region == .command)
    }

    @Test("# は語の頭にあるときだけコメントにする")
    func comment() {
        var state = CommandLineState()
        _ = state.didTypeFirstWord("echo")
        for character in "foo#bar" { state.didPass(character) }
        #expect(state.region == .command)
        state.didPass(" ")
        state.didPass("#")
        #expect(state.region == .comment)
    }

    @Test("Backspace で行の頭まで消すと行の頭に戻る")
    func deleteToLineStart() {
        var state = CommandLineState()
        _ = state.didTypeFirstWord("ls")
        for _ in 0..<3 { state.didDeleteBackward() }
        #expect(state.region == .lineStart)
    }

    @Test("行を終えると行の頭に戻る")
    func endLine() {
        var state = CommandLineState()
        _ = state.didTypeFirstWord("ls")
        state.endLine()
        #expect(state.region == .lineStart)
    }
}

@Suite("日付の候補")
struct DateExpressionsTests {
    private let day = { (offset: Int) in CalendarDate(year: 2019, month: 5, day: 1 + offset, weekday: 4) }

    @Test("令和元年は令和 1 年と書く")
    func reiwaFirstYear() {
        let now = CalendarDate(year: 2019, month: 5, day: 1, weekday: 4)
        #expect(DateExpressions.candidates(for: "きょう", now: now, day: day).contains("令和1年5月1日"))
    }

    @Test("午前 0 時は午前0時と書く")
    func midnight() {
        let now = CalendarDate(year: 2026, month: 1, day: 1, weekday: 5, hour: 0, minute: 3)
        #expect(DateExpressions.candidates(for: "いま", now: now, day: day) == ["0:03", "0時3分", "午前0時3分"])
    }

    @Test("日付の読みでなければ何も出さない")
    func other() {
        #expect(DateExpressions.candidates(for: "あめ", now: CalendarDate(year: 2026, month: 1, day: 1, weekday: 5), day: day).isEmpty)
    }
}

@Suite("ユーザー辞書の編集")
struct UserDictionaryEditingTests {
    @Test("前後の空白を除いて足し，登録済み・形の誤り・上限を断る")
    func add() {
        var entries: [UserDictionaryEntry] = []
        #expect(UserDictionaryEditing.add(reading: " えすきゅー ", word: "s90\u{3000}", to: &entries) == .added)
        #expect(entries == [UserDictionaryEntry(reading: "えすきゅー", word: "s90")])
        #expect(UserDictionaryEditing.add(reading: "えすきゅー", word: "s90", to: &entries) == .alreadyRegistered)
        #expect(UserDictionaryEditing.add(reading: "ABC", word: "x", to: &entries) == .invalid)
        var full = (0..<DefaultSettings.maximumUserDictionaryEntries).map { UserDictionaryEntry(reading: "あ", word: "\($0)") }
        #expect(UserDictionaryEditing.add(reading: "い", word: "x", to: &full) == .full)
    }

    @Test("取り込みは足した数を返し，重複と形の誤りを除く")
    func merge() {
        var entries = [UserDictionaryEntry(reading: "あ", word: "亜")]
        let imported = [UserDictionaryEntry(reading: "あ", word: "亜"), UserDictionaryEntry(reading: "い", word: "井"), UserDictionaryEntry(reading: "X", word: "x")]
        #expect(UserDictionaryEditing.merge(imported, into: &entries) == 1)
        #expect(entries.count == 2)
    }

    @Test("ログに出す表示は中身を伏せる")
    func redacted() {
        let entry = UserDictionaryEntry(reading: "ひみつ", word: "秘密")
        #expect(!String(describing: entry).contains("秘密"))
        var settings = Settings()
        settings.userDictionary = [entry]
        #expect(!String(describing: settings).contains("秘密"))
    }
}

@Suite("かな入力の設定")
struct KanaLayoutSettingsTests {
    @Test("かな入力の句読点・中黒・括弧も設定の文字にする")
    func settings() {
        var settings = Settings()
        settings.punctuation = .commaPeriod
        settings.slash = .slash
        settings.brackets = .square
        #expect(KanaLayout.text(forKey: ",", shift: true, settings: settings) == "，")
        #expect(KanaLayout.text(forKey: ".", shift: true, settings: settings) == "．")
        #expect(KanaLayout.text(forKey: "/", shift: true, settings: settings) == "／")
        #expect(KanaLayout.text(forKey: "[", shift: true, settings: settings) == "［")
        #expect(KanaLayout.text(forKey: "e", shift: true, settings: settings) == "ぃ")
    }
}
