# Critical Code Analysis - Both Mods

**Analysis Date:** Current  
**Versions:** MiningAlgorithm 1.1.7 | ScrapAlgorithm 1.1.7

---

## 🚨 CRITICAL ISSUES (Must Fix)

### 1. **ScrapAlgorithm: Missing Cleanup/Reassignment Logic**
**Severity:** HIGH - Fighters won't reassign when wreckage depleted

**Location:** `autoscrapingcontroller.lua` - Missing function

**Problem:**
```lua
-- MiningAlgorithm has this (line 622-704):
function AutoMiningController.cleanupAssignments()
    -- Checks if asteroids still valid
    -- Reassigns fighters when asteroids depleted
    -- Called every update cycle
end

-- ScrapAlgorithm MISSING equivalent!
-- updateServer() only assigns new fighters, never reassigns existing ones
```

**Impact:**
- Fighters target wreckage until depleted
- Then sit idle even if more wreckage available
- Must manually disable/enable to reassign

**Fix Needed:**
Add `cleanupAssignments()` function to ScrapAlgorithm mirroring MiningAlgorithm's logic.

**Verification:**
Test 3 in testing plan will FAIL without this.

---

### 2. **ScrapAlgorithm: Wrong Index Type in Callback**
**Severity:** MEDIUM - Callback won't clean up properly

**Location:** `autoscrapingcontroller.lua:666`

**Problem:**
```lua
function AutoScrapingController.onWreckageDestroyed(index)
    if not onServer() then return end
    
    local wreckageId = tostring(index)  -- ❌ WRONG: index is already a Uuid object
    
    -- Should be:
    local wreckageId = index.string  -- ✅ CORRECT: like MiningAlgorithm does
```

**Comparison with MiningAlgorithm (line 706):**
```lua
function AutoMiningController.onAsteroidDestroyed(index)
    local indexString = index.string  -- ✅ CORRECT
```

**Impact:**
- `wreckageAssignments` never cleaned up when wreckage destroyed
- Memory leak over time
- Fighters may get confused by stale assignments

**Fix:**
Change `tostring(index)` to `index.string`

---

### 3. **Both Mods: Icon Path Inconsistency**
**Severity:** LOW - UI button may not show icon

**Location:**
- MiningAlgorithm line 18: `"data/icon/icon.png"`
- ScrapAlgorithm line 19: `"data/icons/icon.png"` (note: iconS)

**Problem:**
Directory names don't match. One uses `/icon/`, other uses `/icons/`.

**Fix:**
Verify actual directory structure and make consistent.

---

## ⚠️ POTENTIAL ISSUES (Review Needed)

### 4. **ScrapAlgorithm: Unused/Dead Code**
**Severity:** LOW - Code bloat, confusing maintenance

**Location:** `autoscrapingcontroller.lua:75, 82, 532-603`

**Problem:**
```lua
local collectItemsWhenIdle = false  -- Line 75: Disabled, never used
local itemAssignments = {}  -- Line 82: Never populated (disabled feature)

-- Lines 532-603: Item collection functions defined but NEVER CALLED
function AutoScrapingController.getNearbyCollectibles(entity)
    -- 37 lines of unused code
end

function AutoScrapingController.assignFightersToItems(fighters, items)
    -- 33 lines of unused code
end
```

**Why It's There:**
Comment says "Disabled: Fighters can't actually collect loose items" (line 75)

**Impact:**
- Confuses maintainers
- Increases file size unnecessarily
- May mislead future developers

**Recommendation:**
Remove dead code OR implement properly if intended feature.

---

### 5. **ScrapAlgorithm: Overly Complex Fighter Detection**
**Severity:** MEDIUM - Performance impact, potential bugs

**Location:** `autoscrapingcontroller.lua:742-779`

**Problem:**
ScrapAlgorithm uses complex validation logic:
```lua
for squad = 0, 9 do
    for _, fighter in pairs(fighters) do
        local ai = FighterAI(fighter.id)
        local targetId = ai.target
        if targetId and valid(targetId) then
            local target = Entity(targetId)
            if target and valid(target) then
                if target.type == EntityType.Wreckage then
                    hasValidTarget = true
                    -- Ensure wreckage is in assignments
                    if not wreckageAssignments[wreckageId] then
                        wreckageAssignments[wreckageId] = true
                    end
                end
            end
        end
        -- If no valid target, mark available
        if not hasValidTarget then
            table.insert(availableFighters, fighter)
            assignedFighters[fighterIndex] = nil
        end
    end
end
```

**Comparison with MiningAlgorithm:**
```lua
function AutoMiningController.getAvailableFighters(controller)
    -- Simpler: checks if fighter in assignedFighters table
    -- Uses isFighterBusy() helper function
    -- More readable, less nested
end

function AutoMiningController.isFighterBusy(fighter)
    -- Separate validation logic
    -- Easier to debug
end
```

**Issues:**
1. **Logic in wrong place**: Detection should be in helper function, not `updateServer()`
2. **No cleanup call**: MiningAlgorithm explicitly calls `cleanupAssignments()`, ScrapAlgorithm relies on inline logic
3. **Assignment table pollution**: Line 764 adds to `wreckageAssignments` inside detection loop

**Recommendation:**
Refactor to match MiningAlgorithm's cleaner pattern with separate helper functions.

---

### 6. **Both Mods: Missing minResourceThreshold Persistence**
**Severity:** LOW - Settings not fully saved

**Location:**
- MiningAlgorithm: `minResourceThreshold` (line 71) NOT in `secure()` (line 135-143)
- ScrapAlgorithm: `minValueThreshold` (line 72) IS in `secure()` (line 147-158) ✅

**Problem in MiningAlgorithm:**
```lua
-- Line 71
local minResourceThreshold = 1  -- Not configurable via UI

-- Line 135-143: secure() function
function AutoMiningController.secure()
    return {
        enabled = enabled,
        timePassed = timePassed,
        assignedFighters = assignedFighters,
        asteroidAssignments = asteroidAssignments,
        resourcesPerFighter = resourcesPerFighter,
        maxRange = maxRange
        -- ❌ Missing: minResourceThreshold
    }
end
```

**Impact:**
If threshold ever made configurable, won't persist across sectors.

**Fix:**
Add to `secure()` and `restore()` even if not currently configurable (future-proofing).

---

## 🔍 DESIGN INCONSISTENCIES (Not Bugs, But Confusing)

### 7. **Different Update Intervals**
**Location:**
- MiningAlgorithm line 70: `local updateInterval = 3.0`
- ScrapAlgorithm line 71: `local updateInterval = 1.0`

**Question:**
Why different? Performance testing showed 3.0 is sufficient?

**Impact:**
- ScrapAlgorithm updates 3x more frequently
- More CPU usage for same logic
- No apparent reason for difference

**Recommendation:**
Make both 3.0 unless testing proves 1.0 necessary for scraping.

---

### 8. **Default Range Inconsistency**
**Location:**
- MiningAlgorithm line 73: `local maxRange = 200000` (200km)
- ScrapAlgorithm line 74: `local maxRange = 200000` (comment says 50km!)

**ScrapAlgorithm Comment Mismatch:**
```lua
local maxRange = 200000  -- 50km default range  ❌ WRONG MATH
-- Should say: 200km default range
```

**Also in restore():**
```lua
-- Line 169
maxRange = data.maxRange or 50000  -- Restores to 50km if data missing!
```

**MiningAlgorithm restore():**
```lua
-- Line 153
maxRange = data.maxRange or 50000  -- Also defaults to 50km
```

**Problem:**
- Initial value: 200000 (200km)
- Restore default: 50000 (50km)
- Inconsistent on sector reload!

**Fix:**
Make restore default match initial value: `or 200000`

---

## 🧪 UNVERIFIED CODE PATHS

### 9. **Duplicate Removal Logic Untested**
**Location:** Both mods, `initialize()` function (lines 100-115)

**Code:**
```lua
if scriptCount > 1 then
    local duplicates = scriptCount - 1
    print("[AutoMiner] Removing " .. duplicates .. " duplicate script entries...")
    for _ = 1, duplicates do
        entity:removeScript("data/scripts/entity/autominingcontroller.lua")
    end
end
```

**Concern:**
- Removes scripts DURING initialize()
- What if this script instance is one being removed?
- Lua doesn't have strong guarantees about execution order

**Testing Needed:**
1. Manually add script twice: `entity:addScript()` called twice
2. Verify only one instance remains
3. Verify remaining instance is functional

**Alternative Approach:**
```lua
-- Instead of removing duplicates in initialize(),
-- check in command BEFORE adding:
local scripts = entity:getScripts()
for _, path in pairs(scripts) do
    if path == "data/scripts/entity/autominingcontroller.lua" then
        return -- Already exists, don't add
    end
end
entity:addScriptOnce(...)
```

---

### 10. **Cargo Full Detection Timing**
**Location:** Both mods, `updateServer()` (MiningAlgorithm line 419, ScrapAlgorithm line 726)

**Code:**
```lua
if entity.freeCargoSpace and entity.freeCargoSpace < 1 then
    print("[AutoMiner] Cargo full, stopping")
    AutoMiningController.stopAutoMining()
    broadcastInvokeClientFunction("updateUIStatus", false)
    return
end
```

**Questions:**
1. **What if `freeCargoSpace` is nil?** Check passes, continues with full cargo
2. **Race condition?** Cargo fills BETWEEN check and next update?
3. **What if cargo fills DURING assignment loop?** Fighters already ordered to mine

**Suggestion:**
```lua
-- More defensive check:
if not entity.freeCargoSpace or entity.freeCargoSpace < 1 then
    -- Safer: treats nil as "unknown/full" rather than "has space"
```

---

## ✅ GOOD PATTERNS (Keep These)

### What Works Well:

1. **`ai.ignoreMothershipOrders = true`** - Properly set before every order (lines 593, 681 in MiningAlgorithm)
2. **`callable()` declarations** - All RPC functions properly marked
3. **Client-server separation** - Consistent `onServer()` / `onClient()` checks
4. **Entity validity checks** - Proper use of `valid()` before access
5. **Duplicate prevention** - Entity value flags prevent re-initialization
6. **State persistence** - `secure()` / `restore()` properly implemented (mostly)

---

## 📝 PRIORITY FIX LIST

**Must Fix Before Release:**
1. ✅ **Issue #1** - Add cleanup/reassignment to ScrapAlgorithm (CRITICAL)
2. ✅ **Issue #2** - Fix `index.string` in `onWreckageDestroyed()` (MEDIUM)
3. ✅ **Issue #8** - Fix maxRange restore default inconsistency (EASY)

**Should Fix:**
4. ⚠️ **Issue #7** - Unify updateInterval to 3.0 (EASY)
5. ⚠️ **Issue #5** - Refactor ScrapAlgorithm fighter detection (MEDIUM)
6. ⚠️ **Issue #10** - Improve cargo full check (EASY)

**Optional:**
7. 💡 **Issue #3** - Fix icon path consistency (TRIVIAL)
8. 💡 **Issue #4** - Remove dead item collection code (CLEANUP)
9. 💡 **Issue #6** - Add minResourceThreshold to persistence (FUTURE-PROOF)

---

## 🧪 TESTING STRATEGY

### Critical Path Tests (Must Pass):
1. **Fighter Reassignment** - Will fail for ScrapAlgorithm without Issue #1 fix
2. **Memory Leak Check** - Run both mods for 30min, check assignment table sizes
3. **Sector Transition** - Verify maxRange doesn't reset to 50km (Issue #8)

### Stress Tests:
1. **100+ asteroids/wreckage** - Performance with Issue #7 fix (both at 3.0s)
2. **Rapid on/off cycling** - Verify duplicate removal (Issue #9)
3. **Cargo fills mid-operation** - Verify clean stop (Issue #10)

---

## 🎯 CONCLUSION

**Overall Assessment:**
- MiningAlgorithm is more mature and complete
- ScrapAlgorithm has missing core functionality (cleanup/reassignment)
- Both have minor bugs that may cause issues under specific conditions

**Estimated Stability:**
- MiningAlgorithm: 85% - Will work for most use cases
- ScrapAlgorithm: 60% - Missing reassignment will frustrate users

**Recommendation:**
Fix Critical Issues #1, #2, #8 before running full test suite.

**After fixes, success probability:**
- MiningAlgorithm: 95%
- ScrapAlgorithm: 90%
