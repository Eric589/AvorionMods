# FIXED AUTO MINING MOD - Installation & What Was Fixed

## ✅ What Was Fixed

### Issue 1: Command Not Working (Nothing Happened)
**Problem**: The command was using `craft.index:addScriptOnce()` which doesn't work properly.

**Solution**: Changed to use `Entity(craft.index)` to get proper entity reference:
```lua
-- BEFORE (broken):
craft.index:addScriptOnce("data/scripts/entity/autominingcontroller.lua")

-- AFTER (fixed):
local entity = Entity(craft.index)
entity:addScriptOnce("data/scripts/entity/autominingcontroller.lua")
```

### Issue 2: Wrong init.lua File
**Problem**: The init.lua in your package was for a different mod (lootCleaner), not auto mining.

**Solution**: Replaced with correct auto-mining initialization code that:
- Registers craft change callback
- Automatically adds controller when you board a ship
- Uses proper callable wrapper for server functions

### Issue 3: Missing Callable Wrapper
**Problem**: The `updateUIStatus` function was not marked as callable, preventing client/server sync.

**Solution**: Added `callable(AutoMiningController, "updateUIStatus")` after the function.

## 📦 Installation (Updated)

### Step 1: Copy Fixed Files

Copy these **3 FIXED files** to your Avorion directory:

1. **autominer.lua** → `<Avorion>/data/scripts/commands/autominer.lua`
2. **autominingcontroller.lua** → `<Avorion>/data/scripts/entity/autominingcontroller.lua`  
3. **init.lua** → `<Avorion>/data/scripts/player/init.lua`

⚠️ **IMPORTANT**: Use the files from the `/outputs/` folder - they are the FIXED versions!

### Step 2: Verify Installation

1. **Start/Restart Avorion** (important - restart to reload scripts)
2. Press **Enter** to open chat
3. Type: `/autominer`
4. You should see: `"Usage: /autominer [on|off|status]"`

### Step 3: Test Functionality

1. **Board a mining ship** with fighters
2. Type: `/autominer on`
3. You should see: `"Auto Mining activated. Open the Auto Miner UI (TAB key) to configure."`
4. Press **TAB** → Look for **"Auto Mining Controller"** button (pickaxe icon)
5. Click it to open the UI

## 🎮 Usage After Installation

### Method 1: Using Commands
```bash
/autominer on      # Enable auto-mining
/autominer off     # Disable auto-mining  
/autominer status  # Check current status
```

### Method 2: Using UI
1. Press **TAB** (opens System menu)
2. Look for **"Auto Mining Controller"** button
3. Click to open UI
4. Click **"Enable Auto Mining"** button
5. Deploy fighters (press **H**)
6. Watch them work!

## 🔧 Why It Wasn't Working Before

### The Command Issue
The original code tried to call methods directly on `craft.index` (a Uuid object), but you need to create an Entity object first:

```lua
-- This doesn't work:
craft.index:addScriptOnce(...)

-- This works:
local entity = Entity(craft.index)
entity:addScriptOnce(...)
```

### The init.lua Issue
Your package had the wrong init.lua - it was from a different mod (loot cleaner). The fixed version:
- Properly registers callbacks
- Uses callable wrapper for server-side functions
- Actually adds the auto-mining controller

### The Callable Issue
When client and server need to communicate in Avorion, functions must be marked with `callable()`. The UI status update wasn't working because this was missing.

## ✅ Verification Checklist

After installing the fixed files:

- [ ] Command `/autominer` shows help text (not "unknown command")
- [ ] Command `/autominer on` shows activation message
- [ ] Command `/autominer status` shows status (even if "not active")
- [ ] TAB menu shows "Auto Mining Controller" button
- [ ] Clicking button opens UI window
- [ ] UI shows status, statistics, and settings
- [ ] Toggle button enables/disables mining
- [ ] Fighters mine asteroids when enabled

If all boxes are checked → ✅ **Working perfectly!**

## 🐛 Troubleshooting

### Still Not Working?

1. **Restart Avorion completely** - Scripts are cached
2. **Check file locations** - Must be exact paths:
   - `data/scripts/commands/autominer.lua`
   - `data/scripts/entity/autominingcontroller.lua`
   - `data/scripts/player/init.lua`

3. **Check you used FIXED files** - From `/outputs/` folder, not originals

4. **Enable console** to see error messages:
   - Press `~` key to open console
   - Type `/autominer on`
   - Look for any red error messages

### Common Issues

**"Command not found"**
→ `autominer.lua` not in correct location or Avorion not restarted

**Command works but nothing happens**
→ Not in a ship, or wrong init.lua (use fixed version)

**UI not appearing**
→ Script not attached to ship, use `/autominer on` first

**Fighters not mining**
→ Enable in UI, deploy fighters (H key), check they have mining equipment

## 🎯 Quick Start Workflow

1. **Install** → Copy 3 fixed files
2. **Restart** → Close and reopen Avorion completely
3. **Board** → Get in a mining ship
4. **Activate** → `/autominer on`
5. **Deploy** → Press H to deploy fighters
6. **Configure** → TAB → Auto Mining Controller → Enable
7. **Mine!** → Watch fighters automatically target asteroids

## 📊 Technical Details

### Key Code Changes

**autominer.lua** (lines 20-21):
```lua
local entity = Entity(craft.index)
entity:addScriptOnce("data/scripts/entity/autominingcontroller.lua")
```

**init.lua** (complete rewrite):
- Now uses proper player callbacks
- Includes callable wrapper
- Actually adds the controller script

**autominingcontroller.lua** (line 183):
```lua
callable(AutoMiningController, "updateUIStatus")
```

### Why Entity() Wrapper Matters

In Avorion's Lua API:
- `craft.index` is a **Uuid** (identifier)
- `Entity(uuid)` creates an **Entity object** (has methods)
- Only Entity objects have `:addScriptOnce()` method

This is why the original code failed silently - Lua couldn't find the method.

## 🎉 Success Indicators

You'll know it's working when:

1. ✅ Command gives you feedback messages
2. ✅ UI appears in TAB menu
3. ✅ Status button changes color when enabled
4. ✅ Statistics update in real-time
5. ✅ Fighters target different asteroids
6. ✅ Console shows "[AutoMiner] Auto Mining started"

---

## Files in /outputs/ Folder

- ✅ **autominer.lua** - Fixed command (uses Entity wrapper)
- ✅ **init.lua** - Fixed initialization (correct auto-attach code)
- ✅ **autominingcontroller.lua** - Fixed controller (added callable wrapper)

**Use these files, not the originals in the root folder!**

---

**Everything should now work perfectly. Enjoy automated mining!** ⛏️🚀
