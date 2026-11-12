"""絵文字と記号のパレットの表(data/palette/palette.tsv)を作る．

使い方:
    python3 -I tools/palette/build.py collect <素材のディレクトリ> <symbols.txt>
        読みを求める日本語の語(漢字を含む名前とキーワード)を 1 行に 1 つずつ標準出力に書く
    python3 -I tools/palette/build.py build <素材のディレクトリ> <symbols.txt> <names.txt> <読み.tsv> <出力.tsv>
        表を書く．読み.tsv は collect の語を tools/palette/readings.swift でひらがなにしたもの(「語<タブ>読み」)．
        names.txt は CLDR に名前の無い記号の名前と読み

素材のディレクトリには tools/palette/update.sh が取ってきた次のファイルを置く．
- emoji-test.txt: Unicode の絵文字の一覧と並び順，まとまり，バージョン
- ja.xml，en.xml，ja_derived.xml，en_derived.xml: CLDR の絵文字と記号の名前とキーワード
- emoji_all_E17.0.txt: azooKey の絵文字の読み(Mozc の絵文字データと CLDR から作ったもの)
- emoji.json: 「:bow:」のようなショートコード(iamcal/emoji-data)
- UnicodeData.txt: 記号の英語の名前
- emoticon.tsv，categorized.tsv: Mozc の顔文字と読み，まとまり

出力は 1 行に 1 項目で，列はタブで区切る(HajimeDomain の PaletteCatalog が読む)．
    種類  まとまり  文字  絵文字のバージョン  日本語の名前  名前の読み  英語の名前  読み  キーワード  ショートコード  肌の色の形  名前の出どころ
- 種類は emoji か symbol か kaomoji．まとまりは PaletteCategory の id
- 名前の出どころは，日本語の名前を定めたところ．cldr は CLDR の名前，hajime は Hajime IME が付けた名前(names.txt・Unicode の名前の形から作った名前・
  囲み文字の中の文字)．顔文字と名前の無い項目は空
- 読み・キーワード・ショートコード・肌の色の形は | で区切る．読みはひらがな．肌の色の形は明るい順に 5 つ
- 名前の読みは日本語の名前の読み(ひらがな)．探したときに，名前で当たった項目を読みやキーワードで当たった項目より先にするのに使う
- 絵文字は emoji-test.txt の並び，記号は symbols.txt の並び，顔文字は emoticon.tsv の並びのあとに categorized.tsv にだけある顔文字．
  肌の色を変えた形と部品(Component)は項目にしない
- 顔文字の日本語の名前と名前の読みは，最初の読み(Mozc でいちばん顔文字を表す読み)．英語の名前とキーワードは無い．
  まとまりは Mozc のまとまりと読みから決める(kaomoji_category)
外から来る XML なので，外部の実体を読まない ElementTree で読む
"""
import json
import sys
import unicodedata
import xml.etree.ElementTree as ElementTree

GROUPS = {
    "Smileys & Emotion": "smileys",
    "People & Body": "people",
    "Animals & Nature": "nature",
    "Food & Drink": "food",
    "Travel & Places": "travel",
    "Activities": "activities",
    "Objects": "objects",
    "Symbols": "symbols",
    "Flags": "flags",
}
SKIN_TONES = [0x1F3FB, 0x1F3FC, 0x1F3FD, 0x1F3FE, 0x1F3FF]
SYMBOL_CATEGORIES = ["punctuation", "brackets", "arrows", "math", "letters", "units", "enclosed", "shapes", "lines", "misc"]
KAOMOJI_CATEGORIES = ["joy", "sorrow", "sweat", "anger", "surprise", "greeting", "animals", "otherFaces"]
# 顔文字の長さの上限(DefaultSettings.maximumKaomojiTextLength と同じ)．超えるものは表に入れない
KAOMOJI_MAX_LENGTH = 32
# 顔文字の形を説明する読み．名前には使わない
KAOMOJI_DESCRIPTIVE_READINGS = {"よこおき"}
# Mozc の顔文字のまとまり → パレットのまとまり．OTHER とまとまりの無い顔文字は，読みから振り分ける(KAOMOJI_HINTS)
MOZC_KAOMOJI_CATEGORIES = {"SMILE": "joy", "SADNESS": "sorrow", "SWEAT": "sweat", "DISPLEASURE": "anger", "SURPRISE": "surprise"}
# 読みのどれかがこれなら動物にする(Mozc のまとまりより先)
KAOMOJI_ANIMALS = {"どうぶつ", "ねこ", "いぬ", "くま", "くまー", "にゃー", "ごりら", "たこ"}
# 最初の読みがこれならあいさつと動作にする(Mozc のまとまりより先)．最初の読みだけで決めるのは，
# 「＼(^o^)／」のように後ろの読みに「おーい」を持つ笑顔まで移さないため
KAOMOJI_GREETINGS = {
    "おじぎ", "ぺこり", "ごめん", "ごめんなさい", "ありがとう", "ばいばい", "さようなら", "さよなら", "またね", "こんにちは", "ではでは",
    "よろしく", "けいれい", "おやすみ", "やぁ", "たのむ", "おーい", "ねる", "いっぷく", "おちゃ", "めも", "めもめも", "ちゃぶだい",
}
# Mozc のまとまりが無いか OTHER の顔文字を，読みのどれかで振り分ける．上にあるものを先に当てる．どれにも当たらなければ otherFaces
KAOMOJI_HINTS = [
    ("sorrow", {"なく", "なみだ", "しくしく", "えーん", "うるうる", "しょぼーん", "しょんぼり", "がっくり", "がーん", "ちーん", "ぐすん", "かなしい",
                "ぶわっ", "うわーん", "ぴー"}),
    ("anger", {"いかり", "おこる", "むか", "むかっ", "むかー", "むきー", "ぷんぷん", "ちっ", "こら", "ぶー", "やだやだ", "じと", "じとっ", "じとー"}),
    ("sweat", {"あせ", "ぎくっ", "とほほ", "やれやれ", "がくぶる", "ごくり", "うーん", "はぁ", "はぁはぁ", "ためいき", "えっと", "えーと"}),
    ("surprise", {"びっくり", "びくっ", "めがてん", "はっ", "わお", "ぽかーん", "くわっ", "ええ", "えぇ", "うおお", "きゃー", "どきっ"}),
    ("joy", {"にこ", "にこにこ", "にこっ", "わーい", "うれしい", "てれ", "ぽっ", "ばんざい", "いい", "いいね", "えへへ", "うふふ", "もえ", "わくわく",
             "きゃっ", "ぐっ", "ぶい", "ぴーす", "はーと", "うっとり", "にやにや", "いえい", "きらり", "きらっ", "ぺろ", "ぺろぺろ", "すまいる"}),
]

DIGITS = ["ぜろ", "いち", "に", "さん", "よん", "ご", "ろく", "なな", "はち", "きゅう"]
LETTERS = {
    "A": "えー", "B": "びー", "C": "しー", "D": "でぃー", "E": "いー", "F": "えふ", "G": "じー", "H": "えいち", "I": "あい",
    "J": "じぇー", "K": "けー", "L": "える", "M": "えむ", "N": "えぬ", "O": "おー", "P": "ぴー", "Q": "きゅー", "R": "あーる",
    "S": "えす", "T": "てぃー", "U": "ゆー", "V": "ぶい", "W": "だぶりゅー", "X": "えっくす", "Y": "わい", "Z": "ぜっと",
}
GREEK = {
    "ALPHA": "あるふぁ", "BETA": "べーた", "GAMMA": "がんま", "DELTA": "でるた", "EPSILON": "いぷしろん", "ZETA": "ぜーた",
    "ETA": "いーた", "THETA": "しーた", "IOTA": "いおた", "KAPPA": "かっぱ", "LAMDA": "らむだ", "MU": "みゅー", "NU": "にゅー",
    "XI": "くさい", "OMICRON": "おみくろん", "PI": "ぱい", "RHO": "ろー", "SIGMA": "しぐま", "TAU": "たう", "UPSILON": "うぷしろん",
    "PHI": "ふぁい", "CHI": "かい", "PSI": "ぷさい", "OMEGA": "おめが",
}
NUMBER_WORDS = {
    "ZERO": 0, "ONE": 1, "TWO": 2, "THREE": 3, "FOUR": 4, "FIVE": 5, "SIX": 6, "SEVEN": 7, "EIGHT": 8, "NINE": 9, "TEN": 10,
    "ELEVEN": 11, "TWELVE": 12, "THIRTEEN": 13, "FOURTEEN": 14, "FIFTEEN": 15, "SIXTEEN": 16, "SEVENTEEN": 17, "EIGHTEEN": 18,
    "NINETEEN": 19, "TWENTY": 20, "THIRTY": 30, "FORTY": 40, "FIFTY": 50, "ONE HUNDRED": 100, "FIVE HUNDRED": 500, "ONE THOUSAND": 1000,
}
FRACTIONS = {"HALF": 2, "THIRD": 3, "THIRDS": 3, "QUARTER": 4, "QUARTERS": 4, "FIFTH": 5, "FIFTHS": 5, "SIXTH": 6, "SIXTHS": 6,
             "EIGHTH": 8, "EIGHTHS": 8}
# 日本語の名前の無い記号に，英語の名前に含まれる語から付ける名前と読み(ARROW → 矢印)．上にあるものを先に当てる
ENGLISH_HINTS = [
    ("QUOTATION", "引用符", "いんようふ"), ("LOGICAL OR", "または", "または"), ("ARROW", "矢印", "やじるし"), ("ARROWHEAD", "矢印", "やじるし"), ("BRACKET", "括弧", "かっこ"), ("PARENTHESIS", "括弧", "かっこ"),
    ("STAR", "星", "ほし"), ("ASTERISK", "アスタリスク", "あすたりすく"), ("HEART", "ハート", "はーと"), ("FLORETTE", "花", "はな"),
    ("FLORAL", "花", "はな"), ("FLOWER", "花", "はな"), ("SNOWFLAKE", "雪の結晶", "ゆき"), ("SPARKLE", "きらめき", "きらきら"),
    ("CROSS", "バツ", "ばつ"), ("MULTIPLICATION", "かける", "かける"), ("CHECK", "チェック", "ちぇっく"), ("BALLOT", "チェックボックス", "ちぇっくぼっくす"),
    ("CIRCLE", "丸", "まる"), ("SQUARE", "四角", "しかく"), ("DIAMOND", "ひし形", "ひしがた"), ("LOZENGE", "ひし形", "ひしがた"),
    ("TRIANGLE", "三角", "さんかく"), ("RECTANGLE", "四角", "しかく"), ("PARALLELOGRAM", "平行四辺形", "へいこうしへんけい"),
    ("CHESS", "チェス", "ちぇす"), ("DIE FACE", "さいころ", "さいころ"), ("TELEPHONE", "電話", "でんわ"), ("SCISSORS", "はさみ", "はさみ"),
    ("PENCIL", "鉛筆", "えんぴつ"), ("NIB", "ペン", "ぺん"), ("INDEX", "指", "ゆび"), ("SUN", "太陽", "たいよう"), ("MOON", "月", "つき"),
    ("EARTH", "地球", "ちきゅう"), ("FLAG", "旗", "はた"), ("SIGN", "記号", "きごう"), ("RECYCLING", "リサイクル", "りさいくる"),
    ("MALE", "男性", "おとこ"), ("FEMALE", "女性", "おんな"), ("CONJUNCTION", "合", "ごう"), ("NODE", "交点", "こうてん"),
    ("CURRENCY", "通貨", "つうか"), ("SIGN", "記号", "きごう"), ("INTEGRAL", "積分", "せきぶん"), ("ROOT", "根号", "るーと"),
    ("SUBSET", "部分集合", "ぶぶんしゅうごう"), ("SUPERSET", "上位集合", "じょういしゅうごう"), ("ELEMENT", "要素", "ようそ"),
    ("IDENTICAL", "合同", "ごうどう"), ("TACK", "記号", "きごう"), ("CEILING", "天井関数", "てんじょう"), ("FLOOR", "床関数", "ゆか"),
    ("DOUBLE-STRUCK", "黒板太字", "こくばんふとじ"), ("PER TEN THOUSAND", "ベーシスポイント", "べーしすぽいんと"),
]


def key(text):
    """絵文字を照らし合わせる鍵．異体字セレクタ(FE0F)の有無で別の項目にしない"""
    return text.replace("\ufe0f", "")


def number_reading(n):
    if n < 10:
        return DIGITS[n]
    if n < 100:
        tens, ones = divmod(n, 10)
        head = "" if tens == 1 else DIGITS[tens]
        return head + "じゅう" + (DIGITS[ones] if ones else "")
    return {100: "ひゃく", 500: "ごひゃく", 1000: "せん"}.get(n, "")


def to_hiragana(text):
    return "".join(chr(ord(c) - 0x60) if 0x30A1 <= ord(c) <= 0x30F6 else c for c in text)


def to_katakana(text):
    return "".join(chr(ord(c) + 0x60) if 0x3041 <= ord(c) <= 0x3096 else c for c in text)


def is_kana(text):
    return bool(text) and all(0x3041 <= ord(c) <= 0x3096 or 0x30A1 <= ord(c) <= 0x30FA or c in "ー・" for c in text)


def has_japanese(text):
    return any(0x3041 <= ord(c) <= 0x30FF or 0x3400 <= ord(c) <= 0x9FFF or 0xF900 <= ord(c) <= 0xFAFF for c in text)


def unique(values):
    seen = set()
    result = []
    for value in values:
        value = value.strip()
        if value and value not in seen:
            seen.add(value)
            result.append(value)
    return result


def read_annotations(path):
    """CLDR の annotation を「鍵 → (キーワード, 名前)」にする"""
    keywords = {}
    names = {}
    for element in ElementTree.parse(path).getroot().iter("annotation"):
        cp = element.get("cp")
        text = element.text or ""
        if element.get("type") == "tts":
            names[key(cp)] = text.strip()
        else:
            keywords[key(cp)] = [word.strip() for word in text.split("|")]
    return keywords, names


def read_emoji_test(path):
    """絵文字を並び順に (まとまり, 文字, バージョン, 英語の名前) にし，肌の色を変えた形を鍵ごとにまとめる"""
    entries = []
    tones = {}
    group = None
    for line in open(path, encoding="utf-8"):
        if line.startswith("# group:"):
            group = GROUPS.get(line.split(":", 1)[1].strip())
            continue
        if line.startswith("#") or ";" not in line or group is None:
            continue
        codes, rest = line.split(";", 1)
        if not rest.strip().startswith("fully-qualified"):
            continue
        points = [int(code, 16) for code in codes.split()]
        comment = rest.split("#", 1)[1].strip()
        text = "".join(chr(point) for point in points)
        _, version, name = comment.split(" ", 2)
        modifiers = [point for point in points if point in SKIN_TONES]
        if modifiers:
            # 肌の色を変えた形．人が何人もいる絵文字は，全員が同じ色のものだけを使う
            if len(set(modifiers)) == 1:
                base = key("".join(chr(point) for point in points if point not in SKIN_TONES))
                tones.setdefault(base, {})[modifiers[0]] = text
            continue
        entries.append((group, text, version.lstrip("E"), name))
    return entries, tones


def read_azookey(path):
    words = {}
    for line in open(path, encoding="utf-8"):
        columns = line.rstrip("\n").split("\t")
        if len(columns) >= 2:
            words[key(columns[0])] = [word for word in columns[1].split(",") if word]
    return words


def read_shortcodes(path):
    codes = {}
    for entry in json.load(open(path, encoding="utf-8")):
        for field in ("unified", "non_qualified"):
            if entry.get(field):
                text = "".join(chr(int(code, 16)) for code in entry[field].split("-"))
                codes.setdefault(key(text), entry["short_names"])
    return codes


def read_unicode_names(path):
    names = {}
    for line in open(path, encoding="utf-8"):
        columns = line.split(";")
        if not columns[1].startswith("<"):
            names[chr(int(columns[0], 16))] = columns[1]
    return names


def read_kaomoji(source):
    """Mozc の顔文字を (文字, 読み, Mozc のまとまり) の並びにする．emoticon.tsv の並びのあとに categorized.tsv にだけある顔文字を置き，
    同じ顔文字の読みとまとまりはまとめる(まとまりは categorized.tsv を先にする)"""
    entries = {}
    order = []

    def add(text, readings, categories, first):
        if not text or len(text) > KAOMOJI_MAX_LENGTH or "\t" in text:
            return
        if text not in entries:
            entries[text] = ([], [])
            order.append(text)
        known_readings, known_categories = entries[text]
        # 読みはひらがなと長音にそろえる(「やだね～」→「やだねー」，「どうしましょう・・」→「どうしましょう」)
        readings = [reading.replace("～", "ー").replace("・", "") for reading in readings]
        known_readings.extend(reading for reading in readings if reading and reading not in known_readings)
        new = [category for category in categories if category not in known_categories]
        if first:
            known_categories[:0] = new
        else:
            known_categories.extend(new)

    # emoticon.tsv は「顔文字<タブ>読み(空白区切り)<タブ>まとまり(空白区切り)」．まとまりの無い行もある
    for line in open(f"{source}/emoticon.tsv", encoding="utf-8").read().splitlines()[1:]:
        columns = line.split("\t")
        if len(columns) >= 2:
            add(columns[0], columns[1].split(), columns[2].split() if len(columns) > 2 else [], first=False)
    # categorized.tsv は「顔文字<タブ>まとまり<タブ>読み」
    for line in open(f"{source}/categorized.tsv", encoding="utf-8").read().splitlines():
        if line.startswith("#"):
            continue
        columns = line.split("\t")
        if len(columns) >= 3:
            add(columns[0], columns[2].split(), columns[1].split(), first=True)
    return [(text, *entries[text]) for text in order if entries[text][0]]


def kaomoji_category(readings, mozc_categories):
    """顔文字のまとまり．動物・あいさつ(最初の読み)・Mozc のまとまり・読みの順に決める"""
    if any(reading in KAOMOJI_ANIMALS for reading in readings):
        return "animals"
    if readings and readings[0] in KAOMOJI_GREETINGS:
        return "greeting"
    for category in mozc_categories:
        if category in MOZC_KAOMOJI_CATEGORIES:
            return MOZC_KAOMOJI_CATEGORIES[category]
    for category, hints in KAOMOJI_HINTS:
        if any(reading in hints for reading in readings):
            return category
    return "otherFaces"


def read_symbols(path):
    """symbols.txt を (まとまり, 文字) の並びにする．同じ文字は最初のまとまりだけに置く"""
    result = []
    seen = set()
    for line in open(path, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        category, items = line.rstrip("\n").split("\t", 1)
        if category not in SYMBOL_CATEGORIES:
            sys.exit(f"知らないまとまり: {category}")
        for item in items.split():
            if item.startswith("U+") and ".." in item:
                start, end = item.split("..")
                characters = [chr(point) for point in range(int(start[2:], 16), int(end[2:], 16) + 1)]
            elif item.startswith("U+"):
                characters = [chr(int(item[2:], 16))]
            else:
                characters = [item]
            for character in characters:
                if character not in seen:
                    seen.add(character)
                    result.append((category, character))
    return result


def number_of(words):
    """英語の数の語(TWENTY ONE)を数にする．数でなければ None"""
    if words in NUMBER_WORDS:
        return NUMBER_WORDS[words]
    parts = words.split()
    if len(parts) == 2 and parts[0] in NUMBER_WORDS and parts[1] in NUMBER_WORDS and NUMBER_WORDS[parts[0]] % 10 == 0 and NUMBER_WORDS[parts[1]] < 10:
        return NUMBER_WORDS[parts[0]] + NUMBER_WORDS[parts[1]]
    return None


def generated_symbol_names(character, unicode_name):
    """CLDR に名前の無い記号の日本語の名前と読みを，Unicode の名前の形から作る"""
    name = unicode_name
    for prefix, label, readings in (
        ("DINGBAT NEGATIVE CIRCLED DIGIT ", "黒丸数字", ["くろまる", "まる"]),
        ("DINGBAT NEGATIVE CIRCLED NUMBER ", "黒丸数字", ["くろまる", "まる"]),
        ("NEGATIVE CIRCLED DIGIT ", "黒丸数字", ["くろまる", "まる"]),
        ("NEGATIVE CIRCLED NUMBER ", "黒丸数字", ["くろまる", "まる"]),
        ("CIRCLED DIGIT ", "丸数字", ["まる"]),
        ("CIRCLED NUMBER ", "丸数字", ["まる"]),
        ("PARENTHESIZED DIGIT ", "括弧数字", ["かっこ"]),
        ("PARENTHESIZED NUMBER ", "括弧数字", ["かっこ"]),
        ("SMALL ROMAN NUMERAL ", "小文字のローマ数字", ["ろーま"]),
        ("ROMAN NUMERAL ", "ローマ数字", ["ろーま"]),
    ):
        if name.startswith(prefix):
            number = number_of(name[len(prefix):])
            if number is not None:
                return f"{label}{number}", [head + number_reading(number) for head in readings] + [number_reading(number)]
    for suffix, label in ((" FULL STOP", "ピリオド付き数字"),):
        if name.endswith(suffix):
            number = number_of(name[: -len(suffix)].replace("DIGIT ", "").replace("NUMBER ", ""))
            if number is not None:
                return f"{label}{number}", [number_reading(number)]
    for prefix, label, head in (("SUPERSCRIPT ", "上付き", "うえつき"), ("SUBSCRIPT ", "下付き", "したつき")):
        if name.startswith(prefix):
            word = name[len(prefix):].replace("DIGIT ", "").replace("LATIN SMALL LETTER ", "")
            number = number_of(word)
            if number is not None:
                return f"{label}の{number}", [head + number_reading(number), number_reading(number)]
            if word in LETTERS:
                return f"{label}の{word.lower()}", [head + LETTERS[word], LETTERS[word]]
            signs = {"PLUS SIGN": ("＋", "ぷらす"), "MINUS": ("－", "まいなす"), "EQUALS SIGN": ("＝", "いこーる"),
                     "LEFT PARENTHESIS": ("（", "かっこ"), "RIGHT PARENTHESIS": ("）", "かっこ")}
            if word in signs:
                return f"{label}の{signs[word][0]}", [head + signs[word][1], signs[word][1]]
    if name.startswith("VULGAR FRACTION "):
        words = name[len("VULGAR FRACTION "):].split()
        numerator = number_of(words[0])
        denominator = FRACTIONS.get(words[-1])
        if numerator is not None and denominator:
            return f"{numerator}/{denominator}", [number_reading(denominator) + "ぶんの" + number_reading(numerator), "ぶんすう"]
    for prefix, label, head, small in (
        ("CIRCLED LATIN CAPITAL LETTER ", "丸英字", "まる", False),
        ("CIRCLED LATIN SMALL LETTER ", "丸英字", "まる", True),
        ("PARENTHESIZED LATIN SMALL LETTER ", "括弧英字", "かっこ", True),
    ):
        if name.startswith(prefix):
            letter = name[len(prefix):]
            if letter in LETTERS:
                return f"{label}{letter.lower() if small else letter}", [head + LETTERS[letter], LETTERS[letter]]
    for prefix, label, head in (("GREEK CAPITAL LETTER ", "大文字の", "おおもじの"), ("GREEK SMALL LETTER ", "", ""), ("GREEK ", "", "")):
        if name.startswith(prefix):
            words = name[len(prefix):].replace("FINAL ", "").replace(" SYMBOL", "").replace("LUNATE ", "").split()
            letter = words[-1]
            if letter in GREEK:
                reading = GREEK[letter]
                # 大文字は名前の読みを「おおもじの…」にし，読みだけで探したときは小文字を先に出す
                return f"{label}{to_katakana(reading)}", ([head + reading] if head else []) + [reading]
    if name.startswith("CYRILLIC "):
        return f"キリル文字の{character}", ["きりるもじ"]
    if name.startswith("BOX DRAWINGS "):
        return "罫線", ["けいせん"]
    if " BLOCK" in name or name.startswith("QUADRANT ") or name in ("LIGHT SHADE", "MEDIUM SHADE", "DARK SHADE"):
        return "ブロック", ["ぶろっく"]
    if unicodedata.normalize("NFKC", character) != character and name.startswith("SQUARE "):
        # 組文字(㎜ ㌔)の SQUARE は四角の形ではない
        return None, []
    words = f" {name.replace('-', ' ')} "
    for english, label, reading in ENGLISH_HINTS:
        if f" {english} " in words:
            return label, [reading]
    return None, []


def annotated_key(character, names):
    """CLDR の名前を引く鍵．全角の記号(，)は CLDR に無いので，半角の形(,)の名前を使う"""
    if key(character) in names:
        return key(character)
    folded = "".join(c for c in unicodedata.normalize("NFKC", character) if not unicodedata.combining(c)).strip()
    return key(folded) if folded in names else key(character)


def inner_text(character):
    """囲み文字や組文字の中の文字(㈱ → 株，㍉ → ミリ)．中身が日本語でなければ None"""
    inner = unicodedata.normalize("NFKC", character).strip("()")
    if inner != character and has_japanese(inner):
        return inner
    return None


def name_core(name):
    """名前の読みを求める部分．「旗: 日本」のように分類を前に付けた名前は，後ろの部分にする"""
    return name.split(": ", 1)[1] if ": " in name else name


def name_reading(name, transcriptions):
    """日本語の名前の読み(ひらがな)．求められなければ空"""
    core = name_core(name)
    if is_kana(core):
        return to_hiragana(core).replace("・", "")
    return transcriptions.get(core, "")


def split_japanese(words):
    """日本語の語を，かなだけの読みと，漢字を含むキーワードに分ける"""
    readings = []
    keywords = []
    for word in words:
        if is_kana(word):
            readings.append(to_hiragana(word).replace("・", ""))
        elif word:
            keywords.append(word)
    return readings, keywords


def collect(source, symbols_path):
    """読みを求める語(漢字を含む日本語の名前とキーワード)を集める"""
    ja_keywords, ja_names = read_annotations(f"{source}/ja.xml")
    derived_keywords, derived_names = read_annotations(f"{source}/ja_derived.xml")
    azookey = read_azookey(f"{source}/emoji_all_E17.0.txt")
    entries, _ = read_emoji_test(f"{source}/emoji-test.txt")
    words = set()
    for _, text, _, _ in entries:
        k = key(text)
        name = ja_names.get(k) or derived_names.get(k) or ""
        for word in [name, name_core(name)] + ja_keywords.get(k, derived_keywords.get(k, [])) + azookey.get(k, []):
            if word and not is_kana(word) and has_japanese(word):
                words.add(word)
    for _, character in read_symbols(symbols_path):
        k = annotated_key(character, ja_names)
        for word in [ja_names.get(k, "")] + ja_keywords.get(k, []) + [inner_text(character) or ""]:
            if word and not is_kana(word) and has_japanese(word):
                words.add(word)
    for word in sorted(words):
        print(word)


def read_curated_names(path):
    """names.txt を「文字 → (名前, 読み)」にする"""
    names = {}
    for line in open(path, encoding="utf-8"):
        if line.startswith("#") or not line.strip():
            continue
        character, name, readings = line.rstrip("\n").split("\t")
        names[character] = (name, [reading for reading in readings.split("|") if reading])
    return names


def read_transcriptions(path):
    readings = {}
    for line in open(path, encoding="utf-8"):
        columns = line.rstrip("\n").split("\t")
        if len(columns) == 2 and columns[1]:
            readings[columns[0]] = columns[1]
    return readings


def clean(values):
    return "|".join(unique(value.replace("|", " ").replace("\t", " ") for value in values))


def build(source, symbols_path, names_path, transcriptions_path, destination):
    ja_keywords, ja_names = read_annotations(f"{source}/ja.xml")
    en_keywords, en_names = read_annotations(f"{source}/en.xml")
    derived_ja_keywords, derived_ja_names = read_annotations(f"{source}/ja_derived.xml")
    derived_en_keywords, derived_en_names = read_annotations(f"{source}/en_derived.xml")
    azookey = read_azookey(f"{source}/emoji_all_E17.0.txt")
    shortcodes = read_shortcodes(f"{source}/emoji.json")
    unicode_names = read_unicode_names(f"{source}/UnicodeData.txt")
    transcriptions = read_transcriptions(transcriptions_path)
    curated = read_curated_names(names_path)
    entries, tones = read_emoji_test(f"{source}/emoji-test.txt")

    def reading_of(word):
        reading = transcriptions.get(word)
        return [reading] if reading else []

    lines = []
    for category, text, version, english in entries:
        k = key(text)
        name_ja = ja_names.get(k) or derived_ja_names.get(k) or ""
        name_en = en_names.get(k) or derived_en_names.get(k) or english
        japanese = [name_ja] + ja_keywords.get(k, derived_ja_keywords.get(k, [])) + [word for word in azookey.get(k, []) if has_japanese(word)]
        readings, keywords = split_japanese(japanese)
        for word in keywords:
            readings += reading_of(word)
        english_words = en_keywords.get(k, derived_en_keywords.get(k, [])) + [word for word in azookey.get(k, []) if word.isascii()]
        variants = [tones[k][tone] for tone in SKIN_TONES if tone in tones.get(k, {})] if len(tones.get(k, {})) == len(SKIN_TONES) else []
        lines.append(["emoji", category, text, version, name_ja, name_reading(name_ja, transcriptions), name_en, clean(readings), clean(keywords + [word.lower() for word in english_words]),
                      clean(shortcodes.get(k, [])), clean(variants), "cldr" if name_ja else ""])

    for category, character in read_symbols(symbols_path):
        k = annotated_key(character, ja_names)
        unicode_name = unicode_names.get(character, "")
        generated_name, generated_readings = generated_symbol_names(character, unicode_name)
        curated_name, curated_readings = curated.get(character, (None, []))
        if curated_name:
            generated_name, generated_readings = curated_name, []
        generated_readings = curated_readings + generated_readings
        name_ja = ja_names.get(k) or curated_name or generated_name or ""
        # 名前を定めたところ．CLDR の名前が無ければ，Hajime IME が付けた名前(names.txt か Unicode の名前の形から作った名前か中の文字)
        name_source = "cldr" if ja_names.get(k) else ("hajime" if name_ja or inner_text(character) else "")
        name_en = en_names.get(k) or unicode_name.lower()
        inner = inner_text(character)
        japanese = [name_ja] + ja_keywords.get(k, []) + ([inner] if inner else [])
        readings, keywords = split_japanese(japanese)
        for word in keywords:
            readings += reading_of(word)
        readings += generated_readings
        if not name_ja and inner:
            name_ja = inner
        # 名前の読み．CLDR の名前があればその読み，無ければ names.txt か Unicode の名前の形から作った読みの先頭
        reading = name_reading(name_ja, transcriptions) if ja_names.get(k) else (generated_readings[:1] or [name_reading(name_ja, transcriptions)])[0]
        english_words = en_keywords.get(k, []) + ([unicode_name.lower()] if unicode_name else [])
        lines.append(["symbol", category, character, "", name_ja, reading, name_en, clean(readings), clean(keywords + english_words), "", "", name_source])

    kaomoji = read_kaomoji(source)
    categorized = {category: [] for category in KAOMOJI_CATEGORIES}
    for text, readings, mozc_categories in kaomoji:
        # 名前は最初の読み．「よこおき」(横向きの顔文字)は形の説明なので，ほかの読みがあればそちらにする
        name = next((reading for reading in readings if reading not in KAOMOJI_DESCRIPTIVE_READINGS), readings[0])
        categorized[kaomoji_category(readings, mozc_categories)].append(
            ["kaomoji", None, text, "", name, name, "", clean(readings), "", "", "", ""])
    for category in KAOMOJI_CATEGORIES:
        for columns in categorized[category]:
            columns[1] = category
            lines.append(columns)

    with open(destination, "w", encoding="utf-8", newline="\n") as output:
        output.write("# 絵文字と記号のパレットの表．tools/palette/update.sh が作る．手で書き換えない\n")
        output.write("# 種類\tまとまり\t文字\t絵文字のバージョン\t日本語の名前\t名前の読み\t英語の名前\t読み\tキーワード\tショートコード\t肌の色の形\t名前の出どころ\n")
        for columns in lines:
            output.write("\t".join(columns) + "\n")
    print(f"絵文字 {len(entries)} 個，記号 {len(lines) - len(entries) - len(kaomoji)} 個，顔文字 {len(kaomoji)} 個", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "collect":
        collect(sys.argv[2], sys.argv[3])
    elif len(sys.argv) == 7 and sys.argv[1] == "build":
        build(*sys.argv[2:])
    else:
        sys.exit(__doc__)
