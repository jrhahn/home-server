"""Setzt die Radar-Kartengröße im Template neu und rechnet die Geometrie mit."""
import math, sys
from pathlib import Path

SRC, DST, W = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3])
H = int(sys.argv[4]) if len(sys.argv) > 4 else W
GAP, Z, TILE = 8, 6, 256
LAT, LON = 49.8728, 8.6512
CITIES = {"DA": (49.8728, 8.6512), "GG": (49.9218, 8.4818), "HD": (49.3988, 8.6724)}

n = 2 ** Z * TILE
def gpx(lat, lon):
    s = math.sin(math.radians(lat))
    return (lon + 180) / 360 * n, (0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi)) * n

cx, cy = gpx(LAT, LON)
x0, y0 = round(cx - W / 2), round(cy - H / 2)
res = 156543.03392 * math.cos(math.radians(LAT)) / 2 ** Z
tx = x0 // TILE
assert (x0 + W) // TILE == tx, "zwei Tile-Spalten nötig — mehr Bildabrufe"
tys = sorted({y0 // TILE, (y0 + H) // TILE})
col = 3 * W + 2 + 4 * GAP

marks, labels = [], []
for code, (la, lo) in CITIES.items():
    gx, gy = gpx(la, lo)
    px, py = round(gx - x0), round(gy - y0)
    if code == "DA":
        marks.append(f'            <rect x="{px-6}" y="{py}" width="13" height="1" fill="#000000"/>')
        marks.append(f'            <rect x="{px}" y="{py-6}" width="1" height="13" fill="#000000"/>')
        labels.append(f'          <span class="label label--small" style="position:absolute;left:{px+7}px;top:{py-7}px;background:#FFFFFF;color:#000000">DA</span>')
    else:
        marks.append(f'            <rect x="{px-2}" y="{py}" width="5" height="1" fill="#555555"/>{{%- comment -%}} {code} {{%- endcomment -%}}')
        marks.append(f'            <rect x="{px}" y="{py-2}" width="1" height="5" fill="#555555"/>')
        dx, dy = (-28, -18) if code == "GG" else (7, -7)
        labels.append(f'          <span class="label label--small" style="position:absolute;left:{px+dx}px;top:{py+dy}px;background:#FFFFFF;color:#555555">{code}</span>')

lines = SRC.read_text(encoding="utf-8").split("\n")
i_open = [i for i, l in enumerate(lines) if "position:relative;display:block;width:" in l]
assert len(i_open) == 1
i_open = i_open[0]
i_svg_end = next(i for i in range(i_open, len(lines)) if lines[i].strip() == "</svg>")
i_hd = next(i for i in range(i_svg_end, len(lines)) if ">HD</span>" in lines[i])
i_sep = next(i for i in range(i_hd, len(lines)) if "width:1px;height:" in lines[i])

block = [f'        <span style="position:relative;display:block;width:{W}px;height:{H}px;overflow:hidden;background:#FFFFFF">',
         f'          {{%- comment -%}} Zoom {Z}, {res:.0f} m/px: {W}x{H} px = {W*res/1000:.0f}x{H*res/1000:.0f} km,',
         f'          also {W*res/2000:.0f} km nach Osten und Westen, {H*res/2000:.0f} km nach Norden und Süden.',
         f'          Fenster liegt in einer Tile-Spalte, also zwei Bilder pro Frame {{%- endcomment -%}}']
for ty in tys:
    block.append(f'          <img src="{{{{ host }}}}{{{{ p }}}}/{TILE}/{Z}/{tx}/{ty}/0/1_1.png" alt="" width="{TILE}" height="{TILE}" '
                 f'style="position:absolute;left:{tx*TILE-x0}px;top:{ty*TILE-y0}px;width:{TILE}px;height:{TILE}px;filter:grayscale(1)">')
block.append(f'          <svg viewBox="0 0 {W} {H}" width="{W}" height="{H}" style="position:absolute;left:0;top:0">')
block += marks
block.append("          </svg>")
block += labels

out = lines[:i_open] + block + lines[i_hd + 1:]
i_sep2 = next(i for i, l in enumerate(out) if "width:1px;height:" in l)
out[i_sep2] = f'        <span style="display:block;width:1px;height:{H}px;background:#AAAAAA;align-self:flex-end"></span>'
i_radlbl = next(i for i, l in enumerate(out) if "<span>Radar</span>" in l)
i_col = i_radlbl - 2
assert "flex-direction:column;width:" in out[i_col] and "flex:none" in out[i_col], out[i_col]
out[i_col] = f'  <span style="display:flex;flex-direction:column;width:{col}px;flex:none">'
i_row = next(i for i, l in enumerate(out) if "justify-content:flex-start;gap:" in l)
out[i_row] = f'    <div style="display:flex;flex-direction:row;justify-content:flex-start;gap:{GAP}px;width:100%;margin-top:3px">'

DST.write_text("\n".join(out), encoding="utf-8")
print(f"{W}x{H}px: {W*res/1000:.0f}x{H*res/1000:.0f} km ({W*res/2000:.0f} km O/W, {H*res/2000:.0f} km N/S) | Spalte {col}px, Räume {780-col-18}px | tiles {tx}/{tys}")
