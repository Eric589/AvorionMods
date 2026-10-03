# Boarding Carrier

`BoardingCarrier.xml` is a simple, boxy carrier design made for boarding stations.
It is sized for **10 subsystem sockets**: it has about 14,500 processing power,
and 10 sockets need 12,500 (11 would need about 19,800).
Most blocks are Trinium. The cloning pods, one generator and the tiny transporter are Xanion.

## Install

1. Copy `BoardingCarrier.xml` to `%APPDATA%\Avorion\ships\` (Linux: `~/.avorion/ships/`).
2. In build mode, open the **Ship Designs** tab and load *BoardingCarrier*.
3. Check the socket count, energy and cost in build mode, then build it.

## Layout (back to front)

Inside the hull the ship is 16 wide and 8 high.

| Section | Blocks | Volume |
|---|---|---|
| Rear | 4 engines; Trinium generators + a Xanion generator | 576 + 192 |
| Defense | Shield generator, integrity field | 192 each |
| Cores | Hyperspace core, Trinium computer core | 144, 624 |
| Fighters | Assembly (lower deck) + hangar (upper deck) | 1,280 each |
| Crew production | Xanion cloning pods (lower) + academy (upper) | 1,152 each |
| Living | Crew quarters | 2,048 |
| Front | Cargo, energy container, gyro, inertia dampener, thrusters, armored nose | |
| Outside | 1-thick hull shell, side thruster pods, tiny Xanion transporter on top | |

## Notes

- Cloning pods are only available from Xanion. A Trinium cloning pod is dropped
  when the design loads.
- The processing power figure is an estimate: functional blocks give 1 per volume,
  computer cores give 7.5, and hull and armor give nothing. Build mode shows the real value.

## Tweaking

Edit the section lengths at the top of `generate_boarding_carrier.py` and run
`python3 generate_boarding_carrier.py`. The script checks that no blocks overlap,
then prints the volume of each block type and material, plus the estimated
processing power and socket count.

- Build mode shows 11 sockets: shorten `CORES` or a crew/fighter section.
- Build mode shows 9 sockets: lengthen `CORES` (the computer core gives the most processing power per volume).
- Not enough energy: lengthen `GENERATORS`.
