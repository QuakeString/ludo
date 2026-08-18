"""
Solid-wood storage bed -- parametric geometry model.

A double bed (140 x 200 cm mattress) in solid timber: two frame-and-panel ends
joined to two side rails with mortise-and-tenon joints drawn up by bed bolts,
a slatted deck on a central floor-standing beam, and two large drawers on
castors under one long side.

Everything below is plain Python with no dependencies, so the same numbers feed
the FreeCAD macro, the cut list and the shop drawings.

Units are millimetres throughout.

Axes
    X   across the bed.  0 = outside of the left rail, +X toward the drawers.
    Y   along the bed.   0 = outside of the foot end, +Y toward the head end.
    Z   up from the floor.
"""

from dataclasses import dataclass, field
from typing import List, Optional, Tuple, Union

# --------------------------------------------------------------------------
# Parameters -- change these and every downstream drawing follows
# --------------------------------------------------------------------------

MAT_W, MAT_L, MAT_H = 1400, 2000, 200   # mattress width, length, thickness
FIT = 5                                 # gap between mattress and frame, each side

POST_X, POST_Y = 40, 70                 # corner post section (across, along)
RAIL_T, RAIL_H = 32, 160                # side rail thickness and depth
DECK_Z = 400                            # top face of the slats above the floor

END_T = 32                              # thickness of the head/foot end rails
PANEL_T = 18                            # thickness of the floating panels
GROOVE_D = 10                           # depth of the panel grooves
PLY_T = 12                              # drawer bottoms

FOOT_H = 420                            # top of the foot end above the floor
HEAD_POST_H = 880                       # top of the head posts above the floor
ARCH_RISE = 80                          # how much the headboard curve rises at the centre

BOT_RAIL_H, BOT_RAIL_Z = 90, 30         # end-assembly bottom rail: depth, floor clearance
FOOT_TOP_RAIL_H = 80                    # foot end top rail depth
HEAD_TOP_RAIL_H = 200                   # headboard arched rail: full blank depth

SLAT_T, SLAT_W, SLAT_N = 20, 70, 15     # slat thickness, width, count
CLEAT_W, CLEAT_H = 25, 50               # slat-bearer section (proud of rail, deep)

BEAM_W, BEAM_H = 45, 95                 # centre beam section
BEAM_LEGS = 3                           # floor legs under the centre beam

TENON_T = 20                            # tenon thickness, all joints
SIDE_TENON_L, SIDE_MORTISE_D = 40, 45   # side rail into post
END_TENON_L, END_MORTISE_D = 30, 32     # end rails into post
TENON_SHOULDER = 10                     # shoulder on the long edges of a tenon

BOLT_D, BOLT_CB_D, BOLT_CB_DEPTH = 9, 20, 10    # bed bolt, counterbore
NUT_D = 12                              # cross-drilling for the barrel nut
NUT_SETBACK = 30                        # barrel nut, past the tenon shoulder

N_DRAWERS = 2
DRAWER_GAP = 4                          # reveal around and between drawer fronts
DRAWER_FRONT_H = 225
DRAWER_FLOOR_GAP = 8                    # under the drawer front
CASTOR_H, CASTOR_D = 50, 50
DRAWER_BOX_H = 175
DRAWER_BOX_DEPTH = 620                  # how far the drawer reaches into the bed
DRAWER_SIDE_T = 18
DRAWER_BOTTOM_GROOVE = 12               # bottom groove, up from the box underside
DRAWER_BOTTOM_HOUSING = 8               # depth of that groove
PULL_L, PULL_H, PULL_INSET = 240, 30, 40    # routed finger pull in each front

# --------------------------------------------------------------------------
# Derived sizes
# --------------------------------------------------------------------------

OPEN_W = MAT_W + 2 * FIT                # clear width between the posts
OPEN_L = MAT_L + 2 * FIT                # clear length between the posts
W_OUT = OPEN_W + 2 * POST_X             # overall width of the bed
L_OUT = OPEN_L + 2 * POST_Y             # overall length of the bed

RAIL_Z0 = DECK_Z - RAIL_H               # underside of the side rails
SLAT_Z0 = DECK_Z - SLAT_T
CLEAT_Z1 = SLAT_Z0
CLEAT_Z0 = CLEAT_Z1 - CLEAT_H

POST_IN_L = POST_X                      # inner face of the left posts
POST_IN_R = W_OUT - POST_X              # inner face of the right posts
RAIL_INSET = (POST_X - RAIL_T) / 2.0    # rails centred on the posts, 4 mm shadow line
RAIL_X_L = RAIL_INSET                   # outer face of the left side rail
RAIL_X_R = W_OUT - RAIL_INSET - RAIL_T
RAIL_IN_L = RAIL_X_L + RAIL_T           # inner face of the left side rail
RAIL_IN_R = RAIL_X_R

FOOT_Y1 = POST_Y                        # inner face of the foot posts
HEAD_Y0 = L_OUT - POST_Y                # inner face of the head posts

END_Y0 = (POST_Y - END_T) / 2.0         # end rails/panels centred in the post depth
END_Y1 = END_Y0 + END_T
PANEL_Y0 = (POST_Y - PANEL_T) / 2.0
PANEL_Y1 = PANEL_Y0 + PANEL_T

BOT_RAIL_Z1 = BOT_RAIL_Z + BOT_RAIL_H
FOOT_TOP_RAIL_Z0 = FOOT_H - FOOT_TOP_RAIL_H
HEAD_TOP_RAIL_Z0 = HEAD_POST_H - (HEAD_TOP_RAIL_H - ARCH_RISE)

PANEL_W = OPEN_W + 2 * GROOVE_D         # panels reach into the post grooves
FOOT_PANEL_Z0 = BOT_RAIL_Z1 - GROOVE_D
FOOT_PANEL_Z1 = FOOT_TOP_RAIL_Z0 + GROOVE_D
HEAD_PANEL_Z0 = FOOT_PANEL_Z0
HEAD_PANEL_Z1 = HEAD_TOP_RAIL_Z0 + GROOVE_D

END_RAIL_L = OPEN_W + 2 * END_TENON_L   # blank length of every end rail

SIDE_RAIL_BODY_L = OPEN_L               # shoulder to shoulder
SIDE_RAIL_L = OPEN_L + 2 * SIDE_TENON_L

# the side-rail tenon must clear the end-rail tenons inside the same post
SIDE_TENON_Z0 = RAIL_Z0 + 15
SIDE_TENON_Z1 = FOOT_TOP_RAIL_Z0 + TENON_SHOULDER - 5
BOLT_Z = (SIDE_TENON_Z0 + 20, SIDE_TENON_Z1 - 20)

SLAT_L = (RAIL_IN_R - RAIL_IN_L) - 4    # 2 mm play each end
SLAT_X0 = (W_OUT - SLAT_L) / 2.0
SLAT_PITCH = OPEN_L / float(SLAT_N)
SLAT_GAP = SLAT_PITCH - SLAT_W

BEAM_X0 = (W_OUT - BEAM_W) / 2.0
BEAM_Z1 = SLAT_Z0
BEAM_Z0 = BEAM_Z1 - BEAM_H

DRAWER_OPEN_H = RAIL_Z0                 # floor to the underside of the side rail
FRONT_L = (OPEN_L - (N_DRAWERS + 1) * DRAWER_GAP) / float(N_DRAWERS)
FRONT_X1 = RAIL_X_R + RAIL_T            # fronts finish flush with the side rail
FRONT_X0 = FRONT_X1 - PANEL_T
FRONT_Z0 = DRAWER_FLOOR_GAP
FRONT_Z1 = FRONT_Z0 + DRAWER_FRONT_H

BOX_L = FRONT_L - 40                    # drawer box, along the bed
BOX_X1 = FRONT_X0
BOX_X0 = BOX_X1 - DRAWER_BOX_DEPTH
BOX_Z0 = CASTOR_H
BOX_Z1 = BOX_Z0 + DRAWER_BOX_H
BOX_INNER_X0 = BOX_X0 + DRAWER_SIDE_T
BOX_INNER_X1 = BOX_X1 - DRAWER_SIDE_T
BOTTOM_L = BOX_L - 2 * DRAWER_SIDE_T + 2 * DRAWER_BOTTOM_HOUSING
BOTTOM_D = DRAWER_BOX_DEPTH - 2 * DRAWER_SIDE_T + 2 * DRAWER_BOTTOM_HOUSING
BOTTOM_Z0 = BOX_Z0 + DRAWER_BOTTOM_GROOVE

MATTRESS_X0 = (W_OUT - MAT_W) / 2.0
MATTRESS_Y0 = (L_OUT - MAT_L) / 2.0

# --------------------------------------------------------------------------
# Geometry primitives
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Box:
    """An axis-aligned box given by its minimum corner and its three sizes."""

    x: float
    y: float
    z: float
    dx: float
    dy: float
    dz: float
    kind: str = "solid"     # solid | mortise | groove | rebate | hole | slot | counterbore

    @property
    def x1(self) -> float:
        return self.x + self.dx

    @property
    def y1(self) -> float:
        return self.y + self.dy

    @property
    def z1(self) -> float:
        return self.z + self.dz

    @property
    def volume(self) -> float:
        return self.dx * self.dy * self.dz

    def moved(self, dx: float = 0.0, dy: float = 0.0, dz: float = 0.0) -> "Box":
        return Box(self.x + dx, self.y + dy, self.z + dz, self.dx, self.dy, self.dz, self.kind)

    def overlap(self, other: "Box") -> float:
        """Volume shared with another box; 0.0 when they only touch."""
        ox = min(self.x1, other.x1) - max(self.x, other.x)
        oy = min(self.y1, other.y1) - max(self.y, other.y)
        oz = min(self.z1, other.z1) - max(self.z, other.z)
        if ox <= 0 or oy <= 0 or oz <= 0:
            return 0.0
        return ox * oy * oz


@dataclass(frozen=True)
class Cyl:
    """A cylinder given by the centre of its base face and its axis."""

    x: float
    y: float
    z: float
    r: float
    h: float
    axis: str = "z"
    kind: str = "solid"

    def bbox(self) -> Box:
        if self.axis == "z":
            return Box(self.x - self.r, self.y - self.r, self.z, 2 * self.r, 2 * self.r, self.h, self.kind)
        if self.axis == "y":
            return Box(self.x - self.r, self.y, self.z - self.r, 2 * self.r, self.h, 2 * self.r, self.kind)
        return Box(self.x, self.y - self.r, self.z - self.r, self.h, 2 * self.r, 2 * self.r, self.kind)


Shape = Union[Box, Cyl]


@dataclass
class Solid:
    """One physical part, positioned in the assembled bed."""

    part: str                       # id shared by identical parts
    label: str                      # what this instance is called
    group: str                      # sub-assembly it belongs to
    body: Box                       # main blank, in place
    stock: Tuple[float, float, float]   # length, width, thickness to buy
    material: str = "solid oak"
    adds: List[Shape] = field(default_factory=list)     # tenons and other additions
    cuts: List[Shape] = field(default_factory=list)     # mortises, grooves, holes
    arch: float = 0.0               # rise of an arched top edge, 0 = straight
    grain: str = "along length"
    note: str = ""

    @property
    def envelope(self) -> Box:
        xs = [self.body.x] + [s.bbox().x if isinstance(s, Cyl) else s.x for s in self.adds]
        ys = [self.body.y] + [s.bbox().y if isinstance(s, Cyl) else s.y for s in self.adds]
        zs = [self.body.z] + [s.bbox().z if isinstance(s, Cyl) else s.z for s in self.adds]
        xs1 = [self.body.x1] + [(s.bbox() if isinstance(s, Cyl) else s).x1 for s in self.adds]
        ys1 = [self.body.y1] + [(s.bbox() if isinstance(s, Cyl) else s).y1 for s in self.adds]
        zs1 = [self.body.z1] + [(s.bbox() if isinstance(s, Cyl) else s).z1 for s in self.adds]
        z1 = max(zs1) + self.arch
        return Box(min(xs), min(ys), min(zs), max(xs1) - min(xs), max(ys1) - min(ys), z1 - min(zs))


# --------------------------------------------------------------------------
# The parts
# --------------------------------------------------------------------------

OAK = "solid oak"
PLY = "birch plywood"
HARDWARE = "hardware"


def _post(x0: float, head: bool) -> Solid:
    """A corner post, mortised for one side rail and two end rails."""
    y0 = HEAD_Y0 if head else 0.0
    height = HEAD_POST_H if head else FOOT_H
    left = x0 < W_OUT / 2.0
    x_in = x0 + POST_X if left else x0          # face the panel looks at
    y_in = y0 if head else POST_Y               # face the side rail meets
    y_out = y0 + POST_Y if head else 0.0

    # side rail mortise, cut into the inner end of the post
    side_m = Box(x0 + (POST_X - TENON_T) / 2.0,
                 y_in if head else y_in - SIDE_MORTISE_D,
                 SIDE_TENON_Z0, TENON_T, SIDE_MORTISE_D,
                 SIDE_TENON_Z1 - SIDE_TENON_Z0, "mortise")

    # end rail mortises, cut into the inner face of the post
    def end_mortise(z0: float, z1: float) -> Box:
        return Box(x_in if not left else x_in - END_MORTISE_D,
                   y0 + END_Y0 + (END_T - TENON_T) / 2.0, z0,
                   END_MORTISE_D, TENON_T, z1 - z0, "mortise")

    top_rail_z0 = HEAD_TOP_RAIL_Z0 if head else FOOT_TOP_RAIL_Z0
    cuts: List[Shape] = [
        side_m,
        end_mortise(BOT_RAIL_Z + TENON_SHOULDER, BOT_RAIL_Z1 - TENON_SHOULDER),
        end_mortise(top_rail_z0 + TENON_SHOULDER, height - TENON_SHOULDER),
        # panel groove
        Box(x_in - GROOVE_D if left else x_in, y0 + PANEL_Y0,
            FOOT_PANEL_Z0, GROOVE_D, PANEL_T,
            (HEAD_PANEL_Z1 if head else FOOT_PANEL_Z1) - FOOT_PANEL_Z0, "groove"),
    ]
    for bz in BOLT_Z:
        cuts.append(Cyl(x0 + POST_X / 2.0, y0, bz, BOLT_D / 2.0, POST_Y, "y", "hole"))
        cuts.append(Cyl(x0 + POST_X / 2.0,
                        y_out - BOLT_CB_DEPTH if head else 0.0, bz,
                        BOLT_CB_D / 2.0, BOLT_CB_DEPTH, "y", "counterbore"))

    side = "right" if not left else "left"
    end = "head" if head else "foot"
    return Solid(part=f"{end}-post", label=f"{end.capitalize()} post ({side})",
                 group=f"{end.capitalize()} end",
                 body=Box(x0, y0, 0, POST_X, POST_Y, height),
                 stock=(height, POST_Y, POST_X), material=OAK, cuts=cuts,
                 note="mortise before shaping; keep the bolt counterbore on the outside face")


def _end_rail(part: str, label: str, head: bool, z0: float, h: float,
              groove_on_top: bool, arch: float = 0.0) -> Solid:
    """A rail spanning between the two posts of one end assembly."""
    y0 = (HEAD_Y0 if head else 0.0) + END_Y0
    body = Box(POST_X, y0, z0, OPEN_W, END_T, h)
    ty = y0 + (END_T - TENON_T) / 2.0
    tz0, tz1 = z0 + TENON_SHOULDER, z0 + h - TENON_SHOULDER
    adds: List[Shape] = [
        Box(POST_X - END_TENON_L, ty, tz0, END_TENON_L, TENON_T, tz1 - tz0),
        Box(POST_IN_R, ty, tz0, END_TENON_L, TENON_T, tz1 - tz0),
    ]
    gz = z0 + h - GROOVE_D if groove_on_top else z0
    cuts: List[Shape] = [Box(POST_X, PANEL_Y0 + (HEAD_Y0 if head else 0.0), gz,
                             OPEN_W, PANEL_T, GROOVE_D, "groove")]
    return Solid(part=part, label=label, group=("Head end" if head else "Foot end"),
                 body=body, stock=(END_RAIL_L, h + arch, END_T), material=OAK,
                 adds=adds, cuts=cuts, arch=arch)


def _panel(part: str, label: str, head: bool, z0: float, z1: float) -> Solid:
    y0 = PANEL_Y0 + (HEAD_Y0 if head else 0.0)
    return Solid(part=part, label=label, group=("Head end" if head else "Foot end"),
                 body=Box(POST_X - GROOVE_D, y0, z0, PANEL_W, PANEL_T, z1 - z0),
                 stock=(PANEL_W, z1 - z0, PANEL_T), material=OAK, grain="across width",
                 note="glued up from narrower boards; leave 3 mm play in the grooves "
                      "top and bottom and do not glue it in")


def _side_rail(x0: float) -> Solid:
    left = x0 < W_OUT / 2.0
    tx = x0 + (RAIL_T - TENON_T) / 2.0
    tz0, tz1 = SIDE_TENON_Z0, SIDE_TENON_Z1
    adds: List[Shape] = [
        Box(tx, FOOT_Y1 - SIDE_TENON_L, tz0, TENON_T, SIDE_TENON_L, tz1 - tz0),
        Box(tx, HEAD_Y0, tz0, TENON_T, SIDE_TENON_L, tz1 - tz0),
    ]
    cuts: List[Shape] = []
    for bz in BOLT_Z:
        # clearance hole down the tenon and the barrel-nut cross drilling
        cuts.append(Cyl(x0 + RAIL_T / 2.0, FOOT_Y1 - SIDE_TENON_L, bz, BOLT_D / 2.0,
                        SIDE_TENON_L + NUT_SETBACK + NUT_D / 2.0, "y", "hole"))
        cuts.append(Cyl(x0 + RAIL_T / 2.0,
                        HEAD_Y0 + SIDE_TENON_L - (SIDE_TENON_L + NUT_SETBACK + NUT_D / 2.0),
                        bz, BOLT_D / 2.0, SIDE_TENON_L + NUT_SETBACK + NUT_D / 2.0, "y", "hole"))
        cuts.append(Cyl(x0, FOOT_Y1 + NUT_SETBACK, bz, NUT_D / 2.0, RAIL_T, "x", "hole"))
        cuts.append(Cyl(x0, HEAD_Y0 - NUT_SETBACK, bz, NUT_D / 2.0, RAIL_T, "x", "hole"))
    return Solid(part="side-rail", label=f"Side rail ({'left' if left else 'right'})",
                 group="Side rails", body=Box(x0, FOOT_Y1, RAIL_Z0, RAIL_T, OPEN_L, RAIL_H),
                 stock=(SIDE_RAIL_L, RAIL_H, RAIL_T), material=OAK, adds=adds, cuts=cuts,
                 note="bed bolts pull the joint up; the tenon only locates it")


def _drawer(i: int) -> List[Solid]:
    """One drawer: front, four box sides, a plywood bottom and four castors."""
    fy0 = FOOT_Y1 + DRAWER_GAP + i * (FRONT_L + DRAWER_GAP)
    by0 = fy0 + (FRONT_L - BOX_L) / 2.0
    n = i + 1
    pull = Box(FRONT_X0, fy0 + (FRONT_L - PULL_L) / 2.0,
               FRONT_Z1 - PULL_INSET - PULL_H, PANEL_T, PULL_L, PULL_H, "slot")
    front = Solid("drawer-front", f"Drawer front {n}", f"Drawer {n}",
                  Box(FRONT_X0, fy0, FRONT_Z0, PANEL_T, FRONT_L, DRAWER_FRONT_H),
                  (FRONT_L, DRAWER_FRONT_H, PANEL_T), OAK, cuts=[pull],
                  grain="across width",
                  note="routed finger pull, radiused; screwed to the box from inside")

    def groove(x: float, y: float, z: float, dx: float, dy: float) -> Box:
        return Box(x, y, z, dx, dy, PLY_T, "groove")

    ends = []
    for k, y in enumerate((by0, by0 + BOX_L - DRAWER_SIDE_T)):
        ends.append(Solid("drawer-end",
                          f"Drawer {n} end panel ({'foot' if k == 0 else 'head'} side)",
                          f"Drawer {n}",
                          Box(BOX_X0, y, BOX_Z0, DRAWER_BOX_DEPTH, DRAWER_SIDE_T, DRAWER_BOX_H),
                          (DRAWER_BOX_DEPTH, DRAWER_BOX_H, DRAWER_SIDE_T), OAK,
                          cuts=[groove(BOX_X0 + DRAWER_SIDE_T - DRAWER_BOTTOM_HOUSING,
                                       y if k else y + DRAWER_SIDE_T - DRAWER_BOTTOM_HOUSING,
                                       BOTTOM_Z0, BOTTOM_D, DRAWER_BOTTOM_HOUSING)]))
    longs = []
    for k, x in enumerate((BOX_X0, BOX_INNER_X1)):
        longs.append(Solid("drawer-long",
                           f"Drawer {n} long side ({'back' if k == 0 else 'front'})",
                           f"Drawer {n}",
                           Box(x, by0 + DRAWER_SIDE_T, BOX_Z0, DRAWER_SIDE_T,
                               BOX_L - 2 * DRAWER_SIDE_T, DRAWER_BOX_H),
                           (BOX_L - 2 * DRAWER_SIDE_T, DRAWER_BOX_H, DRAWER_SIDE_T), OAK,
                           cuts=[groove(x if k else x + DRAWER_SIDE_T - DRAWER_BOTTOM_HOUSING,
                                        by0 + DRAWER_SIDE_T - DRAWER_BOTTOM_HOUSING,
                                        BOTTOM_Z0, DRAWER_BOTTOM_HOUSING, BOTTOM_L)]))
    bottom = Solid("drawer-bottom", f"Drawer {n} bottom", f"Drawer {n}",
                   Box(BOX_X0 + DRAWER_SIDE_T - DRAWER_BOTTOM_HOUSING,
                       by0 + DRAWER_SIDE_T - DRAWER_BOTTOM_HOUSING,
                       BOTTOM_Z0, BOTTOM_D, BOTTOM_L, PLY_T),
                   (BOTTOM_L, BOTTOM_D, PLY_T), PLY, grain="n/a",
                   note="slides into the grooves as the box goes together")
    castors = []
    for j, (cx, cy) in enumerate((
            (BOX_X0 + 80, by0 + 80), (BOX_X1 - 80, by0 + 80),
            (BOX_X0 + 80, by0 + BOX_L - 80), (BOX_X1 - 80, by0 + BOX_L - 80))):
        castors.append(Solid("castor", f"Drawer {n} castor {j + 1}", f"Drawer {n}",
                             Cyl(cx, cy, 0, CASTOR_D / 2.0, CASTOR_H).bbox(),
                             (CASTOR_D, CASTOR_D, CASTOR_H), HARDWARE, grain="n/a"))
        castors[-1].adds = [Cyl(cx, cy, 0, CASTOR_D / 2.0, CASTOR_H)]
        castors[-1].body = Box(cx, cy, 0, 0, 0, 0)     # the cylinder is the whole part
    return [front] + ends + longs + [bottom] + castors


def assembly() -> List[Solid]:
    """Every part of the bed, positioned as built."""
    parts: List[Solid] = []

    # head and foot ends
    for head in (False, True):
        parts += [_post(0, head), _post(POST_IN_R, head)]
        end = "head" if head else "foot"
        parts.append(_end_rail(f"{end}-bottom-rail", f"{end.capitalize()} end bottom rail",
                               head, BOT_RAIL_Z, BOT_RAIL_H, groove_on_top=True))
    parts.append(_end_rail("foot-top-rail", "Foot end top rail", False,
                           FOOT_TOP_RAIL_Z0, FOOT_TOP_RAIL_H, groove_on_top=False))
    parts.append(_end_rail("head-top-rail", "Headboard arched top rail", True,
                           HEAD_TOP_RAIL_Z0, HEAD_POST_H - HEAD_TOP_RAIL_Z0,
                           groove_on_top=False, arch=ARCH_RISE))
    parts.append(_panel("foot-panel", "Foot end panel", False, FOOT_PANEL_Z0, FOOT_PANEL_Z1))
    parts.append(_panel("head-panel", "Headboard panel", True, HEAD_PANEL_Z0, HEAD_PANEL_Z1))

    # side rails, slat bearers, slats
    parts += [_side_rail(RAIL_X_L), _side_rail(RAIL_X_R)]
    for x0, side in ((RAIL_IN_L, "left"), (RAIL_IN_R - CLEAT_W, "right")):
        parts.append(Solid("slat-bearer", f"Slat bearer ({side})", "Side rails",
                           Box(x0, FOOT_Y1, CLEAT_Z0, CLEAT_W, OPEN_L, CLEAT_H),
                           (OPEN_L, CLEAT_H, CLEAT_W), OAK,
                           note="glued and screwed to the inside of the rail, "
                                "flush with nothing -- work off the top edge"))
    for i in range(SLAT_N):
        y = FOOT_Y1 + i * SLAT_PITCH + (SLAT_PITCH - SLAT_W) / 2.0
        parts.append(Solid("slat", f"Slat {i + 1}", "Deck",
                           Box(SLAT_X0, y, SLAT_Z0, SLAT_L, SLAT_W, SLAT_T),
                           (SLAT_L, SLAT_W, SLAT_T), OAK))

    # centre beam and its legs
    parts.append(Solid("centre-beam", "Centre beam", "Deck",
                       Box(BEAM_X0, FOOT_Y1, BEAM_Z0, BEAM_W, OPEN_L, BEAM_H),
                       (OPEN_L, BEAM_H, BEAM_W), OAK,
                       note="carries the middle of every slat; screw each slat to it"))
    for i in range(BEAM_LEGS):
        y = FOOT_Y1 + (i + 0.5) * OPEN_L / BEAM_LEGS - BEAM_W / 2.0
        parts.append(Solid("beam-leg", f"Centre beam leg {i + 1}", "Deck",
                           Box(BEAM_X0, y, 0, BEAM_W, BEAM_W, BEAM_Z0),
                           (BEAM_Z0, BEAM_W, BEAM_W), OAK))

    for i in range(N_DRAWERS):
        parts += _drawer(i)
    return parts


def mattress() -> Solid:
    return Solid("mattress", "Mattress (reference only)", "Reference",
                 Box(MATTRESS_X0, MATTRESS_Y0, DECK_Z, MAT_W, MAT_L, MAT_H),
                 (MAT_L, MAT_W, MAT_H), "reference", grain="n/a")


def hardware() -> List[Tuple[int, str, str]]:
    return [
        (8, "Bed bolt", f"M8 x 140 hex head, with washer -- 2 per rail-to-post joint"),
        (8, "Barrel nut (cross dowel)", f"M8, {NUT_D} mm dia x 25 long"),
        (8, "Bolt cap", f"{BOLT_CB_D} mm dia wooden plug or steel cover"),
        (8, "Castor", f"{CASTOR_D} mm twin-wheel, plate fixing, {CASTOR_H} mm overall"),
        (60, "Screw", "5.0 x 60 -- slat bearers into the side rails, every 200 mm"),
        (45, "Screw", "4.0 x 40 -- slats to the bearers and to the centre beam"),
        (16, "Screw", "4.0 x 30 -- drawer fronts to the boxes, from inside"),
        (1, "Wood glue", "PVA -- every joint except the floating panels"),
    ]
