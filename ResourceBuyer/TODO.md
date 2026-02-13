# Resource Buyer - TODO

## Overview
Player creates a shopping list of goods and quantities. The ship scans nearby sectors
(reusing AutoTrader's drone pattern), finds the cheapest sellers, buys everything,
and flies back to the starting sector.

## Phase 1: Shopping List UI
- [ ] HUD button + window with the mod's UI
- [ ] Goods list: scrollable list showing good name + quantity needed
- [ ] Add good: combo box or text input to pick a good, number input for quantity
- [ ] Remove good: button per row to delete from list
- [ ] "Start" button to begin the buy run
- [ ] "Stop" button to abort
- [ ] Status label showing current state
- [ ] Persist shopping list via `secure()` / `restore()`

## Phase 2: Sector Scanning
- [ ] Reuse AutoTrader drone pattern: dispatch scanner drones to known sectors within jump range
- [ ] Drones scan stations for goods on the shopping list (only need buy offers, not sell)
- [ ] Serialize results to `Server():setValue()`, poll for completion
- [ ] Filter by relations threshold (skip hostile stations)

## Phase 3: Route Planning
- [ ] For each good on the list, find the cheapest station(s) that sell it
- [ ] Optimize buying order: minimize jumps (greedy nearest-sector or cluster approach)
- [ ] Account for cargo space: if list exceeds capacity, prioritize or split into trips
- [ ] Account for credits: skip goods the player can't afford
- [ ] Build ordered waypoint list: sector1 -> buy goods A,B -> sector2 -> buy good C -> home

## Phase 4: Buy Execution
- [ ] Multi-jump pathfinding to each buy sector (reuse AutoTrader's `calculateJumpPath`)
- [ ] Dock at station, buy goods (reuse AutoTrader's dock + buy pattern)
- [ ] After buying at a station, check if more stops needed
- [ ] If yes, jump to next buy sector
- [ ] If all goods bought (or best effort), jump back to starting sector
- [ ] Update UI with progress: "Buying 2/5 goods...", "Heading home..."

## Phase 5: Polish
- [ ] Show what was actually bought vs what was requested (partial fills)
- [ ] Handle edge cases: station destroyed, not enough stock, not enough credits
- [ ] Chat message summary on completion: "Bought X goods, spent Y credits"
- [ ] Optional: save favorite shopping lists by name

## Code Reuse from AutoTrader (maximize reuse, minimize new code)
- **Drone scanning**: Copy `dronetradescanner.lua` as-is (already scans all station goods)
- **Drone dispatch**: Copy `startNearbyScan()` logic (range calc, drone creation, sector transfer)
- **Scan result polling**: Copy `updateServer()` scanning state (poll `Server():getValue()`, count received)
- **Scan result parsing**: Copy `collectScanResults()` (deserialize `B|name|stock|...` lines)
- **Jump pathfinding**: Copy `calculateJumpPath()` (multi-hop waypoint calculation)
- **Dock + buy**: Copy `STATE_DOCK_BUY` logic from `updateServer()` (DockAI, `sellToShip` call)
- **Jump state machine**: Copy `STATE_JUMP_TO_BUY` logic (waypoint tracking, sector arrival detection)
- **UI helpers**: Copy `updateStatus()`, `updateInfo()`, `updateButtonText()` pattern
- **Station finder**: Copy `findBestTradingStation()` (find station selling a good in current sector)
- **Utility**: Copy `formatNum()`, `getJumpRange()`, relations threshold, `secure()`/`restore()`

Only new code needed:
- Shopping list UI (add/remove goods, combo box, list display)
- Route planner (pick cheapest seller per good, order stops by proximity)
- Multi-stop buy loop (visit N stations instead of just 1)
- Jump-home state after all buying is done

## Architecture Notes
- Entity script: `data/scripts/entity/resourcebuyercontroller.lua`
- Init script: `data/scripts/entity/init.lua` (attach to player/alliance ships)
- Drone scanner: copy AutoTrader's `dronetradescanner.lua` unchanged
- State machine: IDLE -> SCANNING -> PLANNING -> JUMPING_TO_BUY -> DOCKING_BUY -> (repeat) -> JUMPING_HOME -> DONE
- Communication: `Server():setValue()` for drone results
