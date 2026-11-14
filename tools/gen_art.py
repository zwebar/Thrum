"""Draws Thrum's textures (word-burst shapes, element particles, the stone mana trough, carved
totem plaques...) and writes them as TGA.

Pure Python, no dependencies:  python3 tools/gen_art.py [preview_dir]
Burst shapes and particles are white/grey with dark bark outlines, so the addon tints them with
vertex colours (white becomes the colour, the bark stays dark). Frames (the trough, the totem
plaques, the imbue badge) are painted in their own wood and stone colours and drawn untinted.
With a preview_dir it also writes PNG contact sheets.
"""
import math
import os
import random
import struct
import sys
import zlib

SS = 4  # supersampling per axis
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "Thrum", "Art")


class Bitmap:
    """A 1-bit supersampled canvas; shapes drawn on it are unioned."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.W, self.H = w * SS, h * SS
        self.rows = [bytearray(self.W) for _ in range(self.H)]

    def poly(self, pts):
        pts = [(x * SS, y * SS) for x, y in pts]
        n = len(pts)
        ys = [p[1] for p in pts]
        y0 = max(0, int(math.floor(min(ys))))
        y1 = min(self.H - 1, int(math.ceil(max(ys))))
        for y in range(y0, y1 + 1):
            yc = y + 0.5
            xs = []
            for i in range(n):
                ax, ay = pts[i]
                bx, by = pts[(i + 1) % n]
                if (ay <= yc < by) or (by <= yc < ay):
                    xs.append(ax + (yc - ay) * (bx - ax) / (by - ay))
            xs.sort()
            row = self.rows[y]
            for i in range(0, len(xs) - 1, 2):
                a = max(0, int(math.ceil(xs[i] - 0.5)))
                b = min(self.W, int(math.floor(xs[i + 1] - 0.5)) + 1)
                if b > a:
                    row[a:b] = b"\x01" * (b - a)
        return self

    def circle(self, cx, cy, r, seg=40):
        return self.poly([(cx + r * math.cos(2 * math.pi * i / seg), cy + r * math.sin(2 * math.pi * i / seg))
                          for i in range(seg)])

    def ellipse(self, cx, cy, rx, ry, rot=0.0, seg=48):
        c, s = math.cos(rot), math.sin(rot)
        pts = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            x, y = rx * math.cos(a), ry * math.sin(a)
            pts.append((cx + x * c - y * s, cy + x * s + y * c))
        return self.poly(pts)

    def stroke(self, pts, width, closed=True):
        n = len(pts)
        hw = width / 2.0
        for i in range(n if closed else n - 1):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % n]
            dx, dy = bx - ax, by - ay
            d = math.hypot(dx, dy) or 1.0
            nx, ny = -dy / d * hw, dx / d * hw
            self.poly([(ax + nx, ay + ny), (bx + nx, by + ny), (bx - nx, by - ny), (ax - nx, ay - ny)])
        for x, y in pts:
            self.circle(x, y, hw, 16)
        return self

    def intersect(self, other):
        for y in range(self.H):
            a, b = self.rows[y], other.rows[y]
            self.rows[y] = bytearray(x & z for x, z in zip(a, b))
        return self

    def subtract(self, other):
        for y in range(self.H):
            a, b = self.rows[y], other.rows[y]
            self.rows[y] = bytearray(x & (1 - z) for x, z in zip(a, b))
        return self

    def copy(self):
        b = Bitmap(self.w, self.h)
        b.rows = [bytearray(r) for r in self.rows]
        return b

    def coverage(self):
        out = []
        full = float(SS * SS)
        for y in range(self.h):
            rows = self.rows[y * SS:(y + 1) * SS]
            line = []
            for x in range(self.w):
                a, b = x * SS, (x + 1) * SS
                line.append(sum(sum(r[a:b]) for r in rows) / full)
            out.append(line)
        return out


class Image:
    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[[0.0, 0.0, 0.0, 0.0] for _ in range(w)] for _ in range(h)]

    def paint(self, bitmap, color, alpha=1.0):
        """Composite a colour through the bitmap's coverage, 'over'. color is an rgb tuple or a
        function (x, y) -> rgb."""
        cov = bitmap.coverage()
        fn = color if callable(color) else None
        for y in range(self.h):
            row, crow = self.px[y], cov[y]
            for x in range(self.w):
                a = crow[x] * alpha
                if a <= 0:
                    continue
                r, g, b = fn(x + 0.5, y + 0.5) if fn else color
                p = row[x]
                oa = a + p[3] * (1 - a)
                for i, c in enumerate((r, g, b)):
                    p[i] = (c * a + p[i] * p[3] * (1 - a)) / oa
                p[3] = oa
        return self

    def save_tga(self, name):
        os.makedirs(OUT, exist_ok=True)
        head = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, self.w, self.h, 32, 8)  # bottom-left origin
        body = bytearray()
        for row in reversed(self.px):
            for r, g, b, a in row:
                body += bytes((int(min(1, b) * 255 + 0.5), int(min(1, g) * 255 + 0.5),
                               int(min(1, r) * 255 + 0.5), int(min(1, a) * 255 + 0.5)))
        with open(os.path.join(OUT, name + ".tga"), "wb") as f:
            f.write(head + bytes(body))
        ART[name] = self
        print("wrote", name, "%dx%d" % (self.w, self.h))


ART = {}
BARK = (0.09, 0.06, 0.04)        # the dark outline everything is cut with
WHITE = (1.0, 1.0, 1.0)
SHADE = (0.80, 0.80, 0.80)
WOOD = (0.45, 0.29, 0.16)
WOOD_DARK = (0.30, 0.18, 0.09)
WOOD_LIGHT = (0.62, 0.43, 0.25)
STONE = (0.50, 0.48, 0.44)
STONE_DARK = (0.33, 0.31, 0.28)
STONE_LIGHT = (0.66, 0.63, 0.58)


def mix(a, b, t):
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def noise2(x, y, seed=0):
    """Cheap smooth value noise."""
    def h(i, j):
        n = (i * 374761393 + j * 668265263 + seed * 2147483647) & 0xFFFFFFFF
        n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
        return (n & 0xFFFF) / 65535.0
    xi, yi = math.floor(x), math.floor(y)
    fx, fy = x - xi, y - yi
    fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = h(xi, yi), h(xi + 1, yi)
    c, d = h(xi, yi + 1), h(xi + 1, yi + 1)
    return a + (b - a) * fx + (c - a) * fy + (a - b - c + d) * fx * fy


def grain_fn(base, dark, light, scale=1.0, seed=1, vertical=False):
    """Wood: wavy grain lines with knots of noise."""
    def f(x, y):
        u, v = (y, x) if vertical else (x, y)
        w = math.sin(v * 0.55 / scale + 3.2 * noise2(u * 0.03 / scale, v * 0.08 / scale, seed) + 1.7 * math.sin(u * 0.02 / scale))
        t = max(0.0, w) ** 6
        n = noise2(u * 0.12 / scale, v * 0.4 / scale, seed + 3)
        c = mix(base, dark, 0.65 * t + 0.25 * (n - 0.5))
        if w < -0.92:
            c = mix(c, light, 0.5)
        return c
    return f


def stone_fn(seed=4, scale=1.0):
    def f(x, y):
        n = noise2(x * 0.09 / scale, y * 0.09 / scale, seed) * 0.6 + noise2(x * 0.3 / scale, y * 0.3 / scale, seed + 1) * 0.4
        return mix(STONE_DARK, STONE_LIGHT, 0.2 + 0.7 * n)
    return f


def white_grain(seed=1, scale=1.0, depth=0.22):
    """Grey carving texture for tintable shapes: white with soft grain."""
    def f(x, y):
        w = math.sin(y * 0.5 / scale + 3.0 * noise2(x * 0.03 / scale, y * 0.07 / scale, seed))
        t = max(0.0, w) ** 5
        n = noise2(x * 0.1 / scale, y * 0.1 / scale, seed + 7)
        v = 1.0 - depth * t - 0.10 * n
        return (v, v, v)
    return f


def jag_poly(cx, cy, n, r0, r1, rng, jr=0.1, ja=0.2, rot=0.0):
    pts = []
    for i in range(n * 2):
        a = rot + math.pi * i / n + rng.uniform(-ja, ja) * math.pi / n
        r = (r0 if i % 2 == 0 else r1) * (1 + rng.uniform(-jr, jr))
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def facets(img, fill, pts, cx, cy, light=(1, 1, 1), dark=SHADE):
    """Chisel facets: each wedge from the centre to an edge is lit by its direction."""
    n = len(pts)
    for i in range(n):
        a, b = pts[i], pts[(i + 1) % n]
        mx, my = (a[0] + b[0]) / 2 - cx, (a[1] + b[1]) / 2 - cy
        lit = (-(mx) * 0.6 - my * 0.8) / (math.hypot(mx, my) or 1)  # light from the top left
        t = 0.5 - 0.5 * lit
        inner = (cx + (a[0] - cx) * 0.62, cy + (a[1] - cy) * 0.62), (cx + (b[0] - cx) * 0.62, cy + (b[1] - cy) * 0.62)
        wedge = Bitmap(img.w, img.h).poly([inner[0], a, b, inner[1]]).intersect(fill)
        img.paint(wedge, mix(light, dark, t))


# ---------------------------------------------------------------- word-burst shapes
def stone():
    S = 256
    rng = random.Random(5)
    pts = []
    n = 11
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.15, 0.15)
        pts.append((S / 2 + 118 * math.cos(a) * rng.uniform(0.86, 1.0), S / 2 + 104 * math.sin(a) * rng.uniform(0.86, 1.0)))
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 11), BARK)
    fill = Bitmap(S, S).poly(pts)
    img.paint(fill, white_grain(2, 1.0, 0.10))
    facets(img, fill, pts, S / 2, S / 2)
    # a couple of cracks
    for crack in ([(60, 92), (80, 104), (88, 126)], [(196, 160), (176, 168), (170, 186)]):
        img.paint(Bitmap(S, S).stroke(crack, 3.5, False).intersect(fill), BARK, 0.8)
    img.paint(Bitmap(S, S).stroke(pts, 4.5), BARK)
    img.save_tga("stone")


def flame():
    S = 256
    rng = random.Random(9)
    body = Bitmap(S, S).ellipse(S / 2, S / 2 + 34, 92, 74)
    tongues = []
    for i, (x, h, w) in enumerate([(60, 150, 34), (96, 196, 40), (130, 226, 46), (166, 190, 40), (198, 140, 32)]):
        top = (x + rng.uniform(-10, 10), S / 2 + 40 - h * 0.62)
        tongues.append([(x - w, S / 2 + 40), top, (x + w, S / 2 + 40)])
    for t in tongues:
        body.poly(t)
    ink = body.copy()
    for t in tongues:
        ink.stroke(t, 11)
    ink.circle(S / 2, S / 2 + 34, 80, 48)
    ink.ellipse(S / 2, S / 2 + 34, 98, 80)
    img = Image(S, S)
    img.paint(ink, BARK)
    img.paint(body, (0.86, 0.86, 0.86))
    core = Bitmap(S, S).ellipse(S / 2, S / 2 + 46, 58, 44)
    core.poly([(S / 2 - 34, S / 2 + 40), (S / 2 + 4, S / 2 - 76), (S / 2 + 34, S / 2 + 40)])
    img.paint(core.intersect(body), WHITE)
    img.save_tga("flame")


def splash():
    S = 256
    rng = random.Random(13)
    body = Bitmap(S, S).ellipse(S / 2, S / 2 + 10, 100, 78)
    drops = []
    for i in range(9):
        a = -math.pi + math.pi * (i + 0.5) / 9 + rng.uniform(-0.08, 0.08)
        r = rng.uniform(96, 116)
        x, y = S / 2 + r * math.cos(a), S / 2 + 4 + r * 0.9 * math.sin(a)
        drops.append((x, y, rng.uniform(10, 17)))
        body.poly([(S / 2 + 60 * math.cos(a - 0.16), S / 2 + 10 + 50 * math.sin(a - 0.16)), (x, y),
                   (S / 2 + 60 * math.cos(a + 0.16), S / 2 + 10 + 50 * math.sin(a + 0.16))])
    for x, y, r in drops:
        body.circle(x, y, r, 24)
    ink = body.copy()
    for x, y, r in drops:
        ink.circle(x, y, r + 6, 24)
    ink.ellipse(S / 2, S / 2 + 10, 106, 84)
    img = Image(S, S)
    img.paint(ink, BARK)
    img.paint(body, (0.84, 0.84, 0.84))
    # ripples across the middle
    for k, (rx, ry) in enumerate([(70, 40), (46, 26)]):
        ring = Bitmap(S, S).ellipse(S / 2, S / 2 + 24, rx, ry).subtract(Bitmap(S, S).ellipse(S / 2, S / 2 + 24, rx - 7, ry - 6))
        img.paint(ring.intersect(body), WHITE)
    img.paint(Bitmap(S, S).ellipse(S / 2 - 40, S / 2 - 22, 22, 10, -0.4).intersect(body), WHITE)
    img.save_tga("splash")


def leaf():
    S = 256
    # a broad leaf, pointing up-right
    rot = -0.62
    c, s = math.cos(rot), math.sin(rot)

    def R(x, y):
        return (S / 2 + x * c - y * s, S / 2 + x * s + y * c)
    pts = []
    for i in range(41):
        t = i / 40
        x = -118 + 236 * t
        w = 74 * math.sin(math.pi * t) ** 0.8 * (1 - 0.25 * t)
        pts.append(R(x, -w))
    for i in range(40, -1, -1):
        t = i / 40
        x = -118 + 236 * t
        w = 74 * math.sin(math.pi * t) ** 0.8 * (1 - 0.25 * t)
        pts.append(R(x, w * 0.92))
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 11), BARK)
    fill = Bitmap(S, S).poly(pts)
    img.paint(fill, WHITE)
    # shade the lower half, carve the midrib and veins
    lower = Bitmap(S, S).poly([R(-130, 0), R(130, 0), R(130, 90), R(-130, 90)]).intersect(fill)
    img.paint(lower, SHADE)
    img.paint(Bitmap(S, S).stroke([R(-128, 0), R(112, 0)], 5, False).intersect(fill), BARK)
    for k in range(5):
        x = -70 + k * 40
        for sgn in (-1, 1):
            img.paint(Bitmap(S, S).stroke([R(x, 0), R(x + 34, sgn * 44)], 3, False).intersect(fill), BARK, 0.7)
    img.paint(Bitmap(S, S).stroke(pts, 4.5), BARK)
    img.save_tga("leaf")


def bolt_burst():
    S = 256
    rng = random.Random(17)
    pts = []
    n = 9
    rot = rng.uniform(0, 1)
    for i in range(n):
        a = rot + 2 * math.pi * i / n
        da = math.pi / n
        # each ray is a zigzag (out, a kink back, out to the tip); angles only ever increase,
        # so the outline never crosses itself
        r = rng.uniform(112, 124)
        for rr, aa in ((60, a - da), (98, a - 0.17), (84, a - 0.07), (r, a + 0.03)):
            pts.append((S / 2 + rr * math.cos(aa), S / 2 + rr * math.sin(aa)))
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 10), BARK)
    fill = Bitmap(S, S).poly(pts)
    img.paint(fill, (0.86, 0.86, 0.86))
    img.paint(Bitmap(S, S).circle(S / 2, S / 2, 62, 40).intersect(fill), WHITE)
    img.paint(Bitmap(S, S).stroke(pts, 4), BARK)
    img.save_tga("bolt")


def wisp():
    S = 256
    rng = random.Random(23)
    body = Bitmap(S, S)
    ink = Bitmap(S, S)
    puffs = []
    for i in range(14):
        t = i / 13
        a = t * 5.2
        r = 30 + 72 * t
        x, y = S / 2 + r * math.cos(a) * 1.1, S / 2 + r * math.sin(a) * 0.8
        rr = 26 + 18 * (1 - abs(t - 0.6))
        puffs.append((x, y, rr))
    body.ellipse(S / 2, S / 2, 80, 58)
    ink.ellipse(S / 2, S / 2, 86, 64)
    for x, y, r in puffs:
        body.circle(x, y, r, 30)
        ink.circle(x, y, r + 6, 30)
    img = Image(S, S)
    img.paint(ink, BARK)
    img.paint(body, (0.88, 0.88, 0.88))
    spiral = []
    for i in range(60):
        t = i / 59
        a = t * 4.6
        r = 8 + 60 * t
        spiral.append((S / 2 + r * math.cos(a), S / 2 + r * math.sin(a) * 0.75))
    img.paint(Bitmap(S, S).stroke(spiral, 9, False).intersect(body), WHITE)
    img.paint(Bitmap(S, S).stroke(spiral, 3, False).intersect(body), BARK, 0.5)
    img.save_tga("wisp")


def rune():
    S = 256
    c = S / 2
    rng = random.Random(29)
    pts = jag_poly(c, c, 16, 120, 108, rng, 0.03, 0.1)
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 10), BARK)
    fill = Bitmap(S, S).poly(pts)
    img.paint(fill, WHITE)
    band = Bitmap(S, S).circle(c, c, 96, 64).subtract(Bitmap(S, S).circle(c, c, 72, 64))
    img.paint(band, SHADE)
    for i in range(12):
        a = 2 * math.pi * i / 12
        ax, ay = c + 76 * math.cos(a), c + 76 * math.sin(a)
        bx, by = c + 92 * math.cos(a + (0.12 if i % 2 else -0.12)), c + 92 * math.sin(a + (0.12 if i % 2 else -0.12))
        img.paint(Bitmap(S, S).stroke([(ax, ay), (bx, by)], 4, False), BARK)
    img.paint(Bitmap(S, S).circle(c, c, 98, 64).subtract(Bitmap(S, S).circle(c, c, 94, 64)), BARK)
    img.paint(Bitmap(S, S).circle(c, c, 72, 64).subtract(Bitmap(S, S).circle(c, c, 68, 64)), BARK)
    img.paint(Bitmap(S, S).stroke(pts, 4), BARK)
    img.save_tga("rune")


# ---------------------------------------------------------------- particles
def leaf_p():
    S = 64
    pts = []
    for i in range(21):
        t = i / 20
        pts.append((6 + 52 * t, 32 - 16 * math.sin(math.pi * t) ** 0.8))
    for i in range(20, -1, -1):
        t = i / 20
        pts.append((6 + 52 * t, 32 + 14 * math.sin(math.pi * t) ** 0.8))
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 5), BARK)
    img.paint(Bitmap(S, S).poly(pts), WHITE)
    img.paint(Bitmap(S, S).stroke([(8, 32), (54, 31)], 2.5, False), BARK, 0.8)
    img.save_tga("leaf_p")


def ember():
    S = 64
    c = S / 2
    pts = [(c, 4), (c + 12, c - 4), (c + 7, c + 18), (c, S - 6), (c - 7, c + 18), (c - 12, c - 4)]
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 5), BARK)
    img.paint(Bitmap(S, S).poly(pts), WHITE)
    img.save_tga("ember")


def drop():
    S = 64
    c = S / 2
    pts = [(c, 5)]
    for i in range(25):
        a = -0.35 + (math.pi + 0.7) * i / 24
        pts.append((c + 17 * math.cos(a), 40 + 17 * math.sin(a)))
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 5), BARK)
    img.paint(Bitmap(S, S).poly(pts), WHITE)
    img.paint(Bitmap(S, S).ellipse(c - 6, 38, 4, 7, 0.3), SHADE)
    img.save_tga("drop")


def pebble():
    S = 64
    rng = random.Random(31)
    pts = []
    for i in range(7):
        a = 2 * math.pi * i / 7 + rng.uniform(-0.2, 0.2)
        r = rng.uniform(18, 26)
        pts.append((32 + r * math.cos(a), 32 + r * math.sin(a)))
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 5), BARK)
    fill = Bitmap(S, S).poly(pts)
    img.paint(fill, WHITE)
    facets(img, fill, pts, 32, 32)
    img.save_tga("pebble")


def mote():
    S = 64
    img = Image(S, S)
    for y in range(S):
        for x in range(S):
            d = math.hypot(x + 0.5 - S / 2, y + 0.5 - S / 2) / (S / 2)
            a = max(0.0, 1 - d)
            core = 1.0 if d < 0.28 else 0.0
            img.px[y][x] = [1.0, 1.0, 1.0, min(1.0, a * a * 1.2 + core)]
    img.save_tga("mote")


def zap():
    S = 64
    pts = [(40, 2), (14, 34), (29, 34), (22, 62), (52, 24), (36, 24), (48, 2)]
    img = Image(S, S)
    img.paint(Bitmap(S, S).poly(pts).stroke(pts, 7), BARK)
    img.paint(Bitmap(S, S).poly(pts), WHITE)
    img.save_tga("zap")


def glow():
    S = 128
    img = Image(S, S)
    for y in range(S):
        for x in range(S):
            d = math.hypot(x + 0.5 - S / 2, y + 0.5 - S / 2) / (S / 2)
            a = max(0.0, 1 - d)
            img.px[y][x] = [1.0, 1.0, 1.0, a * a]
    img.save_tga("glow")


def ripple():
    S = 128
    c = S / 2
    img = Image(S, S)
    img.paint(Bitmap(S, S).circle(c, c, 60, 64).subtract(Bitmap(S, S).circle(c, c, 50, 64)), BARK, 0.8)
    img.paint(Bitmap(S, S).circle(c, c, 57, 64).subtract(Bitmap(S, S).circle(c, c, 53, 64)), WHITE)
    img.paint(Bitmap(S, S).circle(c, c, 42, 64).subtract(Bitmap(S, S).circle(c, c, 39, 64)), WHITE, 0.6)
    img.save_tga("ripple")


def rays():
    S = 256
    rng = random.Random(37)
    bm = Bitmap(S, S)
    n = 14
    for i in range(n):
        a = 2 * math.pi * i / n + rng.uniform(-0.06, 0.06)
        r0, r1 = rng.uniform(44, 64), rng.uniform(112, 127)
        w = rng.uniform(0.05, 0.09)
        bm.poly([(S / 2 + r0 * math.cos(a - w * 0.3), S / 2 + r0 * math.sin(a - w * 0.3)),
                 (S / 2 + r1 * math.cos(a - w), S / 2 + r1 * math.sin(a - w)),
                 (S / 2 + (r1 + 6) * math.cos(a), S / 2 + (r1 + 6) * math.sin(a)),
                 (S / 2 + r1 * math.cos(a + w), S / 2 + r1 * math.sin(a + w)),
                 (S / 2 + r0 * math.cos(a + w * 0.3), S / 2 + r0 * math.sin(a + w * 0.3))])
    Image(S, S).paint(bm, WHITE).save_tga("rays")


def arc():
    """A lightning streak along the horizontal middle of a square (so it can be rotated)."""
    S = 256
    rng = random.Random(41)
    pts = [(8, S / 2)]
    x = 8
    while x < S - 30:
        x += rng.uniform(22, 34)
        pts.append((x, S / 2 + rng.uniform(-22, 22)))
    pts.append((S - 8, S / 2))
    img = Image(S, S)
    img.paint(Bitmap(S, S).stroke(pts, 13, False), BARK)
    img.paint(Bitmap(S, S).stroke(pts, 6, False), WHITE)
    # a forked branch
    k = len(pts) // 2
    br = [pts[k], (pts[k][0] + 26, pts[k][1] + 30), (pts[k][0] + 40, pts[k][1] + 54)]
    img.paint(Bitmap(S, S).stroke(br, 8, False), BARK)
    img.paint(Bitmap(S, S).stroke(br, 3, False), WHITE)
    img.save_tga("arc")


# ---------------------------------------------------------------- HUD pieces
BAR_W, BAR_H = 512, 64
BAR_IN = (22, 14, 18)  # inner trough: x margin, y margin, end slant


def bar_inner(inset=0):
    m, my, sl = BAR_IN[0] + inset, BAR_IN[1] + inset, BAR_IN[2]
    return [(m + sl, my), (BAR_W - m - sl, my), (BAR_W - m, BAR_H / 2), (BAR_W - m - sl, BAR_H - my),
            (m + sl, BAR_H - my), (m, BAR_H / 2)]


def bars():
    inner = bar_inner()
    Image(BAR_W, BAR_H).paint(Bitmap(BAR_W, BAR_H).poly(inner), WHITE).save_tga("bar_mask")
    # the carved stone rim
    outer = [(6 + 22, 3), (BAR_W - 6 - 22, 3), (BAR_W - 3, BAR_H / 2), (BAR_W - 6 - 22, BAR_H - 3),
             (6 + 22, BAR_H - 3), (3, BAR_H / 2)]
    img = Image(BAR_W, BAR_H)
    rim = Bitmap(BAR_W, BAR_H).poly(outer).subtract(Bitmap(BAR_W, BAR_H).poly(inner))
    img.paint(Bitmap(BAR_W, BAR_H).stroke(outer, 5).poly(outer).subtract(Bitmap(BAR_W, BAR_H).poly(bar_inner(3))), BARK)
    img.paint(rim, stone_fn(4, 1.0))
    # light top edge, dark lower edge
    img.paint(Bitmap(BAR_W, BAR_H).poly([(28, 4), (BAR_W - 28, 4), (BAR_W - 40, 11), (40, 11)]).intersect(rim), STONE_LIGHT, 0.7)
    img.paint(Bitmap(BAR_W, BAR_H).poly([(40, BAR_H - 11), (BAR_W - 40, BAR_H - 11), (BAR_W - 28, BAR_H - 4), (28, BAR_H - 4)]).intersect(rim), STONE_DARK, 0.8)
    # notches every fifth, carved into the rim top and bottom
    x0, x1 = BAR_IN[0] + BAR_IN[2], BAR_W - BAR_IN[0] - BAR_IN[2]
    for k in range(1, 5):
        x = x0 + (x1 - x0) * k / 5
        for y0, y1 in ((2, BAR_IN[1] + 3), (BAR_H - 2, BAR_H - BAR_IN[1] - 3)):
            img.paint(Bitmap(BAR_W, BAR_H).poly([(x - 5, y0), (x + 5, y0), (x, y1)]), BARK)
    # carved diamonds at the ends
    for cx in (BAR_IN[0] + 2, BAR_W - BAR_IN[0] - 2):
        d = [(cx, BAR_H / 2 - 9), (cx + 6, BAR_H / 2), (cx, BAR_H / 2 + 9), (cx - 6, BAR_H / 2)]
        img.paint(Bitmap(BAR_W, BAR_H).poly(d), BARK)
    # the inner lip
    img.paint(Bitmap(BAR_W, BAR_H).stroke(inner, 3.5), BARK)
    img.save_tga("bar_frame")
    # the fill: water, with a bright surface band and darker depths (tinted in the game)
    img = Image(BAR_W, BAR_H)

    def water(x, y):
        v = 0.86
        surf = BAR_IN[1] + 6 + 2.2 * math.sin(x * 0.07) + 1.5 * math.sin(x * 0.19 + 1.3)
        if y < surf:
            v = 1.0
        elif y > BAR_H - BAR_IN[1] - 12:
            v = 0.72
        v -= 0.07 * noise2(x * 0.06, y * 0.2, 9)
        return (v, v, v)
    img.paint(Bitmap(BAR_W, BAR_H).poly([(0, 0), (BAR_W, 0), (BAR_W, BAR_H), (0, BAR_H)]), water)
    rng = random.Random(43)
    for _ in range(26):
        x, y = rng.uniform(0, BAR_W), rng.uniform(BAR_IN[1] + 12, BAR_H - BAR_IN[1] - 4)
        r = rng.uniform(1.5, 3.2)
        img.paint(Bitmap(BAR_W, BAR_H).circle(x, y, r, 12).subtract(Bitmap(BAR_W, BAR_H).circle(x, y, r - 1.2, 12)), WHITE, 0.8)
    img.save_tga("bar_fill")


def totem():
    """A carved wooden plaque for one totem: a window for the icon, wings at the top corners,
    a notched foot."""
    S = 64
    img = Image(S, S)
    outer = [(10, 6), (20, 12), (44, 12), (54, 6), (58, 18), (54, 26), (54, 50), (40, 60), (24, 60), (10, 50),
             (10, 26), (6, 18)]
    win = [(17, 18), (47, 18), (47, 47), (40, 54), (24, 54), (17, 47)]
    body = Bitmap(S, S).poly(outer)
    # the window stays open: the icon (or the element's sign) shows through it
    img.paint(Bitmap(S, S).poly(outer).stroke(outer, 4).subtract(Bitmap(S, S).poly(win)), BARK)
    img.paint(body.copy().subtract(Bitmap(S, S).poly(win)), grain_fn(WOOD, WOOD_DARK, WOOD_LIGHT, 0.45, 5, True))
    # carved eyes on the wings, a chevron under the window
    for cx in (12, 52):
        img.paint(Bitmap(S, S).circle(cx, 16, 2.2, 10), BARK)
    img.paint(Bitmap(S, S).stroke([(26, 57), (32, 54), (38, 57)], 1.8, False), BARK)
    img.paint(Bitmap(S, S).poly([(20, 13), (44, 13), (42, 15.5), (22, 15.5)]), WOOD_LIGHT, 0.8)
    img.paint(Bitmap(S, S).stroke(win, 3), BARK)
    img.save_tga("totem")


def glyphs():
    """The four elements as carved signs, white with bark edges (tinted per element)."""
    S = 64
    c = S / 2
    shapes = {
        # earth: a mountain over a line
        "g_earth": [[(8, 46), (26, 16), (36, 32), (42, 24), (56, 46)], [(8, 54), (56, 54)]],
        # fire: a flame of three tongues
        "g_fire": None,
        # water: three waves
        "g_water": [[(8, 22), (18, 14), (28, 22), (38, 14), (48, 22), (56, 16)],
                    [(8, 36), (18, 28), (28, 36), (38, 28), (48, 36), (56, 30)],
                    [(8, 50), (18, 42), (28, 50), (38, 42), (48, 50), (56, 44)]],
        # air: a swirl and a gust
        "g_air": None,
    }
    for name, lines in shapes.items():
        img = Image(S, S)
        ink, fill = Bitmap(S, S), Bitmap(S, S)
        if name == "g_fire":
            pts = [(c, 6), (c + 8, 22), (c + 16, 14), (c + 18, 34), (c + 14, 50), (c, 58), (c - 14, 50), (c - 18, 34),
                   (c - 16, 14), (c - 8, 22)]
            fill.poly(pts)
            ink.poly(pts).stroke(pts, 7)
        elif name == "g_air":
            sp = []
            for i in range(40):
                t = i / 39
                a = 0.5 + t * 5.4
                r = 22 * (1 - t) + 3
                sp.append((c + 4 + r * math.cos(a), c - 2 + r * math.sin(a)))
            for l in (sp, [(6, 50), (30, 50), (44, 46)]):
                fill.stroke(l, 6, False)
                ink.stroke(l, 12, False)
        else:
            for l in lines:
                fill.stroke(l, 6, False)
                ink.stroke(l, 12, False)
        img.paint(ink, BARK)
        img.paint(fill, WHITE)
        img.save_tga(name)


def orb():
    S = 64
    c = S / 2
    img = Image(S, S)
    img.paint(Bitmap(S, S).circle(c, c, 28, 40), BARK)

    def shade(x, y):
        d = math.hypot(x - c + 8, y - c + 8) / 34
        v = 1.0 - 0.38 * min(1, d)
        return (v, v, v)
    img.paint(Bitmap(S, S).circle(c, c, 24, 40), shade)
    img.paint(Bitmap(S, S).ellipse(c - 8, c - 9, 7, 4, -0.6), WHITE)
    # a crackle across it
    img.paint(Bitmap(S, S).stroke([(14, 36), (24, 28), (30, 36), (40, 24), (50, 30)], 2.4, False), BARK, 0.7)
    img.save_tga("orb")


def badge():
    """A round carved frame for the weapon imbue, with a window for the icon."""
    S = 64
    c = S / 2
    rng = random.Random(47)
    img = Image(S, S)
    outer = jag_poly(c, c, 10, 30, 28, rng, 0.03, 0.1)
    img.paint(Bitmap(S, S).poly(outer).stroke(outer, 4).subtract(Bitmap(S, S).circle(c, c, 18.5, 40)), BARK)
    ring = Bitmap(S, S).poly(outer).subtract(Bitmap(S, S).circle(c, c, 19, 40))
    img.paint(ring, grain_fn(WOOD, WOOD_DARK, WOOD_LIGHT, 0.4, 8))
    for i in range(8):
        a = 2 * math.pi * i / 8 + 0.2
        img.paint(Bitmap(S, S).stroke([(c + 21 * math.cos(a), c + 21 * math.sin(a)), (c + 27 * math.cos(a), c + 27 * math.sin(a))], 2, False), BARK)
    img.paint(Bitmap(S, S).circle(c, c, 20.5, 40).subtract(Bitmap(S, S).circle(c, c, 18.5, 40)), BARK)
    img.save_tga("badge")


def tablet():
    """Background of a timer box: a light plank with soft grain (tinted per kind)."""
    W, H = 128, 32
    img = Image(W, H)
    img.paint(Bitmap(W, H).poly([(0, 0), (W, 0), (W, H), (0, H)]), white_grain(11, 0.7, 0.18))
    img.paint(Bitmap(W, H).poly([(0, 0), (W, 0), (W, 4), (0, 4)]), WHITE, 0.7)
    img.paint(Bitmap(W, H).poly([(0, H - 5), (W, H - 5), (W, H), (0, H)]), SHADE, 0.8)
    img.save_tga("tablet")


def png(path, w, h, rgba):
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + rgba[y * w * 4:(y + 1) * w * 4] for y in range(h))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def contact_sheet(path, names, tints, bg=(0.16, 0.20, 0.14), cell=256):
    """Each texture, multiplied by a tint and laid over a background, like the game would draw it."""
    w, h = cell * len(names), max(cell, max(ART[n].h for n in names))
    buf = bytearray(w * h * 4)
    for i in range(w * h):
        buf[i * 4:i * 4 + 4] = bytes((int(bg[0] * 255), int(bg[1] * 255), int(bg[2] * 255), 255))
    for k, name in enumerate(names):
        img, tint = ART[name], tints[k % len(tints)]
        ox, oy = k * cell + (cell - img.w) // 2, (h - img.h) // 2
        for y in range(img.h):
            for x in range(img.w):
                r, g, b, a = img.px[y][x]
                if a <= 0 or not (0 <= ox + x < w):
                    continue
                i = ((oy + y) * w + ox + x) * 4
                for c, v in enumerate((r * tint[0], g * tint[1], b * tint[2])):
                    buf[i + c] = int((min(1, v) * a + buf[i + c] / 255.0 * (1 - a)) * 255 + 0.5)
    png(path, w, h, bytes(buf))
    print("preview", path)


if __name__ == "__main__":
    stone()
    flame()
    splash()
    leaf()
    bolt_burst()
    wisp()
    rune()
    leaf_p()
    ember()
    drop()
    pebble()
    mote()
    zap()
    glow()
    ripple()
    rays()
    arc()
    bars()
    totem()
    glyphs()
    orb()
    badge()
    tablet()
    if len(sys.argv) > 1:
        d = sys.argv[1]
        os.makedirs(d, exist_ok=True)
        earth, fire, water, air = (0.66, 0.50, 0.28), (1.0, 0.52, 0.14), (0.28, 0.62, 1.0), (0.80, 0.92, 1.0)
        heal, storm = (0.42, 0.90, 0.48), (0.55, 0.78, 1.0)
        contact_sheet(os.path.join(d, "sheet1.png"), ["stone", "flame", "splash", "leaf", "bolt", "wisp", "rune"],
                      [earth, fire, water, heal, storm, air, (0.95, 0.85, 0.55)])
        contact_sheet(os.path.join(d, "sheet2.png"), ["leaf_p", "ember", "drop", "pebble", "mote", "zap", "glow", "ripple",
                                                      "totem", "badge", "orb", "g_earth", "g_fire", "g_water", "g_air"],
                      [heal, fire, water, earth, air, storm, WHITE, water, WHITE, WHITE, storm, earth, fire, water, air], cell=96)
        contact_sheet(os.path.join(d, "sheet3.png"), ["bar_frame", "bar_fill", "bar_mask"], [WHITE, water, WHITE], cell=520)
        contact_sheet(os.path.join(d, "sheet4.png"), ["rays", "arc", "tablet"], [(1, 0.9, 0.6), storm, (0.85, 0.95, 0.75)])
