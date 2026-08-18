"""
A stand-in for the FreeCAD Python API.

FreeCAD is not a pip package, so the macro cannot be executed on a machine that
has no FreeCAD installed -- including CI.  This module implements just enough of
`FreeCAD` and `Part` for freecad_bed.py to run: primitives keep their bounding
box and volume, booleans record what was added and taken away, and the document
holds the resulting objects.

Volumes are approximate (a cut is accounted for by the overlap of bounding boxes
weighted by how solidly each primitive fills its own box), which is plenty to
catch a part built in the wrong place, at the wrong size, or missing a joint.
It is not a substitute for opening the model in FreeCAD.
"""

import math
import sys
import types

GuiUp = False


# ----------------------------------------------------------------- primitives

def _prim_box(x, y, z, dx, dy, dz):
    return {"kind": "box", "bb": (x, y, z, x + dx, y + dy, z + dz), "vol": dx * dy * dz}


def _prim_cyl(base, direction, r, h):
    x, y, z = base
    dx, dy, dz = direction
    span = [(x, x), (y, y), (z, z)]
    for i, (d, c) in enumerate(zip((dx, dy, dz), (x, y, z))):
        if d:
            span[i] = (min(c, c + d * h), max(c, c + d * h))
        else:
            span[i] = (c - r, c + r)
    bb = (span[0][0], span[1][0], span[2][0], span[0][1], span[1][1], span[2][1])
    return {"kind": "cyl", "bb": bb, "vol": math.pi * r * r * h}


def _bb_union(prims):
    lo = [min(p["bb"][i] for p in prims) for i in range(3)]
    hi = [max(p["bb"][i] for p in prims) for i in range(3, 6)]
    return lo + hi


def _bb_overlap(a, b):
    v = 1.0
    for i in range(3):
        d = min(a[i + 3], b[i + 3]) - max(a[i], b[i])
        if d <= 0:
            return 0.0
        v *= d
    return v


def _density(p):
    bb = p["bb"]
    box = (bb[3] - bb[0]) * (bb[4] - bb[1]) * (bb[5] - bb[2])
    return p["vol"] / box if box else 0.0


# --------------------------------------------------------------------- shapes

class BoundBox(object):
    def __init__(self, bb):
        (self.XMin, self.YMin, self.ZMin, self.XMax, self.YMax, self.ZMax) = bb

    @property
    def XLength(self):
        return self.XMax - self.XMin

    @property
    def YLength(self):
        return self.YMax - self.YMin

    @property
    def ZLength(self):
        return self.ZMax - self.ZMin

    def __repr__(self):
        return "BoundBox(%g %g %g .. %g %g %g)" % (
            self.XMin, self.YMin, self.ZMin, self.XMax, self.YMax, self.ZMax)


class Shape(object):
    def __init__(self, pos=None, neg=None):
        self.pos = list(pos or [])
        self.neg = list(neg or [])

    # booleans ------------------------------------------------------------
    def fuse(self, other):
        return Shape(self.pos + other.pos, self.neg + other.neg)

    def cut(self, other):
        return Shape(self.pos, self.neg + other.pos)

    def common(self, other):
        return Shape([p for p in self.pos if any(_bb_overlap(p["bb"], q["bb"]) > 0
                                                 for q in other.pos)], self.neg)

    def removeSplitter(self):
        return self

    def copy(self):
        return Shape(self.pos, self.neg)

    def translate(self, v):
        for p in self.pos + self.neg:
            bb = p["bb"]
            p["bb"] = (bb[0] + v.x, bb[1] + v.y, bb[2] + v.z,
                       bb[3] + v.x, bb[4] + v.y, bb[5] + v.z)
        return self

    # measurements --------------------------------------------------------
    @property
    def BoundBox(self):
        return BoundBox(_bb_union(self.pos) if self.pos else [0] * 6)

    @property
    def Volume(self):
        total = sum(p["vol"] for p in self.pos)
        for n in self.neg:
            for p in self.pos:
                total -= _bb_overlap(p["bb"], n["bb"]) * _density(p) * _density(n)
        return max(total, 0.0)

    @property
    def Solids(self):
        return [self]

    def __repr__(self):
        return "<Shape %d+ %d- vol=%.0f>" % (len(self.pos), len(self.neg), self.Volume)


# ----------------------------------------------------------------- FreeCAD app

class Vector(object):
    def __init__(self, x=0.0, y=0.0, z=0.0):
        self.x, self.y, self.z = float(x), float(y), float(z)

    def __add__(self, o):
        return Vector(self.x + o.x, self.y + o.y, self.z + o.z)

    def __sub__(self, o):
        return Vector(self.x - o.x, self.y - o.y, self.z - o.z)

    def __mul__(self, k):
        return Vector(self.x * k, self.y * k, self.z * k)

    __rmul__ = __mul__

    def __iter__(self):
        return iter((self.x, self.y, self.z))

    def __repr__(self):
        return "Vector(%g, %g, %g)" % (self.x, self.y, self.z)


class Rotation(object):
    def __init__(self, *a, **k):
        pass


class Placement(object):
    def __init__(self, base=None, rotation=None):
        self.Base = base or Vector()
        self.Rotation = rotation or Rotation()


class _Object(object):
    def __init__(self, type_id, name, doc):
        self.TypeId = type_id
        self.Name = name
        self.Label = name
        self.Shape = None
        self.Group = []
        self.ViewObject = None
        self.Document = doc

    def addObject(self, obj):
        self.Group.append(obj)
        return obj


class Document(object):
    def __init__(self, name):
        self.Name = name
        self.Label = name
        self.Objects = []
        self.saved_to = None
        self._names = {}

    def addObject(self, type_id, name="Unnamed"):
        n = self._names.get(name, 0) + 1
        self._names[name] = n
        obj = _Object(type_id, name if n == 1 else "%s%03d" % (name, n), self)
        self.Objects.append(obj)
        return obj

    def recompute(self):
        return True

    def saveAs(self, path):
        self.saved_to = path
        with open(path, "w") as fh:
            fh.write("stub FCStd written by tools/fakecad.py -- %d objects\n"
                     % len(self.Objects))

    def getObject(self, name):
        for o in self.Objects:
            if o.Name == name:
                return o
        return None


_documents = {}


def newDocument(name="Unnamed"):
    doc = Document(name)
    _documents[name] = doc
    return doc


def getDocument(name):
    return _documents[name]


# ---------------------------------------------------------------- Part module

def makeBox(dx, dy, dz, pnt=None, direction=None):
    p = pnt or Vector()
    return Shape([_prim_box(p.x, p.y, p.z, dx, dy, dz)])


def makeCylinder(r, h, base=None, direction=None, angle=360):
    b = base or Vector()
    d = direction or Vector(0, 0, 1)
    return Shape([_prim_cyl((b.x, b.y, b.z), (d.x, d.y, d.z), r, h)])


class _Edge(object):
    def __init__(self, points):
        self.points = points


class LineSegment(object):
    def __init__(self, a, b):
        self.StartPoint, self.EndPoint = a, b

    def toShape(self):
        return _Edge([self.StartPoint, self.EndPoint])


class Arc(object):
    def __init__(self, a, mid, b):
        self.StartPoint, self.MidPoint, self.EndPoint = a, mid, b

    def toShape(self):
        return _Edge([self.StartPoint, self.MidPoint, self.EndPoint])


class _EdgeSet(object):
    def __init__(self, geoms):
        self.Edges = [g.toShape() for g in geoms]


def Shape_(geoms):
    return _EdgeSet(geoms)


class Wire(object):
    def __init__(self, edges):
        self.Edges = edges
        self.points = [p for e in edges for p in e.points]


class Face(object):
    def __init__(self, wire):
        self.wire = wire

    def extrude(self, v):
        pts = self.wire.points
        xs = [p.x for p in pts]
        zs = [p.z for p in pts]
        y = pts[0].y
        x0, x1, z0, z1 = min(xs), max(xs), min(zs), max(zs)
        corner_top = max(p.z for p in pts if abs(p.x - x0) < 1e-6 or abs(p.x - x1) < 1e-6)
        rise = z1 - corner_top
        # rectangle plus the area under the arc, close enough for a segment
        area = (x1 - x0) * (corner_top - z0) + (2.0 / 3.0) * (x1 - x0) * rise
        thickness = abs(v.x) + abs(v.y) + abs(v.z)
        prim = {"kind": "extrude",
                "bb": (x0, min(y, y + v.y), z0, x1, max(y, y + v.y), z1),
                "vol": area * thickness}
        return Shape([prim])


def export(objects, path):
    with open(path, "w") as fh:
        fh.write("ISO-10303-21;\n/* stub STEP written by tools/fakecad.py */\n")
        for o in objects:
            fh.write("/* %s */\n" % o.Label)
        fh.write("END-ISO-10303-21;\n")


def install():
    """Register the stub as the FreeCAD and Part modules."""
    app = types.ModuleType("FreeCAD")
    for name in ("Vector", "Rotation", "Placement", "BoundBox", "newDocument",
                 "getDocument", "GuiUp"):
        setattr(app, name, globals()[name])
    app.Console = types.SimpleNamespace(PrintMessage=lambda *a: None,
                                        PrintWarning=lambda *a: None)

    part = types.ModuleType("Part")
    part.makeBox = makeBox
    part.makeCylinder = makeCylinder
    part.LineSegment = LineSegment
    part.Arc = Arc
    part.Shape = Shape_
    part.Wire = Wire
    part.Face = Face
    part.export = export

    sys.modules["FreeCAD"] = app
    sys.modules["App"] = app
    sys.modules["Part"] = part
    return app, part
