#!/usr/bin/env python3
"""Rechnet die Radar-Geometrie in zuhause.liquid neu.

    radar-geometry.py QUELLE ZIEL BREITE [HÖHE] [--rivers CACHE.json]

An der Kartengröße hängen über zwanzig Zahlen — Fensterursprung, Tile-Offsets,
fünf Ortsmarken mit je zwei Rechtecken, fünf Labelpositionen, Trennstrichhöhe,
Spaltenbreite und jeder Punkt der Flusslinien. Von Hand ist das eine
Fehlerquelle, also macht es dieses Skript. Erst in eine Kopie schreiben,
rendern, vergleichen, dann übernehmen.

Ohne --rivers wird die Flussgeometrie bei Overpass geholt (OpenStreetMap) und
in die angegebene Datei gelegt; mit --rivers auf eine vorhandene Datei wird sie
von dort gelesen.
"""

import json, math, sys, urllib.parse, urllib.request
from pathlib import Path

TILE, Z, GAP = 256, 6, 8
LAT, LON = 49.8728, 8.6512
TOL, MARGIN = 1.2, 12          # Vereinfachung und Überstand der Flusslinien in Pixeln

#            Breite °N     °O      groß?  Label-Versatz
CITIES = {
    "DA":  (49.8728, 8.6512, True,  (7, -7)),
    "GG":  (49.9218, 8.4818, False, (-7, -16)),
    "HD":  (49.3988, 8.6724, False, (7, -7)),
    "FFM": (50.1109, 8.6821, False, (-6, -17)),
    "MZ":  (49.9929, 8.2473, False, (-18, -7)),
}

args = [a for a in sys.argv[1:] if not a.startswith("--")]
src, dst, W = Path(args[0]), Path(args[1]), int(args[2])
H = int(args[3]) if len(args) > 3 else W
rivers_cache = Path(sys.argv[sys.argv.index("--rivers") + 1]) if "--rivers" in sys.argv else None

n = 2 ** Z * TILE
res = 156543.03392 * math.cos(math.radians(LAT)) / 2 ** Z


def project(lat, lon):
    s = math.sin(math.radians(lat))
    return ((lon + 180) / 360 * n, (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n)


cx, cy = project(LAT, LON)
x0, y0 = round(cx - W / 2), round(cy - H / 2)
tx = x0 // TILE
assert (x0 + W) // TILE == tx, "Fenster bräuchte zwei Tile-Spalten, das verdoppelt die Bildabrufe"
tys = sorted({y0 // TILE, (y0 + H) // TILE})
col = 3 * W + 2 + 4 * GAP


def to_px(lat, lon):
    gx, gy = project(lat, lon)
    return gx - x0, gy - y0


# ---------------------------------------------------------------- Flusslinien
def fetch_rivers():
    def lon_at(x): return x / n * 360 - 180
    def lat_at(y): return math.degrees(math.atan(math.sinh(math.pi * (1 - 2 * y / n))))
    bbox = f"{lat_at(y0 + H):.4f},{lon_at(x0):.4f},{lat_at(y0):.4f},{lon_at(x0 + W):.4f}"
    query = ('[out:json][timeout:90];('
             f'way["waterway"="river"]["name"="Rhein"]({bbox});'
             f'way["waterway"="river"]["name"="Main"]({bbox}););out geom;')
    body = urllib.parse.urlencode({"data": query}).encode()
    with urllib.request.urlopen("https://overpass-api.de/api/interpreter", body, timeout=180) as r:
        return json.loads(r.read())


def chains(ways):
    """Wege an gemeinsamen Endpunkten zu langen Ketten verbinden."""
    todo, out = [w for w in ways if len(w) > 1], []
    while todo:
        cur, changed = todo.pop(), True
        while changed:
            changed = False
            for i, w in enumerate(todo):
                if   w[0]  == cur[-1]: cur = cur + w[1:]
                elif w[-1] == cur[-1]: cur = cur + w[::-1][1:]
                elif w[-1] == cur[0]:  cur = w[:-1] + cur
                elif w[0]  == cur[0]:  cur = w[::-1][:-1] + cur
                else: continue
                todo.pop(i); changed = True; break
        out.append(cur)
    return out


def simplify(pts, tol):
    if len(pts) < 3:
        return pts
    (ax, ay), (bx, by) = pts[0], pts[-1]
    dx, dy = bx - ax, by - ay
    norm = math.hypot(dx, dy) or 1
    worst, idx = 0, 0
    for i, (x, y) in enumerate(pts[1:-1], 1):
        d = abs(dy * (x - ax) - dx * (y - ay)) / norm
        if d > worst:
            worst, idx = d, i
    if worst <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[:idx + 1], tol)[:-1] + simplify(pts[idx:], tol)


def inside_runs(pts):
    run, out = [], []
    for x, y in pts:
        if -MARGIN <= x <= W + MARGIN and -MARGIN <= y <= H + MARGIN:
            run.append((x, y))
        else:
            if len(run) > 1: out.append(run)
            run = []
    if len(run) > 1: out.append(run)
    return out


def river_lines():
    if rivers_cache and rivers_cache.exists():
        data = json.loads(rivers_cache.read_text())
    else:
        data = fetch_rivers()
        if rivers_cache:
            rivers_cache.write_text(json.dumps(data))
    by_name = {}
    for e in data["elements"]:
        name, geo = e["tags"].get("name"), [(g["lat"], g["lon"]) for g in e.get("geometry", []) if g]
        if name and len(geo) > 1:
            by_name.setdefault(name, []).append(geo)
    out, kept = [], 0
    for name in ("Rhein", "Main"):
        for chain in chains(by_name.get(name, [])):
            for run in inside_runs([to_px(la, lo) for la, lo in chain]):
                pts = simplify(run, TOL)
                if len(pts) < 2:
                    continue
                kept += len(pts)
                joined = " ".join(f"{x:.0f},{y:.0f}" for x, y in pts)
                out.append(f'  <polyline points="{joined}" fill="none" stroke="#AAAAAA" '
                           f'stroke-width="1" shape-rendering="crispEdges"/>')
    return out, kept


# ------------------------------------------------------------------- Ausgabe
marks, labels = [], []
for code, (la, lo, big, (dx, dy)) in CITIES.items():
    px, py = (round(v) for v in to_px(la, lo))
    if big:
        marks += [f'            <rect x="{px-6}" y="{py}" width="13" height="1" fill="#000000"/>',
                  f'            <rect x="{px}" y="{py-6}" width="1" height="13" fill="#000000"/>']
    else:
        marks += [f'            <rect x="{px-2}" y="{py}" width="5" height="1" fill="#555555"/>'
                  f'{{%- comment -%}} {code} {{%- endcomment -%}}',
                  f'            <rect x="{px}" y="{py-2}" width="1" height="5" fill="#555555"/>']
    tone = "#000000" if big else "#555555"
    labels.append(f'          <span class="label label--small" style="position:absolute;'
                  f'left:{px+dx}px;top:{py+dy}px;background:#FFFFFF;color:{tone}">{code}</span>')

rivers, river_points = river_lines()

lines = src.read_text(encoding="utf-8").split("\n")

# Flüsse einmal als capture, direkt nach den Frame-Beschriftungen
i_fl = next(i for i, l in enumerate(lines) if "assign frame_labels" in l)
end = next((i for i, l in enumerate(lines) if l.strip() == "{%- endcapture -%}" and i > i_fl), None)
if lines[i_fl + 2:i_fl + 3] and "capture rivers" in "".join(lines[i_fl:i_fl + 4]):
    lines[i_fl + 1:end + 1] = []                      # alten Block entfernen
lines[i_fl + 1:i_fl + 1] = ["",
    "{%- comment -%} Rhein und Main aus OpenStreetMap, projiziert und vereinfacht;",
    "einmal definiert, dreimal ausgegeben — die Karten teilen dieselbe Geometrie {%- endcomment -%}",
    "{%- capture rivers -%}"] + rivers + ["{%- endcapture -%}"]

# Kartenfenster neu schreiben
i_open = next(i for i, l in enumerate(lines) if "position:relative;display:block;width:" in l)
i_svg_end = next(i for i in range(i_open, len(lines)) if lines[i].strip() == "</svg>")
i_last_label = max(i for i, l in enumerate(lines) if 'background:#FFFFFF;color:' in l and "label--small" in l)

block = [f'        <span style="position:relative;display:block;width:{W}px;height:{H}px;overflow:hidden;background:#FFFFFF">',
         f'          {{%- comment -%}} Zoom {Z}, {res:.0f} m/px: {W}x{H} px = {W*res/1000:.0f}x{H*res/1000:.0f} km,',
         f'          also {W*res/2000:.0f} km nach Osten und Westen, {H*res/2000:.0f} km nach Norden und Süden.',
         f'          Fenster liegt in einer Tile-Spalte, also zwei Bilder pro Frame {{%- endcomment -%}}']
for ty in tys:
    block.append(f'          <img src="{{{{ host }}}}{{{{ p }}}}/{TILE}/{Z}/{tx}/{ty}/0/1_1.png" alt="" '
                 f'width="{TILE}" height="{TILE}" style="position:absolute;left:{tx*TILE-x0}px;'
                 f'top:{ty*TILE-y0}px;width:{TILE}px;height:{TILE}px;filter:grayscale(1)">')
block += [f'          <svg viewBox="0 0 {W} {H}" width="{W}" height="{H}" style="position:absolute;left:0;top:0">',
          "            {{ rivers }}"] + marks + ["          </svg>"] + labels

lines[i_open:i_last_label + 1] = block

# Trennstrich und Spaltenbreite mitziehen
i_sep = next(i for i, l in enumerate(lines) if "width:1px;height:" in l)
lines[i_sep] = f'        <span style="display:block;width:1px;height:{H}px;background:#AAAAAA;align-self:flex-end"></span>'
i_col = next(i for i, l in enumerate(lines) if "<span>Radar</span>" in l) - 2
assert "flex-direction:column;width:" in lines[i_col] and "flex:none" in lines[i_col], lines[i_col]
lines[i_col] = f'  <span style="display:flex;flex-direction:column;width:{col}px;flex:none">'

dst.write_text("\n".join(lines), encoding="utf-8")
print(f"{W}x{H}px: {W*res/1000:.0f}x{H*res/1000:.0f} km ({W*res/2000:.0f} km O/W, {H*res/2000:.0f} km N/S)")
print(f"Spalte {col}px, Räume {780-col-18}px | tiles {tx}/{tys}")
print(f"{len(CITIES)} Ortsmarken | {len(rivers)} Flusslinien mit {river_points} Punkten")
