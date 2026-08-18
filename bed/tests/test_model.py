"""Sanity checks on the bed geometry: nothing collides, the mattress fits,
the drawers run clear and every part fits the stock it is cut from."""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import model as m

TOL = 0.51      # mm; joints are modelled to the millimetre


def positives(solid):
    out = []
    if solid.body.dx and solid.body.dy and solid.body.dz:
        out.append(solid.body)
    for s in solid.adds:
        out.append(s.bbox() if isinstance(s, m.Cyl) else s)
    return out


def negatives(solid):
    return [s.bbox() if isinstance(s, m.Cyl) else s for s in solid.cuts]


def contained(inner, outer, tol=TOL):
    return (inner.x >= outer.x - tol and inner.x1 <= outer.x1 + tol
            and inner.y >= outer.y - tol and inner.y1 <= outer.y1 + tol
            and inner.z >= outer.z - tol and inner.z1 <= outer.z1 + tol)


def intersection(a, b):
    x, x1 = max(a.x, b.x), min(a.x1, b.x1)
    y, y1 = max(a.y, b.y), min(a.y1, b.y1)
    z, z1 = max(a.z, b.z), min(a.z1, b.z1)
    if x1 - x <= TOL or y1 - y <= TOL or z1 - z <= TOL:
        return None
    return m.Box(x, y, z, x1 - x, y1 - y, z1 - z)


class TestGeometry(unittest.TestCase):
    def setUp(self):
        self.parts = m.assembly()

    def test_no_two_parts_occupy_the_same_wood(self):
        """Where parts overlap it must be a tenon in its mortise, a panel in
        its groove or a drawer bottom in its housing -- never solid on solid."""
        clashes = []
        for i, a in enumerate(self.parts):
            for b in self.parts[i + 1:]:
                for pa in positives(a):
                    for pb in positives(b):
                        hit = intersection(pa, pb)
                        if hit is None:
                            continue
                        housed = any(contained(hit, c) for c in negatives(a) + negatives(b))
                        if not housed:
                            clashes.append(f"{a.label} vs {b.label} "
                                           f"({hit.volume / 1000.0:.1f} cm3)")
        self.assertEqual([], clashes, "parts clash:\n  " + "\n  ".join(clashes))

    def test_mattress_space_is_clear(self):
        mat = m.mattress().body
        for p in self.parts:
            for pos in positives(p):
                self.assertIsNone(intersection(mat, pos),
                                  f"{p.label} intrudes into the mattress space")

    def test_overall_size(self):
        xs = [b.x for p in self.parts for b in positives(p)]
        ys = [b.y for p in self.parts for b in positives(p)]
        x1 = [b.x1 for p in self.parts for b in positives(p)]
        y1 = [b.y1 for p in self.parts for b in positives(p)]
        self.assertEqual((min(xs), max(x1)), (0, m.W_OUT))
        self.assertEqual((min(ys), max(y1)), (0, m.L_OUT))
        top = max(p.envelope.z1 for p in self.parts)
        self.assertEqual(top, m.HEAD_POST_H + m.ARCH_RISE)

    def test_mattress_is_supported(self):
        """Slat gaps must stay under 70 mm or a foam mattress sags between them."""
        slats = sorted((p for p in self.parts if p.part == "slat"), key=lambda p: p.body.y)
        gaps = [b.body.y - a.body.y1 for a, b in zip(slats, slats[1:])]
        self.assertTrue(all(g <= 70 for g in gaps), f"widest slat gap {max(gaps)} mm")
        self.assertLessEqual(slats[0].body.y - m.FOOT_Y1, 70)
        self.assertLessEqual(m.HEAD_Y0 - slats[-1].body.y1, 70)
        for s in slats:      # bearing on both slat bearers
            self.assertGreaterEqual(m.RAIL_IN_L + m.CLEAT_W - s.body.x, 20)
            self.assertGreaterEqual(s.body.x1 - (m.RAIL_IN_R - m.CLEAT_W), 20)

    def test_drawers_run_clear(self):
        beam_x1 = m.BEAM_X0 + m.BEAM_W
        for p in self.parts:
            if p.group.startswith("Drawer"):
                for b in positives(p):
                    self.assertGreater(b.x, beam_x1,
                                       f"{p.label} fouls the centre beam")
                    self.assertLess(b.z1, m.RAIL_Z0,
                                    f"{p.label} fouls the side rail")
        # and the drawer pulls straight out of the opening
        self.assertLess(m.BOX_Z1, m.RAIL_Z0)
        self.assertLess(m.FRONT_Z1, m.RAIL_Z0)

    def test_parts_fit_their_stock(self):
        for p in self.parts:
            if p.material == m.HARDWARE:
                continue
            env = p.envelope
            got = sorted([env.dx, env.dy, env.dz], reverse=True)
            want = sorted(p.stock, reverse=True)
            for g, w in zip(got, want):
                self.assertLessEqual(g, w + TOL,
                                     f"{p.label}: {got} does not fit stock {want}")

    def test_bolts_land_in_the_tenons(self):
        for z in m.BOLT_Z:
            self.assertGreater(z, m.SIDE_TENON_Z0 + 10)
            self.assertLess(z, m.SIDE_TENON_Z1 - 10)

    def test_headboard_clears_the_side_rail_joint(self):
        """The end-rail tenons and the side-rail tenon share one post."""
        self.assertLess(m.SIDE_TENON_Z1, m.FOOT_TOP_RAIL_Z0 + m.TENON_SHOULDER)
        self.assertGreater(m.SIDE_TENON_Z0, m.BOT_RAIL_Z1 - m.TENON_SHOULDER)


if __name__ == "__main__":
    unittest.main(verbosity=2)
