# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains Avorion game mods written in Lua. Avorion is a space sandbox game, and these mods extend its functionality through the game's scripting API.

**Current Mods:**
- **MiningAlgorithm** (Workshop ID: 3610252115) - Automated fighter-based asteroid mining with intelligent resource distribution
- **ScrapAlgorithm** (Workshop ID: 3610475144) - Automated fighter-based wreckage salvaging system

Both mods are currently at version 1.1.6 and target Avorion version 2.5.11.

## Architecture Overview

### Avorion Mod Structure

Each mod follows Avorion's standard structure:
```
ModName/
├── modinfo.lua          # Mod metadata, dependencies, version info
├── data/
│   ├── scripts/
│   │   ├── commands/    # Chat commands (/autominer, /autoscraper)
│   │   ├── entity/      # Controller scripts attached to ships
│   │   └── player/      # Player-level scripts (auto-attach controllers)
│   └── icon/           # UI icons
└── thumbnail.png       # Workshop thumbnail
```

### Client-Server Architecture

Avorion uses a client-server architecture even in single-player. Scripts must be aware of execution context:
- Use `onServer()` to check if code is running server-side
- Use `onClient()` to check if code is running client-side
- Server handles game logic, entity management, fighter control
- Client handles UI rendering and user input
- Communication between client/server uses RPC via `invokeServerFunction()` and `broadcastInvokeClientFunction()`
- Functions called via RPC must be marked with `callable()`

### Script Lifecycle Callbacks

Avorion scripts use specific lifecycle callbacks:
- `initialize()` - Called when script is first attached to entity
- `secure()` - Save state before sector unload (return table of data)
- `restore(data)` - Restore state when sector reloads
- `updateServer(timeStep)` - Called every frame on server
- `updateClient(timeStep)` - Called every frame on client
- `getUpdateInterval()` - Return update frequency in seconds

### Fighter Management Pattern

Both mods implement automated fighter control with this pattern:

1. **Script Attachment**: Controller script attaches to player ships via `player/init.lua` when boarding
2. **Fighter Assignment**: Track which fighters are assigned to which targets (asteroids/wreckage)
3. **Ignore Mothership Orders**: Set `FighterAI.ignoreMothershipOrders = true` to prevent ship AI from interfering
4. **Order Management**: Use `FighterAI:setOrders()` with appropriate FighterOrders enum (Attack, Salvage, etc.)
5. **Cleanup and Reassignment**: Monitor target validity and reassign fighters when targets are depleted
6. **State Persistence**: Save assignments in `secure()` and restore in `restore()` for sector transitions

### UI Integration

Mods appear in Avorion's HUD via module-level functions:
- `getIcon()` - Return icon path for HUD button
- `interactionPossible(playerIndex)` - Control when UI button is visible
- `getInteractionText()` - Hover text for HUD button
- `initUI()` - Create UI window using ScriptUI API

UI is client-only. Create windows with `ScriptUI()`, use callbacks for user interactions, and sync state to server via `invokeServerFunction()`.

## Key Patterns and Conventions

### Preventing Duplicate Scripts

Both mods use a pattern to prevent duplicate script attachment:
```lua
local initFlag = entity:getValue("modname_initialized")
if not initFlag then
    entity:setValue("modname_initialized", true)
    -- Initialize
end
```

Entity values persist across sector reloads. Check for existing scripts before adding with `entity:getScripts()`.

### Resource Calculation

**MiningAlgorithm**:
- Uses `asteroid:getMineableResources()` to get resource amounts
- Assigns 1 fighter per 1000 resources (configurable)
- Distance-based prioritization (nearest first)

**ScrapAlgorithm**:
- Calculates wreckage value from `plan:getMaterialCounts()`
- Multiplies material amounts by `Material(type).costFactor`
- Assigns 1 fighter per 1000 value (configurable)
- Includes min value threshold to filter low-value wreckage

### Entity Validity Checks

Always use `valid(entity)` before accessing entity properties. Entities can be destroyed between updates.

### Namespace Pattern

Both mods use table namespaces (e.g., `AutoMiningController = {}`) with module-level forwarding functions to satisfy Avorion's callback requirements while keeping code organized.

## Documentation Reference

The `Documentation/` directory contains YAML-formatted Avorion API documentation:
- `API-INDEX.yaml` - Master index of all API classes and functions
- Individual class files (e.g., `FighterAI.yaml`, `Entity.yaml`)
- Callback documentation (`Entity Callbacks.yaml`, `Sector Callbacks.yaml`, etc.)

Reference these files when working with Avorion API features.

## Configuration

`modconfig.lua` at repository root enables/disables mods and controls script caching:
```lua
scriptCachingEnabled = false  -- Disable for development
achievementsEnabled = true
enabled = { "3610252115", "3610475144" }  -- Mod IDs
```

## Common Development Tasks

### Testing Changes

1. Modifications to Lua files are live-reloaded when `scriptCachingEnabled = false`
2. For entity scripts, use `/autominer off` then `/autominer on` to reload
3. For structural changes, restart Avorion

### Adding New Commands

1. Create file in `ModName/data/scripts/commands/commandname.lua`
2. Implement `execute(sender, commandName, ...)` function
3. Implement `getDescription()` and `getHelp()` for documentation
4. Command becomes available as `/commandname` in game

### Modifying Fighter Behavior

Fighter control is in entity controller scripts (`autominingcontroller.lua`, `autoscrapingcontroller.lua`):
- Main logic in `updateServer()` function
- Assignment tracking in `assignedFighters` and target assignment tables
- Cleanup/reassignment in `cleanupAssignments()` function
- Always set `ai.ignoreMothershipOrders = true` and call `ai:clearFeedback()` before orders

### UI Modifications

UI is defined in `initUI()` function of controller scripts. Uses Avorion's immediate-mode UI:
- Create elements with `window:createElement(rect, callback)`
- Store references to elements that need updates (e.g., labels, status text)
- Update UI via client functions called from server (use `broadcastInvokeClientFunction()`)

## Version Compatibility

Current target: **Avorion 2.5.11**

Both mods declare max version compatibility in `modinfo.lua`:
```lua
dependencies = {
    {id = "Avorion", max = "2.5.11"}
}
```

When updating for new Avorion versions, check API changes in Documentation/ and update dependency constraints.

## Important Notes

- All file paths in `addScript()` calls use forward slashes, even on Windows
- Workshop IDs are assigned automatically when uploading to Steam Workshop
- Mod IDs in `modinfo.lua` get replaced with Workshop IDs after upload
- Both mods are marked as not server-side-only (`serverSideOnly = false`) to allow UI functionality
- Fighter orders use enums from `FighterOrders` (Attack, Salvage, Mine, None, etc.)
- Cargo space checks use `entity.freeCargoSpace` and `entity.maxCargoSpace` properties
