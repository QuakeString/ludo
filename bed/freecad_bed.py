"""
Build the bed in FreeCAD.

    GUI:        Macro -> Macros... -> add this folder -> run freecad_bed.py
    Headless:   freecadcmd freecad_bed.py

Every part in model.py becomes one solid in a document tree grouped by
sub-assembly, and the whole thing is written to out/bed.FCStd and out/bed.step.
Nothing here is hand-modelled: change a number in model.py, run again.
"""

import os
import sys

import FreeCAD as App
import Part

HERE = os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else os.getcwd()
if HERE not in sys.path:
    sys.path.insert(0, HERE)

import model as M

SHOW_MATTRESS = False       # set True to check the fit of the mattress

COLOURS = {                 # r, g, b  (dark stained oak, like the photo)
    "Head end": (0.22, 0.16, 0.13),
    "Foot end": (0.22, 0.16, 0.13),
    "Side rails": (0.26, 0.19, 0.15),
    "Deck": (0.72, 0.60, 0.44),
    "Reference": (0.92, 0.92, 0.90),
}
DRAWER_COLOUR = (0.20, 0.15, 0.12)
HARDWARE_COLOUR = (0.35, 0.35, 0.38)

EPS = 0.2       # cutting tools run past the surface, so booleans stay clean


def _vec(x, y, z):
    return App.Vector(x, y, z)


def _box(b, grow=0.0):
    return Part.makeBox(b.dx + 2 * grow, b.dy + 2 * grow, b.dz + 2 * grow,
                        _vec(b.x - grow, b.y - grow, b.z - grow))


def _cylinder(c, grow=0.0):
    direction = {"x": _vec(1, 0, 0), "y": _vec(0, 1, 0), "z": _vec(0, 0, 1)}[c.axis]
    base = _vec(c.x, c.y, c.z) - direction * grow
    return Part.makeCylinder(c.r, c.h + 2 * grow, base, direction)


def _shape_of(prim, grow=0.0):
    if isinstance(prim, M.Cyl):
        return _cylinder(prim, grow)
    return _box(prim, grow)


def _arched(b, rise):
    """A rail whose top edge is an arc rising `rise` at the centre.

    Drawn as a face in the XZ plane and extruded through the thickness."""
    y = b.y
    x0, x1, xm = b.x, b.x1, b.x + b.dx / 2.0
    z0, z1 = b.z, b.z1
    corners = [_vec(x0, y, z0), _vec(x1, y, z0), _vec(x1, y, z1)]
    edges = [
        Part.LineSegment(corners[0], corners[1]),
        Part.LineSegment(corners[1], corners[2]),
        Part.Arc(_vec(x1, y, z1), _vec(xm, y, z1 + rise), _vec(x0, y, z1)),
        Part.LineSegment(_vec(x0, y, z1), corners[0]),
    ]
    wire = Part.Wire(Part.Shape(edges).Edges)
    return Part.Face(wire).extrude(_vec(0, b.dy, 0))


def build_solid(part):
    """One finished part: blank, plus tenons, less mortises, grooves and holes."""
    if part.arch:
        shape = _arched(part.body, part.arch)
    elif part.body.dx and part.body.dy and part.body.dz:
        shape = _box(part.body)
    else:
        shape = None
    for add in part.adds:
        piece = _shape_of(add)
        shape = piece if shape is None else shape.fuse(piece)
    for cut in part.cuts:
        shape = shape.cut(_shape_of(cut, EPS))
    return shape.removeSplitter() if hasattr(shape, "removeSplitter") else shape


def colour_for(part):
    if part.material == M.HARDWARE:
        return HARDWARE_COLOUR
    if part.group.startswith("Drawer"):
        return DRAWER_COLOUR
    return COLOURS.get(part.group, (0.6, 0.45, 0.3))


def build(doc=None):
    doc = doc or App.newDocument("Bed")
    parts = M.assembly()
    if SHOW_MATTRESS:
        parts.append(M.mattress())

    groups = {}
    objects = []
    for part in parts:
        if part.group not in groups:
            name = "".join(ch for ch in part.group if ch.isalnum())
            groups[part.group] = doc.addObject("App::DocumentObjectGroup", name)
            groups[part.group].Label = part.group
        obj = doc.addObject("Part::Feature", "".join(ch for ch in part.part if ch.isalnum()))
        obj.Label = part.label
        obj.Shape = build_solid(part)
        view = getattr(obj, "ViewObject", None)
        if view is not None:
            view.ShapeColor = colour_for(part)
        groups[part.group].addObject(obj)
        objects.append(obj)
    doc.recompute()
    return doc, objects


def export(doc, objects, out_dir=None):
    out_dir = out_dir or os.path.join(HERE, "out")
    if not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    fcstd = os.path.join(out_dir, "bed.FCStd")
    step = os.path.join(out_dir, "bed.step")
    doc.saveAs(fcstd)
    Part.export(objects, step)
    return fcstd, step


def main():
    doc, objects = build()
    fcstd, step = export(doc, objects)
    print("bed: %d parts, %.1f m of solid timber in %d pieces"
          % (len(objects), sum(p.stock[0] for p in M.assembly()
                               if p.material != M.HARDWARE) / 1000.0,
             len([p for p in M.assembly() if p.material != M.HARDWARE])))
    print("wrote", fcstd)
    print("wrote", step)
    return doc


if __name__ == "__main__":
    main()
