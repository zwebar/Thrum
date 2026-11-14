"""Builds Thrum Runes, the addon's lettering: carved, runic-styled capitals.

Pure Python, no dependencies:  python3 tools/gen_font.py
Writes Thrum/Fonts/ThrumRunes.ttf. Every letter is made of straight chisel strokes (curves
become angles, as in runes cut into wood or stone); each stroke tapers a little and ends in
a wedge, and the points are nudged by a seeded jitter so the cuts look hand-hewn.
Lower case maps to the capitals. The font is released under the SIL Open Font License
(Thrum/Fonts/OFL.txt).
"""
import math
import os
import random
import struct
import time

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Thrum", "Fonts", "ThrumRunes.ttf")

UPM = 1000
CAP = 700          # cap height
W = 124            # stroke width
SIDE = 46          # side bearing
FAMILY = "Thrum Runes"
VERSION = "Version 1.000"
COPYRIGHT = "Copyright 2026 The Thrum Runes Project Authors"
LICENSE = ("This Font Software is licensed under the SIL Open Font License, Version 1.1. "
           "This license is available with a FAQ at: https://openfontlicense.org")
LICENSE_URL = "https://openfontlicense.org"

# Glyph designs: advance-box width, then strokes on a unit grid (x 0..1 across the box,
# y 0..1 from baseline to cap height; values outside overshoot). A stroke is a polyline;
# one whose last point equals its first is closed. ("dot", x, y) is a carved diamond.
G = {
    "A": (640, [[(0, 0), (0.5, 1), (1, 0)], [(0.2, 0.36), (0.8, 0.36)]]),
    "B": (600, [[(0, 0), (0, 1)], [(0, 1), (0.68, 1), (0.95, 0.77), (0.68, 0.53), (0, 0.53)],
                [(0.68, 0.53), (1, 0.27), (0.72, 0), (0, 0)]]),
    "C": (600, [[(1, 0.84), (0.72, 1), (0.3, 1), (0, 0.7), (0, 0.3), (0.3, 0), (0.72, 0), (1, 0.16)]]),
    "D": (620, [[(0, 0), (0, 1), (0.55, 1), (1, 0.64), (1, 0.36), (0.55, 0), (0, 0)]]),
    "E": (540, [[(1, 1), (0, 1), (0, 0), (1, 0)], [(0, 0.52), (0.78, 0.52)]]),
    "F": (520, [[(1, 1), (0, 1), (0, 0)], [(0, 0.52), (0.78, 0.52)]]),
    "G": (640, [[(1, 0.84), (0.72, 1), (0.3, 1), (0, 0.7), (0, 0.3), (0.3, 0), (0.74, 0), (1, 0.24),
                 (1, 0.48), (0.55, 0.48)]]),
    "H": (620, [[(0, 0), (0, 1)], [(1, 0), (1, 1)], [(0, 0.52), (1, 0.52)]]),
    "I": (250, [[(0.5, 0), (0.5, 1)]]),
    "J": (520, [[(1, 1), (1, 0.26), (0.72, 0), (0.3, 0), (0, 0.24)]]),
    "K": (600, [[(0, 0), (0, 1)], [(1, 1), (0, 0.42)], [(0.32, 0.6), (1, 0)]]),
    "L": (500, [[(0, 1), (0, 0), (1, 0)]]),
    "M": (760, [[(0, 0), (0, 1), (0.5, 0.42), (1, 1), (1, 0)]]),
    "N": (640, [[(0, 0), (0, 1), (1, 0), (1, 1)]]),
    "O": (640, [[(0.3, 0), (0, 0.3), (0, 0.7), (0.3, 1), (0.7, 1), (1, 0.7), (1, 0.3), (0.7, 0), (0.3, 0)]]),
    "P": (580, [[(0, 0), (0, 1), (0.7, 1), (1, 0.76), (0.7, 0.5), (0, 0.5)]]),
    "Q": (660, [[(0.3, 0), (0, 0.3), (0, 0.7), (0.3, 1), (0.7, 1), (1, 0.7), (1, 0.3), (0.7, 0), (0.3, 0)],
                [(0.6, 0.3), (1.06, -0.12)]]),
    "R": (600, [[(0, 0), (0, 1), (0.7, 1), (1, 0.76), (0.7, 0.5), (0, 0.5)], [(0.42, 0.5), (1, 0)]]),
    "S": (580, [[(1, 0.85), (0.74, 1), (0.26, 1), (0, 0.78), (0.26, 0.55), (0.74, 0.45), (1, 0.22),
                 (0.74, 0), (0.26, 0), (0, 0.15)]]),
    "T": (580, [[(0, 1), (1, 1)], [(0.5, 1), (0.5, 0)]]),
    "U": (620, [[(0, 1), (0, 0.3), (0.3, 0), (0.7, 0), (1, 0.3), (1, 1)]]),
    "V": (630, [[(0, 1), (0.5, 0), (1, 1)]]),
    "W": (840, [[(0, 1), (0.24, 0), (0.5, 0.62), (0.76, 0), (1, 1)]]),
    "X": (610, [[(0, 1), (1, 0)], [(1, 1), (0, 0)]]),
    "Y": (610, [[(0, 1), (0.5, 0.48), (1, 1)], [(0.5, 0.48), (0.5, 0)]]),
    "Z": (570, [[(0, 1), (1, 1), (0, 0), (1, 0)]]),
    "0": (560, [[(0.3, 0), (0, 0.26), (0, 0.74), (0.3, 1), (0.7, 1), (1, 0.74), (1, 0.26), (0.7, 0), (0.3, 0)]]),
    "1": (400, [[(0.12, 0.78), (0.6, 1), (0.6, 0)]]),
    "2": (550, [[(0, 0.8), (0.3, 1), (0.72, 1), (1, 0.78), (1, 0.6), (0, 0), (1, 0)]]),
    "3": (550, [[(0, 0.86), (0.3, 1), (0.72, 1), (1, 0.78), (0.62, 0.54), (0.3, 0.54)],
                [(0.62, 0.54), (1, 0.28), (0.72, 0), (0.3, 0), (0, 0.14)]]),
    "4": (570, [[(0.74, 0), (0.74, 1), (0, 0.32), (1, 0.32)]]),
    "5": (550, [[(1, 1), (0.06, 1), (0, 0.56), (0.7, 0.6), (1, 0.36), (1, 0.24), (0.72, 0), (0.3, 0), (0, 0.14)]]),
    "6": (550, [[(0.9, 1), (0.42, 1), (0, 0.62), (0, 0.26), (0.3, 0), (0.7, 0), (1, 0.26), (1, 0.36),
                 (0.7, 0.6), (0.06, 0.52)]]),
    "7": (530, [[(0, 1), (1, 1), (0.36, 0)]]),
    "8": (570, [[(0.5, 0.54), (0.06, 0.78), (0.5, 1), (0.94, 0.78), (0.5, 0.54), (0, 0.27), (0.5, 0),
                 (1, 0.27), (0.5, 0.54)]]),
    "9": (550, [[(0.1, 0), (0.58, 0), (1, 0.38), (1, 0.74), (0.7, 1), (0.3, 1), (0, 0.74), (0, 0.64),
                 (0.3, 0.4), (0.94, 0.48)]]),
    "!": (290, [[(0.5, 1.02), (0.5, 0.34)], ("dot", 0.5, 0.04)]),
    "?": (530, [[(0, 0.82), (0.3, 1), (0.7, 1), (1, 0.8), (1, 0.64), (0.5, 0.42), (0.5, 0.3)], ("dot", 0.5, 0.04)]),
    ".": (270, [("dot", 0.5, 0.04)]),
    ",": (270, [[(0.6, 0.1), (0.3, -0.18)]]),
    ":": (270, [("dot", 0.5, 0.04), ("dot", 0.5, 0.6)]),
    ";": (270, [[(0.6, 0.1), (0.3, -0.18)], ("dot", 0.5, 0.6)]),
    "'": (250, [[(0.55, 1.02), (0.45, 0.72)]]),
    '"': (380, [[(0.25, 1.02), (0.2, 0.72)], [(0.8, 1.02), (0.75, 0.72)]]),
    "-": (430, [[(0, 0.45), (1, 0.45)]]),
    "+": (520, [[(0, 0.45), (1, 0.45)], [(0.5, 0.12), (0.5, 0.78)]]),
    "=": (520, [[(0, 0.3), (1, 0.3)], [(0, 0.62), (1, 0.62)]]),
    "&": (640, [[(1, 0), (0.16, 0.72), (0.36, 1), (0.6, 1), (0.76, 0.82), (0, 0.32), (0.26, 0), (0.7, 0), (1, 0.42)]]),
    "/": (430, [[(0, -0.04), (1, 1.04)]]),
    "%": (580, [[(0, 0), (1, 1)], ("dot", 0.06, 0.9), ("dot", 0.94, 0.1)]),
    "(": (330, [[(0.85, 1.06), (0.15, 0.62), (0.15, 0.38), (0.85, -0.06)]]),
    ")": (330, [[(0.15, 1.06), (0.85, 0.62), (0.85, 0.38), (0.15, -0.06)]]),
    "*": (490, [[(0.5, 0.42), (0.5, 1)], [(0.12, 0.86), (0.88, 0.56)], [(0.12, 0.56), (0.88, 0.86)]]),
    "#": (620, [[(0.28, 0), (0.42, 1)], [(0.62, 0), (0.76, 1)], [(0, 0.34), (1, 0.34)], [(0, 0.68), (1, 0.68)]]),
    "x": (520, [[(0, 0.7), (1, 0)], [(1, 0.7), (0, 0)]]),  # the multiplication-style x (also used for "×")
}
SPACE = 300


def cross(o, a, b):
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def hull(points):
    pts = sorted(set(points))
    if len(pts) <= 2:
        return pts
    lower, upper = [], []
    for p in pts:
        while len(lower) >= 2 and cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    for p in reversed(pts):
        while len(upper) >= 2 and cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def clockwise(poly):
    area = sum(poly[i][0] * poly[(i + 1) % len(poly)][1] - poly[(i + 1) % len(poly)][0] * poly[i][1]
               for i in range(len(poly)))
    return poly if area < 0 else poly[::-1]  # TrueType outer contours run clockwise


def glyph_contours(ch, width, strokes, rng):
    """Each stroke segment becomes a tapered hexagon with wedge tips at free ends; joints get a
    small octagon so corners are solid. Overlapping contours render as their union."""
    x0, x1 = SIDE + W / 2, width - SIDE - W / 2
    y0, y1 = W / 2, CAP - W / 2

    def P(x, y):
        return (x0 + x * (x1 - x0), y0 + y * (y1 - y0))

    contours = []
    for s in strokes:
        if isinstance(s, tuple) and s[0] == "dot":
            cx, cy = P(s[1], s[2])
            r = W * 0.62
            contours.append([(cx, cy + r * 1.15), (cx + r, cy), (cx, cy - r * 1.15), (cx - r, cy)])
            continue
        pts = [P(x, y) for x, y in s]
        jit = [(x + rng.uniform(-7, 7), y + rng.uniform(-7, 7)) for x, y in pts]
        closed = len(pts) > 2 and s[0] == s[-1]
        if closed:
            jit[-1] = jit[0]
        n = len(jit)
        for i in range(n - 1):
            (ax, ay), (bx, by) = jit[i], jit[i + 1]
            dx, dy = bx - ax, by - ay
            d = math.hypot(dx, dy) or 1.0
            ux, uy = dx / d, dy / d
            nx, ny = -uy, ux
            freeA = i == 0 and not closed
            freeB = i == n - 2 and not closed
            # A carved stroke: flared where it ends free, pinched at the waist, the free ends
            # cut on a slant like a knife stroke.
            h = W / 2
            wA = h * (1.24 if freeA else 0.98) * rng.uniform(0.97, 1.04)
            wB = h * (1.14 if freeB else 0.94) * rng.uniform(0.96, 1.03)
            wM = h * 0.8
            kA = W * 0.3 if freeA else 0
            kB = W * 0.3 if freeB else 0

            def at(t, w, side, slide=0.0):
                return (ax + dx * t + ux * slide + nx * w * side, ay + dy * t + uy * slide + ny * w * side)

            plus = [at(0, wA, 1, kA * 0.5), at(0.5, wM, 1)]
            minus = [at(0, wA, -1, -kA * 0.5), at(0.5, wM, -1)]
            # a small notch cut into long strokes, alternating sides
            if d > 330:
                notch_side = plus if i % 2 == 0 else minus
                s = 1 if i % 2 == 0 else -1
                dep = W * 0.24
                notch_side[1:2] = [at(0.42, wM, s), at(0.5, wM - dep, s), at(0.58, wM, s)]
            plus.append(at(1, wB, 1, kB * 0.5))
            minus.append(at(1, wB, -1, -kB * 0.5))
            contours.append(plus + minus[::-1])
        # joints
        for i in range(n):
            if not closed and (i == 0 or i == n - 1):
                continue
            if closed and i == n - 1:
                continue
            cx, cy = jit[i]
            r = W / 2 * 0.97
            contours.append([(cx + r * math.cos(a), cy + r * math.sin(a))
                             for a in [k * math.pi / 4 + math.pi / 8 for k in range(8)]])
    out = []
    for c in contours:
        pts = []
        for x, y in c:
            p = (int(round(x)), int(round(y)))
            if not pts or pts[-1] != p:
                pts.append(p)
        if len(pts) > 1 and pts[0] == pts[-1]:
            pts.pop()
        if len(pts) >= 3:
            out.append(clockwise(pts))
    return out


# ---------------------------------------------------------------- TrueType tables
def checksum(data):
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(">%dI" % (len(data) // 4), data)) & 0xFFFFFFFF


def glyf_data(contours):
    if not contours:
        return b"", (0, 0, 0, 0), 0
    xs = [p[0] for c in contours for p in c]
    ys = [p[1] for c in contours for p in c]
    bbox = (min(xs), min(ys), max(xs), max(ys))
    out = struct.pack(">hhhhh", len(contours), *bbox)
    ends, n = [], 0
    for c in contours:
        n += len(c)
        ends.append(n - 1)
    out += struct.pack(">%dH" % len(ends), *ends)
    out += struct.pack(">H", 0)  # no instructions
    out += bytes([1] * n)  # all points on the curve; 16-bit deltas
    px = py = 0
    xd, yd = [], []
    for c in contours:
        for x, y in c:
            xd.append(x - px)
            yd.append(y - py)
            px, py = x, y
    out += struct.pack(">%dh" % n, *xd) + struct.pack(">%dh" % n, *yd)
    out += b"\0" * (-len(out) % 4)
    return out, bbox, n


def name_table():
    names = {0: COPYRIGHT, 1: FAMILY, 2: "Regular", 3: FAMILY + ";" + VERSION, 4: FAMILY,
             5: VERSION, 6: "ThrumRunes-Regular", 13: LICENSE, 14: LICENSE_URL}
    records, strings = [], b""
    for plat, enc, lang, codec in ((1, 0, 0, "mac_roman"), (3, 1, 0x409, "utf-16-be")):
        for nid in sorted(names):
            s = names[nid].encode(codec)
            records.append((plat, enc, lang, nid, len(s), len(strings)))
            strings += s
    head = struct.pack(">HHH", 0, len(records), 6 + 12 * len(records))
    return head + b"".join(struct.pack(">6H", *r) for r in records) + strings


def cmap_table(mapping):
    codes = sorted(mapping)
    segs = [(c, c, mapping[c]) for c in codes] + [(0xFFFF, 0xFFFF, 0)]
    n = len(segs)
    sr = 2 * (2 ** int(math.log2(n)))
    es = int(math.log2(sr // 2))
    rs = 2 * n - sr
    ends = [s[1] for s in segs]
    starts = [s[0] for s in segs]
    deltas = [((g - s0) & 0xFFFF) if s0 != 0xFFFF else 1 for s0, _, g in segs]
    body = struct.pack(">HHHH", 2 * n, sr, es, rs)
    body += struct.pack(">%dH" % n, *ends) + b"\0\0" + struct.pack(">%dH" % n, *starts)
    body += struct.pack(">%dH" % n, *deltas) + struct.pack(">%dH" % n, *([0] * n))
    sub = struct.pack(">HHH", 4, 6 + len(body), 0) + body
    return struct.pack(">HHHHIHHI", 0, 2, 0, 3, 20, 3, 1, 20) + sub


def build():
    rng = random.Random(1717)
    order = [".notdef", "space"] + list(G.keys())
    glyphs = {}
    for ch, (width, strokes) in G.items():
        glyphs[ch] = (width, glyph_contours(ch, width, strokes, rng))
    # .notdef: a hollow tablet
    nd = [clockwise([(60, 0), (60, CAP), (440, CAP), (440, 0)]), clockwise([(140, 80), (360, 80), (360, CAP - 80), (140, CAP - 80)])[::-1]]
    glyphs[".notdef"] = (500, nd)
    glyphs["space"] = (SPACE, [])

    glyf, loca, hm = b"", [], []
    max_pts = max_cnt = 0
    gx0 = gy0 = 10 ** 6
    gx1 = gy1 = -10 ** 6
    min_rsb = min_lsb = 10 ** 6
    max_extent = 0
    for name in order:
        width, contours = glyphs[name]
        loca.append(len(glyf))
        data, bbox, npts = glyf_data(contours)
        glyf += data
        lsb = bbox[0] if contours else 0
        hm.append((width, lsb))
        if contours:
            max_pts, max_cnt = max(max_pts, npts), max(max_cnt, len(contours))
            gx0, gy0 = min(gx0, bbox[0]), min(gy0, bbox[1])
            gx1, gy1 = max(gx1, bbox[2]), max(gy1, bbox[3])
            min_lsb = min(min_lsb, bbox[0])
            min_rsb = min(min_rsb, width - bbox[2])
            max_extent = max(max_extent, bbox[2])
    loca.append(len(glyf))
    gid = {n: i for i, n in enumerate(order)}

    mapping = {32: gid["space"], 0xA0: gid["space"]}
    for ch in G:
        if len(ch) == 1 and ch != "x":
            mapping[ord(ch)] = gid[ch]
            if ch.isalpha():
                mapping[ord(ch.lower())] = gid[ch]
    mapping[ord("x")] = gid["X"]
    mapping[0xD7] = gid["x"]
    mapping[0x2019] = gid["'"]
    mapping[0x2013] = gid["-"]
    mapping[0x2014] = gid["-"]

    n = len(order)
    avg = int(sum(w for w, _ in hm) / n)
    created = int(time.mktime((2026, 11, 14, 0, 0, 0, 0, 0, 0))) + 2082844800
    tables = {}
    tables["head"] = struct.pack(">IIIIHHqqhhhhHHhhh", 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, UPM,
                                 created, created, gx0, gy0, gx1, gy1, 0, 8, 2, 1, 0)
    tables["hhea"] = struct.pack(">IhhhHhhhhhh4hhH", 0x00010000, 900, -220, 0, max(w for w, _ in hm),
                                 min_lsb, min_rsb, max_extent, 1, 0, 0, 0, 0, 0, 0, 0, n)
    tables["maxp"] = struct.pack(">IHHHHHHHHHHHHHH", 0x00010000, n, max_pts, max_cnt, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    tables["OS/2"] = struct.pack(">HhHHHhhhhhhhhhhh10sIIII4sHHHhhhHHIIhhHHH",
                                 4, avg, 700, 5, 0,
                                 650, 600, 0, 75, 650, 600, 0, 350, 50, 260,
                                 0, bytes([2, 0, 8, 3, 0, 0, 0, 0, 0, 0]),
                                 1, 0, 0, 0, b"NONE", 0x0040, 32, 0x2019,
                                 800, -200, 100, 950, 260, 1, 0, CAP, CAP, 0, 32, 1)
    tables["hmtx"] = b"".join(struct.pack(">Hh", w, l) for w, l in hm)
    tables["loca"] = struct.pack(">%dI" % len(loca), *loca)
    tables["glyf"] = glyf
    tables["cmap"] = cmap_table(mapping)
    tables["name"] = name_table()
    tables["post"] = struct.pack(">IIhhIIIII", 0x00030000, 0, -120, 60, 0, 0, 0, 0, 0)

    tags = sorted(tables)
    nt = len(tags)
    sr = 16 * (2 ** int(math.log2(nt)))
    head = struct.pack(">IHHHH", 0x00010000, nt, sr, int(math.log2(sr // 16)), nt * 16 - sr)
    offset = 12 + 16 * nt
    dirs, body = b"", b""
    for t in tags:
        data = tables[t]
        dirs += struct.pack(">4sIII", t.encode().ljust(4), checksum(data), offset + len(body), len(data))
        body += data + b"\0" * (-len(data) % 4)
    font = bytearray(head + dirs + body)
    adj = (0xB1B0AFBA - checksum(bytes(font))) & 0xFFFFFFFF
    hoff = offset + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in tags[:tags.index("head")])
    struct.pack_into(">I", font, hoff + 8, adj)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "wb") as f:
        f.write(bytes(font))
    print("wrote", os.path.relpath(OUT), len(font), "bytes,", n, "glyphs")


if __name__ == "__main__":
    build()
