#!/usr/bin/env python3
"""公式サイトのトップページの説明用の画像(apps/docs-site/static/images/hero.webp，features/*.webp，catalog/*.webp)を作る．

Debug でビルドした Hajime Debug が書き出した画面(SnapshotRenderer)を切り抜き，色の面の上に置いて，
短いラベルと引き出し線を添えた HTML を組み，WKWebView(tools/site/render_html.swift)で描いて WebP にする．
候補ウィンドウや設定の見た目を変えたら作り直してコミットする．ImageMagick(magick)と cwebp が要る．

使い方:
  "<Debug のビルド>/Hajime Debug.app/Contents/MacOS/Hajime Debug" --render-snapshots
  python3 -I tools/site/make_site_images.py [書き出した画面のディレクトリ] [--only 名前,名前]
"""
import html
import pathlib
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
IMAGES = ROOT / "apps/docs-site/static/images"
DEFAULT_SNAPSHOTS = pathlib.Path.home() / "Library/Containers/men.haji.inputmethod.debug/Data/tmp/hajime-snapshots"

# 画像の大きさ(CSS のピクセル)．倍率 2 で描くので，書き出す画像はこの 2 倍になる
WIDTH, HEIGHT = 1000, 625
HERO_WIDTH, HERO_HEIGHT = 1200, 560
SCALE = 2
QUALITY = 84

# 色．ロゴの朝日(朱)と階段(藍・藤)からとり，若草と山吹を足した
SHU = "#E4533B"
AI = "#34399C"
FUJI = "#6F56CF"
YORU = "#15172E"
WAKAKUSA = "#178F7C"
YAMABUKI = "#EFA63A"
BENI = "#B4396A"
SORA = "#2C6BCB"
PAPER = "#F4F5FA"
INK = "#15172E"

STYLE = f"""
* {{ box-sizing: border-box; }}
html, body {{ margin: 0; }}
body {{ position: relative; overflow: hidden; font-family: "Hiragino Sans", sans-serif; color: {INK};
  -webkit-font-smoothing: antialiased; background: var(--bg); }}
.sun {{ position: absolute; border-radius: 50%; background: var(--sun); }}
.ui {{ position: absolute; filter: drop-shadow(0 18px 28px rgba(8, 10, 30, .38)); }}
.label {{ position: absolute; transform: translate(-50%, -50%); white-space: nowrap; padding: 8px 18px 7px; border-radius: 999px;
  background: #fff; color: {INK}; font-size: 23px; font-weight: 600; letter-spacing: .02em;
  box-shadow: 0 6px 14px rgba(8, 10, 30, .22); }}
.label.dark {{ background: {INK}; color: #fff; }}
svg.lines {{ position: absolute; inset: 0; width: 100%; height: 100%; }}
svg.lines path {{ fill: none; stroke: var(--line, #fff); stroke-width: 3; stroke-linecap: round; }}
svg.lines circle {{ fill: var(--line, #fff); }}
.keys {{ position: absolute; display: flex; gap: 8px; align-items: center; transform: translate(-50%, -50%); white-space: nowrap;
  color: var(--note, #fff); font-size: 23px; font-weight: 600; }}
kbd {{ display: inline-grid; place-items: center; min-width: 46px; height: 46px; padding: 0 12px; border-radius: 11px;
  background: #fff; color: {INK}; font: 600 22px "Hiragino Sans", sans-serif;
  box-shadow: 0 3px 0 rgba(8, 10, 30, .28), 0 8px 14px rgba(8, 10, 30, .18); }}
.field {{ position: absolute; border-radius: 18px; background: {PAPER}; color: {INK};
  box-shadow: 0 18px 30px rgba(8, 10, 30, .3); padding: 22px 28px; font-size: 34px; font-weight: 600; white-space: nowrap; }}
.field .marked {{ border-bottom: 3px solid {AI}; padding-bottom: 2px; }}
.field .caret {{ display: inline-block; width: 3px; height: 1.1em; margin-left: 3px; vertical-align: -0.16em; background: {AI}; }}
.field .wrong {{ color: #9a9db3; text-decoration: line-through; text-decoration-thickness: 3px; }}
.typed {{ position: absolute; transform: translate(-50%, -50%); white-space: nowrap; font: 500 25px "SF Mono", "Menlo", monospace;
  color: var(--note, #fff); letter-spacing: .04em; opacity: .92; }}
.arrow {{ position: absolute; transform: translate(-50%, -50%); font-size: 30px; font-weight: 700; color: var(--note, #fff); }}
.row {{ position: absolute; display: flex; align-items: center; gap: 16px; white-space: nowrap; }}
.chip {{ border-radius: 14px; background: {PAPER}; color: {INK}; padding: 12px 20px; font-size: 26px; font-weight: 600;
  box-shadow: 0 10px 18px rgba(8, 10, 30, .22); }}
.chip.in {{ background: {INK}; color: #fff; font-family: "SF Mono", "Menlo", "Hiragino Sans", monospace; font-weight: 500; }}
.row .to {{ font-size: 26px; font-weight: 700; color: var(--note, #fff); }}
.app {{ position: absolute; width: 250px; height: 300px; border-radius: 22px; background: {PAPER};
  box-shadow: 0 18px 30px rgba(8, 10, 30, .3); display: grid; justify-items: center; align-content: center; gap: 22px; }}
.app .bar {{ position: absolute; left: 18px; top: 16px; display: flex; gap: 7px; }}
.app .bar i {{ width: 11px; height: 11px; border-radius: 50%; background: #cfd2e2; }}
.app .name {{ font-size: 22px; font-weight: 600; color: {INK}; }}
.app .mode {{ width: 104px; height: 104px; border-radius: 26px; background: {INK}; color: #fff; display: grid; place-items: center;
  font-size: 56px; font-weight: 700; }}
.app .state {{ font-size: 18px; font-weight: 600; color: #6a6e8c; }}

/* 「そのほかの機能」の小さな画像．ページでは幅 300px ほどで出るので，部品を大きく描いて真ん中に積む */
body.catalog {{ display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 38px; padding-bottom: 76px; }}
.crow {{ position: relative; display: flex; align-items: center; justify-content: center; gap: 22px; }}
.cchip {{ border-radius: 24px; background: {PAPER}; color: {INK}; padding: 20px 34px 18px; font-size: 58px; font-weight: 600; white-space: nowrap;
  box-shadow: 0 14px 24px rgba(4, 6, 24, .35); }}
.cchip.in {{ background: rgba(255, 255, 255, .13); color: #fff; box-shadow: inset 0 0 0 3px rgba(255, 255, 255, .34);
  font-family: "SF Mono", "Menlo", "Hiragino Sans", monospace; font-weight: 500; }}
.cchip.dim {{ opacity: .42; box-shadow: none; }}
.cchip.ring {{ box-shadow: 0 0 0 7px var(--sun), 0 14px 24px rgba(4, 6, 24, .35); }}
.cchip.marked {{ text-decoration: underline; text-decoration-thickness: 5px; text-underline-offset: 12px; text-decoration-color: {AI}; }}
.s .cchip, .cchip.s {{ font-size: 48px; padding: 17px 28px 15px; border-radius: 20px; }}
.xs .cchip, .cchip.xs {{ font-size: 40px; padding: 15px 24px 13px; border-radius: 18px; }}
.cto {{ font-size: 58px; font-weight: 700; color: #fff; }}
.ckbd {{ display: grid; place-items: center; min-width: 100px; height: 100px; padding: 0 26px; border-radius: 22px; background: #fff; color: {INK};
  font-size: 48px; font-weight: 600; box-shadow: 0 7px 0 rgba(4, 6, 24, .45), 0 16px 24px rgba(4, 6, 24, .3); }}
.ckbd.s {{ min-width: 92px; height: 92px; font-size: 40px; padding: 0 18px; border-radius: 20px; }}
.cplus {{ font-size: 50px; font-weight: 600; color: #fff; }}
.cnote {{ font-size: 48px; font-weight: 600; color: #fff; white-space: nowrap; }}
.ccol {{ display: flex; flex-direction: column; align-items: center; gap: 16px; }}
.ccol .cnote {{ font-size: 40px; opacity: .9; }}
.cui {{ position: relative; filter: drop-shadow(0 18px 28px rgba(4, 6, 24, .45)); }}
"""


def run(*command, **kwargs):
    return subprocess.run([str(part) for part in command], check=True, capture_output=True, text=True, **kwargs).stdout


class Builder:
    def __init__(self, snapshots: pathlib.Path, work: pathlib.Path):
        self.snapshots = snapshots
        self.work = work
        self.sizes = {}
        self.renderer = work / "render_html"
        run("swiftc", "-O", "-o", self.renderer, ROOT / "tools/site/render_html.swift")

    def cutout(self, name: str, keep_background: bool = False) -> pathlib.Path:
        """窓の外の背景(四隅とつながった同じ色)を透明にした画像．大きさ(CSS のピクセル)も覚える"""
        output = self.work / f"{name}.png"
        if not output.exists():
            source = self.snapshots / f"{name}.png"
            w, h = (int(v) for v in run("magick", "identify", "-format", "%w %h", source).split())
            if keep_background:
                run("magick", source, output)
            else:
                run("magick", source, "-alpha", "set", "-fuzz", "4%", "-fill", "none",
                    "-draw", "color 0,0 floodfill", "-draw", f"color {w - 1},0 floodfill",
                    "-draw", f"color 0,{h - 1} floodfill", "-draw", f"color {w - 1},{h - 1} floodfill", "-trim", "+repage", output)
            w, h = (int(v) for v in run("magick", "identify", "-format", "%w %h", output).split())
            self.sizes[name] = (w / 2, h / 2)
        return output

    def ui(self, name: str, x: float, y: float, width: float, keep_background: bool = False, radius: float = 0):
        """画面を左上 (x, y)，幅 width で置く．返すのは HTML と，画面の中の割合を座標にする関数"""
        path = self.cutout(name, keep_background)
        w, h = self.sizes[name]
        height = width * h / w
        style = f"left:{x}px;top:{y}px;width:{width}px;" + (f"border-radius:{radius}px;" if radius else "")
        tag = f'<img class="ui" src="{path.as_uri()}" style="{style}">'
        return tag, (lambda fx, fy: (x + width * fx, y + height * fy)), height

    def render(self, name: str, body: str, background: str, sun: str, width=WIDTH, height=HEIGHT, extra_style: str = "", hero=False,
               directory: str = "features", scale: float = SCALE, body_class: str = ""):
        page = self.work / f"{name}.html"
        page.write_text(
            f'<!doctype html><meta charset="utf-8"><style>{STYLE}{extra_style}</style>'
            f'<body class="{body_class}" style="width:{width}px;height:{height}px;--bg:{background};--sun:{sun}">{body}</body>',
            encoding="utf-8")
        png = self.work / f"{name}-out.png"
        run(self.renderer, page, png, width, height, scale)
        target = IMAGES / "hero.webp" if hero else IMAGES / directory / f"{name}.webp"
        target.parent.mkdir(parents=True, exist_ok=True)
        run("cwebp", "-quiet", "-q", QUALITY, png, "-o", target)
        print(f"作りました: {target.relative_to(ROOT)}")


def sun(x, y, diameter):
    return f'<div class="sun" style="left:{x - diameter / 2}px;top:{y - diameter / 2}px;width:{diameter}px;height:{diameter}px"></div>'


def label(text, x, y, dark=False):
    return f'<div class="label{" dark" if dark else ""}" style="left:{x}px;top:{y}px">{html.escape(text)}</div>'


def lines(*segments, width=WIDTH, height=HEIGHT):
    """引き出し線．(ラベルの側の点, 指す先の点) を並べる．指す先に丸を付ける"""
    parts = []
    for (x1, y1), (x2, y2) in segments:
        parts.append(f'<path d="M{x1:.1f} {y1:.1f} L{x2:.1f} {y2:.1f}"/><circle cx="{x2:.1f}" cy="{y2:.1f}" r="6"/>')
    return f'<svg class="lines" viewBox="0 0 {width} {height}">{"".join(parts)}</svg>'


def keys(items, x, y, note=""):
    """キーキャップの並び．"+" はキーのあいだの記号としてそのまま出す"""
    caps = "".join(f"<span>{item}</span>" if item == "+" else f"<kbd>{html.escape(item)}</kbd>" for item in items)
    tail = f"<span style='margin-left:6px'>{html.escape(note)}</span>" if note else ""
    return f'<div class="keys" style="left:{x}px;top:{y}px">{caps}{tail}</div>'


def typed(text, x, y):
    return f'<div class="typed" style="left:{x}px;top:{y}px">{html.escape(text)}</div>'


def arrow(x, y, glyph="↓"):
    return f'<div class="arrow" style="left:{x}px;top:{y}px">{glyph}</div>'


def conversion(source, result, x, y):
    return (f'<div class="row" style="left:{x}px;top:{y}px"><span class="chip in">{html.escape(source)}</span>'
            f'<span class="to">→</span><span class="chip">{html.escape(result)}</span></div>')


def app(name, mode, state, x, y):
    return (f'<div class="app" style="left:{x}px;top:{y}px"><div class="bar"><i></i><i></i><i></i></div>'
            f'<div class="name">{html.escape(name)}</div><div class="mode">{html.escape(mode)}</div>'
            f'<div class="state">{html.escape(state)}</div></div>')


def field(inner, x, y):
    """入力欄．x が None なら左右の真ん中に置く"""
    position = "left:50%;transform:translateX(-50%);" if x is None else f"left:{x}px;"
    return f'<div class="field" style="{position}top:{y}px">{inner}</div>'


def scenes(b: Builder):
    out = {}

    def hero():
        w, h = HERO_WIDTH, HERO_HEIGHT
        tag, at, _ = b.ui("branch-station-hold-glass-dark", 250, 110, 640)
        body = sun(1010, 520, 760) + tag
        kinds, clause, candidate, station = at(0.31, 0.03), at(0.02, 0.283), at(0.165, 0.678), at(0.75, 0.578)
        body += lines(((kinds[0], 62), kinds), ((140, clause[1]), clause), ((140, candidate[1]), candidate), ((1040, station[1]), station),
                      width=w, height=h)
        body += label("文字種", kinds[0], 62) + label("文節", 140, clause[1]) + label("候補", 140, candidate[1])
        body += label("意味・連想・マクロ", 1040, station[1])
        body += keys(["←", "→", "↑", "↓"], 1010, 523, "で選択")
        b.render("hero", body, YORU, SHU, width=w, height=h, hero=True)
    out["hero"] = hero

    def live():
        body = sun(170, 80, 520)
        body += typed("kaerini ekimaeno kafeni yotte", 500, 178) + arrow(500, 232)
        body += field('<span class="marked">帰りに駅前のカフェに寄って</span><span class="caret"></span>', None, 272)
        body += keys(["Enter"], 500, 440, "で確定")
        b.render("live-conversion", body, SHU, "#EE6E57")
    out["live-conversion"] = live

    def tree():
        tag, at, _ = b.ui("branch-trunk-glass-dark", 230, 128, 600)
        body = sun(880, 560, 600) + tag
        kinds, clause, candidate = at(0.55, 0.03), at(0.022, 0.305), at(0.305, 0.735)
        body += lines(((kinds[0], 76), kinds), ((120, clause[1]), clause), ((120, candidate[1]), candidate))
        body += label("文字種", kinds[0], 76) + label("文節", 120, clause[1]) + label("候補", 120, candidate[1])
        body += keys(["←", "→", "↑", "↓"], 770, 562, "で移動")
        b.render("candidate-tree", body, AI, "#474DC0")
    out["candidate-tree"] = tree

    def listing():
        tag, at, _ = b.ui("list-glass-dark", 250, 75, 440)
        body = sun(140, 520, 520) + tag
        kinds, candidate = at(0.945, 0.105), at(0.945, 0.385)
        body += lines(((820, kinds[1]), kinds), ((820, candidate[1]), candidate))
        body += label("文字種", 820, kinds[1]) + label("候補", 820, candidate[1])
        body += keys(["Space"], 840, 500, "で次の候補")
        b.render("candidate-list", body, WAKAKUSA, "#21A791")
    out["candidate-list"] = listing

    def suggestion():
        left, at_left, _ = b.ui("suggestion-glass-dark", 130, 215, 360)
        right, at_right, _ = b.ui("prediction-glass-dark", 560, 300, 330)
        top_left, top_right = at_left(0.5, 0.03), at_right(0.5, 0.06)
        body = sun(860, 90, 480) + left + right
        body += lines(((top_left[0], 150), top_left), ((top_right[0], 235), top_right))
        body += label("入力中の候補", top_left[0], 150) + label("予測", top_right[0], 235)
        body += keys(["Tab"], top_right[0], 480, "で確定")
        extra = f"body {{ --note: {INK}; --line: {INK}; }}"
        b.render("suggestion-prediction", body, YAMABUKI, "#F6BD63", extra_style=extra)
    out["suggestion-prediction"] = suggestion

    def typo():
        body = sun(850, 520, 560)
        body += field('<span class="wrong">ありがぷございます</span>', None, 120)
        body += arrow(500, 268)
        body += field('ありがとうございます<span class="caret"></span>', None, 315)
        body += keys(["Esc"], 500, 490, "で復元")
        b.render("typo-correction", body, FUJI, "#836CDD")
    out["typo-correction"] = typo

    def english():
        tag, at, _ = b.ui("correction-glass-dark", 250, 196, 420)
        row = at(0.955, 0.275)
        body = sun(120, 110, 460) + field('<span class="marked">python</span><span class="caret"></span>', 250, 76) + tag
        body += lines(((820, row[1]), row))
        body += label("英単語と判定", 820, row[1])
        b.render("english-words", body, BENI, "#C75182")
    out["english-words"] = english

    def meaning():
        tag, at, _ = b.ui("homophone-list-glass-dark", 70, 160, 760)
        sense, example, homophones = at(0.76, 0.245), at(0.745, 0.535), at(0.8, 0.755)
        body = sun(860, 560, 560) + tag
        body += lines(((915, sense[1]), sense), ((915, example[1]), example), ((915, homophones[1]), homophones))
        body += label("意味", 915, sense[1]) + label("用例", 915, example[1]) + label("同音語", 915, homophones[1])
        b.render("meaning", body, YORU, AI)
    out["meaning"] = meaning

    def association():
        tag, at, _ = b.ui("branch-station-association-hold-glass-dark", 150, 100, 600)
        station, word = at(0.635, 0.43), at(0.975, 0.75)
        inside = at(0.635, 0.25)
        body = sun(120, 560, 520) + tag
        body += lines((inside, station), ((880, word[1]), word))
        body += label("連想", inside[0], inside[1]) + label("類義語", 880, word[1])
        b.render("association", body, "#0E7C86", "#1B97A1")
    out["association"] = association

    def utilities():
        body = sun(900, 90, 480)
        body += conversion("1+2*3=", "7", 130, 118) + conversion("100-0001", "東京都千代田区千代田", 130, 228)
        body += conversion("きょう", "2026/11/14", 130, 338) + conversion("21", "㉑　二一　弐拾壱　ⅩⅩⅠ", 130, 448)
        b.render("date-conversion", body, "#D5762A", "#E39145")
    out["date-conversion"] = utilities

    def palette():
        left, _, _ = b.ui("palette-kaomoji-glass-dark", 90, 150, 270)
        middle, _, _ = b.ui("palette-emoji-glass-dark", 350, 75, 300)
        right, _, _ = b.ui("palette-symbol-glass-dark", 640, 150, 270)
        body = sun(500, 660, 700) + left + right + middle
        body += label("顔文字", 225, 112) + label("絵文字", 500, 40) + label("記号", 775, 112)
        body += keys(["⌃", "⌥", "F"], 225, 575) + keys(["⌃", "⌥", "E"], 500, 575) + keys(["⌃", "⌥", "K"], 775, 575)
        b.render("palette", body, "#C13D63", "#D65C7F")
    out["palette"] = palette

    def handwriting():
        tag, at, _ = b.ui("handwriting-dark", 250, 78, 400, keep_background=True, radius=18)
        chips = at(0.035, 0.912)
        body = sun(850, 540, 560) + tag
        body += lines(((130, chips[1]), chips))
        body += label("候補", 130, chips[1])
        body += keys(["⌃", "⌥", "H"], 810, 300)
        b.render("handwriting", body, YORU, SORA)
    out["handwriting"] = handwriting

    def themes():
        names = [("washi", "和紙"), ("neon", "ネオン"), ("nordic", "北欧"), ("terminal", "ターミナル"), ("indigo", "インディゴ"), ("desk", "夜のデスク")]
        body = sun(880, 80, 480)
        for index, (theme, name) in enumerate(names):
            column, line = index % 3, index // 3
            x, y = 50 + column * 308, 36 + line * 292
            tag, _, height = b.ui(f"branch-hold-{theme}", x, y, 284)
            body += tag + label(name, x + 142, y + height + 34, dark=True)
        b.render("themes", body, "#E6E8F2", "#D3D7EC")
    out["themes"] = themes

    def app_modes():
        body = sun(140, 100, 480)
        body += app("ターミナル", "A", "英数", 95, 162) + app("メモ", "あ", "日本語", 375, 162) + app("ブラウザ", "あ", "日本語", 655, 162)
        b.render("app-modes", body, SORA, "#4583DD")
    out["app-modes"] = app_modes

    def offline():
        cloud = ('<svg style="position:absolute;left:640px;top:215px" width="230" height="190" viewBox="0 0 230 190" fill="none">'
                 '<path d="M62 150a44 44 0 0 1-6-87 62 62 0 0 1 119-12 50 50 0 0 1-4 99z" stroke="#fff" stroke-width="9" stroke-linejoin="round" opacity=".9"/>'
                 '<path d="M30 172 200 22" stroke="#fff" stroke-width="11" stroke-linecap="round"/></svg>')
        device = (f'<div class="app" style="left:130px;top:150px;width:380px;height:320px;align-content:center;gap:16px">'
                  f'<div class="bar"><i></i><i></i><i></i></div>'
                  + "".join(f'<div class="chip in" style="font-family:\'Hiragino Sans\';font-weight:600;font-size:24px;padding:10px 34px">{name}</div>'
                            for name in ("変換", "補正", "学習")) + "</div>")
        body = sun(880, 120, 520) + device + cloud
        body += label("端末内で完結", 320, 110) + label("通信なし", 755, 450)
        b.render("offline", body, "#1D7A4F", "#2C9565")
    out["offline"] = offline

    return out


# 「そのほかの機能」の分類ごとの色(朝日の色)．背景は夜の色でそろえる
CATALOG_BACKGROUND = "#1A1C39"
CATALOG_SUNS = {"input": AI, "conversion": SHU, "correction": FUJI, "language": BENI, "dictionary": WAKAKUSA, "settings": SORA}


def crow(*parts, size=""):
    return f'<div class="crow {size}">{"".join(parts)}</div>'


def cchip(text, kind=""):
    return f'<span class="cchip {kind}">{html.escape(text)}</span>'


def cto(glyph="→"):
    return f'<span class="cto">{glyph}</span>'


def cconv(source, result, size=""):
    return crow(cchip(source, "in"), cto(), cchip(result), size=size)


def ckbd(*names, small=False):
    parts = []
    for name in names:
        parts.append('<span class="cplus">+</span>' if name == "+" else f'<span class="ckbd{" s" if small else ""}">{html.escape(name)}</span>')
    return "".join(parts)


def cnote(text):
    return f'<span class="cnote">{html.escape(text)}</span>'


def ccol(top, caption):
    return f'<div class="ccol">{top}{cnote(caption)}</div>'


def catalog_scenes(b: Builder):
    out = {}

    # 朝日は下の端から少しだけ出す(真ん中に積んだ部品と重ならないように)
    def add(name, group, *rows, sun_at=(500, 1020, 980)):
        def make():
            body = sun(*sun_at) + "".join(rows)
            b.render(name, body, CATALOG_BACKGROUND, CATALOG_SUNS[group], directory="catalog", scale=1, body_class="catalog")
        out[name] = make

    def flow_ui(name, width, keep_background=False, radius=0):
        path = b.cutout(name, keep_background)
        style = f"width:{width}px;" + (f"border-radius:{radius}px;" if radius else "")
        return f'<img class="cui" src="{path.as_uri()}" style="{style}">'

    # 入力
    add("input-styles", "input", crow(cchip("ローマ字"), cchip("かな")), crow(cchip("英字"), cchip("英字(自動)")))
    add("key-layouts", "input", crow(cchip("US"), cchip("Dvorak"), cchip("Colemak"), size="s"))
    add("punctuation", "input", crow(cchip("、。"), cchip("，．"), cchip("、．"), cchip("，。"), size="s"), crow(ckbd("[", "]", "/", "¥")))
    add("shift-english", "input", crow(ckbd("Shift", "+", "H"), cto(), cchip("Hello")))
    add("number-punctuation", "input", crow(cchip("3.14"), cchip("1,000"), cchip("A-1")))
    add("numpad-calc", "input", cconv("12*3", "36"), crow(ckbd("Enter")))
    add("romaji-table", "input", cconv("wyi", "ゐ"), cconv("->", "→"))

    # 変換
    add("segments", "conversion", flow_ui("branch-split-glass-dark", 780))
    add("grid", "conversion", flow_ui("list-grid-glass-dark", 390))
    add("undo", "conversion", crow(ckbd("Esc"), cnote("× 8")))
    add("undo-commit", "conversion", crow(ckbd("⌃", "+", "⌫")), crow(cchip("今日は雷"), cto(), cchip("今日は雷", "marked")))
    add("uncertain", "conversion", crow(ckbd("⌥", "+", "→")), crow(cchip("今日は", "dim"), cchip("公園で", "ring"), cchip("遊ぶ", "dim")))
    add("context", "conversion", crow(cchip("Pythonでプログラムをかこう", "in"), size="xs"), crow(cchip("書こう", "ring"), cchip("加工", "dim")))
    add("reconvert", "conversion", crow(ckbd("⌃", "+", "⇧", "+", "R")), crow(cchip("貴社"), cto(), cchip("記者", "marked")))
    add("script-keys", "conversion", crow(*[ccol(ckbd(key, small=True), kind) for key, kind in
                                          (("F6", "あ"), ("F7", "ア"), ("F8", "ｱ"), ("F9", "Ａ"), ("F10", "A"))], size="s"))
    add("number-forms", "conversion", cconv("21", "㉑"), crow(cchip("二一"), cchip("弐拾壱"), cchip("ⅩⅩⅠ"), size="s"))
    add("proofreading", "conversion", cconv("見れる", "見られる", size="s"), cconv("頭痛が痛い", "頭痛がする", size="s"))
    add("okurigana", "conversion", crow(ccol(cchip("行う"), "本則"), ccol(cchip("行なう"), "許容")))
    add("learning", "conversion", crow(cchip("雷"), cchip("神鳴り", "dim"), cchip("カミナリ", "dim"), size="s"), crow(ckbd("⌃", "+", "⌫"), cnote("で削除")))
    add("prediction-manage", "conversion", flow_ui("prediction-glass-dark", 620), crow(ckbd("⌫"), cnote("で読みに復帰")))
    add("zenzai", "conversion", crow(cchip("精度優先"), cchip("速度優先"), cchip("併用"), size="s"))

    # 補正
    add("double-key", "correction", crow(cchip("koonnnitiha", "in")), cto("↓"), crow(cchip("こんにちは")))
    add("misreading", "correction", cconv("ふいんき", "雰囲気"))
    add("katakana", "correction", crow(cchip("しゅみれーしょん", "in")), cto("↓"), crow(cchip("シミュレーション")))
    add("phonetic", "correction", cconv("ふぉと", "photo"))
    add("hand-shift", "correction", crow(cchip("lpmmoyojs", "in")), cto("↓"), crow(cchip("こんにちは")))
    add("exclusions", "correction", cconv("pthon", "Python3"))

    # 英語と日本語
    add("loanwords", "language", cconv("れっどはっと", "Red Hat", size="s"), cconv("にゅーらる", "neural", size="s"))
    add("previous-word", "language", cconv("npm make", "make", size="s"), cconv("試合に make", "負け", size="s"))
    add("english-japanese-words", "language", crow(cchip("sake", "in")), crow(ccol(cchip("sake"), "英語"), ccol(cchip("酒"), "日本語")))

    # 辞書・マクロ・コマンド
    add("user-dictionary", "dictionary", cconv("gh", "GitHub"))
    add("placeholders", "dictionary", cconv("{date}", "2026/11/14", size="s"), cconv("{uuid}", "3f2a9c1e-…", size="s"))
    add("import", "dictionary", crow(cchip("SKK", "in"), cchip("ほかの IME", "in"), size="s"), cto("↓"), crow(cchip("ユーザー辞書")))
    add("technical-terms", "dictionary", crow(cchip("医学"), cchip("法律"), cchip("情報技術")))
    add("macros", "dictionary", cconv("東京", "【東京】"), crow(cchip("東京（とうきょう）"), cchip("**東京**"), size="s"))
    add("commands", "dictionary", flow_ui("command-list-glass-dark", 680))

    # 設定と更新
    add("keymap", "settings", crow(cchip("標準"), cchip("Windows 風"), cchip("Mac 風"), size="s"),
        crow(cchip("ATOK 風"), cchip("Emacs 風"), cchip("Vim 風"), size="s"))
    add("sync", "settings", crow(cchip("Mac"), cto("⇄"), cchip("Windows")), crow(cchip("Dropbox"), cchip("Google Drive"), cchip("iCloud Drive"), size="xs"))
    add("onboarding", "settings", flow_ui("onboarding-features-dark", 780, keep_background=True, radius=20))
    add("updates", "settings", crow(cchip("変更点を確認", "in"), cto(), cchip("更新"), size="s"))

    return out


def main():
    arguments = [a for a in sys.argv[1:] if not a.startswith("--")]
    only = next((a.split("=", 1)[1].split(",") for a in sys.argv[1:] if a.startswith("--only=")), None)
    snapshots = pathlib.Path(arguments[0]) if arguments else DEFAULT_SNAPSHOTS
    with tempfile.TemporaryDirectory() as work:
        builder = Builder(snapshots, pathlib.Path(work))
        for name, make in {**scenes(builder), **catalog_scenes(builder)}.items():
            if only is None or name in only:
                make()


if __name__ == "__main__":
    main()
