# Installation Guide

## Quick Install

Copy these files to your Avorion installation:

### File 1: Command Script
**Source**: `autominer.lua`
**Destination**: `<Avorion>/data/scripts/commands/autominer.lua`

### File 2: Main Controller
**Source**: `autominingcontroller.lua`
**Destination**: `<Avorion>/data/scripts/entity/autominingcontroller.lua`

### File 3: Auto-Initializer
**Source**: `init.lua`
**Destination**: `<Avorion>/data/scripts/player/init.lua`

## Where is my Avorion folder?

### Windows
```
C:\Program Files (x86)\Steam\steamapps\common\Avorion\
```

### Linux
```
~/.steam/steam/steamapps/common/Avorion/
```

### macOS
```
~/Library/Application Support/Steam/steamapps/common/Avorion/
```

## Quick Start After Installation

1. **Start Avorion**
2. **Load your save** or start a new game
3. **Board a mining ship** with fighters
4. **Type in chat**: `/autominer on`
5. **Open UI**: Press TAB → Look for "Auto Mining Controller" icon (pickaxe)
6. **Deploy fighters**: Press H
7. **Click "Enable Auto Mining"** in the UI

## That's it! Your fighters will now automatically mine nearby asteroids.

---

## File Tree (for reference)

```
Avorion/
└── data/
    └── scripts/
        ├── commands/
        │   └── autominer.lua
        ├── entity/
        │   └── autominingcontroller.lua
        └── player/
            └── init.lua
```

## Verification

After copying files, verify installation:
1. Launch Avorion
2. In chat, type: `/autominer`
3. You should see: "Usage: /autominer [on|off|status]"

If you see that message, installation is successful!

---

## Need Help?

See README.md for detailed instructions and troubleshooting.
