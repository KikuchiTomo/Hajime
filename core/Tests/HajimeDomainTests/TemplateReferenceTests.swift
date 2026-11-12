import HajimeDomain
import Testing

/// 書き方のチップを押したときに語に足す決まり(R-21)．Windows の settings の template_reference のテストと同じ例
struct TemplateReferenceTests {
    @Test("R-21: 書き方は語の末尾に足す")
    func insertingSyntax() {
        let item = TemplateReference.Item("{date}", "今日の日付")
        #expect(TemplateReference.inserting(item, kind: .syntax, into: "") == "{date}")
        #expect(TemplateReference.inserting(item, kind: .syntax, into: "締切 ") == "締切 {date}")
        #expect(TemplateReference.inserting(item, kind: .syntax, into: "{time}") == "{time}{date}")
    }

    @Test("R-21: 値の変え方は最後の書き方の中に足し，足せなければ例の書き方を末尾に足す")
    func insertingFilter() {
        let upper = TemplateReference.Item("|upper", "大文字", sample: "{date:MMM|upper}")
        let chain = TemplateReference.Item("|upper|fullwidth", "左から順にかける", sample: "{date:MMM|upper|fullwidth}")
        #expect(TemplateReference.inserting(upper, kind: .filter, into: "{date:MMM}") == "{date:MMM|upper}")
        #expect(TemplateReference.inserting(upper, kind: .filter, into: "{uuid|lower}") == "{uuid|lower|upper}")
        #expect(TemplateReference.inserting(chain, kind: .filter, into: "{text}") == "{text|upper|fullwidth}")
        #expect(TemplateReference.inserting(upper, kind: .filter, into: "") == "{date:MMM|upper}")
        #expect(TemplateReference.inserting(upper, kind: .filter, into: "{date}です") == "{date}です{date:MMM|upper}")
        // }} は文字の「}」で，書き方の終わりではない
        #expect(TemplateReference.inserting(upper, kind: .filter, into: "{{date}}") == "{{date}}{date:MMM|upper}")
    }

    @Test("R-21: 書式の記号は最後の日時の書き方の書式に足し，書式が無ければ例の書き方を末尾に足す")
    func insertingFormatSymbol() {
        let weekday = TemplateReference.Item("ddd", "曜日（略）", sample: "{date:ddd}")
        #expect(TemplateReference.inserting(weekday, kind: .formatSymbol, into: "{date:M/D}") == "{date:M/Dddd}")
        #expect(TemplateReference.inserting(weekday, kind: .formatSymbol, into: "{date+1w@mon:M/D(|kansuji}") == "{date+1w@mon:M/D(ddd|kansuji}")
        #expect(TemplateReference.inserting(weekday, kind: .formatSymbol, into: "{utc:YYYY}") == "{utc:YYYYddd}")
        // 書式の無い {date} に足すと既定の書式が消えるので，例を足す
        #expect(TemplateReference.inserting(weekday, kind: .formatSymbol, into: "{date}") == "{date}{date:ddd}")
        #expect(TemplateReference.inserting(weekday, kind: .formatSymbol, into: "{holiday:平日}") == "{holiday:平日}{date:ddd}")
        #expect(TemplateReference.inserting(weekday, kind: .formatSymbol, into: "") == "{date:ddd}")
    }

    @Test("R-21: 入力位置の前の打ちかけの書き方を，名前・値の変え方・日時の書式・そのほかの引数に分ける")
    func typing() {
        #expect(TextTemplate.typing(before: "締切 {") == .name(""))
        #expect(TextTemplate.typing(before: "{date} {da") == .name("da"))
        #expect(TextTemplate.typing(before: "{date+1") == .name("date+1"))
        #expect(TextTemplate.typing(before: "{reading|ka") == .filter("ka"))
        #expect(TextTemplate.typing(before: "{date:M月D") == .format("D"))
        #expect(TextTemplate.typing(before: "{date+1w:YY") == .format("YY"))
        #expect(TextTemplate.typing(before: "{date:M月") == .format(""))
        #expect(TextTemplate.typing(before: "{random:1-") == .argument)
        // 閉じた書き方と {{(文字の「{」)は打ちかけではない
        #expect(TextTemplate.typing(before: "{date}") == nil)
        #expect(TextTemplate.typing(before: "{{da") == nil)
        #expect(TextTemplate.typing(before: "") == nil)
    }

    @Test("R-21: 打ちかけの書き方に当たるチップだけを，まとまりの順に返す．名前を打つ前と日時でない引数では絞り込まない")
    func matches() {
        let reference = TemplateReference([
            .init(title: "日時", kind: .syntax, items: [.init("{date}", "日付"), .init("{time}", "時刻"), .init("{datetime}", "日時")]),
            .init(title: "暦", kind: .syntax, items: [.init("{days:12/25}", "日数"), .init("{days:2027-03-31}", "日数"), .init("{date}", "日付")]),
            .init(title: "変換", kind: .filter, items: [.init("|katakana", "カタカナ"), .init("|kansuji", "漢数字"), .init("|upper", "大文字")]),
            .init(title: "書式", kind: .formatSymbol, items: [.init("YYYY", "年"), .init("MM", "月"), .init("mm", "分")]),
        ])
        let codes = { (typing: TextTemplate.Typing?) in reference.matches(for: typing)?.map(\.item.code) }
        // 名前を打ちかけているあいだは名前ごとに 1 つ．打ち終えたら，その名前で始まるものをすべて
        #expect(codes(.name("Da")) == ["{date}", "{datetime}", "{days:12/25}"])
        #expect(codes(.name("date")) == ["{date}", "{datetime}"])
        #expect(codes(.name("days")) == ["{days:12/25}", "{days:2027-03-31}"])
        #expect(codes(.name("date+")) == [])
        #expect(codes(.filter("ka")) == ["|katakana", "|kansuji"])
        #expect(codes(.filter("")) == ["|katakana", "|kansuji", "|upper"])
        // 書式の記号は大文字と小文字を分ける(M は月，m は分)
        #expect(codes(.format("M")) == ["MM"])
        #expect(codes(.name("")) == nil)
        #expect(codes(.argument) == nil)
        #expect(codes(nil) == nil)
        #expect(codes(.name("zzz")) == [])
    }

    @Test("R-21: 打ちかけの書き方は，押したチップで置き換える")
    func insertingOverTyping() {
        let date = TemplateReference.Item("{date}", "日付")
        let katakana = TemplateReference.Item("|katakana", "カタカナ", sample: "{reading|katakana}")
        let year = TemplateReference.Item("YYYY", "年", sample: "{date:YYYY}")
        #expect(TemplateReference.inserting(date, kind: .syntax, into: "締切 {da") == "締切 {date}")
        #expect(TemplateReference.inserting(date, kind: .syntax, into: "{") == "{date}")
        #expect(TemplateReference.inserting(katakana, kind: .filter, into: "{reading|ka") == "{reading|katakana")
        #expect(TemplateReference.inserting(katakana, kind: .filter, into: "{reading") == "{reading|katakana")
        #expect(TemplateReference.inserting(year, kind: .formatSymbol, into: "{date:M/D YY") == "{date:M/D YYYY")
        #expect(TemplateReference.inserting(year, kind: .formatSymbol, into: "{date+1d") == "{date+1d:YYYY")
    }

    @Test("R-21: 入力位置に入れ，書き換える範囲は変わる部分だけにする(後ろの文字は残す)")
    func insertionAtSelection() {
        let date = TemplateReference.Item("{date}", "日付")
        let upper = TemplateReference.Item("|upper", "大文字", sample: "{date:MMM|upper}")
        // 「締切 {da|まで」(| が入力位置)．打ちかけの {da を {date} にし，後ろの「まで」は残す
        #expect(TemplateReference.insertion(of: date, kind: .syntax, in: "締切 {daまで", selection: 6..<6)
            == .init(range: 6..<6, replacement: "te}"))
        // 選んでいる部分は置き換える
        #expect(TemplateReference.insertion(of: date, kind: .syntax, in: "締切 XX", selection: 3..<5)
            == .init(range: 3..<5, replacement: "{date}"))
        // 入力位置の直前の書き方に値の変え方を足す(閉じかっこの前に入る)
        #expect(TemplateReference.insertion(of: upper, kind: .filter, in: "{uuid} です", selection: 6..<6)
            == .init(range: 5..<6, replacement: "|upper}"))
        // 範囲の外の入力位置は末尾にそろえる
        #expect(TemplateReference.insertion(of: date, kind: .syntax, in: "😀", selection: 9..<9)
            == .init(range: 2..<2, replacement: "{date}"))
    }

    @Test("R-21: 置き換えられない部分(知らない名前・読めない引数・閉じていない {)を誤りとして返す")
    func problems() {
        let values = TextTemplate.Values(now: CalendarDate(year: 2026, month: 4, day: 1, weekday: 4), random: { $0.lowerBound })
        #expect(TextTemplate.problems(in: "{date}と{time}", values: values).isEmpty)
        #expect(TextTemplate.problems(in: "締切 {dat}", values: values) == ["{dat}"])
        #expect(TextTemplate.problems(in: "{random:9-1}・{date|nothing}", values: values) == ["{random:9-1}", "{date|nothing}"])
        // 閉じていない { は次の { の前まで．後ろの書き方は読める
        #expect(TextTemplate.problems(in: "{date:M/D {time}", values: values) == ["{date:M/D "])
        #expect(TextTemplate.problems(in: "締切 {date", values: values) == ["{date"])
        // {{ と }} は文字なので誤りではない．単語では {text} は置き換えられない
        #expect(TextTemplate.problems(in: "{{date}}", values: values).isEmpty)
        #expect(TextTemplate.problems(in: "{text}", values: values) == ["{text}"])
        // 閉じていない { があっても，入る文字はこれまでと同じ
        #expect(TextTemplate.expand("{date:M/D {time}", values: values) == "{date:M/D 00:00")
    }
}
