# 🔍 DETAILED COMPARISON - What Changed

## File 1: autominer.lua

### ❌ BEFORE (Lines 14-21) - BROKEN
```lua
if action == "on" or action == "start" or action == "enable" then
    -- Add script to player's craft
    local craft = player.craft
    if not craft or not valid(craft) then
        return 0, "", "No craft selected. Please board a ship first."
    end

    craft.index:addScriptOnce("data/scripts/entity/autominingcontroller.lua")
    return 0, "", "Auto Mining activated. Open the Auto Miner UI to configure."
```

**Problem**: `craft.index` is a Uuid, not an Entity. Uuid objects don't have `addScriptOnce()` method.

### ✅ AFTER (Lines 13-25) - FIXED
```lua
if action == "on" or action == "start" or action == "enable" then
    -- Add script to player's craft
    local craft = player.craft
    if not craft or not valid(craft) then
        return 0, "", "No craft selected. Please board a ship first."
    end

    local entity = Entity(craft.index)
    if not entity then
        return 0, "", "Could not access craft entity."
    end

    entity:addScriptOnce("data/scripts/entity/autominingcontroller.lua")
    return 0, "", "Auto Mining activated. Open the Auto Miner UI (TAB key) to configure."
```

**Fix**: 
1. Create Entity object from craft.index
2. Check if entity is valid
3. Call method on Entity object
4. Added clarification "(TAB key)" to message

---

### ❌ BEFORE (Lines 23-27) - BROKEN
```lua
elseif action == "off" or action == "stop" or action == "disable" then
    local craft = player.craft
    if not craft or not valid(craft) then
        return 0, "", "No craft selected."
    end

    local ok, err = craft.index:invokeFunction("data/scripts/entity/autominingcontroller.lua", "disableAutoMining")
```

**Problem**: Same issue - `craft.index:invokeFunction()` doesn't exist.

### ✅ AFTER (Lines 27-38) - FIXED
```lua
elseif action == "off" or action == "stop" or action == "disable" then
    local craft = player.craft
    if not craft or not valid(craft) then
        return 0, "", "No craft selected."
    end

    local entity = Entity(craft.index)
    if not entity then
        return 0, "", "Could not access craft entity."
    end

    local ok, err = entity:invokeFunction("data/scripts/entity/autominingcontroller.lua", "disableAutoMining")
```

**Fix**: Same pattern - create Entity object first.

---

### ❌ BEFORE (Lines 36-40) - BROKEN
```lua
elseif action == "status" then
    local craft = player.craft
    if not craft or not valid(craft) then
        return 0, "", "No craft selected."
    end

    local ok, status = craft.index:invokeFunction("data/scripts/entity/autominingcontroller.lua", "getStatus")
```

**Problem**: Same issue.

### ✅ AFTER (Lines 50-61) - FIXED
```lua
elseif action == "status" then
    local craft = player.craft
    if not craft or not valid(craft) then
        return 0, "", "No craft selected."
    end

    local entity = Entity(craft.index)
    if not entity then
        return 0, "", "Could not access craft entity."
    end

    local ok, status = entity:invokeFunction("data/scripts/entity/autominingcontroller.lua", "getStatus")
```

**Fix**: Same pattern consistently applied.

---

## File 2: init.lua

### ❌ BEFORE (ENTIRE FILE) - COMPLETELY WRONG
```lua
local entity = Entity()

if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            if not entity:hasScript("lib/lootCleaner.lua") then
                entity:addScriptOnce("lib/lootCleaner.lua")
            end
        end
    end
end
```

**Problem**: 
1. This is for a DIFFERENT mod (lootCleaner)
2. Wrong script path
3. No proper initialization structure
4. No callbacks
5. No callable wrapper

### ✅ AFTER (ENTIRE FILE) - COMPLETELY REWRITTEN
```lua
-- data/scripts/player/init.lua
-- This script automatically adds the auto-mining controller to player ships

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function initialize()
    if onClient() then
        Player():registerCallback("onCraftChanged", "onCraftChanged")
    end
end

function onCraftChanged(playerIndex, craftIndex)
    if onClient() then
        -- Request server to add script
        invokeServerFunction("addControllerToShip", craftIndex)
    end
end

function addControllerToShip(craftIndex)
    if not onServer() then return end
    
    local craft = Entity(craftIndex)
    if not craft or not valid(craft) then return end
    
    -- Check if it's a ship
    if not craft.isShip then return end
    
    -- Check if it belongs to the player
    if not craft.playerOwned and not craft.allianceOwned then return end
    
    -- Add the auto-mining controller if not already present
    if not craft:hasScript("data/scripts/entity/autominingcontroller.lua") then
        craft:addScriptOnce("data/scripts/entity/autominingcontroller.lua")
        print("[AutoMiner] Added Auto Mining Controller to ship: " .. (craft.name or "unnamed"))
    end
end
callable(nil, "addControllerToShip")
```

**Fix**:
1. Proper initialization with callback registration
2. Correct script path for auto-mining
3. Client/server architecture with invokeServerFunction
4. Callable wrapper for server function
5. Proper entity checks
6. Debug output for verification

---

## File 3: autominingcontroller.lua

### ❌ BEFORE (Lines 168-182) - MISSING CALLABLE
```lua
function AutoMiningController.updateUIStatus(isEnabled)
    if not AutoMiningController.statusText then return end
    
    enabled = isEnabled
    
    if isEnabled then
        AutoMiningController.statusText.caption = "Active"
        AutoMiningController.statusText.color = ColorRGB(0.3, 1, 0.3)
        AutoMiningController.toggleButton.caption = "Disable Auto Mining"
    else
        AutoMiningController.statusText.caption = "Inactive"
        AutoMiningController.statusText.color = ColorRGB(1, 0.3, 0.3)
        AutoMiningController.toggleButton.caption = "Enable Auto Mining"
    end
end
```

**Problem**: No `callable()` wrapper, so client can't invoke this from server.

### ✅ AFTER (Lines 168-183) - CALLABLE ADDED
```lua
function AutoMiningController.updateUIStatus(isEnabled)
    if not AutoMiningController.statusText then return end
    
    enabled = isEnabled
    
    if isEnabled then
        AutoMiningController.statusText.caption = "Active"
        AutoMiningController.statusText.color = ColorRGB(0.3, 1, 0.3)
        AutoMiningController.toggleButton.caption = "Disable Auto Mining"
    else
        AutoMiningController.statusText.caption = "Inactive"
        AutoMiningController.statusText.color = ColorRGB(1, 0.3, 0.3)
        AutoMiningController.toggleButton.caption = "Enable Auto Mining"
    end
end
callable(AutoMiningController, "updateUIStatus")
```

**Fix**: Added `callable(AutoMiningController, "updateUIStatus")` on line 183.

---

## Summary of Changes

| File | Lines Changed | Type of Fix |
|------|--------------|-------------|
| autominer.lua | 14-21, 23-34, 36-47 | Add Entity() wrapper |
| init.lua | ENTIRE FILE | Complete rewrite |
| autominingcontroller.lua | +183 | Add callable wrapper |

## Why Each Fix Was Necessary

### Entity() Wrapper in autominer.lua
**Without it**: Lua tries to call methods on a Uuid (just an ID)
**With it**: Lua calls methods on an Entity object (has the methods)

### Rewritten init.lua
**Without it**: Wrong mod loaded (lootCleaner)
**With it**: Auto-mining controller properly attached to ships

### Callable Wrapper in autominingcontroller.lua
**Without it**: Client can't receive status updates from server
**With it**: UI status syncs between client and server

---

## Testing Each Fix

### Test 1: Command Works
```bash
/autominer on
```
**Expected**: "Auto Mining activated. Open the Auto Miner UI (TAB key) to configure."
**Verifies**: autominer.lua fix

### Test 2: Script Auto-Attaches
```bash
Board a ship, then: /autominer status
```
**Expected**: Status message (even if inactive)
**Verifies**: init.lua fix

### Test 3: UI Updates
```bash
Open UI, click Enable button
```
**Expected**: Status changes from red "Inactive" to green "Active"
**Verifies**: autominingcontroller.lua fix

---

**All three fixes are required for the mod to work correctly.**
