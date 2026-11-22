#!/usr/bin/env python3
"""Render the homelab diagram (r/homelab style) from inventory.yaml.

Usage: python3 build.py [--unredacted] [--inventory FILE]
                                         → out/homelab.svg + out/homelab.png
                                            (--unredacted → out/homelab-unredacted.*)
Content comes from inventory.yaml; the layout (positions of every box and line) is
hand-placed in this file for one specific network, so expect to move things around.
Line width encodes link speed (SPEED_W); trunks are drawn as a light cable with a dark core.
Written with Claude (Anthropic) in Claude Code, see README.md.
"""
import base64
import html
import pathlib
import subprocess
import sys

import yaml

ROOT = pathlib.Path(__file__).resolve().parent
if "--inventory" in sys.argv:
    _i = sys.argv.index("--inventory") + 1
    if _i >= len(sys.argv) or sys.argv[_i].startswith("--"):
        raise SystemExit("--inventory needs a file")
    INV_FILE = pathlib.Path(sys.argv[_i])
else:
    INV_FILE = ROOT / "inventory.yaml"
INV = yaml.safe_load(INV_FILE.read_text())
ICONS = ROOT / "icons"
OUT = ROOT / "out"

UNREDACTED = "--unredacted" in sys.argv
RED = INV["redact"]
DOMAIN = INV["meta"]["domain"]
SHOWN_DOMAIN = DOMAIN if (UNREDACTED or not RED["domain"]) else RED["domain_placeholder"]

W, H = 2400, 0      # H is set at the end from the content (see "canvas height")

# ---------------------------------------------------------------- palette
BG = "#0b0f15"
GRID = "#151c26"
PANEL = "#111821"
PANEL2 = "#161f2b"
CHIP = "#19222e"
BORDER = "#253042"
TEXT = "#e6edf3"
MUTED = "#8d9aab"
FAINT = "#5d6a7c"
TRUNK = "#d5dde6"
TRUNK_BORDER = "#3a475a"   # border for devices on a tagged trunk (not in a single VLAN)
LINK = "#79c0ff"
REDDIT = "#ff5722"
DISK = "#1d2734"
DISK_EDGE = "#5a6b82"
PROTO = {"TCP": "#79c0ff", "UDP": "#39c5cf"}
UNKNOWN = "#6b7a90"   # a used port whose VLANs aren't known
SPEED_W = {"10G": 9.5, "2.5G": 3.8, "1G": 2.4, "100M": 1.4}   # access-line widths
VLAN = {v["key"]: v for v in INV["vlans"]}
C = {k: v["color"] for k, v in VLAN.items()}
SANS = "Fira Sans"
MONO = "Fira Code"


def trunk_w(speed):
    return SPEED_W[speed] + 3.4


def sub(s):
    """Fill {domain} placeholders and apply redaction."""
    s = str(s).replace("{domain}", SHOWN_DOMAIN)
    if not UNREDACTED and RED["domain"]:
        s = s.replace(DOMAIN, SHOWN_DOMAIN)
    return s


def esc(s):
    return html.escape(sub(s), quote=True)


def tw(s, size, mono=False):
    """Rough text width for layout decisions."""
    return len(sub(s)) * size * (0.6 if mono else 0.53)


def _font_file(pattern):
    """Path of an installed font via fontconfig (fc-match), or None."""
    try:
        out = subprocess.run(["fc-match", "-f", "%{file}", pattern], capture_output=True, text=True, timeout=5)
        return out.stdout.strip() or None
    except Exception:
        return None


try:
    from PIL import ImageFont
    _FONTS = {700: _font_file("Fira Sans:bold"), 600: _font_file("Fira Sans:semibold"),
              400: _font_file("Fira Sans:regular")}
    if not all(_FONTS.values()):
        raise RuntimeError("Fira Sans not found")
    _FCACHE = {}

    def measure(s, size, weight=700):
        key = (weight, size)
        if key not in _FCACHE:
            _FCACHE[key] = ImageFont.truetype(_FONTS[weight], size=size * 8)
        return _FCACHE[key].getlength(s) / 8
except Exception:          # no Pillow / font file: rough estimate
    def measure(s, size, weight=700):
        return tw_title(s, size)


def tw_title(s, size):
    """Width estimate for bold title text (capitals are wider than lowercase)."""
    return sum(0.68 if c.isupper() else 0.58 if c.isdigit() else 0.5 for c in s) * size


def fqdn(h):
    return f"{h}.{SHOWN_DOMAIN}"


class SVG:
    def __init__(self):
        self.p = []
        self._icon_cache = {}

    def add(self, s):
        self.p.append(s)

    def rect(self, x, y, w, h, rx=10, fill=PANEL, stroke=BORDER, sw=1.2, op=1, dash=None):
        d = f' stroke-dasharray="{dash}"' if dash else ""
        self.add(f'<rect x="{x:.1f}" y="{y:.1f}" width="{w:.1f}" height="{h:.1f}" rx="{rx}" '
                 f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}" opacity="{op}"{d}/>')

    def text(self, x, y, s, size=14, fill=TEXT, weight=400, anchor="start", mono=False, ls=0, op=1):
        fam = MONO if mono else SANS
        lsa = f' letter-spacing="{ls}"' if ls else ""
        self.add(f'<text x="{x:.1f}" y="{y:.1f}" font-family="{fam}" font-size="{size}" fill="{fill}" '
                 f'font-weight="{weight}" text-anchor="{anchor}" opacity="{op}"{lsa}>{esc(s)}</text>')

    def icon(self, name, x, y, size):
        if name not in self._icon_cache:
            f = ICONS / f"{name}.svg"
            if not f.exists():
                raise SystemExit(f"missing icon '{name}' – run: python3 fetch_icons.py")
            self._icon_cache[name] = base64.b64encode(f.read_bytes()).decode()
        self.add(f'<image x="{x:.1f}" y="{y:.1f}" width="{size}" height="{size}" '
                 f'href="data:image/svg+xml;base64,{self._icon_cache[name]}"/>')

    def line(self, pts, color, sw=3, dash=None, r=10, op=1, cap="round"):
        self.add(f'<path d="{rounded(pts, r)}" fill="none" stroke="{color}" stroke-width="{sw}" '
                 f'stroke-linecap="{cap}" stroke-linejoin="round" opacity="{op}"'
                 + (f' stroke-dasharray="{dash}"' if dash else "") + "/>")

    def trunk(self, pts, r=12, sw=7):
        """Tagged trunk: light cable with a dark core."""
        self.line(pts, TRUNK, sw=sw, r=r)
        self.line(pts, BG, sw=sw - 4.4, r=r)

    def arrow(self, pts, color=MUTED, sw=1.8, dash=None, r=8):
        """Line with an arrowhead at the last point."""
        self.line(pts, color, sw, dash=dash, r=r)
        (x0, y0), (x1, y1) = pts[-2], pts[-1]
        dx, dy = x1 - x0, y1 - y0
        ln = max(abs(dx), abs(dy)) or 1
        ux, uy = dx / ln, dy / ln
        a, b = 8, 4.5
        p1 = (x1 - ux * a - uy * b, y1 - uy * a + ux * b)
        p2 = (x1 - ux * a + uy * b, y1 - uy * a - ux * b)
        self.add(f'<path d="M{x1},{y1} L{p1[0]:.1f},{p1[1]:.1f} L{p2[0]:.1f},{p2[1]:.1f} Z" fill="{color}"/>')

    def pill(self, x, y, s, color, size=12, fill=None, mono=False, anchor="start", h=None, pad=8, tcolor=None, weight=600):
        w = tw(s, size, mono) + pad * 2
        h = h or size + 10
        if anchor == "middle":
            x -= w / 2
        elif anchor == "end":
            x -= w
        self.rect(x, y, w, h, rx=h / 2, fill=fill or color + "22", stroke=color + "88", sw=1)
        self.text(x + w / 2, y + h / 2 + size * 0.36, s, size, tcolor or color, weight, "middle", mono)
        return w

    def label(self, x, y, s, color=MUTED, size=12, anchor="middle", mono=False, bg=BG):
        """Text on a line, with a background knock-out."""
        w = tw(s, size, mono) + 12
        bx = x - w / 2 if anchor == "middle" else (x if anchor == "start" else x - w)
        self.rect(bx, y - size - 2, w, size + 9, rx=5, fill=bg, stroke=bg, sw=0)
        self.text(bx + w / 2, y + 1, s, size, color, 500, "middle", mono)

    def render(self):
        return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">'
                + "".join(self.p) + "</svg>")


def rounded(pts, r):
    """Orthogonal polyline with rounded corners."""
    if len(pts) == 2:
        return f"M{pts[0][0]},{pts[0][1]} L{pts[1][0]},{pts[1][1]}"
    d = f"M{pts[0][0]},{pts[0][1]}"
    for i in range(1, len(pts) - 1):
        (x0, y0), (x1, y1), (x2, y2) = pts[i - 1], pts[i], pts[i + 1]
        l1 = max(abs(x1 - x0), abs(y1 - y0))
        l2 = max(abs(x2 - x1), abs(y2 - y1))
        rr = min(r, l1 / 2, l2 / 2)
        ax = x1 - (x1 - x0) / l1 * rr if l1 else x1
        ay = y1 - (y1 - y0) / l1 * rr if l1 else y1
        bx = x1 + (x2 - x1) / l2 * rr if l2 else x1
        by = y1 + (y2 - y1) / l2 * rr if l2 else y1
        d += f" L{ax:.1f},{ay:.1f} Q{x1},{y1} {bx:.1f},{by:.1f}"
    d += f" L{pts[-1][0]},{pts[-1][1]}"
    return d


S = SVG()


# ---------------------------------------------------------------- shared pieces
def hostname(g):
    """(text, color) for the second address line: local DNS name, public host, or <name>.internal."""
    if g.get("dns"):
        return f"{g['dns']}.{SHOWN_DOMAIN}", None
    if g.get("host"):
        return fqdn(g["host"]), LINK
    if g.get("internal"):
        return f"{g['internal']}.internal", None
    return None, None


def addr(x, y, ip, g, color, size=12):
    """Address line under a card's name (like the switch): IP · hostname, in the VLAN color
    (a public Traefik hostname is blue)."""
    S.text(x, y, ip, size, color, 500, mono=True)
    name, ncol = hostname(g)
    if name:
        cw_ = size * 0.6                      # Fira Code advance width
        dx = x + len(ip) * cw_ + cw_ * 0.6
        S.text(dx, y, "·", size, MUTED, 400, mono=True)
        S.text(dx + cw_ * 1.6, y, name, size, ncol or color, 400, mono=True, op=1 if ncol else 0.85)


def card(x, y, w, h, color=None, title=None, icons=None, sub_=None, isz=34, tsize=19):
    """Panel with a colored left accent, icons, title and subtitle."""
    S.rect(x, y, w, h, rx=14, fill=PANEL, stroke=(color + "aa") if color else BORDER, sw=1.6)
    if color:
        S.add(f'<rect x="{x+1}" y="{y+14}" width="4" height="{h-28}" rx="2" fill="{color}"/>')
    ix = x + 18
    for ic in icons or []:
        S.icon(ic, ix, y + 16, isz)
        ix += isz + 6
    tx_ = ix + 4 if icons else x + 18
    if title:
        S.text(tx_, y + 16 + isz * 0.5 - (2 if sub_ else -6), title, tsize, TEXT, 600)
    if sub_:
        S.text(tx_, y + 16 + isz * 0.5 + 17, sub_, 13, MUTED, 400)
    return tx_


HWC = "#c08a5c"   # "physical hardware" accent (same tan as the HARDWARE labels)


def hw_bar(x, y, h):
    """Left accent bar = this card is a physical box / hardware part."""
    S.add(f'<rect x="{x+1}" y="{y+12}" width="4" height="{h-24}" rx="2" fill="{HWC}"/>')


TAB = 34   # height of the folder tab on physical-device cards


def tab_width(g):
    """Tab fits 'name · type' (name 20px bold, type 14px semibold), measured from the font."""
    return 16 + measure(g["name"], 20, 700) + 7 + measure("·", 20, 700) + 7 + measure(g["type"], 14, 600) + 18


def folder(x, y, w, h, tab_w, fill, stroke, sw):
    """Card body at (x, y, w, h) with a folder tab on its top-left edge, tab_w wide and TAB high."""
    t = y - TAB
    r, rt, sl = 12, 9, 16
    d = (f"M{x},{y+h-r} L{x},{t+rt} Q{x},{t} {x+rt},{t} L{x+tab_w-sl:.1f},{t} "
         f"C{x+tab_w-sl/3:.1f},{t} {x+tab_w-sl/3:.1f},{y} {x+tab_w+sl/2:.1f},{y} "
         f"L{x+w-r},{y} Q{x+w},{y} {x+w},{y+r} L{x+w},{y+h-r} Q{x+w},{y+h} {x+w-r},{y+h} "
         f"L{x+r},{y+h} Q{x},{y+h} {x},{y+h-r} Z")
    S.add(f'<path d="{d}" fill="{fill}" stroke="{stroke}" stroke-width="{sw}"/>')


def device_card(x, y, w, h, icons, g, color, fill=PANEL, stroke=None, sw=1.6):
    """Physical device: folder tab 'name · type'; body = icon, full device name, IP · hostname, OS."""
    folder(x, y, w, h, tab_width(g), fill, stroke or color + "aa", sw)
    S.add(f'<text x="{x+16}" y="{y-10}" font-family="{SANS}" fill="{TEXT}">'
          f'<tspan font-size="20" font-weight="700">{esc(g["name"])}</tspan>'
          f'<tspan dx="7" font-size="20" font-weight="700" fill-opacity="0.6">·</tspan>'
          f'<tspan dx="7" font-size="14" font-weight="600">{esc(g["type"])}</tspan></text>')
    ix = x + 14
    for ic in icons:                      # icon spans the three body lines (full name … OS)
        S.icon(ic, ix, y + 15, 54)
        ix += 58
    tx_ = ix + 8
    dy = 0 if g.get("os") else 8          # no OS line → center the two lines on the icon
    S.text(tx_, y + 28 + dy, g.get("model") or "custom build", 14, TEXT if g.get("model") else MUTED, 500)
    addr(tx_, y + 48 + dy, g["ip"], g, color)
    if g.get("os"):
        S.text(tx_, y + 66, g["os"], 12, MUTED, 400)
    if g.get("config"):                   # optional 4th line: how the device is set up
        S.text(tx_, y + 84, g["config"], 12, FAINT, 400)


def jack(x, y, w, h, fill, stroke, sfp=False):
    S.rect(x, y, w, h, rx=5, fill=fill, stroke=stroke, sw=1.4)
    if sfp:
        S.rect(x + 8, y + 9, w - 16, h - 18, rx=2, fill="#0b0f15", stroke="none", sw=0)
    else:
        S.add(f'<path d="M{x+10},{y+h-8} v-14 h6 v-5 h{w-32} v5 h6 v14 z" fill="#0b0f15"/>')


def ticks(cx, y, untagged=None, tagged=(), up=False):
    """VLAN indicator bars for a port: tall = untagged, short = tagged. up=True grows upwards."""
    vk = ([untagged] if untagged else []) + list(tagged)
    x0 = cx - (len(vk) * 7) / 2
    for j, k in enumerate(vk):
        hh = 8 if k == untagged else 5
        yy = y - hh if up else y
        S.add(f'<rect x="{x0 + j*7:.1f}" y="{yy}" width="5" height="{hh}" rx="1" fill="{C[k]}"/>')


def vlan_tag(vkey):
    v = VLAN[vkey]
    return f"{v['tag']} · {v['name']}" if v["tag"].startswith("VLAN") else v["name"]


# ---------------------------------------------------------------- background + header
S.add(f'<defs><pattern id="dots" width="24" height="24" patternUnits="userSpaceOnUse">'
      f'<circle cx="1.5" cy="1.5" r="1.3" fill="{GRID}"/></pattern></defs>')
BG_IDX = len(S.p)
S.add("")   # background + dot grid: drawn at the end, once the canvas height is known
S.add("")

meta = INV["meta"]
title = meta["title"] if (UNREDACTED or not RED["domain"]) else meta["title_redacted"]
S.text(40, 86, title, 46, TEXT, 700, ls=-0.5)
S.text(W - 40, 74, meta["watermark"], 21, REDDIT, 700, "end")
S.text(W - 40, 100, meta["date"], 16, MUTED, 400, "end")

LAB = "12"           # the lab VLAN: card borders, IPs
STOR = "128"         # Longhorn storage VLAN


def speed_tag(x, y, txt, color, anchor="start"):
    """Small speed label where a cable reaches a device."""
    S.label(x, y, txt, color, 11, anchor=anchor, mono=True)


def route(cables, y0, step=10):
    """Cables from a row of ports (y = start) down to targets below, without crossings.
    cables: list of dicts {sx, tx, ty, draw(pts)}; source/target order must match.
    Rightward cables: the further right, the higher they turn; leftward: the further left, the higher."""
    right = sorted([c for c in cables if c["tx"] >= c["sx"]], key=lambda c: -c["sx"])
    left = sorted([c for c in cables if c["tx"] < c["sx"]], key=lambda c: c["sx"])
    for grp in (right, left):
        for k, c in enumerate(grp):
            ly = y0 + k * step
            c["draw"]([(c["sx"], c["y"]), (c["sx"], ly), (c["tx"], ly), (c["tx"], c["ty"])])
    return y0 + max(len(right), len(left)) * step


# ================================================================ left column: networks
vx, vy, vw = 40, 150, 500
vh = 70 + len(INV["vlans"]) * 60
S.rect(vx, vy, vw, vh, rx=14, fill=PANEL, stroke=BORDER, sw=1.4)
S.text(vx + 20, vy + 36, "Networks", 19, TEXT, 600)
for i, v in enumerate(INV["vlans"]):
    y = vy + 56 + i * 60
    S.rect(vx + 14, y, vw - 28, 52, rx=9, fill=CHIP, stroke=v["color"] + "55", sw=1)
    S.add(f'<rect x="{vx+14}" y="{y}" width="6" height="52" rx="3" fill="{v["color"]}"/>')
    S.text(vx + 32, y + 22, v["tag"], 13, v["color"], 600, mono=True)
    S.text(vx + 128, y + 22, v["name"], 15.5, TEXT, 600)
    S.text(vx + vw - 28, y + 22, v["subnet"], 13.5, TEXT, 500, "end", mono=True)
    S.text(vx + 32, y + 42, v["note"], 12, MUTED, 400)

# ================================================================ TOP: internet → ISP → Sophos
CX = 1190
cy0 = 172

# AWS (reached over Tailscale: tailscale-01 in the VPC <-> ts-onprem on nuc-00)
aws = INV["aws"]
ax, ay, aw, ah = 572, 140, 430, 268
S.line([(ax + aw, ay + 40), (CX - 100, ay + 40)], C["ts"], 1.8, dash="2 5", r=0)

blobs = [(-95, 18, 42), (-45, -8, 56), (25, -18, 62), (90, 6, 48), (130, 26, 30), (-130, 30, 28)]
for dx, dy, r in blobs:
    S.add(f'<circle cx="{CX+dx}" cy="{cy0+dy}" r="{r+2.5}" fill="#3a4a60"/>')
S.add(f'<rect x="{CX-150}" y="{cy0+12}" width="300" height="46" rx="23" fill="#3a4a60"/>')
for dx, dy, r in blobs:
    S.add(f'<circle cx="{CX+dx}" cy="{cy0+dy}" r="{r}" fill="#1a2433"/>')
S.add(f'<rect x="{CX-147.5}" y="{cy0+14.5}" width="295" height="41" rx="20.5" fill="#1a2433"/>')
S.text(CX, cy0 + 14, "Internet", 26, TEXT, 600, "middle")
S.text(CX, cy0 + 40, INV["internet"]["public_ip"] + " public IPv4", 13, MUTED, 400, "middle")

S.rect(ax, ay, aw, ah, rx=14, fill=PANEL, stroke=C["aws"] + "aa", sw=1.6)
S.add(f'<rect x="{ax+1}" y="{ay+14}" width="4" height="{ah-28}" rx="2" fill="{C["aws"]}"/>')
S.icon("aws-l", ax + 16, ay + 14, 34)
S.text(ax + 62, ay + 32, f"{aws['name']} · {aws['region']}", 18, TEXT, 600)
S.text(ax + 62, ay + 52, f"VPC {aws['vpc']} · {aws['note']}", 12.5, MUTED, 400)
iy = ay + 68
for inst in aws["instances"]:
    S.rect(ax + 14, iy, aw - 28, 64, rx=9, fill=CHIP, stroke=BORDER, sw=1)
    S.icon(inst["icon"], ax + 24, iy + 11, 26)
    S.text(ax + 60, iy + 22, inst["name"], 14, TEXT, 600)
    S.text(ax + aw - 26, iy + 22, inst["ip"], 12, C["aws"], 500, "end", mono=True)
    S.text(ax + 60, iy + 39, inst["note"], 11.5, MUTED, 400)
    if inst.get("dns"):
        S.text(ax + 60, iy + 55, f"{inst['dns']}.{SHOWN_DOMAIN}", 10.5, C["aws"], 400, mono=True, op=0.85)
    iy += 72
S.icon("tailscale", ax + 16, iy + 6, 18)
for k, ln in enumerate(aws["tailnet"]):
    S.text(ax + 42, iy + 14 + k * 16, ln, 11.5, C["ts"], 500)
assert iy + 14 + len(aws["tailnet"]) * 16 <= ay + ah, f"AWS panel too short: {iy + 14 + len(aws['tailnet']) * 16 - ay}"
assert vy + vh < 800 - TAB - 8, "networks table runs into the Cisco"

# cloud services (right column), dotted = over the internet
csx, csy = 1790, 146
for i, cs in enumerate(INV["internet"]["cloud_services"]):
    y = csy + i * 54
    yy = y + 22
    S.line([(CX + 140, cy0 - 6 + i * 22), (csx - 40 + i * 0, cy0 - 6 + i * 22), (csx - 40, yy), (csx, yy)],
           FAINT, 1.6, dash="2 5", r=8)
for i, cs in enumerate(INV["internet"]["cloud_services"]):
    y = csy + i * 54
    S.rect(csx, y, 570, 44, rx=10, fill=PANEL2, stroke=BORDER)
    S.icon(cs["icon"], csx + 10, y + 9, 26)
    S.text(csx + 46, y + 20, cs["name"], 14, TEXT, 600)
    S.text(csx + 46, y + 36, cs["note"], 12, MUTED, 400)

# ISP: bridged, not managed by me → small box
isp = INV["isp"]
SBY = 322
S.line([(CX, cy0 + 58), (CX, SBY)], "#6b7a90", 3)
ISPD = INV["internet"]["speed"]
S.label(CX - 10, (cy0 + 58 + SBY) / 2 + 5, "↓ " + ISPD["down"], "#c3cdd9", 12, anchor="end", mono=True)
S.label(CX + 10, (cy0 + 58 + SBY) / 2 + 5, "↑ " + ISPD["up"], "#c3cdd9", 12, anchor="start", mono=True)

# Sophos card
fw = INV["firewall"]
ox, oy, ow, oh = 620, 470, 1140, 180
FW_ORDER = ["Port2", "Port4", "Port1", "Port3"]          # drawn in this order so no cables cross
FWP = {p["name"]: p for p in fw["ports"]}
FPX = {n: CX + k * 140 for k, n in enumerate(FW_ORDER)}
FJY = oy + oh - 56                                        # jack top

# core switch geometry (needed for the cables from the Sophos)
core = INV["core"]
bx, by, bw, bh = 40, 800, 2320, 124
SB = by + bh
PX0, PITCH = bx + 500, 62
N_RJ = 24


def port_x(i):
    """Center x of Cisco port i (0-based); the 4 combo ports (GE25-28) after a small gap."""
    return PX0 + i * PITCH + 24 + (20 if i >= N_RJ else 0)


CPORT = {p["name"]: port_x(i) for i, p in enumerate(core["ports"])}

# WAN: ISP box → Port2 (2.5G)
S.line([(CX, SBY + 60), (FPX["Port2"], FJY)], C["wan"], SPEED_W["2.5G"])
S.label(CX + 8, (SBY + 62 + oy - TAB) / 2 + 4, fw["ports"][1]["speed"], C["wan"], 11, anchor="start", mono=True)
S.rect(CX - 170, SBY, 340, 62, rx=12, fill=PANEL, stroke=C["wan"] + "aa", sw=1.6)
S.text(CX, SBY + 26, f"{isp['name']} · {isp['type']}", 16, TEXT, 600, "middle")
S.text(CX, SBY + 46, isp["model"], 12.5, MUTED, 400, "middle")

# Sophos → Cisco cables (rightward, staggered so they don't cross)
fcables = []
for n in FW_ORDER:
    p = FWP[n]
    if not p.get("to"):
        continue
    unt, tg = p.get("untagged"), p.get("tagged", [])
    if tg:
        drawf = (lambda pts: S.trunk(pts, sw=trunk_w("1G")))
    else:
        drawf = (lambda pts, c=C[unt], s=p["speed"]: S.line(pts, c, SPEED_W[s]))
    fcables.append({"sx": FPX[n], "y": FJY + 30, "tx": CPORT[p["to"]], "ty": by, "draw": drawf})
route(fcables, oy + oh + 20, step=20)

device_card(ox, oy, ow, oh, ["sophos"], fw, C[LAB], stroke=TRUNK_BORDER)
for n in FW_ORDER:
    p = FWP[n]
    x = FPX[n]
    unt, tg = p.get("untagged"), p.get("tagged", [])
    fill, stroke = ("#2a3443", TRUNK) if tg else (C[unt] + "55", C[unt])
    jack(x - 24, FJY, 48, 36, fill, stroke)
    S.text(x, FJY - 7, n, 11, MUTED, 500, "middle", mono=True)
    ticks(x, FJY + 41, unt, tg)
    S.text(x + 32, FJY + 14, f"{p['zone']} · {p['speed']}", 11.5, C[unt], 600, mono=True)
    S.text(x + 32, FJY + 30, p["ip"], 11, MUTED, 500, mono=True)

# ================================================================ legend (right column)
LG_ROWS = ["trunk", "access", "wan", "kvm", "net", "speed", "dns", "ticks", "lag", "unknown"]
lgx, lgy, lgw = 1790, 320, 570
LR = 27
lgh = 52 + len(LG_ROWS) * LR + 4
S.rect(lgx, lgy, lgw, lgh, rx=14, fill=PANEL, stroke=BORDER, sw=1.4)
S.text(lgx + 20, lgy + 36, "Legend", 19, TEXT, 600)
SX, TX = lgx + 22, lgx + 162
for i, k in enumerate(LG_ROWS):
    y = lgy + 66 + i * LR
    t = None
    if k == "trunk":
        S.trunk([(SX, y), (SX + 50, y)], sw=trunk_w("1G"), r=0); t = "802.1Q trunk (tagged VLANs)"
    elif k == "access":
        for jj, c in enumerate(["192", "172", "12", STOR]):
            S.line([(SX + jj * 13, y), (SX + jj * 13 + 9, y)], C[c], 3.6, r=0, cap="butt")
        t = "access / single-VLAN link, colored by VLAN"
    elif k == "wan":
        S.line([(SX, y), (SX + 50, y)], C["wan"], 3, r=0); t = "WAN (Comporium, bridged)"
    elif k == "kvm":
        S.line([(SX, y), (SX + 50, y)], MUTED, 2, dash="5 5", r=0, cap="butt"); t = "NanoKVM console (HDMI + USB)"
    elif k == "net":
        S.line([(SX, y), (SX + 50, y)], MUTED, 1.8, dash="2 5", r=0); t = "over the internet (not a cable)"
    elif k == "speed":
        S.text(SX, y + 4.5, "line width = speed", 12.5, MUTED, 400)
        x0 = TX
        for lbl in ("2.5G", "1G", "100M"):
            S.line([(x0, y), (x0 + 26, y)], C[LAB], SPEED_W[lbl], r=0, cap="butt")
            S.text(x0 + 32, y + 4.5, lbl, 12, TEXT, 500, mono=True)
            x0 += 32 + tw(lbl, 12, True) + 20
    elif k == "dns":
        S.text(SX, y + 4.5, "host.homelab." + SHOWN_DOMAIN, 12, C[LAB], 400, mono=True, op=0.85)
        S.text(lgx + lgw - 20, y + 4.5, "local DNS (BIND on nuc-00)", 13, MUTED, 400, "end")
    elif k == "ticks":
        for jj, c in enumerate(["192", "172", "12"]):
            S.add(f'<rect x="{SX + jj*7}" y="{y-5 if jj == 0 else y-2}" width="5" height="{8 if jj == 0 else 5}" rx="1" fill="{C[c]}"/>')
        t = "port VLANs (tall = untagged, short = tagged)"
    elif k == "lag":
        jack(SX, y - 9, 22, 18, UNKNOWN + "44", UNKNOWN)
        jack(SX + 26, y - 9, 22, 18, UNKNOWN + "44", UNKNOWN)
        t = "LAG member / VLANs not known yet"
    elif k == "unknown":
        S.text(SX + 10, y + 5, "?", 15, "#f0883e", 700, "middle", mono=True); t = "not known yet, to fill in"
    if t:
        S.text(TX, y + 4.5, t, 13, MUTED, 400)
assert lgy + lgh < oy + oh + 20, "legend runs into the Sophos cables"

# ================================================================ core switch (Cisco SG300-28)
device_card(bx, by, bw, bh, ["cisco"], core, C[LAB], fill="#141b25", stroke=TRUNK_BORDER)
S.text((port_x(24) + port_x(27)) / 2, by + 12, "combo RJ45 / SFP", 10, FAINT, 500, "middle")
for i, p in enumerate(core["ports"]):
    x = port_x(i) - 24
    y = by + 30
    unt = p.get("untagged")
    tagged = p.get("tagged", [])
    if p["to"] == "free":
        fill, stroke = "#1b222c", "#3a475a"
    elif p.get("lag") or (not unt and not tagged):
        fill, stroke = UNKNOWN + "44", UNKNOWN
    elif unt and not tagged:
        fill, stroke = C[unt] + "55", C[unt]
    else:
        fill, stroke = "#2a3443", TRUNK
    jack(x, y, 48, 36, fill, stroke)
    S.text(port_x(i), y - 7, p["name"].replace("GE", ""), 11, MUTED, 500, "middle", mono=True)
    ticks(port_x(i), y + 41, unt, tagged)
    lbl = p.get("short", p["to"])
    S.text(port_x(i), by + bh - 9, lbl, 10.5, FAINT if p["to"] == "free" else ("#f0883e" if lbl == "?" else MUTED),
           500, "middle")
# LAG brackets under the paired ports
names = [p["name"] for p in core["ports"]]
for a, b_ in (("GE9", "GE10"), ("GE14", "GE15"), ("GE18", "GE19")):
    xa, xb = CPORT[a], CPORT[b_]
    S.line([(xa - 18, by + 76), (xa - 18, by + 82), (xb + 18, by + 82), (xb + 18, by + 76)], UNKNOWN, 1.2, r=0, cap="butt")
    S.text((xa + xb) / 2, by + 96, "LAG", 10, UNKNOWN, 700, "middle", mono=True)
assert port_x(len(core["ports"]) - 1) + 40 <= bx + bw, "core ports run past the card"

# ================================================================ lab switches + NUC columns
LY, LH = 1050, 140          # lab switch body
KY, KH = 1346, 44           # NanoKVM chips
NY, NH = 1450, 150          # NUC cards (body)
LS = INV["lab_switches"]
nodes = {n["name"]: n for n in INV["harvester"]["nodes"]}

# columns: (key, x, width)
COLS_NIC = [("nuc-00", 40, 270), ("nuc-04", 324, 250), ("nuc-05", 588, 250), ("nuc-06", 852, 250)]
COLS_MT = [("nuc-01", 1122, 280), ("nuc-02", 1416, 280), ("nuc-03", 1710, 280)]
NIC_X, NIC_W, NIC_P = 40, 1062, 52
MT_X, MT_W, MT_P = 1122, 868, 43
NAS_X, NAS_W = 2010, 350


def lport(x, pitch, i):
    """Center x of port i on a lab switch: 16 RJ45, then 2 SFP+."""
    if i < 16:
        return x + 20 + i * pitch + pitch / 2
    sw_ = pitch + 8
    return x + 20 + 16 * pitch + 14 + (i - 16) * (sw_ + 8) + sw_ / 2


def port_plan(sw):
    """Port index (0-based) -> (host, role) from inventory lab_switches.<sw>.ports.
    role: mgmt | stor | kvm | idle | ?   (a third item "assumed" = not traced yet)"""
    return {int(p) - 1: tuple(v) for p, v in LS[sw]["ports"].items()}


NIC_PLAN = port_plan("nicgiga")
NIC_PLAN[14] = ("cisco", "up")
NIC_PLAN[15] = ("mikrotik", "link")
MT_PLAN = port_plan("mikrotik")
MT_PLAN[15] = ("nicgiga", "link")


def entries(key, x, w):
    """Where the cables enter a column: kvm chip top center, mgmt + storage into the card body."""
    if key == "nuc-00":
        return {"mgmt": x + w - 40}
    return {"kvm": x + 75, "mgmt": x + w - 60, "stor": x + w - 25}


def role_style(role, key):
    """(color, width, untagged, tagged) of a lab link."""
    if role in ("?", "idle"):
        return UNKNOWN, SPEED_W["1G"], None, []
    if role == "kvm":
        return C[LAB], SPEED_W["100M"], LAB, []
    if role == "stor":
        return C[STOR], SPEED_W[nodes[key]["storage"]], None, [STOR]
    spd = INV["nuc00"]["speed"] if key == "nuc-00" else nodes[key]["mgmt"]
    return C[LAB], SPEED_W[spd], LAB, []


def lab_switch(sw, x, w, pitch, plan):
    folder(x, LY, w, LH, tab_width(sw), "#141b25", TRUNK_BORDER, 1.6)
    S.add(f'<text x="{x+16}" y="{LY-10}" font-family="{SANS}" fill="{TEXT}">'
          f'<tspan font-size="20" font-weight="700">{esc(sw["name"])}</tspan>'
          f'<tspan dx="7" font-size="20" font-weight="700" fill-opacity="0.6">·</tspan>'
          f'<tspan dx="7" font-size="14" font-weight="600">{esc(sw["type"])}</tspan></text>')
    S.icon("mikrotik-l" if "MikroTik" in sw["model"] else "glyph-nic", x + 14, LY + 12, 30)
    S.text(x + 54, LY + 26, sw["model"], 14, TEXT, 500)
    if sw.get("ip"):
        addr(x + 54, LY + 45, sw["ip"], sw, C[LAB])
    else:
        S.text(x + 54, LY + 45, "unmanaged · no IP · passes tagged frames", 12, MUTED, 400)
    jy = LY + 64
    groups = {}
    for i in range(18):
        cx_ = lport(x, pitch, i)
        sfp = i >= 16
        jw = (pitch + 8 if sfp else pitch - 8)
        used = plan.get(i)
        if not used:
            fill, stroke, unt, tg = "#1b222c", "#3a475a", None, []
        else:
            key, role = used[:2]
            if role in ("?", "idle"):
                unt, tg = None, []
            elif role in ("up",):
                unt, tg = LAB, []
            elif role == "link":
                unt, tg = LAB, [STOR]
            else:
                _, _, unt, tg = role_style(role, key)
            if role in ("?", "idle"):
                fill, stroke = "#2a3443", UNKNOWN
            elif unt and not tg:
                fill, stroke = C[unt] + "55", C[unt]
            elif tg and not unt:
                fill, stroke = C[tg[0]] + "33", C[tg[0]]
            else:
                fill, stroke = "#2a3443", TRUNK
            groups.setdefault(key, []).append(cx_)
        jack(cx_ - jw / 2, jy, jw, 32, fill, stroke, sfp)
        S.text(cx_, jy - 5, str(i + 1), 10, FAINT, 500, "middle", mono=True)
        if used:
            ticks(cx_, jy + 37, unt, tg)
            S.text(cx_, LY + LH - 24, used[1] + ("?" if "assumed" in used[2:] else ""), 9.5,
                   "#f0883e" if "assumed" in used[2:] else MUTED, 500, "middle")
            if used and used[0] not in ("cisco", "mikrotik", "nicgiga"):   # host per port: they interleave
                S.text(cx_, LY + LH - 9, used[0], 9, TEXT, 600, "middle")


# cables above the lab switches: Cisco → NICGIGA, Cisco → NAS, NICGIGA ↔ MikroTik
nic_up = lport(NIC_X, NIC_P, 14)
nic_link = lport(NIC_X, NIC_P, 15)
mt_link = lport(MT_X, MT_P, 15)
NAS_IN = {"GE2": NAS_X + 190, "GE9": NAS_X + 236, "GE10": NAS_X + 270}
up = [
    {"sx": CPORT["GE1"], "y": SB, "tx": nic_up, "ty": LY,
     "draw": lambda pts: S.line(pts, C[LAB], SPEED_W[LS["nicgiga"]["uplink"]["speed"]])},
    {"sx": CPORT["GE2"], "y": SB, "tx": NAS_IN["GE2"], "ty": NY,
     "draw": lambda pts: S.line(pts, C["192"], SPEED_W["1G"])},
    {"sx": CPORT["GE9"], "y": SB, "tx": NAS_IN["GE9"], "ty": NY,
     "draw": lambda pts: S.line(pts, UNKNOWN, SPEED_W["1G"])},
    {"sx": CPORT["GE10"], "y": SB, "tx": NAS_IN["GE10"], "ty": NY,
     "draw": lambda pts: S.line(pts, UNKNOWN, SPEED_W["1G"])},
]
lvl_end = route(up, SB + 16, step=14)
LINK_Y = lvl_end + 6
S.trunk([(nic_link, LY), (nic_link, LINK_Y), (mt_link, LINK_Y), (mt_link, LY)], sw=trunk_w(LS["mikrotik"]["uplink"]["speed"]))
assert LINK_Y < LY - TAB - 4, f"not enough room above the lab switches: {LINK_Y} vs {LY - TAB}"
S.label((nic_link + mt_link) / 2, LINK_Y + 4, "port 16 ↔ port 16 · 1G copper · VLAN 12 + 128", TRUNK, 11, mono=True)
speed_tag(nic_up + 6, LY - 12, "1G", C[LAB])

lab_switch(LS["nicgiga"], NIC_X, NIC_W, NIC_P, NIC_PLAN)
lab_switch(LS["mikrotik"], MT_X, MT_W, MT_P, MT_PLAN)


ENT = {key: entries(key, cx, cw) for key, cx, cw in COLS_NIC + COLS_MT}


def lab_cable(x, pitch, i, key, role):
    col, wdt, _, _ = role_style(role, key)
    ty = KY if role == "kvm" else NY

    def draw(pts):
        S.line(pts, BG, wdt + 5)   # halo: crossings read as over/under
        S.line(pts, col, wdt)
    return {"sx": lport(x, pitch, i), "y": LY + LH, "tx": ENT[key][role], "ty": ty, "draw": draw}


# both switches' cables in one routing pass: KVMs and storage cross between the switches
cab = [lab_cable(x, pitch, i, used[0], used[1])
       for x, pitch, plan in ((NIC_X, NIC_P, NIC_PLAN), (MT_X, MT_P, MT_PLAN))
       for i, used in sorted(plan.items()) if used[0] in ENT and used[1] in ENT[used[0]]]
end = route(cab, LY + LH + 12, step=9)
assert end <= KY - 4, f"lab cables need more room: {end} > {KY - 4}"

# ---- Harvester panel geometry (NUC cards connect to it)
HX = COLS_NIC[1][1]
HW = COLS_MT[-1][1] + COLS_MT[-1][2] - HX
HY = NY + NH + 40
hv = INV["harvester"]
CL_H = 250
HH = 112 + CL_H + 20
# nuc-00's card lists services + VMs; the bottom row grows to fit it
N0_NEED = NY + 138 + len(INV["nuc00"]["services"]) * 46 + 26 + len(INV["nuc00"]["vms"]) * 50 + 8
PB = max(HY + HH, N0_NEED)       # bottom of the tall cards (nuc-00, NAS) and the Harvester panel
HH = PB - HY

for key, cx, cw in COLS_NIC[1:] + COLS_MT:
    S.line([(cx + cw / 2, NY + NH), (cx + cw / 2, HY)], MUTED, 1.6, dash="3 4", cap="butt")


def kvm_chip(key, x):
    n = nodes[key]
    S.line([(x + 75, KY + KH), (x + 75, NY - TAB)], MUTED, 2, dash="5 5", cap="butt")
    S.rect(x, KY, 150, KH, rx=9, fill=CHIP, stroke=C[LAB] + "99", sw=1.2)
    S.icon("sipeed", x + 8, KY + 11, 22)
    S.text(x + 38, KY + 19, f"{key}-kvm", 12.5, TEXT, 600)
    S.text(x + 38, KY + 35, f".{n['kvm'].split('.')[-1]} · NanoKVM", 10.5, FAINT, 500, mono=True)


def nuc_card(key, x, w):
    n = nodes[key]
    g = {"name": key, "type": n["gen"]}
    folder(x, NY, w, NH, tab_width(g), PANEL, TRUNK_BORDER, 1.6)
    S.add(f'<text x="{x+16}" y="{NY-10}" font-family="{SANS}" fill="{TEXT}">'
          f'<tspan font-size="20" font-weight="700">{esc(key)}</tspan>'
          f'<tspan dx="7" font-size="20" font-weight="700" fill-opacity="0.6">·</tspan>'
          f'<tspan dx="7" font-size="14" font-weight="600">{esc(g["type"])}</tspan></text>')
    S.icon("intel", x + w - 46, NY + 12, 30)
    S.text(x + 14, NY + 26, "Intel " + n["model"], 14, TEXT, 600)
    S.text(x + 14, NY + 44, n["cpu"], 12, MUTED, 400)
    S.text(x + 14, NY + 60, f"{n['ram']} · {n['disks']}", 12, MUTED, 400)
    S.text(x + 14, NY + 82, n["ip"], 12, C[LAB], 500, mono=True)
    S.text(x + 14, NY + 98, f"{key}.prime.{SHOWN_DOMAIN}", 10.5, C[LAB], 400, mono=True, op=0.85)
    S.text(x + 14, NY + 120, f"onboard {n['mgmt']} → mgmt", 11, FAINT, 500)
    usb = f"USB-C {n['storage_nic']} @ {n['storage']}" if n.get("storage_nic") else f"USB-C {n['storage']}"
    S.text(x + 14, NY + 136, f"{usb} → storage", 11, FAINT, 500)
    e = ENT[key]
    S.label(e["mgmt"], KY + 18, n["mgmt"], C[LAB], 10.5, mono=True)
    S.label(e["stor"], KY + 42, n["storage"], C[STOR], 10.5, mono=True)


for key, cx, cw in COLS_NIC[1:] + COLS_MT:
    kvm_chip(key, cx)
    nuc_card(key, cx, cw)
assert tab_width({"name": "nuc-04", "type": "gen13"}) + 16 < 250 - 60, "NUC tab runs under the cables"

# ---- nuc-00 (admin host): tall card with services + VMs
n0 = INV["nuc00"]
x0, w0 = COLS_NIC[0][1], COLS_NIC[0][2]
folder(x0, NY, w0, PB - NY, tab_width(n0), PANEL, C[LAB] + "aa", 1.6)
S.add(f'<text x="{x0+16}" y="{NY-10}" font-family="{SANS}" fill="{TEXT}">'
      f'<tspan font-size="20" font-weight="700">{esc(n0["name"])}</tspan>'
      f'<tspan dx="7" font-size="20" font-weight="700" fill-opacity="0.6">·</tspan>'
      f'<tspan dx="7" font-size="14" font-weight="600">{esc(n0["type"])}</tspan></text>')
S.icon("intel", x0 + w0 - 46, NY + 12, 30)
m1, m2 = n0["model"].split(" · ", 1)
S.text(x0 + 14, NY + 26, m1, 14, TEXT, 600)
S.text(x0 + 14, NY + 44, m2, 12, MUTED, 400)
S.text(x0 + 14, NY + 66, n0["ip"], 12, C[LAB], 500, mono=True)
S.text(x0 + 14, NY + 82, f"{n0['dns']}.{SHOWN_DOMAIN}", 10.5, C[LAB], 400, mono=True, op=0.85)
S.text(x0 + 14, NY + 100, n0["os"], 12, MUTED, 400)
S.label(ENT["nuc-00"]["mgmt"], KY + 18, n0["speed"], C[LAB], 10.5, mono=True)
yy = NY + 128
S.text(x0 + 14, yy, "SERVICES", 11.5, HWC, 700, ls=1.4)
yy += 10
for sv in n0["services"]:
    S.rect(x0 + 12, yy, w0 - 24, 40, rx=8, fill=CHIP, stroke=BORDER, sw=1)
    S.icon(sv["icon"], x0 + 20, yy + 9, 22)
    S.text(x0 + 52, yy + 17, sv["name"], 13, TEXT, 600)
    S.text(x0 + 52, yy + 32, sv["note"], 10.5, MUTED, 400)
    yy += 46
yy += 16
S.text(x0 + 14, yy, "VMs (libvirt)", 11.5, HWC, 700, ls=1.4)
yy += 10
for vm in n0["vms"]:
    S.rect(x0 + 12, yy, w0 - 24, 44, rx=8, fill=CHIP, stroke=BORDER, sw=1)
    S.icon(vm["icon"], x0 + 20, yy + 11, 22)
    S.text(x0 + 52, yy + 19, vm["name"], 13, TEXT, 600)
    S.text(x0 + w0 - 22, yy + 19, vm["ip"], 11, FAINT if vm["ip"] != "?" else "#f0883e", 500, "end", mono=True)
    S.text(x0 + 52, yy + 35, vm["note"], 10.5, MUTED, 400)
    yy += 50
assert yy <= PB - 4, f"nuc-00 card too short: {yy} > {PB}"

# ---- NAS (TrueNAS) on the Cisco
nas = INV["nas"]
folder(NAS_X, NY, NAS_W, PB - NY, tab_width(nas), PANEL, TRUNK_BORDER, 1.6)
S.add(f'<text x="{NAS_X+16}" y="{NY-10}" font-family="{SANS}" fill="{TEXT}">'
      f'<tspan font-size="20" font-weight="700">{esc(nas["name"])}</tspan>'
      f'<tspan dx="7" font-size="20" font-weight="700" fill-opacity="0.6">·</tspan>'
      f'<tspan dx="7" font-size="14" font-weight="600">{esc(nas["type"])}</tspan></text>')
S.icon("truenas", NAS_X + NAS_W - 50, NY + 12, 34)
m1, m2 = nas["model"].split(" · ", 1)
S.text(NAS_X + 14, NY + 26, m1, 14, TEXT, 600)
S.text(NAS_X + 14, NY + 44, m2, 12, MUTED, 400)
S.text(NAS_X + 14, NY + 66, nas["ip"], 12, C[LAB], 500, mono=True)
S.text(NAS_X + 14, NY + 82, f"{nas['dns']}.{SHOWN_DOMAIN}", 10.5, C[LAB], 400, mono=True, op=0.85)
S.text(NAS_X + 14, NY + 100, nas["os"], 12, MUTED, 400)
S.text(NAS_X + 14, NY + 122, "GE2 · VLAN 192 (LAN leg)", 11, C["192"], 500, mono=True)
S.text(NAS_X + 14, NY + 138, "GE9 + GE10 · LAG · VLAN ?", 11, UNKNOWN, 500, mono=True)
speed_tag(NAS_IN["GE2"] - 6, KY + 18, "1G", C["192"], anchor="end")
S.add(f'<ellipse cx="{(NAS_IN["GE9"] + NAS_IN["GE10"]) / 2}" cy="{KY + 22}" rx="30" ry="10" fill="none" '
      f'stroke="{UNKNOWN}" stroke-width="1.4" stroke-dasharray="3 3"/>')
S.label((NAS_IN["GE9"] + NAS_IN["GE10"]) / 2, KY + 52, "LAG 2× 1G", UNKNOWN, 10.5, mono=True)
# pool
pool = nas["pool"]
py_ = NY + 160
S.rect(NAS_X + 12, py_, NAS_W - 24, 150, rx=10, fill=CHIP, stroke=BORDER, sw=1)
S.text(NAS_X + 26, py_ + 24, f"pool {pool['name']}", 15.5, TEXT, 700)
S.text(NAS_X + 26, py_ + 42, pool["layout"], 12, MUTED, 400)
dx = NAS_X + 26
for _ in range(3):
    S.rect(dx, py_ + 56, 30, 40, rx=4, fill=DISK, stroke=DISK_EDGE, sw=1.2)
    S.add(f'<circle cx="{dx+15}" cy="{py_+72}" r="9" fill="none" stroke="{C[LAB]}" stroke-width="1.6"/>'
          f'<circle cx="{dx+15}" cy="{py_+72}" r="2" fill="{C[LAB]}"/>')
    dx += 37
S.text(dx + 8, py_ + 72, "3× 4 TB HDD", 12.5, TEXT, 500)
S.text(dx + 8, py_ + 88, "used / free: ?", 11.5, MUTED, 400)
S.text(NAS_X + 26, py_ + 122, "+ 1 TB SSD (boot)", 11.5, MUTED, 400)
S.text(NAS_X + 26, py_ + 138, pool["note"], 11, FAINT, 400)

# ---- Harvester cluster panel
S.rect(HX, HY, HW, HH, rx=14, fill="#0f151e", stroke=TRUNK_BORDER, sw=2)
S.icon("harvester", HX + 18, HY + 18, 44)
S.text(HX + 74, HY + 42, f"Harvester cluster · {hv['name']}", 22, TEXT, 700)
S.text(HX + 74, HY + 64, f"{hv['version']} · {len(hv['nodes'])} nodes (nuc-01 … nuc-06) · VIP", 13, MUTED, 400)
vipx = HX + 74 + measure(f"{hv['version']} · {len(hv['nodes'])} nodes (nuc-01 … nuc-06) · VIP", 13, 400) + 6
addr(vipx, HY + 64, hv["vip"], {"dns": hv["dns"]}, C[LAB])
S.text(HX + 74, HY + 84, hv["storage_note"], 12, MUTED, 400)
# totals as hardware tiles
thr = sum(int(n["cpu"].split("/")[-1].rstrip("T")) for n in hv["nodes"])
tiles = [("glyph-cpu", "CPU", f"{thr} threads", "3× i7-10710U · 3× i7-1360P"),
         ("glyph-ram", "MEMORY", f"{sum(int(n['ram'].split()[0]) for n in hv['nodes'])} GB", "6× 64 GB"),
         ("glyph-ssd", "SSD", "6× 2 TB", "one per node"),
         ("glyph-ssd", "NVMe", "6× 1 TB", "one per node")]
tx_ = HX + HW - 16 - len(tiles) * 196 + 10
for ic, lb, val, sb in tiles:
    S.rect(tx_, HY + 18, 186, 58, rx=11, fill="#151d29", stroke="#2e3a4c", sw=1.2)
    hw_bar(tx_, HY + 18, 58)
    S.icon(ic, tx_ + 12, HY + 33, 28)
    S.text(tx_ + 50, HY + 35, lb, 10, HWC, 700, ls=1.3)
    S.text(tx_ + 50, HY + 53, val, 15.5, TEXT, 700)
    S.text(tx_ + 50, HY + 68, sb, 10.5, MUTED, 400)
    tx_ += 196
assert HX + 74 + measure(hv["storage_note"], 12, 400) < HX + HW - 16 - len(tiles) * 196, "Harvester header text runs into the tiles"

S.text(HX + 20, HY + 104, "RKE2 GUEST CLUSTERS · SL Micro 6.2 VMs", 11.5, HWC, 700, ls=1.4)
cg = 16
cw_ = (HW - 32 - cg * 2) / 3
for k, cl in enumerate(hv["clusters"]):
    x = HX + 16 + k * (cw_ + cg)
    y = HY + 114
    S.rect(x, y, cw_, CL_H, rx=12, fill=PANEL, stroke=C[LAB] + "88", sw=1.4)
    S.icon(cl["icon"], x + 16, y + 14, 34)
    S.text(x + 60, y + 30, cl["name"], 18, TEXT, 600)
    S.text(x + 60 + measure(cl["name"], 18, 600) + 10, y + 30, cl["what"], 12.5, MUTED, 400)
    addr(x + 60, y + 50, "VIP " + cl["vip"], {"dns": cl["dns"]}, C[LAB])
    S.text(x + 60, y + 68, cl["k8s"], 12, MUTED, 400)
    vx_ = x + 16
    for vm in cl["vms"]:
        vw_ = (cw_ - 32 - 2 * 8) / 3
        S.rect(vx_, y + 84, vw_, 40, rx=8, fill=CHIP, stroke=BORDER, sw=1)
        S.text(vx_ + 10, y + 101, vm["name"], 12.5, TEXT, 600)
        S.text(vx_ + 10, y + 117, f"VM · {vm['ip']}", 10.5, FAINT, 500, mono=True)
        vx_ += vw_ + 8
    S.text(x + 16, y + 146, "WORKLOADS", 10.5, HWC, 700, ls=1.3)
    for j, a in enumerate(cl["apps"]):
        ry = y + 156 + j * 26
        S.icon(a["icon"], x + 16, ry, 20)
        S.text(x + 44, ry + 15, a["name"], 13, TEXT, 600)
        S.text(x + 44 + measure(a["name"], 13, 600) + 10, ry + 15, a["note"], 11.5, MUTED, 400)
    assert y + 156 + len(cl["apps"]) * 26 <= y + CL_H, f"cluster {cl['name']} card too short"

# ---------------------------------------------------------------- canvas height
H = int(PB + 40)
S.rect(0, 0, W, H, rx=0, fill=BG, stroke=BG, sw=0)
S.rect(0, 0, W, H, rx=0, fill="url(#dots)", stroke="none", sw=0)
dots = S.p.pop()
S.p[BG_IDX], S.p[BG_IDX + 1] = S.p.pop(), dots

OUT.mkdir(exist_ok=True)
name = "homelab-unredacted" if UNREDACTED else "homelab"
svg_path = OUT / f"{name}.svg"
svg_path.write_text(S.render())
png_path = OUT / f"{name}.png"
subprocess.run(["rsvg-convert", "-z", "1.6", "-o", str(png_path), str(svg_path)], check=True)
print(svg_path, png_path)
