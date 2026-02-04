# Future Mod Implementations

This document tracks planned mods to be developed for this Avorion mods collection.

## Planned Mods

### 1. Auto Explore
**Status:** Planned  
**Complexity:** Medium  

**Description:**  
Ship automatically detects nearby signals and explores them, adding information about detected objects to the player's knowledge base.

**Key Features:**
- Detect signals in nearby sectors
- Automatically navigate to signal locations
- Explore and catalog discovered objects
- Update player's map with discovered information
- Prioritize unexplored signals

**Technical Considerations:**
- Use sector queries to detect signals
- Integrate with Avorion's hidden mass/signal system
- Store exploration state in entity values for persistence
- Client-server sync for UI updates showing explored objects

---

### 2. Auto Buy/Sell (Advanced Trading)
**Status:** Planned  
**Complexity:** High  

**Description:**  
Ship gathers information from nearby sectors and communicates with other ships that have the trade extension installed. Calculates the highest profit per jump/station to dock, including owned stations.

**Key Features:**
- Scan nearby sectors for trade opportunities
- Communicate with ships that have trade extensions
- Calculate optimal trade routes (profit per jump)
- Include player-owned stations in calculations
- Auto-dock and execute trades
- Multi-ship coordination for trade fleets

**Technical Considerations:**
- Use sector queries to get station/price data
- RPC communication between ships with trade extensions
- Pathfinding algorithm for multi-jump routes
- Profit calculation: `(sell_price - buy_price) / (jumps + docking_time)`
- Store trade routes in entity values
- Handle cargo capacity constraints
- Integration with existing autopilot/navigation systems

---

### 3. Tech Level Display
**Status:** Planned  
**Complexity:** Low-Medium  

**Description:**  
Adds a display overlay to the galaxy map showing the tech level of sectors.

**Key Features:**
- Visual overlay on galaxy map
- Color-coded tech levels
- Toggle on/off
- Show tech level numbers or color gradient
- Update as player explores new sectors

**Technical Considerations:**
- UI overlay using Avorion's GUI system
- Access sector coordinates and tech level data
- Color mapping: low tech (red/orange) to high tech (blue/purple)
- Client-side rendering (galaxy map is client-side)
- Persist display settings in player values

---

### 4. Auto Miner/Scraper Explorer
**Status:** Planned  
**Complexity:** Medium-High  
**Related Mods:** MiningAlgorithm, ScrapAlgorithm (existing)

**Description:**  
Enhanced version of existing auto-miner/scraper that explores new systems autonomously. Instead of 4-hour autopilot mining, ships fly in manual mode, scrap sectors completely, refine all resources, and continue to next sector.

**Key Features:**
- Autonomous sector-to-sector navigation
- Complete sector scrapping (all asteroids/wreckage)
- Auto-refine resources after clearing sector
- Move to adjacent sectors when current is cleared
- Return to base when cargo full
- Avoid dangerous sectors (configurable threat level)

**Technical Considerations:**
- Build on existing MiningAlgorithm/ScrapAlgorithm controller logic
- Add sector completion detection (no more targets)
- Integrate with refinery commands
- Navigation between sectors (avoid long-distance jumps without player)
- Cargo management and auto-return logic
- Sector threat assessment (pirate/Xsotan presence)
- State machine: MINING → REFINING → MOVING → MINING

---

### 5. Auto Patrol & Scrap
**Status:** Planned  
**Complexity:** High  

**Description:**  
Ships automatically patrol a defined region, detect enemies, engage and clear them, then call in auto-scrapers to salvage the wreckage. Works like autopilot mode but fully autonomous.

**Key Features:**
- Define patrol region (multiple sectors)
- Auto-navigate between sectors in region
- Detect enemies within range
- Engage and clear hostiles
- Call scraper ships after battle
- Coordinated fleet operations (combat ships + scrapers)
- Return to base for repairs when damaged

**Technical Considerations:**
- Region definition system (coordinate ranges or sector lists)
- Enemy detection using sector queries
- Combat AI integration (target prioritization)
- Multi-ship coordination via RPC
- Signal system: combat ship → scraper ship ("sector cleared")
- Damage threshold for retreat/repair
- Prevent scraper ships from entering combat zones
- State machine: PATROLLING → ENGAGING → WAITING_FOR_SCRAP → PATROLLING
- Integration with existing ScrapAlgorithm for wreckage collection

**Fleet Coordination Pattern:**
```lua
-- Combat ship detects enemies
-- Combat ship clears sector
-- Combat ship broadcasts: sectorCleared(x, y)
-- Scraper ships receive signal
-- Scraper ships navigate to (x, y)
-- Scraper ships activate ScrapAlgorithm
-- Scraper ships signal: scrapComplete(x, y)
-- Combat ship resumes patrol
```

---

## Implementation Priority

**Recommended Order:**
1. **Tech Level Display** (Easy win, low complexity, high utility)
2. **Auto Explore** (Medium complexity, builds sector navigation experience)
3. **Auto Miner/Scraper Explorer** (Extends existing mods, good incremental step)
4. **Auto Buy/Sell** (Complex but self-contained)
5. **Auto Patrol & Scrap** (Most complex, requires multi-ship coordination)

## Common Technical Patterns

### Sector Navigation
All mods #2-5 require autonomous sector navigation:
```lua
-- Get current sector
local x, y = Sector():getCoordinates()

-- Navigate to target sector
local entity = Entity()
entity:addScriptOnce("ai/patrol.lua", targetX, targetY)
```

### Multi-Ship Coordination
Mods #2 and #5 require ship-to-ship communication:
```lua
-- Ship A broadcasts signal
broadcastInvokeClientFunction("onSignalReceived", signalType, data)

-- Ship B receives and responds
function ModuleName.onSignalReceived(signalType, data)
    if signalType == "SECTOR_CLEARED" then
        -- Navigate to sector and scrap
    end
end
callable(ModuleName, "onSignalReceived")
```

### State Persistence
All mods require sector transition handling:
```lua
function ModuleName.secure()
    return {
        state = currentState,
        targetSector = {x = targetX, y = targetY},
        patrolRegion = patrolRegion,
        -- Save all state
    }
end

function ModuleName.restore(data)
    if data then
        currentState = data.state
        targetX, targetY = data.targetSector.x, data.targetSector.y
        patrolRegion = data.patrolRegion
    end
end
```

## Architecture Notes

### Client-Server Separation
- **Server:** All game logic, entity management, navigation, combat
- **Client:** UI, user input, status displays
- **RPC:** Communication between client and server

### Performance Considerations
- Use sector queries sparingly (expensive operations)
- Cache sector data when possible
- Update intervals: 1-3 seconds for active operations
- Use longer intervals (5-10s) for patrol/exploration checks

### Integration Points
- Existing MiningAlgorithm/ScrapAlgorithm for #4
- Avorion's autopilot system for navigation reference
- Trade system API for #2
- Galaxy map UI for #3
- Fighter AI patterns from existing mods

## Version Planning

Each mod should follow semantic versioning:
- **v1.0.0** - Initial release with core functionality
- **v1.x.x** - Feature additions and improvements
- **v2.0.0** - Major architectural changes or breaking changes

All versions should be committed to git with version number in commit message.
