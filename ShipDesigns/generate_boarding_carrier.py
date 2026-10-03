#!/usr/bin/env python3
"""Generates BoardingCarrier.xml, an Avorion ship design for boarding stations.

Copy the XML into %APPDATA%/Avorion/ships/ and load it in build mode
(Ship Designs tab). Edit the sizes below and re-run to tweak the design:
    python3 generate_boarding_carrier.py

Coordinates are in build-mode units: +Z is forward, +Y is up, X is width.
"""

import os
from collections import defaultdict

# Materials (block attribute "material")
IRON, TITANIUM, NAONITE, TRINIUM, XANION = 0, 1, 2, 3, 4
MATERIAL_NAMES = {0: "Iron", 1: "Titanium", 2: "Naonite", 3: "Trinium", 4: "Xanion"}

# Ship XML block indices (block attribute "index")
HULL = 1
ENGINE = 3
CARGO = 5
QUARTERS = 6
THRUSTER = 7
ARMOR = 8
HANGAR = 10
GYRO = 14
INERTIA_DAMPENER = 15
ASSEMBLY = 17
SHIELD = 50
ENERGY_CONTAINER = 51
GENERATOR = 52
INTEGRITY_FIELD = 53
COMPUTER_CORE = 54
HYPERSPACE_CORE = 55
TRANSPORTER = 56
ACADEMY = 57
CLONING_PODS = 58

BLOCK_NAMES = {
    HULL: "Hull", ENGINE: "Engine", CARGO: "Cargo Bay", QUARTERS: "Crew Quarters",
    THRUSTER: "Thruster", ARMOR: "Armor", HANGAR: "Hangar", GYRO: "Gyro",
    INERTIA_DAMPENER: "Inertia Dampener", ASSEMBLY: "Assembly (fighter production)",
    SHIELD: "Shield Generator", GENERATOR: "Generator", INTEGRITY_FIELD: "Integrity Field",
    COMPUTER_CORE: "Computer Core", HYPERSPACE_CORE: "Hyperspace Core", TRANSPORTER: "Transporter",
    ENERGY_CONTAINER: "Energy Container",
    ACADEMY: "Academy", CLONING_PODS: "Cloning Pods",
}

# Colors (ARGB)
GREY = "ff7f8c99"
DARK = "ff3c4650"
ACCENT = "ffd08a2c"
SYSTEM = "ff5aa0c8"

blocks = []  # (lower, upper, index, material, color)


def box(x0, x1, y0, y1, z0, z1, index, material=TRINIUM, color=SYSTEM):
    blocks.append(((x0, y0, z0), (x1, y1, z1), index, material, color))


def mirrored(x0, x1, y0, y1, z0, z1, index, material=TRINIUM, color=SYSTEM):
    """Adds a block and its mirror on the other side of X = 0 (x0, x1 > 0)."""
    box(x0, x1, y0, y1, z0, z1, index, material, color)
    box(-x1, -x0, y0, y1, z0, z1, index, material, color)


# --- Interior: 12 wide (x -6..6), 6 high (y -3..3), back to front along z ---

# Power: Trinium generators on the sides, a Xanion generator in the middle
mirrored(2, 6, -3, 3, -18, -14, GENERATOR)
box(-2, 2, -3, 3, -18, -14, GENERATOR, XANION)

# Defense systems
box(-6, 0, -3, 3, -14, -12, SHIELD)
box(0, 6, -3, 3, -14, -12, INTEGRITY_FIELD)

# Jump drive + processing power (system upgrade slots)
box(-6, 0, -3, 3, -12, -10, HYPERSPACE_CORE)
box(0, 6, -3, 3, -12, -10, COMPUTER_CORE, XANION)

# Fighters: assembly below, hangar above
box(-6, 6, -3, 0, -10, 0, ASSEMBLY)
box(-6, 6, 0, 3, -10, 0, HANGAR)

# Crew production: cloning pods below, academy above
box(-6, 6, -3, 0, 0, 8, CLONING_PODS)
box(-6, 6, 0, 3, 0, 8, ACADEMY)

# Living space for boarders and the crew running everything else
box(-6, 6, -3, 3, 8, 15, QUARTERS)

# Front utility slice
box(-6, -4.5, -3, 3, 15, 18, CARGO)
box(-4.5, -3, -3, 3, 15, 18, ENERGY_CONTAINER)
box(-3, 0, -3, 3, 15, 18, GYRO)
box(0, 3, -3, 3, 15, 18, INERTIA_DAMPENER)
box(3, 6, -3, 3, 15, 18, THRUSTER)

# --- Outer shell (1 thick Trinium hull) ---
box(-7, 7, 3, 4, -19, 19, HULL, color=GREY)     # top
box(-7, 7, -4, -3, -19, 19, HULL, color=GREY)   # bottom
mirrored(6, 7, -3, 3, -19, 19, HULL, color=GREY)  # sides
box(-6, 6, -3, 3, -19, -18, HULL, color=DARK)   # rear bulkhead
box(-6, 6, -3, 3, 18, 19, HULL, color=GREY)     # front bulkhead

# Accent stripe along the top
box(-1, 1, 4, 4.5, -17, 17, HULL, color=ACCENT)

# Tiny transporter on top, just in front of the stripe
box(-0.5, 0.5, 4, 5, 17.5, 18.5, TRANSPORTER, XANION, ACCENT)

# --- Armored stepped nose ---
box(-7, 7, -4, 4, 19, 21, ARMOR, color=DARK)
box(-5, 5, -3, 3, 21, 23, ARMOR, color=DARK)
box(-3, 3, -2, 2, 23, 24, ARMOR, color=ACCENT)

# --- Side thruster pods ---
mirrored(7, 8, -2, 2, -14, 14, THRUSTER, color=DARK)

# --- Engines: 2x2 cluster on the rear bulkhead ---
for x0, x1 in ((-6, -0.5), (0.5, 6)):
    for y0, y1 in ((-3, -0.25), (0.25, 3)):
        box(x0, x1, y0, y1, -22, -19, ENGINE, color=DARK)


def volume(lower, upper):
    return (upper[0] - lower[0]) * (upper[1] - lower[1]) * (upper[2] - lower[2])


def overlaps(a, b):
    return all(a[0][i] < b[1][i] and b[0][i] < a[1][i] for i in range(3))


def fmt(v):
    return f"{float(v):g}"


def write_xml(path):
    lines = ['<?xml version="1.0" encoding="utf-8"?>', "<ship_design>",
             '\t<plan accumulateHealth="true" convex="false">']
    for i, (lower, upper, index, material, color) in enumerate(blocks):
        parent = -1 if i == 0 else 0
        lines.append(f'\t\t<item parent="{parent}" index="{i}">')
        lines.append(
            f'\t\t\t<block lx="{fmt(lower[0])}" ly="{fmt(lower[1])}" lz="{fmt(lower[2])}" '
            f'ux="{fmt(upper[0])}" uy="{fmt(upper[1])}" uz="{fmt(upper[2])}" '
            f'index="{index}" material="{material}" look="1" up="3" color="{color}"/>')
        lines.append("\t\t</item>")
    lines += ["\t</plan>", "</ship_design>", ""]
    with open(path, "w", newline="\n") as f:
        f.write("\n".join(lines))


def main():
    for i in range(len(blocks)):
        for j in range(i + 1, len(blocks)):
            if overlaps(blocks[i], blocks[j]):
                raise SystemExit(f"blocks {i} and {j} overlap: {blocks[i]} / {blocks[j]}")

    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "BoardingCarrier.xml")
    write_xml(out)

    by_type = defaultdict(float)
    by_material = defaultdict(float)
    for lower, upper, index, material, _ in blocks:
        by_type[(index, material)] += volume(lower, upper)
        by_material[material] += volume(lower, upper)

    print(f"Wrote {out} ({len(blocks)} blocks)")
    for (index, material), vol in sorted(by_type.items(), key=lambda kv: -kv[1]):
        print(f"  {BLOCK_NAMES[index]:<30} {MATERIAL_NAMES[material]:<8} volume {vol:g}")
    for material, vol in sorted(by_material.items()):
        print(f"  total {MATERIAL_NAMES[material]:<8} volume {vol:g}")


if __name__ == "__main__":
    main()
