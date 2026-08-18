"""Run the FreeCAD macro against the API stub in tools/fakecad.py.

This proves the macro executes end to end and puts every part where model.py
says it goes.  Volumes from the stub are approximate; the placement is not."""

import os
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)
sys.path.insert(0, os.path.join(ROOT, "tools"))

import fakecad

fakecad.install()

import model as M
import freecad_bed as FB

TOL = 0.6


class TestMacro(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.doc, cls.objects = FB.build()
        cls.parts = M.assembly()

    def test_every_part_is_built(self):
        self.assertEqual(len(self.parts), len(self.objects))
        self.assertEqual([p.label for p in self.parts], [o.Label for o in self.objects])
        self.assertEqual(len(set(o.Label for o in self.objects)), len(self.objects))

    def test_parts_land_where_the_model_says(self):
        for part, obj in zip(self.parts, self.objects):
            bb = obj.Shape.BoundBox
            env = part.envelope
            for got, want, axis in ((bb.XMin, env.x, "x"), (bb.YMin, env.y, "y"),
                                    (bb.ZMin, env.z, "z"), (bb.XMax, env.x1, "x1"),
                                    (bb.YMax, env.y1, "y1"), (bb.ZMax, env.z1, "z1")):
                self.assertAlmostEqual(got, want, delta=TOL,
                                       msg=f"{part.label}: {axis} {got} != {want}")

    def test_joints_actually_remove_wood(self):
        """A mortised part must weigh less than its blank."""
        for part, obj in zip(self.parts, self.objects):
            if not part.cuts:
                continue
            blank = part.envelope.volume
            self.assertLess(obj.Shape.Volume, blank,
                            f"{part.label}: cuts removed nothing")
            self.assertGreater(obj.Shape.Volume, 0.4 * blank,
                               f"{part.label}: cuts removed far too much")

    def test_the_bed_is_the_size_it_should_be(self):
        boxes = [o.Shape.BoundBox for o in self.objects]
        self.assertAlmostEqual(min(b.XMin for b in boxes), 0, delta=TOL)
        self.assertAlmostEqual(max(b.XMax for b in boxes), M.W_OUT, delta=TOL)
        self.assertAlmostEqual(min(b.YMin for b in boxes), 0, delta=TOL)
        self.assertAlmostEqual(max(b.YMax for b in boxes), M.L_OUT, delta=TOL)
        self.assertAlmostEqual(max(b.ZMax for b in boxes),
                               M.HEAD_POST_H + M.ARCH_RISE, delta=TOL)

    def test_arched_rail_is_curved_not_square(self):
        rail = [o for o in self.objects if o.Label.startswith("Headboard arched")][0]
        blank = M.END_RAIL_L * M.HEAD_TOP_RAIL_H * M.END_T
        self.assertLess(rail.Shape.Volume, blank)

    def test_document_is_grouped_by_sub_assembly(self):
        groups = [o for o in self.doc.Objects if o.TypeId == "App::DocumentObjectGroup"]
        self.assertEqual(sorted(g.Label for g in groups),
                         ["Deck", "Drawer 1", "Drawer 2", "Foot end", "Head end",
                          "Side rails"])
        self.assertEqual(sum(len(g.Group) for g in groups), len(self.objects))

    def test_export_writes_both_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            fcstd, step = FB.export(self.doc, self.objects, tmp)
            self.assertTrue(os.path.getsize(fcstd) > 0)
            self.assertTrue(os.path.getsize(step) > 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
