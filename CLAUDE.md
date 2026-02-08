# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This repository contains Avorion game mods written in Lua. Avorion is a space sandbox game, and these mods extend its functionality through the game's scripting API. Target Avorion version: **2.5.11**.

**Active Mods:**
- **FastExploration** (v1.0.x, in development) - Dispatch drones to explore unknown sectors
- **MiningAlgorithm** (Workshop ID: 3610252115, v2.0) - Automated fighter-based asteroid mining
- **ScrapAlgorithm** (Workshop ID: 3610475144, v2.0) - Automated fighter-based wreckage salvaging

**Reference Mods** (in `SampleMods/`, not actively developed — use for code snippets and patterns):
- `2792015591` - ReImproved Harvest AI (fighter target-switching)
- `2794468392` - Auto Return (fighter recall before jumps)
- `3359665253` - Sector Cleaner / lootCleaner (complex UI, RPC patterns, file I/O config)

**Other:**
- **UiSample** - Template mod demonstrating UI integration, commands, and HUD button

## Critical Pitfalls

### Namespace Comment is MANDATORY
Every entity/lib script MUST have `-- namespace NamespaceName` as a comment. Without it, `invokeServerFunction()` and `broadcastInvokeClientFunction()` silently fail — buttons click but nothing happens.

```lua
-- namespace MyController
MyController = {}
```

**Consequences of setting the namespace:**
- ALL functions (including lifecycle callbacks) must be on the namespace table: `MyController.initialize()`, not `function initialize()`
- Global forwarding functions are silently ignored and will break the mod
- Button callback strings use plain names: `"onPress"` not `"MyController.onPress"` — namespace resolution is automatic
- `callable(MyController, "funcName")` is required for any function called via RPC

**Debugging:** If the HUD icon disappears, `getIcon`/`interactionPossible` are probably still globals. If buttons don't work, the namespace comment or `callable()` is missing.

### Booleans Don't Serialize Over RPC
`broadcastInvokeClientFunction()` and `invokeServerFunction()` do NOT serialize Lua booleans. They arrive as `nil` on the receiving end. Use numbers (`0`/`1`) or strings (`"true"`/`"false"`) instead. See `SampleMods/3359665253/data/scripts/lib/lootCleaner.lua` for a working example.

### Entity Validity
Always use `valid(entity)` before accessing entity properties. Entities can be destroyed between updates.

### File Paths
All file paths in `addScript()` calls must use forward slashes, even on Windows.

## Architecture

### Client-Server Model
Avorion uses client-server architecture even in single-player:
- `onServer()` / `onClient()` to check execution context
- Server: game logic, entity management, fighter control
- Client: UI rendering, user input
- Client-to-server: `invokeServerFunction("funcName", args...)` — target function must be registered with `callable()`
- Server-to-client: `broadcastInvokeClientFunction("funcName", args...)` — target function must be registered with `callable()`

### Script Lifecycle Callbacks
- `initialize()` - Called when script first attaches to entity
- `secure()` - Return table of state to save before sector unload
- `restore(data)` - Restore state when sector reloads
- `updateServer(timeStep)` / `updateClient(timeStep)` - Called each tick
- `getUpdateInterval()` - Return tick frequency in seconds

### UI Integration (Client-Side Only)
Mods appear in the HUD via these functions on the namespace table:
- `getIcon()` - Icon path for HUD button
- `interactionPossible(playerIndex)` - When the button is visible
- `getInteractionText()` - Hover text
- `initUI()` - Create window with `ScriptUI()`, register with `menu:registerWindow()`

### Script Attachment Pattern
All mods use `data/scripts/entity/init.lua` to auto-attach controllers to player/alliance ships:
```lua
local entity = Entity()
if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            entity:addScriptOnce("data/scripts/entity/mycontroller.lua")
        end
    end
end
```

Prevent duplicate initialization with entity values:
```lua
local initFlag = entity:getValue("modname_initialized")
if not initFlag then
    entity:setValue("modname_initialized", true)
end
```

### Fighter Management Pattern (MiningAlgorithm / ScrapAlgorithm)
1. Controller attaches via `entity/init.lua`
2. Track fighter-to-target assignments in tables
3. Set `FighterAI.ignoreMothershipOrders = true` and call `ai:clearFeedback()` before issuing orders
4. Use `FighterAI:setOrders()` with `FighterOrders` enum (Attack, Salvage, Mine, None)
5. Monitor target validity in `updateServer()`, reassign on depletion
6. Persist assignments via `secure()` / `restore()`

## Configuration

`modconfig.lua` at repository root controls which mods are loaded:
```lua
scriptCachingEnabled = false  -- Disable for development (enables live reload)
achievementsEnabled = true
enabled = { "ModIdOrWorkshopId", ... }
```

Mods use their folder name or Workshop ID in the `enabled` list. Workshop IDs in `modinfo.lua` get replaced after Steam upload.

## Testing Changes

1. With `scriptCachingEnabled = false`, Lua file changes are live-reloaded
2. For entity scripts, toggle the mod off/on via its chat command to force reload
3. For structural changes (new files, init.lua changes), restart Avorion

## Documentation Reference

The `Documentation/` directory contains YAML-formatted Avorion API docs:
- `API-INDEX.yaml` - Master index of all classes and functions
- Individual class files (`FighterAI.yaml`, `Entity.yaml`, `Sector [Server].yaml`, etc.)
- Callback docs (`Entity Callbacks.yaml`, `Sector Callbacks.yaml`)

## Version Convention

Mods in this repository use **1.0.x** patch versioning during development. Update the patch number in `modinfo.lua` for each release.

All mods declare Avorion version compatibility in `modinfo.lua`:
```lua
dependencies = {
    {id = "Avorion", max = "2.5.11"}
}
```
