# Avorion Mods - Fast Parallel Testing

**Versions:** MiningAlgorithm 1.1.7 | ScrapAlgorithm 1.1.7 | Avorion 2.5.11

## Setup (One Time)
```lua
scriptCachingEnabled = false  -- in modconfig.lua
```
Ship: 12+ fighters, empty cargo  
Location: Sector with BOTH asteroids AND wreckage (10+ of each)

---

## Single Game Session Test (All 5 Tests in One Run)

### Test 1: Enable Both + Fighters Work
```
/autominer on
/autoscraper on
```
Wait 5 seconds, watch console and fighters.

**PASS IF:**
- ✅ Console shows `[AutoMiner] Assigned fighter...ignoreMothershipOrders=true`
- ✅ Console shows `[AutoScraper] Assigned fighter...`
- ✅ Some fighters go to asteroids, others to wreckage
- ✅ Mining/salvage beams visible
- ✅ Cargo starts filling

---

### Test 2: Status Check Both
```
/autominer status
/autoscraper status
```

**PASS IF:**
- ✅ Both show ACTIVE
- ✅ Both show fighters > 0, targets > 0

---

### Test 3: Reassignment (Wait ~2 minutes)
Watch until some asteroids/wreckage fully depleted.

**PASS IF:**
- ✅ Fighters switch to new targets (don't go idle)
- ✅ Console shows reassignment messages

---

### Test 4: Sector Jump Persistence
```
Jump to another sector
Jump back
```

**PASS IF:**
- ✅ Both mods still ACTIVE (check status commands)
- ✅ Fighters reassign to new asteroids/wreckage
- ✅ No errors in console

---

### Test 5: Duplicate Prevention + Clean Stop
```
/autominer on  (while already on)
/autoscraper on  (while already on)
```
Then:
```
/autominer off
/autoscraper off
```

**PASS IF:**
- ✅ Both say "already active" (no duplicates)
- ✅ Both stop cleanly
- ✅ Console shows "stopped" for both
- ✅ Fighters released (no errors)

---

## Optional: Cargo Full Test (If time)
Re-enable both, let cargo fill to 100%.

**PASS IF:** Both auto-stop with "Cargo full" message

---

## Quick Log
```
Date: ______  Time: ~5 minutes

[ ] Test 1: Enable + Fighters Work
[ ] Test 2: Status Shows Active
[ ] Test 3: Reassignment Works
[ ] Test 4: Sector Persistence
[ ] Test 5: No Duplicates + Clean Stop
[ ] (Optional) Cargo Full

Result: __/5 PASSED (6 if optional)

Issues: ________________
```

**Total Time: ~5 minutes for all critical tests in single game session**

---

## If Any Test Fails
1. Note which test
2. Copy console output (screenshot or text)
3. Run cleanup: `/autominer off` + `/autoscraper off`
4. Report: "Test X failed: [console error]"

**Most common failure:** Test 1 - no "ignoreMothershipOrders=true" in console OR fighters return to ship
