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


# Interior half extents: 16 wide (x -8..8), 8 high (y -4..4)
HW, HH = 8, 4

# Length of each interior section, back to front
GENERATORS = 6
DEFENSE = 3
CORES = 6
FIGHTERS = 20
CREW = 18
LIVING = 16
UTILITY = 4

z = -(GENERATORS + DEFENSE + CORES + FIGHTERS + CREW + LIVING + UTILITY) / 2
REAR = z


def section(length):
    global z
    z0, z = z, z + length
    return z0, z


# Power: Trinium generators on the sides, a Xanion generator in the middle
z0, z1 = section(GENERATORS)
mirrored(2, HW, -HH, HH, z0, z1, GENERATOR)
box(-2, 2, -HH, HH, z0, z1, GENERATOR, XANION)

# Defense systems
z0, z1 = section(DEFENSE)
box(-HW, 0, -HH, HH, z0, z1, SHIELD)
box(0, HW, -HH, HH, z0, z1, INTEGRITY_FIELD)

# Jump drive + computer core (processing power -> 10 subsystem sockets)
z0, z1 = section(CORES)
box(-HW, -5, -HH, HH, z0, z1, HYPERSPACE_CORE)
box(-5, HW, -HH, HH, z0, z1, COMPUTER_CORE)

# Fighters: assembly below, hangar above
z0, z1 = section(FIGHTERS)
box(-HW, HW, -HH, 0, z0, z1, ASSEMBLY)
box(-HW, HW, 0, HH, z0, z1, HANGAR)

# Crew production: cloning pods (clone chamber) below, academy above.
# Cloning pods need Xanion or better; Trinium ones are dropped on load.
z0, z1 = section(CREW)
box(-HW, HW, -HH, 0, z0, z1, CLONING_PODS, XANION)
box(-HW, HW, 0, HH, z0, z1, ACADEMY)

# Living space for boarders and the crew running everything else
z0, z1 = section(LIVING)
box(-HW, HW, -HH, HH, z0, z1, QUARTERS)

# Front utility slice
z0, z1 = section(UTILITY)
box(-HW, -5, -HH, HH, z0, z1, CARGO)
box(-5, -3, -HH, HH, z0, z1, ENERGY_CONTAINER)
box(-3, 0, -HH, HH, z0, z1, GYRO)
box(0, 3, -HH, HH, z0, z1, INERTIA_DAMPENER)
box(3, HW, -HH, HH, z0, z1, THRUSTER)
FRONT = z

# --- Outer shell (1 thick Trinium hull) ---
box(-HW - 1, HW + 1, HH, HH + 1, REAR - 1, FRONT + 1, HULL, color=GREY)     # top
box(-HW - 1, HW + 1, -HH - 1, -HH, REAR - 1, FRONT + 1, HULL, color=GREY)   # bottom
mirrored(HW, HW + 1, -HH, HH, REAR - 1, FRONT + 1, HULL, color=GREY)        # sides
box(-HW, HW, -HH, HH, REAR - 1, REAR, HULL, color=DARK)                     # rear bulkhead
box(-HW, HW, -HH, HH, FRONT, FRONT + 1, HULL, color=GREY)                   # front bulkhead

# Accent stripe along the top
box(-1, 1, HH + 1, HH + 1.5, REAR + 1, FRONT - 1, HULL, color=ACCENT)

# Tiny transporter on top, just in front of the stripe
box(-0.5, 0.5, HH + 1, HH + 2, FRONT - 0.5, FRONT + 0.5, TRANSPORTER, XANION, ACCENT)

# --- Armored stepped nose ---
box(-HW - 1, HW + 1, -HH - 1, HH + 1, FRONT + 1, FRONT + 3, ARMOR, color=DARK)
box(-HW + 1, HW - 1, -HH, HH, FRONT + 3, FRONT + 5, ARMOR, color=DARK)
box(-HW + 3, HW - 3, -HH + 1, HH - 1, FRONT + 5, FRONT + 6, ARMOR, color=ACCENT)

# --- Side thruster pods ---
mirrored(HW + 1, HW + 2, -HH + 1, HH - 1, REAR + 4, FRONT - 4, THRUSTER, color=DARK)

# --- Engines: 2x2 cluster on the rear bulkhead ---
for x0, x1 in ((-HW, -0.5), (0.5, HW)):
    for y0, y1 in ((-HH, -0.25), (0.25, HH)):
        box(x0, x1, y0, y1, REAR - 4, REAR - 1, ENGINE, color=DARK)


def volume(lower, upper):
    return (upper[0] - lower[0]) * (upper[1] - lower[1]) * (upper[2] - lower[2])


def overlaps(a, b):
    return all(a[0][i] < b[1][i] and b[0][i] < a[1][i] for i in range(3))


# Processing power: functional blocks give 1 per volume unit, computer cores 7.5,
# hull and armor give none. Sockets unlock at these processing power values.
NO_PROCESSING = {HULL, ARMOR}
SOCKET_THRESHOLDS = [0, 51, 128, 320, 800, 2000, 3162, 5000, 7906, 12500, 19764]


def processing_power():
    total = 0.0
    for lower, upper, index, _, _ in blocks:
        if index in NO_PROCESSING:
            continue
        total += volume(lower, upper) * (7.5 if index == COMPUTER_CORE else 1.0)
    return total


def sockets(pp):
    return sum(1 for t in SOCKET_THRESHOLDS if pp >= t)


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
    pp = processing_power()
    print(f"  estimated processing power {pp:g} -> {sockets(pp)} sockets")


if __name__ == "__main__":
    main()
