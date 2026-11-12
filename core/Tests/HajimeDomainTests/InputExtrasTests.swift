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

    @Test("R-21: {uuid}・{random} は渡した作り方で作る．知らない名前と {{ }} はそのまま")
    func otherTemplates() {
        let values = TextTemplate.Values(now: now, uuid: { "UUID" }, random: { $0.upperBound })
        #expect(TextTemplate.expand("{datetime+1d:MM/DD}", values: values) == "11/02")
        #expect(TextTemplate.expand("{datetime-7d:M/D}", values: values) == "10/25")
        #expect(TextTemplate.expand("id={uuid} n={random:1-6}", values: values) == "id=UUID n=6")
        #expect(TextTemplate.expand("{clipboard} {{x}} {text}", values: values) == "{clipboard} {x} {text}")
        #expect(TextTemplate.expand("{random:9-1}", values: values) == "{random:9-1}")
        #expect(TextTemplate.containsPlaceholder("{date}"))
        #expect(!TextTemplate.containsPlaceholder("{{date}}"))
        #expect(!TextTemplate.containsPlaceholder("ふつうの語"))
    }

    @Test("R-21: 日時は分・時間・日・週・月・年でずらし，その週の曜日・その月の日・月末に合わせる．左から順に当てる")
    func dateSteps() {
        // 2026/11/01 は日曜日．週は月曜から数える
        let values = TextTemplate.Values(now: now)
        #expect(TextTemplate.expand("{time+2h}・{time-30m}・{time+15h:M/D hh:mm}", values: values) == "11:05・08:35・11/2 00:05")
        #expect(TextTemplate.expand("{date+1w:M/D(ddd)}・{date+1M}・{date-1y}", values: values) == "11/8(日)・2026/12/01・2025/11/01")
        #expect(TextTemplate.expand("{date@mon:M/D(ddd)}・{date+1w@mon:M/D(ddd)}・{date@fri:M/D}", values: values) == "10/26(月)・11/2(月)・10/30")
        #expect(TextTemplate.expand("{date@end:M/D}・{date+1M@1:M/D}・{date+1M@end:M/D}・{date@31:M/D}", values: values)
            == "11/30・12/1・12/31・11/30")
        // 1 月 31 日の 1 か月後は月末(うるう年は 29 日)
        let january = TextTemplate.Values(now: CalendarDate(year: 2028, month: 1, day: 31, weekday: 2))
        #expect(TextTemplate.expand("{date+1M}・{date+1y+1M}", values: january) == "2028/02/29・2029/02/28")
        #expect(TextTemplate.expand("{datetime+1q}・{date@xyz}・{text+1d}・{date+99999d}", values: values)
            == "{datetime+1q}・{date@xyz}・{text+1d}・{date+99999d}")
    }

    @Test("R-21: 英語の月と曜日・年の何日目・週番号・四半期・AM と PM・協定世界時・UNIX 時間")
    func dateFormatSymbols() {
        let values = TextTemplate.Values(now: now)
        #expect(TextTemplate.expand("{date:MMMM MMM EEEE EEE}", values: values) == "November Nov Sunday Sun")
        #expect(TextTemplate.expand("{date:DDDD DDD 'W'WW Q AA}", values: values) == "305 305 W44 4 AM")
        #expect(TextTemplate.expand("{utc}", values: values) == "2026-11-01T00:05:07Z")
        #expect(TextTemplate.expand("{unixtime}・{unixtime+1d}", values: values) == "1793491507・1793577907")
        // 年の初めの週番号は前の年の週のことがある(2027/1/1 は金曜で，2026 年の第 53 週)
        let newYear = TextTemplate.Values(now: CalendarDate(year: 2027, month: 1, day: 1, weekday: 6))
        #expect(TextTemplate.expand("{date:W}・{date+3d:W}", values: newYear) == "53・1")
        // 元号は始まりの日で切り替える
        let heisei = TextTemplate.Values(now: CalendarDate(year: 2019, month: 4, day: 30, weekday: 3))
        #expect(TextTemplate.expand("{date:GGE年}・{date+1d:GGE年}・{date-31y:GGE年}", values: heisei) == "平成31年・令和1年・昭和63年")
    }

    @Test("R-21: 英数字・16 進数の乱数と，並べた中から 1 つを選ぶ")
    func randomTexts() {
        let last = TextTemplate.Values(random: { $0.upperBound })
        let first = TextTemplate.Values(random: { $0.lowerBound })
        #expect(TextTemplate.expand("{alnum:4}・{hex}・{hex:3|upper}", values: last) == "9999・ffffffff・FFF")
        #expect(TextTemplate.expand("{alnum:2}・{pick:犬,猫,鳥}・{pick:犬,猫,鳥}", values: first) == "AA・犬・犬")
        #expect(TextTemplate.expand("{pick:犬,猫,鳥}", values: last) == "鳥")
        #expect(TextTemplate.expand("{alnum:0}・{alnum:65}・{pick}", values: last) == "{alnum:0}・{alnum:65}・{pick}")
    }

    @Test("R-21: {text|upper} など，値に変換をかける")
    func templateFilters() {
        let values = TextTemplate.Values(text: "hello", reading: "はろー")
        #expect(TextTemplate.expand("{text|upper}/{text|capitalize}/{reading|katakana}/{text|fullwidth}", values: values) == "HELLO/Hello/ハロー/ｈｅｌｌｏ")
        #expect(TextTemplate.expand("{text|fullwidth|ascii}・{reading|halfwidth}・{text|length}・{text|nothing}", values: values)
            == "hello・ﾊﾛｰ・5・{text|nothing}")
    }

    @Test("R-21: 英語の語の書き方(snake・camel・pascal・kebab)と URL の形")
    func wordCaseFilters() {
        let values = TextTemplate.Values(text: "Hello world HTTPServer v2", reading: "")
        #expect(TextTemplate.expand("{text|snake}", values: values) == "hello_world_http_server_v2")
        #expect(TextTemplate.expand("{text|kebab}", values: values) == "hello-world-http-server-v2")
        #expect(TextTemplate.expand("{text|camel}", values: values) == "helloWorldHttpServerV2")
        #expect(TextTemplate.expand("{text|pascal}", values: values) == "HelloWorldHttpServerV2")
        #expect(TextFilter.snake.apply(to: "parseJSONValue") == "parse_json_value")
        #expect(TextFilter.url.apply(to: "東京 タワー/a~b") == "%E6%9D%B1%E4%BA%AC%20%E3%82%BF%E3%83%AF%E3%83%BC%2Fa~b")
    }

    @Test("R-21: 祝日の名前と，土日と祝日を飛ばす平日のずらし")
    func holidaysAndBusinessDays() {
        // 2026/11/01 は日曜日．11/3 は文化の日
        let values = TextTemplate.Values(now: now)
        #expect(TextTemplate.expand("[{holiday}]・{holiday:平日}・{holiday+2d}", values: values) == "[]・平日・文化の日")
        #expect(TextTemplate.expand("{date+1b:M/D}・{date+2b:M/D(ddd)}・{date-1b:M/D(ddd)}・{date+0b:M/D}", values: values)
            == "11/2・11/4(水)・10/30(金)・11/1")
        // 年をまたぐと，元日と土日を飛ばす
        let yearEnd = TextTemplate.Values(now: CalendarDate(year: 2026, month: 12, day: 31, weekday: 5))
        #expect(TextTemplate.expand("{date+1b}・{date+1d:GGEE年 FFFF年度}", values: yearEnd) == "2027/01/04・令和9年 2026年度")

        func holiday(_ year: Int, _ month: Int, _ day: Int) -> String? {
            JapaneseCalendar.holiday(on: CalendarDate(year: year, month: month, day: day, weekday: 1))
        }
        // 敬老の日(9/21)と秋分の日(9/23)に挟まれた日は国民の休日，日曜日の祝日のあとは振替休日
        #expect(holiday(2026, 9, 21) == "敬老の日" && holiday(2026, 9, 22) == "国民の休日" && holiday(2026, 9, 23) == "秋分の日")
        #expect(holiday(2026, 5, 3) == "憲法記念日" && holiday(2026, 5, 6) == "振替休日" && holiday(2026, 5, 7) == nil)
        #expect(holiday(2027, 3, 21) == "春分の日" && holiday(2027, 3, 22) == "振替休日")
        #expect(holiday(2026, 3, 20) == "春分の日" && holiday(2026, 1, 12) == "成人の日" && holiday(2026, 10, 12) == "スポーツの日")
        // 2021 年は山の日を 8/8 に移し，日曜日なので 8/9 が振替休日．祝日を求めない年は nil
        #expect(holiday(2021, 8, 8) == "山の日" && holiday(2021, 8, 9) == "振替休日" && holiday(2021, 8, 11) == nil)
        #expect(holiday(2019, 1, 1) == nil && holiday(2100, 1, 1) == nil)
    }

    @Test("R-21: 時候の挨拶・時刻の挨拶・ある日までの日数・満年齢")
    func seasonGreetingDaysAndAge() {
        let values = TextTemplate.Values(now: now)
        #expect(TextTemplate.expand("{season}・{season+2M}", values: values) == "晩秋の候・厳寒の候")
        #expect(TextTemplate.expand("{greeting}・{greeting+3h}・{greeting+10h}・{greeting-6h}", values: values)
            == "おはようございます・こんにちは・こんばんは・こんばんは")
        // 年を書かなければ次に来るその日．2/29 は次のうるう年
        #expect(TextTemplate.expand("{days:12/25}・{days:11/1}・{days:10/31}・{days:2026-10-01}・{days:2/29}", values: values)
            == "54・0・364・-31・485")
        #expect(TextTemplate.expand("{age:1990-04-01}・{age:1990/11/2}", values: values) == "36・35")
        #expect(TextTemplate.expand("{days:2/30}・{days}・{days:x}・{age:12/25}・{age:2030-01-01}・{days:99999-1-1}", values: values)
            == "{days:2/30}・{days}・{days:x}・{age:12/25}・{age:2030-01-01}・{days:99999-1-1}")
    }

    @Test("R-21: 年度・元年・和風月名・干支の書式")
    func japaneseDateSymbols() {
        let values = TextTemplate.Values(now: now)
        #expect(TextTemplate.expand("{date:FFFF年度 'FY'FF NN JJ}", values: values) == "2026年度 FY26 霜月 丙午")
        #expect(TextTemplate.expand("{date+4M:FFFF}・{date+5M:FFFF}", values: values) == "2026・2027")
        let heisei = TextTemplate.Values(now: CalendarDate(year: 2019, month: 4, day: 30, weekday: 3))
        #expect(TextTemplate.expand("{date:GGEE年}・{date+1d:GGEE年}・{date+1d:GGE年}", values: heisei) == "平成31年・令和元年・令和1年")
        #expect(TextTemplate.expand("{date:GGEE年M月D日|kansuji}", values: heisei) == "平成三十一年四月三十日")
    }

    @Test("R-21: 数字の漢数字・大字・3 桁区切り・丸数字と，HTML・Base64 の形")
    func numberAndEncodingFilters() {
        let values = TextTemplate.Values(text: "2026年 第3回 1234567.89 007 ７５", reading: "")
        #expect(TextTemplate.expand("{text|kansuji}", values: values) == "二千二十六年 第三回 百二十三万四千五百六十七.89 七 七十五")
        #expect(TextTemplate.expand("{text|kanjidigits}", values: values) == "二〇二六年 第三回 一二三四五六七.89 〇〇七 七五")
        #expect(TextTemplate.expand("{text|comma}", values: values) == "2,026年 第3回 1,234,567.89 007 ７５")
        #expect(TextTemplate.expand("{text|circled}", values: values) == "2026年 第③回 1234567.89 ⑦ ７５")
        #expect(TextFilter.daiji.apply(to: "金12000円・10・0") == "金壱万弐千円・壱拾・0")
        #expect(TextFilter.kansuji.apply(to: "0・00・12345678901234567") == "〇・〇・12345678901234567")
        #expect(TextFilter.html.apply(to: "<a href=\"x\">&'") == "&lt;a href=&quot;x&quot;&gt;&amp;&#39;")
        #expect(TextFilter.base64.apply(to: "東京") == "5p2x5Lqs")
    }

    @Test("R-22: かなをヘボン式のローマ字にする(ん は n，っ は子音を重ね，ー は母音を重ねる)")
    func romaji() {
        #expect(HepburnRomanizer.romaji(from: "とうきょう") == "toukyou")
        #expect(HepburnRomanizer.romaji(from: "しんぶん") == "shinbun")
        #expect(HepburnRomanizer.romaji(from: "ちゃっと・まっちゃ") == "chatto・matcha")
        #expect(HepburnRomanizer.romaji(from: "ふじさん") == "fujisan")
        #expect(HepburnRomanizer.romaji(from: "コーヒー") == "koohii")
        #expect(HepburnRomanizer.romaji(from: "ティーシャツ") == "tiishatsu")
        #expect(HepburnRomanizer.romaji(from: "ヴァイオリン") == "vaiorin")
        #expect(HepburnRomanizer.romaji(from: "東京タワー") == "東京tawaa")
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
        // 候補の窓では印を除いた名前を出す．印の無い文字列はそのまま
        #expect(LauncherCommand.title(ofCandidateText: command().candidateText) == command().title)
        #expect(LauncherCommand.title(ofCandidateText: "クロード") == "クロード")
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

    @Test("R-22: 足した既定の形は無効で入り，オンにすれば使える．id は重ならない")
    func addedMacroPresets() {
        let added = DefaultSettings.addedMacros
        #expect(added.allSatisfy { $0.isValid && !$0.isEnabled })
        #expect(Set(DefaultSettings.conversionMacros.map(\.id)).count == DefaultSettings.conversionMacros.count)
        let enabled = added.map { ConversionMacro(id: $0.id, pattern: $0.pattern) }
        let results = ConversionMacros.results(text: "東京", reading: "とうきょう", macros: enabled)
        #expect(results.contains("東京（トウキョウ）"))
        #expect(results.contains("toukyou"))
        #expect(results.contains("[[rb:東京 > とうきょう]]"))
        #expect(results.contains("\\ruby{東京}{とうきょう}"))
        #expect(results.contains("《《東京》》"))
        #expect(results.contains("[東京](https://ja.wikipedia.org/wiki/%E6%9D%B1%E4%BA%AC)"))
        #expect(!ConversionMacros.results(text: "東京", reading: "とうきょう", macros: added).contains("toukyou"))
    }

    @Test("R-22: 変換マクロでも日時と乱数を使える．かなの語には，語と読みを並べる形を出さない(設定で切れる)")
    func macrosWithValuesAndKanaWords() {
        let macros = [ConversionMacro(pattern: "{text}（{date:M/D}）"), ConversionMacro(pattern: "{text}（{reading}）"),
                      ConversionMacro(pattern: "{reading|romaji}")]
        let values = TextTemplate.Values(now: now)
        #expect(ConversionMacros.results(text: "東京", reading: "とうきょう", macros: macros, values: values, skipsSameReading: true)
            == ["東京（11/1）", "東京（とうきょう）", "toukyou"])
        #expect(ConversionMacros.results(text: "すし", reading: "すし", macros: macros, values: values, skipsSameReading: true)
            == ["すし（11/1）", "sushi"])
        #expect(ConversionMacros.results(text: "スシ", reading: "すし", macros: macros, values: values, skipsSameReading: true)
            == ["スシ（11/1）", "sushi"])
        #expect(ConversionMacros.results(text: "すし", reading: "すし", macros: macros, values: values, skipsSameReading: false)
            == ["すし（11/1）", "すし（すし）", "sushi"])
    }

    @Test("R-22: 前のバージョンで保存した一覧には，足した形を無効のまま末尾に足す．消した既定の形は戻さない")
    func macroPresetUpgrade() throws {
        let kept = DefaultSettings.conversionMacros[2]
        let custom = ConversionMacro(pattern: "<<{text}>>")
        let oldList = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode([kept, custom]))
        var object: [String: JSONValue] = [SettingsSchema.versionKey: .number(10), "macros": oldList]
        SettingsSchema.migrate(&object)
        let upgraded = try #require(object["macros"])
        let macros = try JSONDecoder().decode([ConversionMacro].self, from: JSONEncoder().encode(upgraded))
        #expect(macros == [kept, custom] + DefaultSettings.addedMacros)
        // もう一度移し替えても重ねて足さない
        var again: [String: JSONValue] = [SettingsSchema.versionKey: .number(10), "macros": upgraded]
        SettingsSchema.migrate(&again)
        #expect(again["macros"] == upgraded)
        // 一覧を書いていない設定は触らない(読むときに既定の一覧になる)
        var empty: [String: JSONValue] = [SettingsSchema.versionKey: .number(10)]
        SettingsSchema.migrate(&empty)
        #expect(empty["macros"] == nil)
        // バージョン 14 で保存した一覧には，バージョン 15 で足した形だけを足す
        let version14 = Array(DefaultSettings.conversionMacros.prefix(DefaultSettings.conversionMacros.count - 3))
        var saved: [String: JSONValue] = [
            SettingsSchema.versionKey: .number(14), "macros": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(version14)),
        ]
        SettingsSchema.migrate(&saved)
        let upgraded15 = try JSONDecoder().decode([ConversionMacro].self, from: JSONEncoder().encode(try #require(saved["macros"])))
        #expect(upgraded15 == DefaultSettings.conversionMacros)
    }

    @Test("R-22: 数字の形の変換マクロは，語に数字があるときだけ出る")
    func numberMacroPresets() {
        let macros = DefaultSettings.addedMacros.suffix(3).map { ConversionMacro(id: $0.id, pattern: $0.pattern) }
        #expect(ConversionMacros.results(text: "第3回", reading: "だいさんかい", macros: macros) == ["第三回", "第参回"])
        #expect(ConversionMacros.results(text: "12000円", reading: "12000えん", macros: macros) == ["一万二千円", "壱万弐千円", "12,000円"])
        #expect(ConversionMacros.results(text: "東京", reading: "とうきょう", macros: macros).isEmpty)
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
