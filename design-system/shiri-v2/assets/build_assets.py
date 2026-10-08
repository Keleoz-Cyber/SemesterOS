"""拾日 · 晴日 v2 矢量资源生成器。

生成 illustrations/、icons/、patterns/wave-hero.svg。所有图形只用 Flutter (flutter_svg) 支持的元素：
path/rect/circle/ellipse/line/g/defs/linearGradient/radialGradient/clipPath，不用 filter/mask/pattern/style/text。
日历卡、太阳、波浪的几何比例直接取自 apps/mobile/assets/brand/app_icon.svg。

运行：python build_assets.py   （在本文件所在目录）
"""
import math
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
PRIMARY, SOFT = "#2E6FE0", "#8DC2FF"
SKY, CYAN, MINT = "#4CA4FF", "#63CFE9", "#8DE0B2"
SUN1, SUN2 = "#FFEBA6", "#F6C86B"
COURSE = {"sky": ("#E8F2FF", "#4A90F0"), "mint": ("#E4F6EF", "#3DBE8B"), "lilac": ("#EFECFF", "#8C7BF0"),
          "apricot": ("#FFF0E6", "#F39A62"), "blossom": ("#FDECF2", "#E7779D"), "aqua": ("#E3F6FA", "#33B5CF")}


def f(v):
    return f"{v:.1f}".rstrip("0").rstrip(".")


# ---------------------------------------------------------------- 共享 defs
DEFS = f"""
<linearGradient id="brand" x1="0" y1="0" x2="1" y2="1"><stop stop-color="{SKY}"/><stop offset=".52" stop-color="{CYAN}"/><stop offset="1" stop-color="{MINT}"/></linearGradient>
<linearGradient id="brandH" x1="0" y1="0" x2="1" y2="0"><stop stop-color="{SKY}"/><stop offset=".52" stop-color="{CYAN}"/><stop offset="1" stop-color="{MINT}"/></linearGradient>
<linearGradient id="sun" x1="0" y1="0" x2=".6" y2="1"><stop stop-color="{SUN1}"/><stop offset="1" stop-color="{SUN2}"/></linearGradient>
<radialGradient id="sunGlow"><stop stop-color="#FFE9A8" stop-opacity=".75"/><stop offset="1" stop-color="#FFE9A8" stop-opacity="0"/></radialGradient>
<radialGradient id="halo"><stop stop-color="#E3F0FF" stop-opacity=".95"/><stop offset=".7" stop-color="#EEF6FF" stop-opacity=".5"/><stop offset="1" stop-color="#F3F7FC" stop-opacity="0"/></radialGradient>
<linearGradient id="card" x1="0" y1="0" x2=".7" y2="1"><stop stop-color="#E9F6FF"/><stop offset=".58" stop-color="#D5ECFA"/><stop offset="1" stop-color="#D5F1EC"/></linearGradient>
<linearGradient id="tab" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#69B8F7"/><stop offset="1" stop-color="#408FF3"/></linearGradient>
<linearGradient id="line1" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#9CE7C9"/><stop offset="1" stop-color="#60D2D2"/></linearGradient>
<linearGradient id="line2" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#B9E8F7"/><stop offset="1" stop-color="#74B8F3"/></linearGradient>
<linearGradient id="paper" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#EEF5FD"/></linearGradient>
<linearGradient id="mintG" x1="0" y1="0" x2="1" y2="1"><stop stop-color="#9CE7C9"/><stop offset="1" stop-color="#3FBF8F"/></linearGradient>
<linearGradient id="wave1" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#D5EFEA"/><stop offset="1" stop-color="#D8EAFB"/></linearGradient>
<linearGradient id="wave2" x1="0" y1="0" x2="1" y2="0"><stop stop-color="#CFEDE9"/><stop offset="1" stop-color="#CDE2F8"/></linearGradient>
<linearGradient id="cloud" x1="0" y1="0" x2="0" y2="1"><stop stop-color="#FFFFFF"/><stop offset="1" stop-color="#E4F0FD"/></linearGradient>
"""


def svg(w, h, body, extra_defs=""):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}" fill="none">'
            f'<defs>{DEFS}{extra_defs}</defs>{body}</svg>\n')


# ---------------------------------------------------------------- 图形部件
def halo(cx, cy, r):
    return f'<g id="bg"><circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="url(#halo)"/></g>'


def ground(cx, cy, rx, ry=6):
    return f'<ellipse id="ground" cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}" fill="#142238" fill-opacity=".07"/>'


WAVE_BACK = [(0, .1495), (.1103, 0, .2316, .0514, .3529, .2617), (.4706, .4673, .5895, .5841, .6973, .5),
             (.8088, .4112, .9007, .1776, 1, .1308)]
WAVE_FRONT = [(0, .4907), (.1299, .215, .2831, .2523, .4326, .4766), (.5392, .6402, .6434, .757, .7537, .7009),
              (.8615, .6449, .9412, .4393, 1, .3785)]


def wave_path(spec, x, y, w, h):
    p = f"M{f(x + spec[0][0] * w)} {f(y + spec[0][1] * h)}"
    for c in spec[1:]:
        p += "C" + " ".join(f"{f(x + c[i] * w)} {f(y + c[i + 1] * h)}" for i in range(0, 6, 2))
    return p + f"V{f(y + h)}H{f(x)}Z"


def waves(x, y, w, h, clip_id=None):
    clip = f' clip-path="url(#{clip_id})"' if clip_id else ""
    return (f'<g id="wave"{clip}><path d="{wave_path(WAVE_BACK, x, y, w, h)}" fill="url(#wave1)" fill-opacity=".82"/>'
            f'<path d="{wave_path(WAVE_FRONT, x, y, w, h)}" fill="url(#wave2)" fill-opacity=".88"/></g>')


def island_clip(cid, cx, cy, rx, ry):
    return f'<clipPath id="{cid}"><ellipse cx="{f(cx)}" cy="{f(cy)}" rx="{f(rx)}" ry="{f(ry)}"/></clipPath>'


def sun(cx, cy, r, glow=True, rays=True, highlight=False):
    out = '<g id="sun">'
    if glow:
        out += f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r * 2.1)}" fill="url(#sunGlow)"/>'
    if rays:
        for deg in (-125, -90, -55):
            a = math.radians(deg)
            out += (f'<line x1="{f(cx + math.cos(a) * r * 1.34)}" y1="{f(cy + math.sin(a) * r * 1.34)}" '
                    f'x2="{f(cx + math.cos(a) * r * 1.86)}" y2="{f(cy + math.sin(a) * r * 1.86)}" '
                    f'stroke="#F8D27E" stroke-width="{f(r * .3)}" stroke-linecap="round"/>')
    out += f'<circle cx="{f(cx)}" cy="{f(cy)}" r="{f(r)}" fill="url(#sun)"/>'
    if highlight:
        out += (f'<path d="M{f(cx - r * .62)} {f(cy + r * .05)}C{f(cx - r * .3)} {f(cy - r * .2)} {f(cx + r * .1)} '
                f'{f(cy - r * .2)} {f(cx + r * .62)} {f(cy + r * .38)}" stroke="#FFFDF8" stroke-opacity=".8" '
                f'stroke-width="{f(r * .2)}" stroke-linecap="round"/>')
    return out + "</g>"


def cal_card(x, y, w, lines=True, panel_fill="#FBFEFF", line_fills=("url(#line1)", "url(#line2)"), inner=""):
    """图标同款日历卡：外框圆角≈0.23w，两枚装订扣，内面板 + 两道文字线。"""
    h = w * 222 / 254
    r = w * .228
    out = (f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(r)}" fill="url(#card)"/>'
           f'<rect x="{f(x + w * .142)}" y="{f(y + h * .252)}" width="{f(w * .717)}" height="{f(h * .577)}" rx="{f(w * .134)}" fill="{panel_fill}"/>')
    tw, th = w * .126, h * .288
    for tx in (.209, .748):
        out += f'<rect x="{f(x + w * tx)}" y="{f(y - h * .09)}" width="{f(tw)}" height="{f(th)}" rx="{f(tw / 2)}" fill="url(#tab)"/>'
    if lines:
        lh = h * .108
        out += (f'<rect x="{f(x + w * .256)}" y="{f(y + h * .41)}" width="{f(w * .508)}" height="{f(lh)}" rx="{f(lh / 2)}" fill="{line_fills[0]}"/>'
                f'<rect x="{f(x + w * .256)}" y="{f(y + h * .649)}" width="{f(w * .425)}" height="{f(lh)}" rx="{f(lh / 2)}" fill="{line_fills[1]}"/>')
    return out + inner


def sparkle(cx, cy, s, fill="#FFFFFF", op=1):
    return (f'<path d="M{f(cx)} {f(cy - s)}C{f(cx + s * .12)} {f(cy - s * .12)} {f(cx + s * .12)} {f(cy - s * .12)} {f(cx + s)} {f(cy)}'
            f'C{f(cx + s * .12)} {f(cy + s * .12)} {f(cx + s * .12)} {f(cy + s * .12)} {f(cx)} {f(cy + s)}'
            f'C{f(cx - s * .12)} {f(cy + s * .12)} {f(cx - s * .12)} {f(cy + s * .12)} {f(cx - s)} {f(cy)}'
            f'C{f(cx - s * .12)} {f(cy - s * .12)} {f(cx - s * .12)} {f(cy - s * .12)} {f(cx)} {f(cy - s)}Z" fill="{fill}" fill-opacity="{op}"/>')


def note(x, y, w, h, rot=0, lines=2):
    cx, cy = x + w / 2, y + h / 2
    ls = "".join(f'<rect x="{f(x + w * .18)}" y="{f(y + h * (.34 + i * .24))}" width="{f(w * (.62 - i * .16))}" height="{f(h * .1)}" rx="{f(h * .05)}" fill="{["#CFE4FA", "#DCEBFA", "#E4EFFA"][i]}"/>' for i in range(lines))
    return (f'<g transform="rotate({rot} {f(cx)} {f(cy)})"><rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(min(w, h) * .2)}" fill="url(#paper)"/>'
            f'<rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(min(w, h) * .2)}" stroke="#D9E8F7" stroke-width="1.2"/>{ls}</g>')


def check_mark(cx, cy, s, color="#FFFFFF", width=None):
    return (f'<path d="M{f(cx - s * .5)} {f(cy + s * .02)}L{f(cx - s * .12)} {f(cy + s * .4)}L{f(cx + s * .55)} {f(cy - s * .35)}" '
            f'stroke="{color}" stroke-width="{f(width or s * .2)}" stroke-linecap="round" stroke-linejoin="round"/>')


def course_block(x, y, w, h, key, rot=0):
    bg, acc = COURSE[key]
    cx, cy = x + w / 2, y + h / 2
    return (f'<g transform="rotate({rot} {f(cx)} {f(cy)})"><rect x="{f(x)}" y="{f(y)}" width="{f(w)}" height="{f(h)}" rx="{f(min(w, h) * .22)}" fill="{bg}"/>'
            f'<rect x="{f(x)}" y="{f(y + h * .12)}" width="{f(max(2.2, w * .09))}" height="{f(h * .76)}" rx="1.2" fill="{acc}"/>'
            f'<rect x="{f(x + w * .28)}" y="{f(y + h * .22)}" width="{f(w * .5)}" height="{f(max(2.4, h * .1))}" rx="1.4" fill="{acc}" fill-opacity=".55"/></g>')


# ---------------------------------------------------------------- 插画 240×180
def empty_today():
    clip = island_clip("isl", 120, 150, 96, 24)
    body = (halo(120, 84, 84) + waves(24, 128, 192, 44, "isl") +
            ground(120, 150, 58, 5) + sun(166, 52, 15, highlight=True) +
            f'<g id="main">{cal_card(72, 58, 96, line_fills=("#E1ECF8", "#E8F0FA"))}</g>' +
            f'<g id="sparkle">{sparkle(56, 60, 5, SUN2, .9)}</g>')
    return svg(240, 180, body, clip)


def all_done():
    inner = (f'<circle cx="120" cy="104" r="19" fill="url(#mintG)"/>' + check_mark(120, 104, 20))
    body = (halo(120, 86, 84) + ground(120, 152, 60, 6) + sun(168, 46, 14, highlight=True) +
            f'<g id="main">{cal_card(70, 62, 100, lines=False, inner=inner)}</g>' +
            f'<g id="sparkle">{sparkle(52, 72, 6, SUN2)}{sparkle(190, 92, 4.5, CYAN, .9)}{sparkle(62, 122, 3.5, SKY, .7)}</g>')
    return svg(240, 180, body)


def empty_tasks():
    trail = '<path d="M96 96C120 70 140 70 158 58" stroke="#9BC9EE" stroke-width="2" stroke-linecap="round" stroke-dasharray="2 6"/>'
    plane = ('<g id="sparkle" transform="rotate(-18 176 52)"><path d="M158 52L196 38L184 66L174 57Z" fill="url(#brand)"/>'
             '<path d="M174 57L196 38L170 51Z" fill="#FFFFFF" fill-opacity=".55"/></g>')
    body = (halo(116, 90, 84) + ground(104, 150, 50, 5) + trail +
            f'<g id="main">{note(58, 74, 76, 64, -7, 3)}</g>' + plane + sparkle(196, 96, 4, SUN2, .9))
    return svg(240, 180, body)


def empty_week():
    tiles = ""
    for i in range(7):
        x = 38 + i * 24
        fill = "#FFFFFF" if i != 2 else "#EAF2FF"
        tiles += f'<rect x="{x}" y="84" width="20" height="30" rx="7" fill="{fill}" stroke="#D9E8F7" stroke-width="1.2"/>'
        tiles += f'<rect x="{x + 6}" y="90" width="8" height="2.4" rx="1.2" fill="#D2DDEA"/>'
    tiles += '<circle cx="88" cy="106" r="3" fill="url(#sun)"/>'
    body = (halo(120, 92, 84) + sun(176, 70, 13) + ground(120, 140, 92, 5) +
            f'<g id="main"><rect x="28" y="72" width="184" height="56" rx="18" fill="url(#card)"/>{tiles}</g>')
    return svg(240, 180, body)


def no_results():
    cells = ""
    for r in range(3):
        for c in range(3):
            cells += f'<rect x="{82 + c * 24}" y="{70 + r * 20}" width="18" height="14" rx="4" stroke="#BFD7F1" stroke-width="1.3" stroke-dasharray="2.4 2.4"/>'
    mag = ('<g id="sparkle"><circle cx="152" cy="112" r="20" fill="#FFFFFF" fill-opacity=".7"/>'
           '<circle cx="152" cy="112" r="20" stroke="url(#brand)" stroke-width="6"/>'
           '<path d="M166.5 126.5L180 140" stroke="url(#brand)" stroke-width="8" stroke-linecap="round"/>'
           '<path d="M142 104C145 100 150 99 154 100" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round"/></g>')
    body = (halo(120, 92, 84) + ground(122, 152, 62, 6) +
            f'<g id="main"><rect x="70" y="56" width="100" height="84" rx="22" fill="url(#paper)" stroke="#D9E8F7" stroke-width="1.2"/>{cells}</g>' + mag)
    return svg(240, 180, body)


def offline():
    cloud = ('<g id="main"><path d="M78 118C64 118 56 108 56 98C56 87 65 79 76 80C78 64 92 54 108 56C119 57 128 63 132 72'
             'C136 69 141 68 146 68C160 68 170 79 170 92C182 94 188 103 188 108C188 114 182 118 176 118Z" fill="url(#cloud)"/>'
             '<path d="M78 118C64 118 56 108 56 98C56 87 65 79 76 80C78 64 92 54 108 56C119 57 128 63 132 72'
             'C136 69 141 68 146 68C160 68 170 79 170 92C182 94 188 103 188 108C188 114 182 118 176 118Z" stroke="#D3E4F6" stroke-width="1.4"/></g>')
    line = ('<path d="M122 124V134" stroke="#9BC9EE" stroke-width="3" stroke-linecap="round"/>'
            '<path d="M117 141L127 151M127 141L117 151" stroke="#F0705A" stroke-opacity=".8" stroke-width="2.6" stroke-linecap="round"/>'
            '<path d="M122 158V166" stroke="#9BC9EE" stroke-width="3" stroke-linecap="round"/>'
            '<circle cx="122" cy="170" r="3" fill="#9BC9EE"/>')
    body = halo(120, 92, 84) + sun(92, 66, 14, glow=True) + cloud + line
    return svg(240, 180, body)


def import_timetable():
    grid = ""
    for r in range(3):
        for c in range(4):
            grid += f'<rect x="{68 + c * 27}" y="{84 + r * 20}" width="23" height="16" rx="5" fill="#FFFFFF" fill-opacity=".85"/>'
    blocks = (course_block(68, 84, 23, 36, "sky") + course_block(95, 104, 23, 36, "mint") +
              course_block(149, 84, 23, 16, "lilac") + course_block(122, 124, 23, 16, "apricot"))
    drop = ('<path d="M136 52V70" stroke="#9BC9EE" stroke-width="2" stroke-linecap="round" stroke-dasharray="2 5"/>' +
            course_block(124, 60, 24, 22, "blossom", 8))
    body = (halo(120, 96, 84) + ground(120, 160, 64, 6) +
            f'<g id="main"><rect x="58" y="72" width="124" height="80" rx="22" fill="url(#card)"/>{grid}{blocks}</g>' +
            f'<g id="sparkle">{drop}</g>' + sparkle(60, 60, 5, SUN2, .9))
    return svg(240, 180, body)


def assistant_hello():
    left = ('<path d="M44 62C44 53 51 46 60 46H132C141 46 148 53 148 62V86C148 95 141 102 132 102H70L56 112V100C49 98 44 92 44 86Z" fill="url(#paper)"/>'
            '<path d="M44 62C44 53 51 46 60 46H132C141 46 148 53 148 62V86C148 95 141 102 132 102H70L56 112V100C49 98 44 92 44 86Z" stroke="#D9E8F7" stroke-width="1.2"/>'
            '<rect x="60" y="62" width="70" height="7" rx="3.5" fill="#CFE4FA"/><rect x="60" y="78" width="50" height="7" rx="3.5" fill="#DCEBFA"/>')
    right = ('<path d="M104 106C104 99 110 94 117 94H182C189 94 195 99 195 106V140C195 147 189 152 182 152H118L106 160V149C105 147 104 144 104 140Z" fill="#EAF2FF"/>' +
             cal_card(130, 106, 40))
    body = (halo(120, 98, 86) + ground(122, 166, 60, 5) + f'<g id="main">{left}{right}</g>' +
            f'<g id="sparkle">{sparkle(176, 64, 9, "url(#sun)")}{sparkle(194, 80, 4.5, CYAN, .85)}</g>')
    return svg(240, 180, body)


def semester_start():
    clip = island_clip("isl", 120, 148, 104, 30)
    # 一串由远及近的周次圆点：远处小、近处大，最近的是"本周"
    pts = [(120, 118, 2.2), (116, 126, 2.8), (110, 135, 3.4), (101, 145, 4.1), (90, 156, 5)]
    path = '<path d="M120 116C116 128 108 142 86 162" stroke="#FFFFFF" stroke-width="10" stroke-linecap="round" stroke-opacity=".75"/>'
    dots = "".join(f'<circle cx="{x}" cy="{y}" r="{r}" fill="url(#brand)"/>' for x, y, r in pts[:-1])
    dots += f'<circle cx="90" cy="156" r="7" fill="#FFFFFF"/><circle cx="90" cy="156" r="4.6" fill="url(#sun)"/>'
    body = (halo(120, 92, 88) + sun(120, 96, 17, highlight=True) +
            '<path d="M28 114H212" stroke="#D2DDEA" stroke-width="1.6" stroke-linecap="round"/>' +
            waves(16, 114, 208, 62, "isl") + f'<g id="main">{path}{dots}</g>' +
            f'<g id="sparkle">{sparkle(64, 72, 4.5, SUN2, .9)}{sparkle(182, 62, 3.5, CYAN, .8)}</g>')
    return svg(240, 180, body, clip)


def reminder_permission():
    bell = ('<g id="sparkle"><path d="M136 120V100C136 86 146 76 158 76C170 76 180 86 180 100V120Z" fill="url(#sun)"/>'
            '<rect x="128" y="118" width="60" height="9" rx="4.5" fill="url(#sun)"/>'
            '<path d="M150 133C151 138 154 141 158 141C162 141 165 138 166 133" stroke="#F2B33D" stroke-width="4" stroke-linecap="round"/>'
            '<path d="M146 92C148 86 152 83 157 82" stroke="#FFFFFF" stroke-opacity=".8" stroke-width="3.5" stroke-linecap="round"/>'
            '<path d="M188 84C193 89 195 95 195 101M128 84C123 89 121 95 121 101" stroke="#F6C86B" stroke-width="3" stroke-linecap="round" stroke-opacity=".7"/></g>')
    body = halo(120, 92, 86) + ground(120, 156, 64, 6) + f'<g id="main">{cal_card(48, 64, 92)}</g>' + bell
    return svg(240, 180, body)


# ---------------------------------------------------------------- 引导插画 320×240
def onboard_collect():
    notes = (note(28, 40, 54, 40, -14) + note(236, 30, 56, 42, 12) + note(30, 150, 50, 38, 9) + note(246, 148, 50, 38, -10))
    trails = "".join(f'<path d="{d}" stroke="#9BC9EE" stroke-width="2" stroke-linecap="round" stroke-dasharray="2 6"/>' for d in
                     ("M86 66C104 74 116 84 124 96", "M232 58C214 68 204 80 198 94", "M84 164C100 156 112 148 120 140", "M244 162C228 156 214 148 204 140"))
    body = (halo(160, 120, 112) + ground(160, 200, 70, 7) + trails + notes +
            f'<g id="main">{cal_card(110, 92, 100)}</g>' +
            f'<g id="sparkle">{sparkle(160, 62, 8, "url(#sun)")}{sparkle(214, 196, 4, CYAN, .85)}</g>')
    return svg(320, 240, body)


def onboard_plan():
    col = '<rect x="104" y="40" width="112" height="170" rx="26" fill="url(#paper)" stroke="#D9E8F7" stroke-width="1.2"/>'
    rows = (course_block(120, 58, 80, 34, "sky") +
            '<rect x="120" y="100" width="80" height="38" rx="10" stroke="#9BC9EE" stroke-width="1.6" stroke-dasharray="3.5 3"/>'
            '<rect x="124" y="104" width="44" height="30" rx="8" fill="url(#brandH)"/>' + check_mark(146, 119, 12) +
            course_block(120, 146, 80, 44, "mint"))
    body = (halo(160, 124, 112) + ground(160, 222, 64, 6) + sun(232, 52, 16, highlight=True) +
            f'<g id="main">{col}{rows}</g>' + f'<g id="sparkle">{sparkle(84, 112, 6, SUN2)}{sparkle(236, 140, 4, CYAN, .8)}</g>')
    return svg(320, 240, body)


def onboard_adapt():
    clip = island_clip("isl", 160, 206, 128, 26)
    arrows = ('<path d="M120 92C138 64 182 64 200 92" stroke="url(#brandH)" stroke-width="3" stroke-linecap="round"/>'
              '<path d="M193 84L200 92L190 95" stroke="#63CFE9" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>'
              '<path d="M200 160C182 188 138 188 120 160" stroke="url(#brandH)" stroke-width="3" stroke-linecap="round"/>'
              '<path d="M127 168L120 160L130 157" stroke="#4CA4FF" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/>')
    blocks = course_block(76, 100, 72, 52, "lilac") + (
        '<rect x="172" y="100" width="72" height="52" rx="12" fill="#EAF2FF"/>'
        '<rect x="172" y="100" width="72" height="52" rx="12" stroke="#8DBBF5" stroke-width="1.6" stroke-dasharray="4 3"/>'
        '<rect x="172" y="112" width="4" height="28" rx="2" fill="url(#brand)"/>'
        '<rect x="186" y="114" width="40" height="6" rx="3" fill="#8DBBF5"/>')
    body = (halo(160, 124, 112) + waves(32, 186, 256, 54, "isl") + f'<g id="main">{arrows}{blocks}</g>' +
            sun(250, 54, 14) + f'<g id="sparkle">{sparkle(70, 70, 5, SUN2, .9)}</g>')
    return svg(320, 240, body, clip)


ILLUSTRATIONS = {
    "empty-today": empty_today, "all-done": all_done, "empty-tasks": empty_tasks, "empty-week": empty_week,
    "no-results": no_results, "offline": offline, "import-timetable": import_timetable,
    "assistant-hello": assistant_hello, "semester-start": semester_start, "reminder-permission": reminder_permission,
    "onboard-collect": onboard_collect, "onboard-plan": onboard_plan, "onboard-adapt": onboard_adapt,
}

# ---------------------------------------------------------------- 双色图标 24×24
STROKE = f'stroke="{PRIMARY}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"'
S2 = f'fill="{SOFT}"'
CAL_HEAD = f'<path d="M4 9.5V8a3 3 0 0 1 3-3h10a3 3 0 0 1 3 3v1.5z" {S2}/>'
ICONS = {
    "course": f'<path d="M12 6.6c-2.1-1.3-4.8-1.9-8-1.7v12.6c3.2-.2 5.9.4 8 1.7z" {S2}/><path d="M12 6.6c-2.1-1.3-4.8-1.9-8-1.7v12.6c3.2-.2 5.9.4 8 1.7m0-12.6c2.1-1.3 4.8-1.9 8-1.7v12.6c-3.2-.2-5.9.4-8 1.7m0-12.6v12.6" {STROKE}/>',
    "exam": f'<rect x="4.5" y="3.5" width="12" height="17" rx="3" {S2}/><rect x="4.5" y="3.5" width="12" height="17" rx="3" {STROKE}/><path d="M8 8.5h5M8 12h3" {STROKE}/><path d="M20.1 10.6l-5.7 5.7-2.6.8.8-2.6 5.7-5.7a1.2 1.2 0 0 1 1.8 1.8z" fill="#FFFFFF" stroke="{PRIMARY}" stroke-width="2" stroke-linejoin="round"/>',
    "task": f'<rect x="3.5" y="4.5" width="6.5" height="6.5" rx="2.2" {S2}/><rect x="3.5" y="4.5" width="6.5" height="6.5" rx="2.2" {STROKE}/><path d="M5.3 7.9l1.2 1.1 1.9-2.1" {STROKE}/><rect x="3.5" y="13.5" width="6.5" height="6.5" rx="2.2" {STROKE}/><path d="M14 7.8h6.5M14 16.8h6.5" {STROKE}/>',
    "event": f'<path d="M6.5 4.5h10.5l-2.2 3.6 2.2 3.6H6.5z" {S2}/><path d="M6.5 20.5v-16h10.5l-2.2 3.6 2.2 3.6H6.5" {STROKE}/>',
    "plan": f'{CAL_HEAD}<rect x="4" y="5" width="16" height="15" rx="3" {STROKE}/><path d="M8 3v4M16 3v4M4 9.5h16" {STROKE}/><path d="M12 11.6c.3 1.8 1.1 2.6 2.9 2.9-1.8.3-2.6 1.1-2.9 2.9-.3-1.8-1.1-2.6-2.9-2.9 1.8-.3 2.6-1.1 2.9-2.9z" fill="{PRIMARY}"/>',
    "deadline": f'<path d="M8.2 19.5h7.6c0-2.6-1.5-4-3.8-5.3-2.3 1.3-3.8 2.7-3.8 5.3z" {S2}/><path d="M6.5 3.5h11M6.5 20.5h11M8 3.5c0 3.4 1.6 5.4 4 8.5 2.4-3.1 4-5.1 4-8.5M8 20.5c0-3.4 1.6-5.4 4-8.5 2.4 3.1 4 5.1 4 8.5" {STROKE}/>',
    "reminder": f'<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5z" {S2}/><path d="M4.5 16.5h15M6 16.5V11a6 6 0 0 1 12 0v5.5M10 19.6a2 2 0 0 0 4 0M12 3.5V5" {STROKE}/>',
    "location": f'<circle cx="12" cy="9.8" r="2.4" {S2}/><path d="M12 20.5s-6.5-5.5-6.5-10.8a6.5 6.5 0 0 1 13 0c0 5.3-6.5 10.8-6.5 10.8z" {STROKE}/><circle cx="12" cy="9.8" r="2.4" {STROKE}/>',
    "gap": f'<rect x="6.2" y="10" width="6.3" height="4" rx="1.6" fill="{PRIMARY}"/><rect x="3.5" y="7.5" width="17" height="9" rx="3.2" stroke="{PRIMARY}" stroke-width="2" stroke-dasharray="2.6 2.4" stroke-linecap="round"/><rect x="13.6" y="10" width="4.2" height="4" rx="1.6" {S2}/>',
    "reschedule": f'<circle cx="12" cy="12" r="2.6" {S2}/><path d="M5 10a7 7 0 0 1 12.3-4.4M19 14a7 7 0 0 1-12.3 4.4" {STROKE}/><path d="M17.9 2.7l-.4 3.7-3.6-.4M6.1 21.3l.4-3.7 3.6.4" {STROKE}/>',
    "cancelled": f'{CAL_HEAD}<rect x="4" y="5" width="16" height="15" rx="3" {STROKE}/><path d="M8 3v4M16 3v4M4 9.5h16M10.2 12.8v4M13.8 12.8v4" {STROKE}/>',
    "voice": f'<rect x="9.5" y="3.5" width="5" height="10" rx="2.5" {S2}/><rect x="9.5" y="3.5" width="5" height="10" rx="2.5" {STROKE}/><path d="M6.5 11a5.5 5.5 0 0 0 11 0M12 16.5v3.5M3.5 9.5v2M20.5 9.5v2" {STROKE}/>',
    "image": f'<path d="M4.5 16.5l4-4 3 3 2.5-2.5 5.5 5.5v.5a2 2 0 0 1-2 2h-11a2 2 0 0 1-2-2z" {S2}/><rect x="3.5" y="4.5" width="17" height="16" rx="3" {STROKE}/><circle cx="15.5" cy="9.2" r="2" {STROKE}/>',
    "notice": f'<path d="M5 9.5h3.5l7-4v13l-7-4H5z" {S2}/><path d="M5 9.5h3.5l7-4v13l-7-4H5a1.5 1.5 0 0 1-1.5-1.5v-2A1.5 1.5 0 0 1 5 9.5zM8.5 14.5l1.3 4.5M18.5 9.5a3 3 0 0 1 0 5" {STROKE}/>',
    "import": f'<path d="M4 14.5h4.2l1.3 2h5l1.3-2H20v3a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3z" {S2}/><path d="M4 14.5h4.2l1.3 2h5l1.3-2H20M4 14.5v3a3 3 0 0 0 3 3h10a3 3 0 0 0 3-3v-3M12 3.5V12M8.5 8.5L12 12l3.5-3.5" {STROKE}/>',
    "stats": f'<rect x="4" y="11" width="4.2" height="9" rx="2.1" fill="{PRIMARY}"/><rect x="9.9" y="4.5" width="4.2" height="15.5" rx="2.1" {S2}/><rect x="15.8" y="8.5" width="4.2" height="11.5" rx="2.1" fill="{PRIMARY}"/>',
    "tag": f'<path d="M4 5.5v5.4a2 2 0 0 0 .6 1.4l7.6 7.6a2 2 0 0 0 2.8 0l4.6-4.6a2 2 0 0 0 0-2.8L12 4.9a2 2 0 0 0-1.4-.6H5.2A1.2 1.2 0 0 0 4 5.5z" {S2}/><path d="M4 5.5v5.4a2 2 0 0 0 .6 1.4l7.6 7.6a2 2 0 0 0 2.8 0l4.6-4.6a2 2 0 0 0 0-2.8L12 4.9a2 2 0 0 0-1.4-.6H5.2A1.2 1.2 0 0 0 4 5.5z" {STROKE}/><circle cx="8.2" cy="8.5" r="1.5" fill="{PRIMARY}"/>',
    "semester": f'<path d="M12 4.5h5.5l-1.4 2.1 1.4 2.1H12z" {S2}/><path d="M3.5 17.5h5.9M14.6 17.5h5.9M12 14.9V4.5h5.5l-1.4 2.1 1.4 2.1H12" {STROKE}/><circle cx="12" cy="17.5" r="2.6" {STROKE}/><circle cx="6" cy="17.5" r="1.4" fill="{PRIMARY}"/><circle cx="18" cy="17.5" r="1.4" fill="{PRIMARY}"/>',
    "sparkle": f'<path d="M10.5 3.5c.5 4 2.6 6.1 6.6 6.6-4 .5-6.1 2.6-6.6 6.6-.5-4-2.6-6.1-6.6-6.6 4-.5 6.1-2.6 6.6-6.6z" fill="{PRIMARY}"/><path d="M18 13.8c.25 1.9 1.2 2.85 3.1 3.1-1.9.25-2.85 1.2-3.1 3.1-.25-1.9-1.2-2.85-3.1-3.1 1.9-.25 2.85-1.2 3.1-3.1z" {S2}/>',
    "today": f'<circle cx="12" cy="13" r="4.2" {S2}/><circle cx="12" cy="13" r="4.2" {STROKE}/><path d="M12 4.6v1.6M5.9 7.2l1.2 1.2M18.1 7.2l-1.2 1.2M3.8 13h1.6M18.6 13h1.6M6.5 20h11" {STROKE}/>',
    "schedule": f'<path d="M3.6 10.4V8.8a3.6 3.6 0 0 1 3.6-3.6h9.6a3.6 3.6 0 0 1 3.6 3.6v1.6z" {S2}/><rect x="3.6" y="5.2" width="16.8" height="15" rx="3.6" {STROKE}/><path d="M3.6 10.4h16.8M9.3 10.4v9.8M14.7 10.4v9.8M8.2 3.4v3.4M15.8 3.4v3.4" {STROKE}/>',
    "tasks": f'<circle cx="7" cy="7.5" r="2.7" {S2}/><circle cx="7" cy="7.5" r="2.7" {STROKE}/><circle cx="7" cy="16.5" r="2.7" {STROKE}/><path d="M12.6 7.5h7.4M12.6 16.5h7.4" {STROKE}/>',
}
CC = 'stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" fill="none"'
NAV = {
    "nav-today": f'<circle cx="12" cy="13" r="4.2" {CC}/><path d="M12 4.6v1.6M5.9 7.2l1.2 1.2M18.1 7.2l-1.2 1.2M3.8 13h1.6M18.6 13h1.6M6.5 20h11" {CC}/>',
    "nav-today-filled": f'<circle cx="12" cy="13" r="5" fill="currentColor"/><path d="M12 4.6v1.6M5.9 7.2l1.2 1.2M18.1 7.2l-1.2 1.2M3.8 13h1.6M18.6 13h1.6M6.5 20h11" {CC}/>',
    "nav-schedule": f'<rect x="3.6" y="5.2" width="16.8" height="15" rx="3.6" {CC}/><path d="M3.6 10.4h16.8M9.3 10.4v9.8M14.7 10.4v9.8M8.2 3.4v3.4M15.8 3.4v3.4" {CC}/>',
    "nav-schedule-filled": '<path d="M7.2 5.2h9.6a3.6 3.6 0 0 1 3.6 3.6v1.6H3.6V8.8a3.6 3.6 0 0 1 3.6-3.6zM3.6 12h4.9v8.2H7.2a3.6 3.6 0 0 1-3.6-3.6zm6.5 0h3.8v8.2h-3.8zm5.4 0h4.9v4.6a3.6 3.6 0 0 1-3.6 3.6h-1.3z" fill="currentColor"/>' + f'<path d="M8.2 3.4v3.4M15.8 3.4v3.4" {CC}/>',
    "nav-tasks": f'<circle cx="7" cy="7.5" r="2.7" {CC}/><circle cx="7" cy="16.5" r="2.7" {CC}/><path d="M12.6 7.5h7.4M12.6 16.5h7.4" {CC}/>',
    "nav-tasks-filled": '<circle cx="7" cy="7.5" r="3.6" fill="currentColor"/><path d="M5.4 7.5l1.1 1.1 2-2.1" stroke="#FFFFFF" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" fill="none"/>' + f'<circle cx="7" cy="16.5" r="2.7" {CC}/><path d="M12.6 7.5h7.4M12.6 16.5h7.4" {CC}/>',
    "nav-semester": f'<path d="M3.8 17.5h5.6M14.6 17.5h5.6" {CC}/><circle cx="6.8" cy="17.5" r="1.5" fill="currentColor"/><circle cx="17.2" cy="17.5" r="1.5" fill="currentColor"/><circle cx="12" cy="17.5" r="2.6" {CC}/><path d="M12 14.9V5.2h5.6l-1.5 2.2 1.5 2.2H12" {CC}/>',
    "nav-semester-filled": f'<path d="M3.8 17.5h16.4" {CC}/><circle cx="6.8" cy="17.5" r="1.5" fill="currentColor"/><circle cx="17.2" cy="17.5" r="1.5" fill="currentColor"/><circle cx="12" cy="17.5" r="3.2" fill="currentColor"/><path d="M12 14.9V5.2h5.6l-1.5 2.2 1.5 2.2H12z" fill="currentColor" {CC.replace(" fill=\"none\"", "")}/>',
}


def icon_svg(inner):
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none">{inner}</svg>\n'


def main():
    for sub in ("illustrations", "icons", "patterns"):
        os.makedirs(os.path.join(ROOT, sub), exist_ok=True)
    for name, fn in ILLUSTRATIONS.items():
        open(os.path.join(ROOT, "illustrations", f"{name}.svg"), "w", encoding="utf-8").write(fn())
    for name, inner in {**ICONS, **NAV}.items():
        open(os.path.join(ROOT, "icons", f"{name}.svg"), "w", encoding="utf-8").write(icon_svg(inner))
    wave = (f'<svg xmlns="http://www.w3.org/2000/svg" width="390" height="72" viewBox="0 0 390 72" fill="none" preserveAspectRatio="none">'
            f'<defs>{DEFS}</defs>{waves(0, 0, 390, 72)}</svg>\n')
    open(os.path.join(ROOT, "patterns", "wave-hero.svg"), "w", encoding="utf-8").write(wave)
    print(f"{len(ILLUSTRATIONS)} illustrations, {len(ICONS) + len(NAV)} icons, 1 pattern")


if __name__ == "__main__":
    main()
