# Boarding Carrier

`BoardingCarrier.xml` is a simple, boxy carrier design made for boarding stations.
It is built from Trinium, with a little Xanion: about 169 volume of Xanion blocks
(a generator, the computer core and a tiny transporter).

## Install

1. Copy `BoardingCarrier.xml` to `%APPDATA%\Avorion\ships\` (Linux: `~/.avorion/ships/`).
2. In build mode, open the **Ship Designs** tab and load *BoardingCarrier*.
3. Check the resource cost and slot count in build mode, then build it.

## Layout (back to front)

| Section | Blocks |
|---|---|
| Rear | 4 engines, Trinium generators + a Xanion generator |
| Systems | Shield generator, integrity field, hyperspace core, Xanion computer core |
| Fighters | Assembly (lower deck) + hangar (upper deck), 360 volume each |
| Crew production | Cloning pods (lower) + academy (upper), 288 volume each |
| Living | Crew quarters, 504 volume |
| Front | Cargo, energy container, gyro, inertia dampener, thrusters, armored nose |
| Outside | 1-thick hull shell, side thruster pods, tiny Xanion transporter on top |

## Tweaking

Edit the sizes in `generate_boarding_carrier.py` and run `python3 generate_boarding_carrier.py`.
The script checks that no blocks overlap and prints the volume of each block type
and material.

- Over 10 slots: make the Xanion computer core smaller, or change it to Trinium.
- Over 10,000 Xanion: shrink the Xanion generator, or change it to Trinium.
- Not enough energy: make the Trinium generators bigger.
