"""The cutting list must account for every part, with stock big enough to cut it."""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import cutlist
import model as M


class TestCutlist(unittest.TestCase):
    def setUp(self):
        self.rows = cutlist.rows()
        self.parts = [p for p in M.assembly() if p.material != M.HARDWARE]

    def test_every_part_is_listed_once(self):
        ids = [r["id"] for r in self.rows]
        self.assertEqual(len(ids), len(set(ids)))
        self.assertEqual(set(ids), set(p.part for p in self.parts))

    def test_quantities_add_up(self):
        self.assertEqual(sum(r["qty"] for r in self.rows), len(self.parts))

    def test_rough_stock_is_bigger_than_finished(self):
        for r in self.rows:
            self.assertGreater(r["rough_length"], r["length"])
            self.assertGreater(r["rough_width"], r["width"])
            self.assertGreater(r["rough_thickness"], r["thickness"])

    def test_names_lose_their_instance_numbers(self):
        self.assertEqual(cutlist.generic_name("Drawer 2 end panel (head side)"),
                         "Drawer end panel")
        self.assertEqual(cutlist.generic_name("Slat 12"), "Slat")
        self.assertEqual(cutlist.generic_name("Head post (left)"), "Head post")

    def test_it_writes_both_formats(self):
        with tempfile.TemporaryDirectory() as tmp:
            md = cutlist.write_markdown(self.rows, os.path.join(tmp, "c.md"))
            csv_path = cutlist.write_csv(self.rows, os.path.join(tmp, "c.csv"))
            body = open(md).read()
            self.assertIn("Bed bolt", body)
            self.assertIn("Side rail", body)
            self.assertEqual(len(open(csv_path).read().strip().splitlines()),
                             len(self.rows) + 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
