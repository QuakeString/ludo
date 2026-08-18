"""Regenerate everything in out/ that does not need FreeCAD installed."""

import cutlist
import drawings


def main():
    written = cutlist.main() + drawings.all_drawings()
    for path in written:
        print("wrote", path)
    print("\nFor the 3D model, run this folder's freecad_bed.py inside FreeCAD:")
    print("    freecadcmd freecad_bed.py")
    return written


if __name__ == "__main__":
    main()
