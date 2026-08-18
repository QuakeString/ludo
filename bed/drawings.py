"""
Shop drawings, straight from the model.

Writes SVGs into out/: an isometric of the whole bed, dimensioned orthographic
views, and one sheet per part with the joinery marked out.  Everything is drawn
in millimetres at 1:1 in the SVG user space, so printing at any scale keeps the
dimensions honest.
"""

import math
import os
from typing import List, Optional, Sequence, Tuple

import model as M

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

LINE = "#1b1b1b"
THIN = "#6b6b6b"
DIMC = "#b4472b"
FILL = "#f4efe6"
FILL2 = "#e6dccb"
FILL3 = "#d5c7ae"
BG = "#ffffff"

FONT = "font-family='DejaVu Sans, Helvetica, Arial, sans-serif'"


# ------------------------------------------------------------------- svg bits

class Svg(object):
    def __init__(self, w: float, h: float, title: str):
        self.w, self.h, self.title = w, h, title
        self.parts: List[str] = []

    def add(self, s: str) -> None:
        self.parts.append(s)

    def rect(self, x, y, w, h, fill=FILL, stroke=LINE, sw=2.0, dash=None, opacity=1.0):
        d = f" stroke-dasharray='{dash}'" if dash else ""
        self.add(f"<rect x='{x:.1f}' y='{y:.1f}' width='{w:.1f}' height='{h:.1f}' "
                 f"fill='{fill}' fill-opacity='{opacity}' stroke='{stroke}' "
                 f"stroke-width='{sw}'{d}/>")

    def line(self, x1, y1, x2, y2, stroke=LINE, sw=2.0, dash=None):
        d = f" stroke-dasharray='{dash}'" if dash else ""
        self.add(f"<line x1='{x1:.1f}' y1='{y1:.1f}' x2='{x2:.1f}' y2='{y2:.1f}' "
                 f"stroke='{stroke}' stroke-width='{sw}'{d}/>")

    def path(self, d, fill="none", stroke=LINE, sw=2.0):
        self.add(f"<path d='{d}' fill='{fill}' stroke='{stroke}' stroke-width='{sw}' "
                 f"stroke-linejoin='round'/>")

    def circle(self, cx, cy, r, fill="none", stroke=LINE, sw=2.0, dash=None):
        d = f" stroke-dasharray='{dash}'" if dash else ""
        self.add(f"<circle cx='{cx:.1f}' cy='{cy:.1f}' r='{r:.1f}' fill='{fill}' "
                 f"stroke='{stroke}' stroke-width='{sw}'{d}/>")

    def text(self, x, y, s, size=26, anchor="start", fill=LINE, weight="normal"):
        s = (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
        self.add(f"<text x='{x:.1f}' y='{y:.1f}' font-size='{size}' {FONT} "
                 f"text-anchor='{anchor}' fill='{fill}' font-weight='{weight}'>{s}</text>")

    def dumps(self) -> str:
        return (f"<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 {self.w:.0f} "
                f"{self.h:.0f}' width='100%'>\n<title>{self.title}</title>\n"
                f"<rect width='{self.w:.0f}' height='{self.h:.0f}' fill='{BG}'/>\n"
                + "\n".join(self.parts) + "\n</svg>\n")

    def write(self, path: str) -> str:
        with open(path, "w") as fh:
            fh.write(self.dumps())
        return path


class View(object):
    """A projection placed on the sheet: view coordinates in, paper out."""

    def __init__(self, svg: Svg, ox: float, oy: float, height: float):
        self.svg, self.ox, self.oy, self.height = svg, ox, oy, height

    def pt(self, u: float, v: float) -> Tuple[float, float]:
        return self.ox + u, self.oy + self.height - v

    def rect(self, u, v, du, dv, **kw):
        x, y = self.pt(u, v + dv)
        self.svg.rect(x, y, du, dv, **kw)

    def line(self, u1, v1, u2, v2, **kw):
        x1, y1 = self.pt(u1, v1)
        x2, y2 = self.pt(u2, v2)
        self.svg.line(x1, y1, x2, y2, **kw)

    def circle(self, u, v, r, **kw):
        x, y = self.pt(u, v)
        self.svg.circle(x, y, r, **kw)

    def text(self, u, v, s, size=26, **kw):
        x, y = self.pt(u, v)
        self.svg.text(x, y, s, size, **kw)

    # dimension lines ------------------------------------------------------
    def dim_h(self, u1: float, u2: float, v: float, label: Optional[str] = None,
              off: float = 0.0):
        x1, y = self.pt(u1, v)
        x2, _ = self.pt(u2, v)
        y += off
        s = self.svg
        s.line(x1, y, x2, y, DIMC, 1.6)
        for x in (x1, x2):
            s.line(x, y - 9, x, y + 9, DIMC, 1.6)
        s.text((x1 + x2) / 2.0, y - 10, label or f"{abs(u2 - u1):.0f}", 26, "middle", DIMC)

    def dim_v(self, v1: float, v2: float, u: float, label: Optional[str] = None,
              off: float = 0.0):
        x, y1 = self.pt(u, v1)
        _, y2 = self.pt(u, v2)
        x += off
        s = self.svg
        s.line(x, y1, x, y2, DIMC, 1.6)
        for y in (y1, y2):
            s.line(x - 9, y, x + 9, y, DIMC, 1.6)
        s.add(f"<text x='{x - 12:.1f}' y='{(y1 + y2) / 2.0:.1f}' font-size='26' {FONT} "
              f"text-anchor='middle' fill='{DIMC}' "
              f"transform='rotate(-90 {x - 12:.1f} {(y1 + y2) / 2.0:.1f})'>"
              f"{label or f'{abs(v2 - v1):.0f}'}</text>")


# ------------------------------------------------------------ shape helpers

def solid_boxes(part: M.Solid, slices: int = 20) -> List[M.Box]:
    """The positive volume of a part as boxes, arches sliced into strips."""
    out: List[M.Box] = []
    body = part.body
    if body.dx and body.dy and body.dz:
        if part.arch:
            step = body.dx / float(slices)
            for i in range(slices):
                x = body.x + i * step
                t = (x + step / 2.0 - body.x) / body.dx        # 0..1 across the rail
                rise = part.arch * math.sin(math.pi * t)
                out.append(M.Box(x, body.y, body.z, step, body.dy, body.dz + rise))
        else:
            out.append(body)
    for a in part.adds:
        out.append(a.bbox() if isinstance(a, M.Cyl) else a)
    return out


def arch_path(view: View, u0, u1, v0, v1, rise, flip=False):
    """Outline of an arched rail in a view where u is across its length."""
    p = view.pt
    a, b = p(u0, v0), p(u1, v0)
    c, d = p(u1, v1), p(u0, v1)
    ctrl = p((u0 + u1) / 2.0, v1 + 2.0 * rise)
    return (f"M {a[0]:.1f} {a[1]:.1f} L {b[0]:.1f} {b[1]:.1f} L {c[0]:.1f} {c[1]:.1f} "
            f"Q {ctrl[0]:.1f} {ctrl[1]:.1f} {d[0]:.1f} {d[1]:.1f} Z")


# --------------------------------------------------------- assembly drawings

def _draw_ortho(view: View, parts: Sequence[M.Solid], axes: str, mirror_u: float = 0.0,
                ghost=None):
    """axes: which world axes map to (u, v).  'yz', 'xz' or 'xy'.

    Parts behind the cutting plane are ghosted: thin grey, no fill, drawn first."""
    def uv(b: M.Box):
        if axes == "yz":
            u, du, v, dv = b.y, b.dy, b.z, b.dz
        elif axes == "xz":
            u, du, v, dv = b.x, b.dx, b.z, b.dz
        else:
            u, du, v, dv = b.x, b.dx, b.y, b.dy
        if mirror_u:
            u = mirror_u - u - du
        return u, du, v, dv

    ordered = sorted(parts, key=lambda p: (not (ghost and ghost(p)), p.group))
    for part in ordered:
        behind = bool(ghost and ghost(part))
        fill = FILL3 if part.group.startswith("Drawer") else (
            FILL2 if part.group in ("Deck",) else FILL)
        if part.material == M.HARDWARE:
            fill = "#cfcfd4"
        if behind:
            fill = "none"
        stroke, sw = (THIN, 1.1) if behind else (LINE, 1.8)
        if part.arch and axes == "xz":
            u, du, v, dv = uv(part.body)
            view.svg.path(arch_path(view, u, u + du, v, v + dv, part.arch), fill, stroke, sw)
            for a in part.adds:
                u, du, v, dv = uv(a if isinstance(a, M.Box) else a.bbox())
                view.rect(u, v, du, dv, fill=fill, stroke=stroke, sw=sw)
            continue
        for b in solid_boxes(part, slices=1):
            u, du, v, dv = uv(b)
            view.rect(u, v, du, dv, fill=fill, stroke=stroke, sw=sw)
        if behind:
            continue
        for c in part.cuts:
            cb = c.bbox() if isinstance(c, M.Cyl) else c
            if cb.kind in ("slot",):
                u, du, v, dv = uv(cb)
                view.rect(u, v, du, dv, fill=BG, sw=1.6)


def assembly_views() -> str:
    parts = M.assembly()
    gap, m = 260.0, 190.0
    side_w, side_h = M.L_OUT, M.HEAD_POST_H + M.ARCH_RISE
    end_w = M.W_OUT
    plan_h = M.L_OUT
    sheet_w = m * 2 + side_w + gap + end_w
    sheet_h = m * 2 + side_h + gap + plan_h + 120

    svg = Svg(sheet_w, sheet_h, "Storage bed - general arrangement")
    svg.text(m, m - 90, "STORAGE BED - GENERAL ARRANGEMENT", 46, weight="bold")
    svg.text(m, m - 44,
             f"mattress {M.MAT_W} x {M.MAT_L} - overall {M.W_OUT} x {M.L_OUT} x "
             f"{M.HEAD_POST_H + M.ARCH_RISE} - all dimensions in mm", 26, fill=THIN)

    # elevation of the drawer side, head to the left
    side = View(svg, m, m, side_h)
    _draw_ortho(side, parts, "yz", mirror_u=M.L_OUT,
                ghost=lambda p: (p.envelope.x + p.envelope.x1) / 2.0 < M.W_OUT / 2.0)
    side.text(0, -70, "DRAWER SIDE ELEVATION", 30, weight="bold")
    side.dim_h(0, M.L_OUT, 0, off=110)
    side.dim_v(0, M.DECK_Z, M.L_OUT, "deck 400", off=70)
    side.dim_v(0, M.RAIL_Z0, 0, "drawer opening 240", off=-70)
    side.dim_v(0, M.HEAD_POST_H + M.ARCH_RISE, M.L_OUT, None, off=160)
    side.dim_h(M.L_OUT - M.HEAD_Y0, M.L_OUT - M.HEAD_Y0 + M.FRONT_L, M.FRONT_Z0,
               f"drawer front {M.FRONT_L:.0f}", off=180)

    # end elevation, looking at the foot end
    end = View(svg, m + side_w + gap, m, side_h)
    _draw_ortho(end, parts, "xz",
                ghost=lambda p: (p.envelope.y + p.envelope.y1) / 2.0 > M.L_OUT / 2.0)
    end.text(0, -70, "FOOT END ELEVATION", 30, weight="bold")
    end.dim_h(0, M.W_OUT, 0, off=110)
    end.dim_h(M.POST_X, M.POST_IN_R, 0, f"opening {M.OPEN_W:.0f}", off=170)
    end.dim_v(0, M.FOOT_H, M.W_OUT, None, off=70)

    # plan with the deck removed
    plan = View(svg, m, m + side_h + gap + 60, plan_h)
    _draw_ortho(plan, [p for p in parts if p.part not in ("slat",)], "xy")
    for p in [p for p in parts if p.part == "slat"]:
        plan.rect(p.body.x, p.body.y, p.body.dx, p.body.dy, fill="none",
                  stroke=THIN, sw=1.4, dash="14 10")
    plan.text(0, plan_h + 40, "PLAN - slats shown dashed", 30, weight="bold")
    plan.dim_h(0, M.W_OUT, 0, off=110)
    plan.dim_v(0, M.L_OUT, M.W_OUT, None, off=70)
    plan.dim_v(M.FOOT_Y1, M.FOOT_Y1 + M.SLAT_PITCH, M.SLAT_X0,
               f"slat pitch {M.SLAT_PITCH:.0f}", off=-60)

    # key, in the space beside the plan
    kx, ky = m + M.L_OUT + gap, m + side_h + gap + 120
    svg.text(kx, ky, "KEY DIMENSIONS", 32, weight="bold")
    lines = [
        f"mattress                {M.MAT_W} x {M.MAT_L}",
        f"overall                 {M.W_OUT} wide x {M.L_OUT} long",
        f"height, headboard       {M.HEAD_POST_H + M.ARCH_RISE} at the centre of the arch",
        f"height, foot end        {M.FOOT_H}",
        f"top of slats            {M.DECK_Z} above the floor",
        f"drawer opening          {M.RAIL_Z0} high x {M.OPEN_L} long",
        f"side rail               {M.RAIL_H} x {M.RAIL_T}, {M.SIDE_RAIL_L} over the tenons",
        f"posts                   {M.POST_Y} x {M.POST_X}",
        f"slats                   {M.SLAT_N} off {M.SLAT_W} x {M.SLAT_T}, "
        f"{M.SLAT_GAP:.0f} gap",
        "",
        "JOINTS",
        f"side rail to post       {M.TENON_T} mm tenon, {M.SIDE_MORTISE_D} deep,",
        f"                        drawn up by 2 bed bolts per joint",
        f"end rails to post       {M.TENON_T} mm tenon, {M.END_MORTISE_D} deep, glued",
        f"panels                  {M.PANEL_T} thick, floating in {M.GROOVE_D} mm grooves",
        "",
        "The bed knocks down: undo eight bolts and the two ends,",
        "two rails and the deck come apart.",
    ]
    for i, line in enumerate(lines):
        svg.text(kx, ky + 52 + i * 34, line, 26,
                 weight="bold" if line in ("JOINTS",) else "normal",
                 fill=LINE if line in ("JOINTS",) else THIN)

    return svg.write(os.path.join(OUT, "01-general-arrangement.svg"))


def _cells(b: M.Box, step: float = 150.0):
    """Chop a box into cells so a painter's-algorithm sort orders it correctly
    against anything that crosses it.  Cell faces that fall on the outside of
    the parent box keep their black edge; the cuts between cells do not."""
    def splits(lo, size):
        n = max(1, int(math.ceil(size / step)))
        return [lo + i * size / n for i in range(n + 1)]

    xs, ys, zs = splits(b.x, b.dx), splits(b.y, b.dy), splits(b.z, b.dz)
    edges = ((b.x, b.x1), (b.y, b.y1), (b.z, b.z1))
    for i in range(len(xs) - 1):
        for j in range(len(ys) - 1):
            for k in range(len(zs) - 1):
                yield (M.Box(xs[i], ys[j], zs[k], xs[i + 1] - xs[i],
                             ys[j + 1] - ys[j], zs[k + 1] - zs[k]), edges)


def isometric() -> str:
    """Painter's-algorithm isometric of the assembled bed."""
    parts = [p for p in M.assembly() if p.material != M.HARDWARE]
    cos30 = math.cos(math.radians(30))

    def project(x, y, z):
        return (x - y) * cos30, (x + y) * 0.5 - z

    items = []          # (depth, kind, payload)
    for p in parts:
        shade = 1 if p.group.startswith("Drawer") else (2 if p.group == "Deck" else 0)
        if p.arch:
            body = p.body
            fine = 40
            for i in range(fine):
                w = body.dx / fine
                x = body.x + i * w
                t = (x + w / 2.0 - body.x) / body.dx
                rise = p.arch * math.sin(math.pi * t)
                cell = M.Box(x, body.y, body.z, w, body.dy, body.dz + rise)
                items.append((_depth(cell), "cell", (cell, None, shade)))
            items.append((_depth(body) + 1e6, "arch", (p, shade)))
            for a in p.adds:
                for cell, edges in _cells(a):
                    items.append((_depth(cell), "cell", (cell, edges, shade)))
            continue
        for b in solid_boxes(p, slices=1):
            for cell, edges in _cells(b):
                items.append((_depth(cell), "cell", (cell, edges, shade)))

    pts = [project(b.x + dx, b.y + dy, b.z + dz)
           for d, k, pay in items if k == "cell"
           for b in (pay[0],)
           for dx in (0, b.dx) for dy in (0, b.dy) for dz in (0, b.dz)]
    minx, miny = min(p[0] for p in pts), min(p[1] for p in pts)
    maxx, maxy = max(p[0] for p in pts), max(p[1] for p in pts)
    m = 160.0
    svg = Svg(maxx - minx + 2 * m, maxy - miny + 2 * m + 120, "Storage bed - isometric")

    def P(x, y, z):
        px, py = project(x, y, z)
        return px - minx + m, py - miny + m + 100

    svg.text(m, m + 20, "STORAGE BED - ISOMETRIC", 46, weight="bold")
    tops = ("#efe6d6", "#e3d6bf", "#f2ead9")
    sides = ("#cbb99c", "#bda882", "#dfd2bb")
    fronts = ("#a8927a", "#9c8465", "#c4b499")

    items.sort(key=lambda t: t[0])
    for _, kind, payload in items:
        if kind == "arch":
            part, shade = payload
            b = part.body
            _draw_arch_outline(svg, P, b, part.arch)
            continue
        b, edges, shade = payload
        x0, x1, y0, y1, z0, z1 = b.x, b.x1, b.y, b.y1, b.z, b.z1
        faces = [
            ([(x0, y0, z1), (x1, y0, z1), (x1, y1, z1), (x0, y1, z1)], tops[shade]),
            ([(x1, y0, z0), (x1, y1, z0), (x1, y1, z1), (x1, y0, z1)], sides[shade]),
            ([(x0, y1, z0), (x1, y1, z0), (x1, y1, z1), (x0, y1, z1)], fronts[shade]),
        ]
        for corners, fill in faces:
            d = "M " + " L ".join("%.1f %.1f" % P(*c) for c in corners) + " Z"
            svg.path(d, fill, fill, 1.0)
            if edges is None:
                continue
            for a, bb in zip(corners, corners[1:] + corners[:1]):
                if _is_parent_edge(a, bb, edges):
                    pa, pb = P(*a), P(*bb)
                    svg.line(pa[0], pa[1], pb[0], pb[1], LINE, 1.4)
    return svg.write(os.path.join(OUT, "00-isometric.svg"))


def _depth(b: M.Box) -> float:
    return (b.x + b.x1 + b.y + b.y1 + b.z + b.z1) / 2.0


def _is_parent_edge(a, b, edges) -> bool:
    """True when the two corners share two coordinates that both sit on the
    outside of the parent box -- i.e. this is a real edge of the part."""
    on_parent = 0
    for i in range(3):
        if abs(a[i] - b[i]) > 1e-9:
            continue
        if any(abs(a[i] - e) < 1e-9 for e in edges[i]):
            on_parent += 1
        else:
            return False
    return on_parent == 2


def _draw_arch_outline(svg: Svg, P, b: M.Box, rise: float) -> None:
    """A clean outline over the sliced arch: front face, then the top surface."""
    def arc_pts(y, n=48):
        pts = []
        for i in range(n + 1):
            t = i / float(n)
            x = b.x + t * b.dx
            pts.append(P(x, y, b.z1 + rise * math.sin(math.pi * t)))
        return pts

    front = arc_pts(b.y1)
    back = arc_pts(b.y)
    corners = [P(b.x, b.y1, b.z), P(b.x1, b.y1, b.z)]
    d = ("M %.1f %.1f L %.1f %.1f " % (corners[0][0], corners[0][1],
                                       corners[1][0], corners[1][1])
         + "L " + " L ".join("%.1f %.1f" % p for p in reversed(front)) + " Z")
    svg.path(d, "none", LINE, 1.6)
    top = ("M " + " L ".join("%.1f %.1f" % p for p in front)
           + " L " + " L ".join("%.1f %.1f" % p for p in reversed(back)) + " Z")
    svg.path(top, "none", LINE, 1.6)


# ------------------------------------------------------------- part drawings

def _local(part: M.Solid):
    """Part geometry moved to the origin, with the axes sorted long->short."""
    env = part.envelope
    dims = [("x", env.dx), ("y", env.dy), ("z", env.dz)]
    order = [a for a, _ in sorted(dims, key=lambda t: -t[1])]
    size = {a: d for a, d in dims}

    def to_local(b: M.Box):
        lo = {"x": b.x - env.x, "y": b.y - env.y, "z": b.z - env.z}
        sz = {"x": b.dx, "y": b.dy, "z": b.dz}
        return ([lo[a] for a in order], [sz[a] for a in order], b.kind)

    pos = [to_local(b) for b in solid_boxes(part, slices=1)]
    cuts = [to_local(c.bbox() if isinstance(c, M.Cyl) else c) for c in part.cuts]
    holes = []
    for c in part.cuts:
        if isinstance(c, M.Cyl):
            b = c.bbox()
            lo, sz, _ = to_local(b)
            holes.append((lo, sz, c.axis, c.r, c.kind))
    return order, [size[a] for a in order], pos, cuts, holes


def _features(part: M.Solid, order, size):
    """Every hole, mortise and groove in the part, in its own coordinates.

    Returned as (ref, description, along, length, across, width, depth, face)
    with `along` measured from the left-hand end of the drawing."""
    env = part.envelope
    L, W, T = size
    rows = []
    for a in part.adds:
        b = a.bbox() if isinstance(a, M.Cyl) else a
        lo = {"x": b.x - env.x, "y": b.y - env.y, "z": b.z - env.z}
        sz = {"x": b.dx, "y": b.dy, "z": b.dz}
        al, ac = [lo[k] for k in order], [sz[k] for k in order]
        rows.append(["tenon", al[0], ac[0], al[1], ac[1], ac[2],
                     f"{al[2]:.0f} mm shoulder each face"])
    for c in part.cuts:
        b = c.bbox() if isinstance(c, M.Cyl) else c
        lo = {"x": b.x - env.x, "y": b.y - env.y, "z": b.z - env.z}
        sz = {"x": b.dx, "y": b.dy, "z": b.dz}
        al, ac, dp = [lo[a] for a in order], [sz[a] for a in order], None
        depth = ac[2]
        if isinstance(c, M.Cyl):
            axis_i = order.index(c.axis)
            if axis_i == 2:
                desc = f"dia {2 * c.r:.0f} {b.kind}"
            elif axis_i == 0:
                desc = f"dia {2 * c.r:.0f} {b.kind}, drilled from the end"
            else:
                desc = f"dia {2 * c.r:.0f} {b.kind}, drilled across the face"
            depth = c.h
        else:
            desc = b.kind
        if isinstance(c, M.Cyl) and order.index(c.axis) == 0:
            face = "drilled in from the end"
        elif al[2] <= 0.5 and depth >= T - 0.5:
            face = "through"
        elif al[2] <= 0.5:
            face = "from base (EDGE)"
        elif al[2] + depth >= T - 0.5:
            face = "from top (EDGE)"
        elif abs(al[2] - (T - depth - al[2])) <= 1.0:
            face = "centred in the thickness"
        else:
            face = f"set in {al[2]:.0f} from the base"
        rows.append([desc, al[0], ac[0], al[1], ac[1], depth, face])
    rows.sort(key=lambda r: (r[1], r[3]))
    refs = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    return [[refs[i % 26]] + r for i, r in enumerate(rows)]


def part_sheet(part: M.Solid, qty: int) -> str:
    order, size, pos, cuts, holes = _local(part)
    L, W, T = size
    rows = _features(part, order, size)
    m = 170.0
    gapv = 220.0
    table_h = 100 + 40 * (len(rows) + 1) if rows else 0
    table_w = 1900.0
    sheet_w = max(m * 2 + L + 300, m + table_w)
    sheet_h = m * 2 + 250 + W + gapv + T + 200 + table_h
    svg = Svg(sheet_w, sheet_h, part.label)

    svg.text(m, m - 110, part.label.upper(), 44, weight="bold")
    svg.text(m, m - 62,
             f"{qty} off   -   {L:.0f} x {W:.0f} x {T:.0f} mm   -   {part.material}"
             f"   -   grain {part.grain}", 28, fill=THIN)
    if part.note:
        svg.text(m, m - 24, part.note, 25, fill=THIN)

    face = View(svg, m, m + 190, W)
    edge = View(svg, m, m + 190 + W + gapv, T)

    def draw(view: View, ui: int, vi: int, arch_here: bool, letters: bool):
        for lo, sz, _ in pos:
            view.rect(lo[ui], lo[vi], sz[ui], sz[vi], fill=FILL, sw=2.2)
        if arch_here and part.arch:
            b, env = part.body, part.envelope
            u0 = b.x - env.x
            x, y = view.pt(0, W)
            view.svg.rect(x, y, L, W, fill=BG, stroke="none")
            view.rect(0, 0, L, W, fill="none", stroke=THIN, sw=1.4, dash="16 10")
            view.svg.path(arch_path(view, u0, u0 + b.dx, 0, b.dz, part.arch), FILL, LINE, 2.2)
            for a in part.adds:
                view.rect(a.x - env.x, a.z - env.z, a.dx, a.dz, fill=FILL, sw=2.2)
        for lo, sz, kind in cuts:
            if kind in ("hole", "counterbore"):
                continue
            view.rect(lo[ui], lo[vi], sz[ui], sz[vi], fill=BG, stroke=LINE, sw=1.6,
                      dash="12 8")
        for lo, sz, axis, r, kind in holes:
            axis_i = order.index(axis)
            if axis_i not in (ui, vi):
                view.circle(lo[ui] + sz[ui] / 2.0, lo[vi] + sz[vi] / 2.0, r,
                            fill=BG, sw=1.6, dash="10 7" if kind == "hole" else None)
            else:
                view.rect(lo[ui], lo[vi], sz[ui], sz[vi], fill="none", sw=1.4, dash="10 7")
        if not letters:
            return
        for i, row in enumerate(rows):
            ref, along, length = row[0], row[2], row[4]
            u = along + length / 2.0
            v = W + 26 + 40 * (i % 4)
            view.line(u, W, u, v - 26, stroke=DIMC, sw=1.0)
            view.text(u, v - 18, ref, 30, anchor="middle", weight="bold", fill=DIMC)

    draw(face, 0, 1, arch_here=(order[1] == "z"), letters=True)
    draw(edge, 0, 2, arch_here=False, letters=False)
    face.text(0, -34, "FACE", 26, fill=THIN)
    edge.text(0, -34, "EDGE", 26, fill=THIN)

    face.dim_h(0, L, 0, off=100)
    face.dim_v(0, W, L, off=80)
    edge.dim_v(0, T, L, off=80)

    if rows:
        ty = m + 190 + W + gapv + T + 170
        svg.text(m, ty, "SETTING OUT", 32, weight="bold")
        cols = [0, 70, 620, 810, 1000, 1190, 1330]
        head = ["", "feature", "from left end", "length", "across face",
                "width", "depth"]
        for c, h in zip(cols, head):
            svg.text(m + c, ty + 46, h, 24, fill=THIN)
        svg.line(m, ty + 58, m + cols[-1] + 300, ty + 58, THIN, 1.2)
        svg.text(m, ty + 96 + 40 * len(rows) + 30,
                 "EDGE view is the same part on its side; 'top' and 'base' name the "
                 "face the cut is made from.  Dashed outlines are hidden work.",
                 24, fill=THIN)
        for i, (ref, desc, along, length, across, width, depth, facing) in enumerate(rows):
            y = ty + 96 + i * 40
            for c, txt in zip(cols, [ref, desc, f"{along:.0f}", f"{length:.0f}",
                                     f"{across:.0f}", f"{width:.0f}",
                                     (f"{depth:.0f} thick, {facing}"
                                      if desc == "tenon"
                                      else f"{depth:.0f}  {facing}")]):
                svg.text(m + c, y, txt, 25,
                         weight="bold" if c == 0 else "normal",
                         fill=DIMC if c == 0 else LINE)
    return svg.write(os.path.join(OUT, f"part-{part.part}.svg"))


def unique_parts() -> List[Tuple[M.Solid, int]]:
    seen = {}
    order = []
    for p in M.assembly():
        if p.material == M.HARDWARE:
            continue
        if p.part not in seen:
            seen[p.part] = [p, 0]
            order.append(p.part)
        seen[p.part][1] += 1
    return [tuple(seen[k]) for k in order]


def all_drawings() -> List[str]:
    if not os.path.isdir(OUT):
        os.makedirs(OUT)
    written = [isometric(), assembly_views()]
    for part, qty in unique_parts():
        written.append(part_sheet(part, qty))
    return written


if __name__ == "__main__":
    for f in all_drawings():
        print("wrote", os.path.relpath(f))
