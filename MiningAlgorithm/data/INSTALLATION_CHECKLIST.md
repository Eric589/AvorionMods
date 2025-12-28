# ✅ INSTALLATION CHECKLIST - Fixed Auto Mining Mod

## Pre-Installation

- [✅] Downloaded all files from /outputs/ folder
- [✅] Located Avorion installation folder
- [✅] Have a text editor ready (optional, for verification)

## Installation Steps

### Step 1: Copy Files
- [✅] Copy `autominer.lua` to `<Avorion>/data/scripts/commands/autominer.lua`
- [✅] Copy `autominingcontroller.lua` to `<Avorion>/data/scripts/entity/autominingcontroller.lua`
- [✅] Copy `init.lua` to `<Avorion>/data/scripts/player/init.lua`

⚠️ **CRITICAL**: Use files from `/outputs/` folder, NOT the originals!

### Step 2: Restart Avorion
- [✅] Close Avorion completely (if running)
- [✅] Start Avorion fresh
- [✅] Load your save game

### Step 3: Verify Installation
- [✅] Open chat (press Enter)
- [✅] Type: `/autominer`
- [✅] See help text: "Usage: /autominer [on|off|status]"

✅ If you see help text → Installation successful!
❌ If you see "Command not found" → Check file locations

## First Use

### Step 4: Activate System
- [✅] Board a mining ship with fighters
- [✅] Type: `/autominer on`
- [✅] See: "Auto Mining activated. Open the Auto Miner UI (TAB key) to configure."

### Step 5: Test UI
- [✅] Press TAB key
- [✅] Look for "Auto Mining Controller" button (pickaxe icon)
- [✅] Click button to open UI
- [✅] See window with status, statistics, and settings

### Step 6: Start Mining
- [✅] Deploy fighters (press H)
- [✅] In UI, click "Enable Auto Mining" button
- [✅] Status should turn green: "Active"
- [ ] Watch fighters target asteroids

## Verification Tests

### Test 1: Command Functionality
```bash
/autominer status
```
- [ ] Shows current status (even if "INACTIVE")

### Test 2: UI Functionality
- [ ] Open UI (TAB → Auto Mining Controller)
- [ ] Click "Enable Auto Mining"
- [ ] Status changes from red to green
- [ ] Statistics update in real-time

### Test 3: Mining Functionality
- [ ] Deploy at least 2 fighters
- [ ] Enable auto-mining
- [ ] Fighters target different asteroids
- [ ] Cargo percentage increases
- [ ] System stops when cargo full

## Troubleshooting

### Issue: Command not found
**Solution**: 
- [ ] Check autominer.lua is in `commands/` folder
- [ ] Restart Avorion completely
- [ ] Try absolute path: `<Avorion>/data/scripts/commands/autominer.lua`

### Issue: Command works but nothing happens
**Solution**:
- [ ] Check you're in a ship (not station)
- [ ] Check init.lua is in `player/` folder
- [ ] Board ship again to trigger initialization

### Issue: UI not appearing
**Solution**:
- [ ] Use `/autominer on` command first
- [ ] Check you're piloting the ship
- [ ] Check autominingcontroller.lua is in `entity/` folder
- [ ] Press TAB and look carefully for pickaxe icon

### Issue: Fighters not mining
**Solution**:
- [ ] Enable system in UI
- [ ] Deploy fighters (press H)
- [ ] Check fighters have mining equipment
- [ ] Move to sector with asteroids

## File Locations Quick Reference

### Windows
```
C:\Program Files (x86)\Steam\steamapps\common\Avorion\data\scripts\
```

### Linux
```
~/.steam/steam/steamapps/common/Avorion/data/scripts/
```

### macOS
```
~/Library/Application Support/Steam/steamapps/common/Avorion/data/scripts/
```

## Expected File Structure

```
Avorion/
└── data/
    └── scripts/
        ├── commands/
        │   └── autominer.lua ✅
        ├── entity/
        │   └── autominingcontroller.lua ✅
        └── player/
            └── init.lua ✅
```

## Success Indicators

You'll know everything is working when:

- ✅ `/autominer` shows help text
- ✅ `/autominer on` gives activation message
- ✅ `/autominer status` shows status
- ✅ TAB menu has Auto Mining Controller button
- ✅ UI opens and shows green/red status
- ✅ Toggle button changes UI status color
- ✅ Statistics update in real-time
- ✅ Fighters target different asteroids
- ✅ Console shows "[AutoMiner] Auto Mining started"

## Final Checks

Before considering installation complete:

- [ ] All 3 files copied to correct locations
- [ ] Avorion restarted
- [ ] Command works and gives output
- [ ] UI accessible via TAB
- [ ] UI responds to button clicks
- [ ] Fighters mine when enabled

## Support

If issues persist after checking all boxes:

1. Read FIXED_README.md for detailed explanations
2. Read DETAILED_COMPARISON.md to understand the fixes
3. Check console (~ key) for error messages
4. Verify you used files from /outputs/ folder

---

## Quick Command Reference

```bash
/autominer            # Show help
/autominer on         # Enable auto-mining
/autominer off        # Disable auto-mining
/autominer status     # Check status
```

## Quick Usage Workflow

1. **Install** → Copy 3 files
2. **Restart** → Close and reopen Avorion
3. **Board** → Get in mining ship
4. **Activate** → `/autominer on`
5. **Deploy** → Press H
6. **Open UI** → Press TAB
7. **Enable** → Click button
8. **Mine** → Watch it work!

---

**When all boxes are checked → You're ready to mine! ⛏️🚀**
