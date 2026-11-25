#!/usr/bin/env python3
"""Render the Kubernetes view of the homelab (same look as build.py) from inventory.yaml.

Usage: python3 build_k8s.py [--unredacted] [--inventory FILE]
                                         → out/kubernetes.svg + out/kubernetes.png
Content: the `kubernetes:` section of inventory.yaml plus `harvester:` (nodes, clusters, VIPs).
Palette, fonts and drawing helpers come from build.py (everything above its
"background + header" marker), so both pictures stay in the same style.
Layout is hand-placed, like build.py.
"""
import pathlib
import subprocess

_SRC = (pathlib.Path(__file__).resolve().parent / "build.py").read_text()
_MARK = "# ---------------------------------------------------------------- background + header"
assert _MARK in _SRC, "build.py layout marker moved, update build_k8s.py"
exec(compile(_SRC.split(_MARK)[0], "build.py", "exec"))   # noqa: S102 - our own file: palette + helpers

K = INV["kubernetes"]
HV = INV["harvester"]
KH = K["harvester"]
for n in K["networks"]:
    if n.get("color"):
        C[n["key"]] = n["color"]
for k in ("12", "128", "ts"):
    assert k in C
LABC = C["12"]
STORC = C["128"]
MANAGE = "#c3cdd9"     # Rancher "manages" arrows


def section(x, y, s):
    S.text(x, y, s, 10.5, HWC, 700, ls=1.3)


def kv(x, y, key, val, kw=78, vcol=TEXT, mono=False, size=12.5):
    """Small key/value row: key in faint mono, value next to it ("?" values in orange)."""
    S.text(x, y, key, 10.5, FAINT, 600, mono=True)
    col = "#f0883e" if "?" in str(val) else vcol
    S.text(x + kw, y, val, size, col, 500 if mono else 400, mono=mono)


def chip(x, y, s, color, size=11):
    """Small CIDR chip in a network color; returns its width."""
    return S.pill(x, y, s, color, size=size, mono=True, h=20, pad=7, weight=500)


# ---------------------------------------------------------------- background + header
S.add(f'<defs><pattern id="dots" width="24" height="24" patternUnits="userSpaceOnUse">'
      f'<circle cx="1.5" cy="1.5" r="1.3" fill="{GRID}"/></pattern>'
      f'<marker id="arr" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="7" markerHeight="7" orient="auto">'
      f'<path d="M0,0 L10,5 L0,10 z" fill="{MANAGE}"/></marker></defs>')
BG_IDX = len(S.p)
S.add("")
S.add("")
meta = INV["meta"]
S.icon("kubernetes", 40, 44, 52)
S.text(106, 86, K["title"], 46, TEXT, 700, ls=-0.5)
S.text(W - 40, 74, meta["watermark"], 21, REDDIT, 700, "end")
S.text(W - 40, 100, f"{meta['date']} · ENVIRONMENT={K['env']}", 16, MUTED, 400, "end")

ROW1 = 150

# ================================================================ networks (left)
vx, vw = 40, 500
nets = K["networks"]
vh = 70 + len(nets) * 60
eh = 60 + len(K["endpoints"]) * 50
ROW1_END = max(ROW1 + vh, ROW1 + eh + 16 + 46 + max(len(K["trust"]), len(K["registries"])) * 48 + 10)
vh = ROW1_END - ROW1
S.rect(vx, ROW1, vw, vh, rx=14, fill=PANEL, stroke=BORDER, sw=1.4)
S.text(vx + 20, ROW1 + 36, "Kubernetes networks", 19, TEXT, 600)
for i, v in enumerate(nets):
    y = ROW1 + 56 + i * 60
    col = C[v["key"]]
    S.rect(vx + 14, y, vw - 28, 52, rx=9, fill=CHIP, stroke=col + "55", sw=1)
    S.add(f'<rect x="{vx+14}" y="{y}" width="6" height="52" rx="3" fill="{col}"/>')
    S.text(vx + 32, y + 22, v["tag"], 13, col, 600, mono=True)
    S.text(vx + 128, y + 22, v["name"], 15.5, TEXT, 600)
    S.text(vx + vw - 28, y + 22, v["subnet"], 13.5, TEXT, 500, "end", mono=True)
    S.text(vx + 32, y + 42, v["note"], 12, MUTED, 400)

# ================================================================ endpoints (middle top)
ex, ew = 572, 1186
eps = K["endpoints"]
eh = 60 + len(eps) * 50
S.rect(ex, ROW1, ew, eh, rx=14, fill=PANEL, stroke=LABC + "aa", sw=1.6)
S.add(f'<rect x="{ex+1}" y="{ROW1+14}" width="4" height="{eh-28}" rx="2" fill="{LABC}"/>')
S.text(ex + 20, ROW1 + 36, "Endpoints", 19, TEXT, 600)
S.text(ex + 20 + measure("Endpoints", 19, 600) + 12, ROW1 + 36,
       "DNS (BIND on nuc-00) → VIP on VLAN 12 → backend", 13, MUTED, 400)
for i, e in enumerate(eps):
    y = ROW1 + 52 + i * 50
    S.rect(ex + 14, y, ew - 28, 42, rx=9, fill=CHIP, stroke=BORDER, sw=1)
    S.icon(e["icon"], ex + 24, y + 9, 24)
    S.text(ex + 58, y + 26, fqdn(e["dns"]), 13, LABC, 500, mono=True)
    S.text(ex + 380, y + 26, e["ip"], 13, TEXT, 600, mono=True)
    S.text(ex + 510, y + 26, e["ports"], 12, MUTED, 500, mono=True)
    S.text(ex + 700, y + 26, "→ " + e["backend"], 12.5,
           "#f0883e" if "?" in e["backend"] else TEXT, 400)

# trust + registries under the endpoints
ty = ROW1 + eh + 16
th = ROW1_END - ty
pw = (ew - 16) / 2
for k, (title, rows) in enumerate((("TLS & trust", K["trust"]), ("Registries", K["registries"]))):
    px = ex + k * (pw + 16)
    S.rect(px, ty, pw, th, rx=14, fill=PANEL, stroke=BORDER, sw=1.4)
    S.text(px + 20, ty + 32, title, 17, TEXT, 600)
    for j, r in enumerate(rows):
        ry = ty + 46 + j * 48
        S.rect(px + 14, ry, pw - 28, 42, rx=9, fill=PANEL2, stroke=BORDER, sw=1)
        S.icon(r["icon"], px + 24, ry + 9, 24)
        S.text(px + 58, ry + 18, r["name"], 13.5, TEXT, 600)
        S.text(px + 58, ry + 34, r["note"], 11, MUTED, 400)
    assert ty + 46 + len(rows) * 48 <= ty + th, f"{title} panel too short"

# ================================================================ legend + AWS (right)
lgx, lgw = 1790, 570
LG = ["manage", "vm", "access", "cidr", "speed", "dns", "unknown"]
LR = 27
lgh = 52 + len(LG) * LR + 4
S.rect(lgx, ROW1, lgw, lgh, rx=14, fill=PANEL, stroke=BORDER, sw=1.4)
S.text(lgx + 20, ROW1 + 36, "Legend", 19, TEXT, 600)
SX, TX = lgx + 22, lgx + 162
for i, k in enumerate(LG):
    y = ROW1 + 66 + i * LR
    t = None
    if k == "manage":
        S.add(f'<path d="M{SX},{y} H{SX+48}" stroke="{MANAGE}" stroke-width="2" marker-end="url(#arr)"/>')
        t = "Rancher provisions / manages"
    elif k == "vm":
        S.line([(SX, y), (SX + 50, y)], LABC, 2, dash="6 5", r=0, cap="butt"); t = "runs as KubeVirt VMs on Harvester"
    elif k == "access":
        S.line([(SX, y), (SX + 22, y)], LABC, 3.6, r=0, cap="butt")
        S.line([(SX + 28, y), (SX + 50, y)], STORC, 3.6, r=0, cap="butt")
        t = "node NIC on VLAN 12 (mgmt) / VLAN 128 (storage)"
    elif k == "cidr":
        chip(SX, y - 10, "10.42/16", C["pod"], 10); t = "in-cluster CIDR (pods / services)"
    elif k == "speed":
        S.text(SX, y + 4.5, "line width = speed", 12.5, MUTED, 400)
        x0 = TX
        for lbl in ("2.5G", "1G"):
            S.line([(x0, y), (x0 + 26, y)], LABC, SPEED_W[lbl], r=0, cap="butt")
            S.text(x0 + 32, y + 4.5, lbl, 12, TEXT, 500, mono=True)
            x0 += 32 + tw(lbl, 12, True) + 20
    elif k == "dns":
        S.text(SX, y + 4.5, "host.prime." + SHOWN_DOMAIN, 12, LABC, 400, mono=True, op=0.85)
        S.text(lgx + lgw - 20, y + 4.5, "local DNS (BIND on nuc-00)", 13, MUTED, 400, "end")
    elif k == "unknown":
        S.text(SX + 10, y + 5, "?", 15, "#f0883e", 700, "middle", mono=True); t = "not known yet / assumed, to fill in"
    if t:
        S.text(TX, y + 4.5, t, 13, MUTED, 400)

aws = INV["aws"]
ra = next(i for i in aws["instances"] if i["icon"] == "rancher")
ay = ROW1 + lgh + 16
ah = ROW1_END - ay
S.rect(lgx, ay, lgw, ah, rx=14, fill=PANEL, stroke=C["aws"] + "aa", sw=1.6, dash="6 4")
S.add(f'<rect x="{lgx+1}" y="{ay+14}" width="4" height="{ah-28}" rx="2" fill="{C["aws"]}"/>')
S.icon("aws-l", lgx + 16, ay + 14, 30)
S.text(lgx + 56, ay + 32, f"Hybrid option · RANCHER_LOCATION=aws", 15, TEXT, 600)
S.icon("rancher", lgx + 20, ay + 56, 24)
S.text(lgx + 56, ay + 66, ra["name"], 14, TEXT, 600)
S.text(lgx + lgw - 20, ay + 66, ra["ip"], 12, C["aws"], 500, "end", mono=True)
S.text(lgx + 56, ay + 84, ra["note"], 11.5, MUTED, 400)
S.text(lgx + 56, ay + 100, f"{ra['dns']}.{SHOWN_DOMAIN}", 10.5, C["aws"], 400, mono=True, op=0.85)
S.icon("tailscale", lgx + 20, ay + 116, 20)
S.text(lgx + 50, ay + 130, "manages Harvester + RKE2 on-prem over Tailscale", 12, C["ts"], 500)
assert ay + 140 <= ROW1_END, "AWS panel too short"

# ================================================================ guest RKE2 clusters
GY = ROW1_END + 90
GH = 520
cg = 20
cw = (W - 80 - 2 * cg) / 3
LANE = GY - 40
gx = [40 + k * (cw + cg) for k in range(3)]
HY = GY + GH + 70                       # Harvester panel top

# Rancher → downstream clusters + Harvester
src = gx[0] + cw - 90
S.add(f'<path d="{rounded([(src, GY), (src, LANE), (gx[2] + cw / 2, LANE), (gx[2] + cw / 2, GY - 4)], 10)}" '
      f'fill="none" stroke="{MANAGE}" stroke-width="2" marker-end="url(#arr)"/>')
S.add(f'<path d="M{gx[1] + cw / 2},{LANE} V{GY - 4}" stroke="{MANAGE}" stroke-width="2" marker-end="url(#arr)"/>')
S.add(f'<path d="{rounded([(gx[2] + cw / 2, LANE), (W - 20, LANE), (W - 20, HY + 40), (W - 44, HY + 40)], 10)}" '
      f'fill="none" stroke="{MANAGE}" stroke-width="2" marker-end="url(#arr)"/>')
S.label((src + gx[1] + cw / 2) / 2, LANE + 4, "provisions + manages · Harvester node driver", MANAGE, 12)
S.label((gx[1] + gx[2] + cw) / 2 + 10, LANE + 4, "imports prime-harvester · Virtualization Management", MANAGE, 12)

gmeta = K["guests"]
for k, cl in enumerate(HV["clusters"]):
    g = gmeta[cl["name"]]
    x, y = gx[k], GY
    planned = g.get("status") == "planned"
    S.rect(x, y, cw, GH, rx=14, fill=PANEL, stroke=LABC + ("66" if planned else "aa"), sw=1.6,
           dash="8 6" if planned else None)
    S.add(f'<rect x="{x+1}" y="{y+14}" width="4" height="{GH-28}" rx="2" fill="{LABC}" opacity="{0.45 if planned else 1}"/>')
    if planned:
        S.pill(x + cw - 16, y + 16, "PLANNED · not deployed yet", "#f0883e", size=11, anchor="end", h=22)
    S.icon(cl["icon"], x + 18, y + 16, 38)
    S.text(x + 68, y + 36, cl["name"], 22, TEXT, 700)
    S.text(x + 68 + measure(cl["name"], 22, 700) + 10, y + 36, cl["what"], 13, MUTED, 400)
    addr(x + 68, y + 57, "VIP " + cl["vip"], {"dns": cl["dns"]}, LABC)
    S.text(x + 68, y + 76, f"{cl['k8s']} · SL Micro 6.2 · {g['provisioned']}", 12, MUTED, 400)

    # nodes (VMs)
    vms = cl["vms"]
    vw_ = (cw - 32 - 2 * 8) / 3
    for j, vm in enumerate(vms):
        cx = x + 16 + j * (vw_ + 8)
        S.rect(cx, y + 92, vw_, 50, rx=8, fill=CHIP, stroke=BORDER, sw=1)
        S.text(cx + 10, y + 112, vm["name"], 13, TEXT, 600)
        on = g.get("placement", {}).get(vm["name"])
        ip = g.get("live_ips", {}).get(vm["name"], vm["ip"])
        S.text(cx + 10, y + 130, f"VM · {ip}" + (f" · on {on}" if on else ""), 10.5, FAINT, 500, mono=True)
    kv(x + 16, y + 162, "vm", f"{g['vm_size']} · ns {g['namespace']}", vcol=MUTED, size=11.5)

    section(x + 16, y + 192, "NETWORK")
    ny = y + 214
    S.text(x + 16, ny, "cni", 10.5, FAINT, 600, mono=True)
    cni = g.get("cni", "Canal")
    S.text(x + 94, ny, cni, 12.5, TEXT, 500)
    cx = x + 94 + measure(cni, 12.5, 400) + 12
    cx += chip(cx, ny - 14, "pods 10.42.0.0/16", C["pod"]) + 6
    chip(cx, ny - 14, "svcs 10.43.0.0/16", C["svc"])
    kv(x + 16, ny + 26, "ingress", g["ingress"])
    kv(x + 16, ny + 52, "vip", f"{cl['vip']} · Harvester LB on vmnet-vms" + (" ?" if planned else ""))

    section(x + 16, y + 312, "STORAGE")
    kv(x + 16, y + 334, "vm disk", g["vm_sc"], mono=True, size=12)
    kv(x + 16, y + 360, "pvc", g["pvc_sc"], mono=True, size=12)

    section(x + 16, y + 394, "WORKLOADS")
    apps = g.get("apps", cl["apps"]) + g.get("extra_apps", [])
    for j, a in enumerate(apps):
        ry = y + 406 + j * 26
        S.icon(a["icon"], x + 16, ry, 20)
        S.text(x + 44, ry + 15, a["name"], 13, TEXT, 600)
        S.text(x + 44 + measure(a["name"], 13, 600) + 10, ry + 15, a["note"], 11.5, MUTED, 400)
    assert y + 406 + len(apps) * 26 <= y + GH - 8, f"cluster {cl['name']} card too short"

    # runs on Harvester
    mx = x + cw / 2
    S.line([(mx, y + GH), (mx, HY)], LABC, 2, dash="6 5", r=0, cap="butt", op=0.5 if planned else 1)
    S.label(mx, y + GH + 40, "KubeVirt VMs · vmnet-vms · Longhorn volumes" + (" (planned)" if planned else ""),
            "#f0883e" if planned else LABC, 12)

# ================================================================ Harvester (host cluster)
HX, HW = 40, W - 80
S.rect(HX, HY, HW, 10, rx=16, fill="none", stroke="none", sw=0)   # placeholder, real panel drawn below
HP_IDX = len(S.p) - 1
S.icon("harvester", HX + 20, HY + 18, 44)
S.text(HX + 76, HY + 42, f"Harvester cluster · {HV['name']}", 22, TEXT, 700)
S.text(HX + 76 + measure(f"Harvester cluster · {HV['name']}", 22, 700) + 12, HY + 42,
       f"{HV['version']} · {KH['k8s']}", 13, MUTED, 400)
addr(HX + 76, HY + 64, "VIP " + HV["vip"], {"dns": HV["dns"]}, LABC)
hc = HX + 76 + len("VIP " + HV["vip"]) * 7.2 + 16 + len(fqdn(HV["dns"])) * 7.2 + 16
hc += chip(hc, HY + 50, "pods 10.52.0.0/16", C["hpod"]) + 6
chip(hc, HY + 50, "svcs 10.53.0.0/16", C["hsvc"])

# three sub-panels: compute / network / storage
SPY, SPH = HY + 92, 272
sg = 16
sw_ = (HW - 32 - 2 * sg) / 3
spx = [HX + 16 + k * (sw_ + sg) for k in range(3)]


def subpanel(x, title, sub_, icon):
    S.rect(x, SPY, sw_, SPH, rx=12, fill=PANEL2, stroke=BORDER, sw=1.2)
    S.icon(icon, x + 14, SPY + 14, 28)
    S.text(x + 52, SPY + 33, title, 16, TEXT, 600)
    S.text(x + 52 + measure(title, 16, 600) + 10, SPY + 33, sub_, 12, MUTED, 400)


# compute
subpanel(spx[0], "Compute", "KubeVirt VMs + images", "glyph-cpu")
cy = SPY + 64
for cl in HV["clusters"]:
    g = gmeta[cl["name"]]
    names = ", ".join(v["name"] for v in cl["vms"])
    S.rect(spx[0] + 14, cy, sw_ - 28, 38, rx=8, fill=CHIP, stroke=BORDER, sw=1)
    S.text(spx[0] + 26, cy + 16, names, 12.5, TEXT, 600)
    st = "planned · " if g.get("status") == "planned" else ""
    S.text(spx[0] + 26, cy + 31, f"{st}ns {g['namespace']} · {g['vm_size']}", 10.5,
           "#f0883e" if st or "?" in g["namespace"] + g["vm_size"] else FAINT, 500, mono=True)
    cy += 44
S.text(spx[0] + 16, cy + 16, "IMAGES · ns default", 10, FAINT, 700, ls=1.1)
ix = spx[0] + 16
iy = cy + 26
for im in KH["images"]:
    iw = tw(im, 11, True) + 14
    if ix + iw > spx[0] + sw_ - 14:
        ix, iy = spx[0] + 16, iy + 26
    chip(ix, iy, im, MUTED)
    ix += iw + 6
assert iy + 20 <= SPY + SPH - 8, "compute panel too short"

# network
subpanel(spx[1], "Network", "Multus cluster networks + LB", "glyph-nic")
ny = SPY + 64
for n in KH["networks"]:
    col = C[n["key"]]
    S.rect(spx[1] + 14, ny, sw_ - 28, 38, rx=8, fill=CHIP, stroke=col + "55", sw=1)
    S.add(f'<rect x="{spx[1]+14}" y="{ny}" width="5" height="38" rx="2.5" fill="{col}"/>')
    S.text(spx[1] + 28, ny + 16, n["name"], 12.5, TEXT, 600)
    S.text(spx[1] + 28, ny + 31, n["note"], 11, MUTED, 400)
    ny += 44
S.text(spx[1] + 16, ny + 14, "LOAD BALANCER · IP POOLS (VLAN 12)", 10, FAINT, 700, ls=1.1)
lx = spx[1] + 16
for e in eps:
    if e["dns"].startswith("harvester"):
        continue
    last = e["ip"].split(".")[-1]
    lbl = f".{last} {e['dns'].split('.')[0]}"
    lw = tw(lbl, 11, True) + 14
    if lx + lw > spx[1] + sw_ - 14:
        lx = spx[1] + 16
        ny += 26
    chip(lx, ny + 24, lbl, "#f0883e" if "planned" in e["backend"] or "?" in e["backend"] else LABC)
    lx += lw + 6
S.text(spx[1] + 16, ny + 66, "ippool-rancher → lb-rancher (workloadType vm, VM label) · ingress-expose → .100", 11, MUTED, 400)
S.text(spx[1] + 16, ny + 84, "orange = planned, no pool yet", 11, "#f0883e", 400)

# storage
subpanel(spx[2], "Storage", "Longhorn on the storage network", "longhorn")
sy = SPY + 64
for sc in KH["storage_classes"]:
    S.rect(spx[2] + 14, sy, sw_ - 28, 38, rx=8, fill=CHIP, stroke=STORC + "55", sw=1)
    S.text(spx[2] + 26, sy + 16, sc["name"], 12, TEXT, 600, mono=True)
    S.text(spx[2] + 26, sy + 31, sc["note"], 11, MUTED, 400)
    sy += 44
S.text(spx[2] + 16, sy + 12, KH["storage_classes_other"], 11, MUTED, 400, mono=False)
sy += 22
for ic, lb, val in (("glyph-ssd", "SSD", "6× 2 TB · one per node"), ("glyph-ssd", "NVMe", "6× 1 TB · one per node")):
    S.icon(ic, spx[2] + 16, sy + 2, 20)
    S.text(spx[2] + 44, sy + 17, lb, 10, HWC, 700, ls=1.3)
    S.text(spx[2] + 84, sy + 17, val, 12.5, TEXT, 500)
    sy += 26
kv(spx[2] + 16, sy + 16, "backup", KH["backups"], kw=56, size=12)

# nodes
NY = SPY + SPH + 28
NH = 128
ng = 16
nw = (HW - 32 - 5 * ng) / 6
nodes = HV["nodes"]
BUS_M = NY + NH + 46
BUS_S = BUS_M + 34
for j, n in enumerate(nodes):
    x = HX + 16 + j * (nw + ng)
    S.rect(x, NY, nw, NH, rx=12, fill=PANEL, stroke="#2e3a4c", sw=1.4)
    hw_bar(x, NY, NH)
    S.text(x + 16, NY + 26, n["name"], 17, TEXT, 700)
    S.text(x + 16 + measure(n["name"], 17, 700) + 8, NY + 26, n["gen"], 12.5, MUTED, 600)
    role = KH["roles"][n["gen"]]
    S.pill(x + nw - 12, NY + 11, role, "#bc8cff" if role == "control-plane" else LABC, size=10.5, anchor="end", h=20)
    S.text(x + 16, NY + 46, n["ip"], 12, LABC, 500, mono=True)
    S.text(x + 16, NY + 64, f"{n['cpu']} · {n['ram']}", 11.5, MUTED, 400)
    S.text(x + 16, NY + 81, n["disks"], 11.5, MUTED, 400)
    S.text(x + 16, NY + 100, f"onboard {n['mgmt']} → mgmt", 10.5, FAINT, 500, mono=True)
    S.text(x + 16, NY + 116, f"{KH['storage_nics'][n['gen']]} {n['storage']} → storage", 10.5, FAINT, 500, mono=True)
    mx, sx_ = x + nw * 0.38, x + nw * 0.62
    S.line([(mx, NY + NH), (mx, BUS_M)], LABC, SPEED_W[n["mgmt"]], r=0, cap="butt")
    S.line([(sx_, NY + NH), (sx_, BUS_S)], STORC, SPEED_W[n["storage"]], r=0, cap="butt")
    S.add(f'<circle cx="{mx}" cy="{BUS_M}" r="3.5" fill="{LABC}"/><circle cx="{sx_}" cy="{BUS_S}" r="3.5" fill="{STORC}"/>')
bx0, bx1 = HX + 16 + nw * 0.38 - 30, HX + 16 + 5 * (nw + ng) + nw * 0.62 + 30
S.line([(bx0, BUS_M), (bx1, BUS_M)], LABC, 2.4, r=0)
S.line([(bx0, BUS_S), (bx1, BUS_S)], STORC, 2.4, r=0)
lx = bx0
for col, txt in ((LABC, "mgmt-br · VLAN 12 · 10.10.15.0/24 · NICGIGA (2.5G) / MikroTik (1G)"),
                 (STORC, "storage · VLAN 128 · 192.168.128.0/24 · USB NICs")):
    S.line([(lx, BUS_S + 28), (lx + 26, BUS_S + 28)], col, 2.4, r=0, cap="butt")
    S.text(lx + 34, BUS_S + 32, txt, 11.5, col, 500, mono=True)
    lx += 34 + tw(txt, 11.5, True) + 40
HH = BUS_S + 52 - HY
S.p[HP_IDX] = (f'<rect x="{HX}" y="{HY}" width="{HW}" height="{HH}" rx="16" fill="#0f151e" '
               f'stroke="{C["12"]}aa" stroke-width="1.6"/>'
               f'<rect x="{HX+1}" y="{HY+16}" width="4" height="{HH-32}" rx="2" fill="{C["12"]}"/>')

# ---------------------------------------------------------------- canvas height + output
H = int(HY + HH + 40)
S.rect(0, 0, W, H, rx=0, fill=BG, stroke=BG, sw=0)
S.rect(0, 0, W, H, rx=0, fill="url(#dots)", stroke="none", sw=0)
dots = S.p.pop()
S.p[BG_IDX], S.p[BG_IDX + 1] = S.p.pop(), dots

OUT.mkdir(exist_ok=True)
name = "kubernetes-unredacted" if UNREDACTED else "kubernetes"
svg_path = OUT / f"{name}.svg"
svg_path.write_text(S.render())
png_path = OUT / f"{name}.png"
subprocess.run(["rsvg-convert", "-z", "1.6", "-o", str(png_path), str(svg_path)], check=True)
print(svg_path, png_path)
