"""Cutting list and hardware schedule, written from the same model."""

import csv
import os
import re
from collections import OrderedDict

import model as M

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")

# what the carpenter buys: nominal sections, sawn oversize and planed down
PLANING_ALLOWANCE = 4       # mm on the width and thickness
LENGTH_ALLOWANCE = 30       # mm on the length, for trimming


SUB_ORDER = ["Head end", "Foot end", "Side rails", "Deck", "Drawers"]


def generic_name(label):
    """'Drawer 1 end panel 2' -> 'Drawer end panel'; 'Head post (left)' -> 'Head post'."""
    name = label.split(" (")[0]
    name = re.sub(r"\bDrawer \d+\b", "Drawer", name)
    return re.sub(r"\s*\d+$", "", name).strip()


def rows():
    """One row per distinct part, grouped by sub-assembly, longest first."""
    groups = OrderedDict()
    for p in M.assembly():
        if p.material == M.HARDWARE:
            continue
        key = p.part
        if key not in groups:
            groups[key] = {"part": p, "qty": 0, "labels": []}
        groups[key]["qty"] += 1
        groups[key]["labels"].append(p.label)
    out = []
    for key, g in groups.items():
        p = g["part"]
        L, W, T = p.stock
        out.append({
            "id": key,
            "name": generic_name(p.label),
            "qty": g["qty"],
            "length": L,
            "width": W,
            "thickness": T,
            "material": p.material,
            "grain": p.grain,
            "sub_assembly": p.group if not p.group.startswith("Drawer") else "Drawers",
            "rough_length": L + LENGTH_ALLOWANCE,
            "rough_width": W + PLANING_ALLOWANCE,
            "rough_thickness": T + PLANING_ALLOWANCE,
            "note": p.note,
        })
    out.sort(key=lambda r: (SUB_ORDER.index(r["sub_assembly"]), -r["length"]))
    return out


def timber_volume(rs):
    """Finished volume in litres, and rough-sawn volume including allowances."""
    fin = sum(r["qty"] * r["length"] * r["width"] * r["thickness"] for r in rs
              if r["material"] != M.PLY)
    rough = sum(r["qty"] * r["rough_length"] * r["rough_width"] * r["rough_thickness"]
                for r in rs if r["material"] != M.PLY)
    ply = sum(r["qty"] * r["length"] * r["width"] for r in rs if r["material"] == M.PLY)
    return fin / 1e6, rough / 1e6, ply / 1e6


def write_csv(rs, path):
    fields = ["sub_assembly", "id", "name", "qty", "length", "width", "thickness",
              "material", "grain", "rough_length", "rough_width", "rough_thickness",
              "note"]
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        for r in rs:
            w.writerow({k: r[k] for k in fields})
    return path


def write_markdown(rs, path):
    fin, rough, ply = timber_volume(rs)
    lines = [
        "# Cutting list",
        "",
        f"Storage bed for a {M.MAT_W} x {M.MAT_L} mm mattress. "
        f"Overall {M.W_OUT} wide x {M.L_OUT} long x {M.HEAD_POST_H + M.ARCH_RISE} high.",
        "",
        "Sizes are **finished** sizes in millimetres. The rough columns add "
        f"{LENGTH_ALLOWANCE} mm on the length and {PLANING_ALLOWANCE} mm on the "
        "section for planing and trimming.",
        "",
    ]
    current = None
    for r in rs:
        if r["sub_assembly"] != current:
            current = r["sub_assembly"]
            lines += ["", f"## {current}", "",
                      "| Qty | Part | Length | Width | Thick | Rough L x W x T | Material |",
                      "| ---:| --- | ---:| ---:| ---:| --- | --- |"]
        lines.append(
            f"| {r['qty']} | {r['name']} | {r['length']:.0f} | {r['width']:.0f} | "
            f"{r['thickness']:.0f} | {r['rough_length']:.0f} x {r['rough_width']:.0f} x "
            f"{r['rough_thickness']:.0f} | {r['material']} |")

    lines += [
        "",
        "## Timber",
        "",
        f"- Finished solid timber: **{fin:.1f} litres** "
        f"({fin / 1000.0:.3f} m3, about {fin * 0.75:.0f} kg in oak)",
        f"- Rough sawn to buy: **{rough:.1f} litres** ({rough / 1000.0:.3f} m3) "
        "before waste and defects -- add a further 20 % when ordering",
        f"- Plywood: {ply:.2f} m2 of {M.PLY_T} mm for the drawer bottoms",
        "",
        "Glued-up panels (headboard, foot end) should be made from boards no wider "
        "than about 150 mm, alternating the growth rings, and left to settle before "
        "final thicknessing.",
        "",
        "## Hardware",
        "",
        "| Qty | Item | Specification |",
        "| ---:| --- | --- |",
    ]
    for qty, item, spec in M.hardware():
        lines.append(f"| {qty} | {item} | {spec} |")
    lines += ["", "## Notes", ""]
    for r in rs:
        if r["note"]:
            lines.append(f"- **{r['name']}** -- {r['note']}")
    lines.append("")
    with open(path, "w") as fh:
        fh.write("\n".join(lines))
    return path


def main():
    if not os.path.isdir(OUT):
        os.makedirs(OUT)
    rs = rows()
    return [write_markdown(rs, os.path.join(OUT, "cutlist.md")),
            write_csv(rs, os.path.join(OUT, "cutlist.csv"))]


if __name__ == "__main__":
    for f in main():
        print("wrote", os.path.relpath(f))
