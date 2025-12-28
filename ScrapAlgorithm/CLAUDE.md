# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ScrapAlgorithm is an Avorion game mod that automates fighter deployment for salvaging wreckage. The mod efficiently distributes salvaging fighters to nearby wreckage based on resource value, managing assignments and preventing duplicate work.

## Architecture

This is an **Avorion mod** written in Lua following Avorion's client-server script architecture pattern:

### Client-Server Split
- **Server-side**: All game logic, fighter assignments, wreckage tracking, state persistence
- **Client-side**: UI rendering, user input handling, display updates
- **Communication**: Uses `invokeServerFunction()` and `broadcastInvokeClientFunction()` for client-server RPC

### Core Components

1. **Player Init Script** (`data/scripts/player/init.lua`)
   - Auto-attaches the controller script when players board/switch ships
   - Uses `onCraftChanged` callback to detect ship switches
   - Prevents duplicate script instances using `autoscraper_initialized` flag

2. **Chat Command Handler** (`data/scripts/commands/autoscraper.lua`)
   - Provides `/autoscraper [on|off|status]` command interface
   - Server-side script management (add/remove/status)
   - Duplicate detection and cleanup

3. **Main Controller** (`data/scripts/entity/autoscrapingcontroller.lua`)
   - **Namespaced**: All functions under `AutoScrapingController` namespace
   - **HUD Integration**: Uses `getIcon()` and `interactionPossible()` to show UI button in game HUD
   - **State Persistence**: Implements `secure()`/`restore()` for sector transitions
   - **Update Loop**: Server-side `updateServer(timeStep)` runs at 1-second intervals
   - **Fighter Management**: Assigns fighters based on wreckage value and distance
   - **UI**: ScriptUI-based window with status, statistics, and configurable settings

### Key Patterns

**Callable Functions**: Server functions callable from client must use:
```lua
callable(AutoScrapingController, "functionName")
```

**Duplicate Prevention**: The mod uses multiple mechanisms to prevent duplicate script instances:
- Persistent `autoscraper_initialized` flag on entities
- Script list checking before adding new instances
- Automatic cleanup of duplicates in `initialize()`

**Fighter Assignment Algorithm**:
- Scans wreckage within configurable range (default 200km)
- Filters by minimum value threshold
- Allocates fighters proportionally to wreckage value (configurable value-per-fighter ratio)
- Sorts targets by distance (nearest first)
- Stops when cargo is full

## Avorion Modding Specifics

**Mod Structure**:
- `modinfo.lua`: Mod metadata, dependencies, version info
- `data/scripts/player/`: Player-level scripts (persistent across ships)
- `data/scripts/commands/`: Chat command handlers
- `data/scripts/entity/`: Entity-attached scripts (ship-specific)
- `data/icons/`: UI resources

**Script Lifecycle**:
- `initialize()`: Called when script is first added to entity
- `secure()`: Called before sector save - return state to persist
- `restore(data)`: Called on sector load - restore persisted state
- `updateServer(timeStep)`: Server-side update loop
- `updateClient(timeStep)`: Client-side update loop (currently unused)

**Component System**: Avorion uses component-based entities:
- Check components with `entity:hasComponent(ComponentType.FighterController)`
- Get component instances: `FighterController(entity.id)`, `FighterAI(fighter.id)`

**Entity Validity**: Always validate entities with `valid(entity)` before use

## Configuration Values

Default settings (stored in controller script, configurable via UI):
- `updateInterval`: 1.0 second
- `valuePerFighter`: 1000 (resources per fighter allocated)
- `maxRange`: 200000 (200km in meters)
- `minValueThreshold`: 1 (minimum wreckage value to consider)

## Testing Notes

Since this is an Avorion mod, testing requires:
- Running within Avorion game environment
- Testing both single-player and multiplayer scenarios
- Verifying client-server sync behavior
- Testing sector transitions (save/restore cycle)
- No automated test framework - manual in-game testing required
