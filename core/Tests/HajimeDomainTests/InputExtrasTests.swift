import Foundation
import HajimeDomain
import Testing

@Suite("手のずれ・ローマ字の読み・動的な語・うろ覚えの語・発音どおりの綴り・コマンド・変換マクロ")
struct InputExtrasTests {
    // MARK: 手のずれ(R-20)

    @Test("R-20: 右手だけ 1 つ右にずれた並びを戻すと，元の並びが候補に入る")
    func rightHandShift() {
        // konnnitiha を右手だけ右にずらすと，k→l，o→p，n→m，i→o，h→j になる(左手の t・a はそのまま)
        let shifted = HandShift.variants(of: "lpmmmotoja", layout: .qwerty)
        #expect(shifted.contains { $0.keys == "konnnitiha" && $0.shift == HandShift.Shift(hands: .right, offset: 1) })
    }

    @Test("R-20: 両手がずれた並びも戻す．戻す先にキーが無い(段の端)ときは，両手の組は作らない")
    func bothHandsShift() {
        // arigatou を両手とも右にずらすと sthohsyp になる
        #expect(HandShift.variants(of: "stohsypi", layout: .qwerty).contains { $0.keys == "arigatou" && $0.shift.hands == .both })
        // q の左にはキーが無いので，両手が左にずれたとして戻す組(q を右へ)は作れない
        #expect(!HandShift.variants(of: "pq", layout: .qwerty).contains { $0.shift == HandShift.Shift(hands: .both, offset: 1) })
    }

    @Test("R-20: Dvorak の配列では，Dvorak の位置で戻す")
    func dvorakShift() {
        // Dvorak の中の段は aoeuidhtns．右手が右に 1 つずれると h→t，t→n になる
        let variants = HandShift.variants(of: "tn", layout: .dvorak)
        #expect(variants.contains { $0.keys == "ht" })
        #expect(KeyboardGeometry.of(.dvorakQwertyCommand) == .dvorak)
        #expect(KeyboardGeometry.of(.system) == .qwerty)
    }

    @Test("R-20: 記号のキーに戻る組と，配列に無い文字を含む並びは作らない．長音の - はそのまま残す")
    func shiftExcludesSymbols() {
        #expect(HandShift.variants(of: "l", layout: .qwerty).allSatisfy { $0.keys.allSatisfy(\.isLetter) })
        #expect(HandShift.variants(of: "k@", layout: .qwerty).isEmpty)
        #expect(HandShift.variants(of: "lp-", layout: .qwerty).contains { $0.keys == "ko-" })
    }

    // MARK: ローマ字の読み(R-21)

    @Test("R-21: ローマ字・英字の読みは，打ったときと同じ読みにそろえる．カタカナはひらがなにする")
    func readingNormalization() {
        #expect(ReadingNormalization.normalized("toyota") == "とよた")
        #expect(ReadingNormalization.normalized("gh") == "gh")
        #expect(ReadingNormalization.normalized("GitHub") == "ぎてゅb")
        #expect(ReadingNormalization.normalized(" カタカナ ") == "かたかな")
        #expect(ReadingNormalization.normalized("漢字") == nil)
        #expect(ReadingNormalization.normalized("123") == nil)
        #expect(ReadingNormalization.normalized("") == nil)
        #expect(UserDictionaryEntry(reading: "gh", word: "GitHub").isValid)
        #expect(UserDictionaryEntry(reading: "gh", word: "GitHub").hasKanaReading == false)
        #expect(UserDictionaryEntry(reading: "toyota", word: "トヨタ").hasKanaReading)
        #expect(!UserDictionaryEntry(reading: "a/b", word: "x").isValid)
    }

    // MARK: 動的な語(TextTemplate)

    private let now = CalendarDate(year: 2026, month: 11, day: 1, weekday: 1, hour: 9, minute: 5, second: 7, utcOffsetSeconds: 9 * 3600)

    @Test("R-21: {datetime:...} を書式で置き換える．記号でない文字と '…' で囲んだ字はそのまま")
    func datetimeTemplate() {
        let values = TextTemplate.Values(now: now)
        #expect(TextTemplate.expand("{datetime:YYYY}/{datetime:MM}/{datetime:DD} {datetime:hh}:{datetime:mm}:{datetime:ss}", values: values)
            == "2026/11/01 09:05:07")
        #expect(TextTemplate.expand("{datetime:YYYY-MM-DD'T'hh:mm:ssZZ}", values: values) == "2026-11-01T09:05:07+09:00")
        #expect(TextTemplate.expand("{datetime:GGE年M月D日(ddd) A K時}", values: values) == "令和8年11月1日(日) 午前 9時")
        #expect(TextTemplate.expand("{date}・{time}", values: values) == "2026/11/01・09:05")
        #expect(TextTemplate.expand("{datetime:EEE dddd}", values: values) == "Sun 日曜日")
    }

    @Test("R-21: {datetime+nd:...} は日をずらし，{uuid}・{random} は渡した作り方で作る．知らない名前と {{ }} はそのまま")
    func otherTemplates() {
        let values = TextTemplate.Values(
            now: now, day: { CalendarDate(year: 2026, month: 11, day: 1 + $0, weekday: 1) }, uuid: { "UUID" }, random: { $0.upperBound })
        #expect(TextTemplate.expand("{datetime+1d:MM/DD}", values: values) == "11/02")
        #expect(TextTemplate.expand("{datetime-7d:D}", values: values) == "-6")
        #expect(TextTemplate.expand("id={uuid} n={random:1-6}", values: values) == "id=UUID n=6")
        #expect(TextTemplate.expand("{clipboard} {{x}} {text}", values: values) == "{clipboard} {x} {text}")
        #expect(TextTemplate.expand("{random:9-1}", values: values) == "{random:9-1}")
        #expect(TextTemplate.containsPlaceholder("{date}"))
        #expect(!TextTemplate.containsPlaceholder("{{date}}"))
        #expect(!TextTemplate.containsPlaceholder("ふつうの語"))
    }

    @Test("R-21: {text|upper} など，値に変換をかける")
    func templateFilters() {
        let values = TextTemplate.Values(text: "hello", reading: "はろー")
        #expect(TextTemplate.expand("{text|upper}/{text|capitalize}/{reading|katakana}/{text|fullwidth}", values: values) == "HELLO/Hello/ハロー/ｈｅｌｌｏ")
    }

    @Test("R-21: 「にちじ」で日付と時刻を合わせた形を出す．「いま」には秒までの形も出す")
    func dateTimeExpressions() {
        let candidates = DateExpressions.candidates(for: "にちじ", now: now, day: { _ in now })
        #expect(candidates.first == "2026/11/01 09:05:07")
        #expect(candidates.contains("2026-11-01T09:05:07+09:00"))
        #expect(candidates.contains("20261101090507"))
        #expect(DateExpressions.candidates(for: "いま", now: now, day: { _ in now }).contains("09:05:07"))
    }

    // MARK: うろ覚えの語・発音どおりの綴り

    @Test("R-20: うろ覚えの読みの組み替えに，正しい読みが入る")
    func looseReadings() {
        #expect(LooseReadings.variants(of: "しゅみれーしょん").contains("しみゅれーしょん"))
        #expect(LooseReadings.variants(of: "こみにけーしょん").contains("こみゅにけーしょん"))
        #expect(LooseReadings.variants(of: "ぶるどっく").contains("ぶるどっぐ"))
        #expect(LooseReadings.variants(of: "ぎぶす").contains("ぎぷす"))
        #expect(LooseReadings.variants(of: "あ").isEmpty)
        #expect(LooseReadings.variants(of: "しゅみれーしょん").count <= DefaultSettings.maximumLooseReadingVariants)
    }

    @Test("R-20: 発音どおりの綴りの置き換えに，正しい綴りが入る")
    func phoneticSpelling() {
        #expect(PhoneticSpelling.variants(of: "foto").contains("photo"))
        #expect(PhoneticSpelling.variants(of: "fone").contains("phone"))
        #expect(PhoneticSpelling.variants(of: "fotograf").contains("photograph"))
        #expect(PhoneticSpelling.variants(of: "kat").contains("cat"))
        #expect(PhoneticSpelling.variants(of: "ab").isEmpty)
        #expect(PhoneticSpelling.variants(of: "foto1").isEmpty)
    }

    // MARK: コマンド(R-22)

    private func command(_ kind: LauncherCommand.Kind = .openURL, target: String = "https://claude.ai", reading: String = "くろーど") -> LauncherCommand {
        LauncherCommand(reading: reading, title: "Claude を開く", kind: kind, target: target)
    }

    @Test("R-22: コマンドの行き先は形を確かめる．URL は http・https だけで，制御文字は入れない")
    func commandValidity() {
        #expect(command().isValid)
        #expect(!command(target: "file:///etc/passwd").isValid)
        #expect(!command(target: "javascript:alert(1)").isValid)
        #expect(!command(target: "https://").isValid)
        #expect(!command(.openApplication, target: "/Applications/A.app\n").isValid)
        #expect(command(.openApplication, target: "/Applications/Claude.app").isValid)
        #expect(!LauncherCommand(id: "../x", reading: "くろーど", title: "x", kind: .openURL, target: "https://a.b").isValid)
        #expect(!LauncherCommand(reading: "くろーど", title: " ", kind: .openURL, target: "https://a.b").isValid)
        #expect(command().candidateText.hasPrefix(DefaultSettings.commandCandidateMark))
    }

    @Test("R-22: 読みで引くときはローマ字の読みもそろえ，使わないコマンドは引かない")
    func commandMatching() {
        var off = command(reading: "claude")
        #expect(LauncherCommands.matching("cぁうで", in: [off]).count == 1)
        off.isEnabled = false
        #expect(LauncherCommands.matching("cぁうで", in: [off]).isEmpty)
    }

    @Test("R-22: id の無いコマンドとマクロ(Windows の設定の画面で足した行)は，読むときに id を付ける")
    func decodeWithoutID() throws {
        let json = #"{"reading":"くろーど","title":"Claude","kind":"openURL","target":"https://claude.ai"}"#
        let decoded = try JSONDecoder().decode(LauncherCommand.self, from: Data(json.utf8))
        #expect(decoded.isValid)
        #expect(decoded.isEnabled)
        let macro = try JSONDecoder().decode(ConversionMacro.self, from: Data(#"{"pattern":"【{text}】"}"#.utf8))
        #expect(macro.isValid)
    }

    @Test("R-22: コマンドは同期のまとまりに入るが，同期できるまとまりには入らない．読み込んだ設定でも書き換えない")
    func commandsAreNotSynced() {
        #expect(SyncGroup.commands.fieldNames == ["launcherCommands", "commands"])
        #expect(!SyncGroup.syncableCases.contains(.commands))
        var current = Settings()
        current.commands = [command()]
        current.launcherCommands = true
        var imported = Settings()
        imported.commands = [command(target: "https://example.com")]
        imported.liveConversion = false
        let merged = imported.keepingCommands(of: current)
        #expect(merged.commands == current.commands)
        #expect(merged.launcherCommands)
        #expect(!merged.liveConversion)
    }

    @Test("R-15: 同期の突き合わせで，コマンドのまとまりは範囲を「同期する」にしても同期のファイルに書かない")
    func syncMergeIgnoresCommands() {
        let local: [String: JSONValue] = ["commands": .array([]), "launcherCommands": .bool(true)]
        let result = SyncMerge.merge(local: local, ledger: SyncLedger(), remote: nil, scopes: [.commands: .synced], now: Date(timeIntervalSince1970: 100))
        #expect(result.document.groups[.commands] == nil)
        #expect(result.settings["launcherCommands"] == .bool(true))
        #expect(result.settings["commands"] == .array([]))
        var ledger = SyncLedger()
        SyncMerge.noteChange(from: local, to: ["commands": .array([]), "launcherCommands": .bool(false)], ledger: &ledger, now: Date())
        #expect(ledger.groupModifiedAt[.commands] == nil)
    }

    // MARK: 変換マクロ

    @Test("R-22: 変換マクロは選んでいる語と読みを差し込み，元の語と同じものと重なりを除く")
    func macros() {
        let results = ConversionMacros.results(text: "東京", reading: "とうきょう", macros: DefaultSettings.conversionMacros)
        #expect(results.first == "「東京」")
        #expect(results.contains("東京（とうきょう）"))
        #expect(results.contains("<ruby>東京<rt>とうきょう</rt></ruby>"))
        #expect(!results.contains("東京"))
        #expect(DefaultSettings.conversionMacros.allSatisfy { $0.isValid })
        #expect(!ConversionMacro(pattern: "固定の文字").isValid)
    }

    @Test("設定の新しい項目は既定でオフで，ファイルに書いて読み戻せる")
    func settingsRoundTrip() throws {
        let defaults = Settings()
        #expect(!defaults.handShiftCorrection && !defaults.looseReadings && !defaults.phoneticSpelling && !defaults.dynamicDictionary
            && !defaults.conversionMacros && !defaults.launcherCommands)
        var settings = Settings()
        settings.handShiftCorrection = true
        settings.launcherCommands = true
        settings.commands = [command()]
        settings.macros = [ConversionMacro(pattern: "[{text}]")]
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(Settings.self, from: data) == settings)
    }
}
