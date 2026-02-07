# AGENTS.md

This file provides operational guidelines for AI coding agents working in this Avorion mods repository.

## Repository Context

This is a collection of **Avorion game mods** written in **Lua**. Avorion is a space sandbox game with a Lua scripting API. The mods extend game functionality through entity scripts, commands, and UI systems.

**Active Mods:**
- **MiningAlgorithm** (Workshop ID: 3610252115) - Automated fighter-based asteroid mining
- **ScrapAlgorithm** (Workshop ID: 3610475144) - Automated fighter-based wreckage salvaging
- **UiSample** - UI testing/example mod

**Target Avorion Version:** 2.5.11

## Build & Test Commands

### Development Workflow

```bash
# No build system - Avorion uses direct Lua script loading
# Scripts are hot-reloaded when scriptCachingEnabled = false in modconfig.lua

# Enable/disable mods by editing modconfig.lua
# Set scriptCachingEnabled = false for development
```

### Testing In-Game

Since this is game mod development, testing requires running Avorion:

1. **Start Avorion** with `scriptCachingEnabled = false` in `modconfig.lua`
2. **Enable mod** via `/autominer on` or `/autoscraper on` commands
3. **Reload scripts** by toggling off/on: `/autominer off && /autominer on`
4. **Check status** via `/autominer status` or `/autoscraper status`
5. **Monitor console** for `print()` debug output (prefixed with `[AutoMiner]` or `[AutoScraper]`)

**Testing Changes:**
- Lua files hot-reload when `scriptCachingEnabled = false`
- Entity scripts require disable/enable cycle to reload
- Structural changes (new files, modinfo.lua) require game restart

### No Traditional Tests

This repository has no unit tests or automated test suite. All testing is manual in-game.

## Code Style Guidelines

### File Structure

```lua
-- Header comment with file path and version/notes
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")        -- Avorion standard libraries
include("stringutility")
include("callable")

-- Namespace declaration
ModuleName = {}

-- Module-level callback forwarding functions (required by Avorion)
function initialize()
    return ModuleName.initialize()
end

-- Implementation in namespace
function ModuleName.initialize()
    -- Implementation
end
```

### Imports/Includes

**Always at top of file:**
```lua
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")        -- For valid(), onServer(), onClient()
include("stringutility")  -- For string manipulation
include("callable")       -- For RPC functions
```

**Do NOT use `require()`** - use Avorion's `include()` system.

### Naming Conventions

- **Namespaces:** PascalCase (e.g., `AutoMiningController`, `AutoScrapingController`)
- **Functions:** camelCase (e.g., `getNearbyAsteroids`, `assignFighters`)
- **Local variables:** camelCase (e.g., `enabled`, `timePassed`, `assignedFighters`)
- **Constants:** camelCase with descriptive names (e.g., `updateInterval`, `maxRange`)
- **Module-level callbacks:** lowercase Avorion convention (e.g., `initialize`, `updateServer`)

### Variable Declarations

```lua
-- Configuration constants at top of namespace
local updateInterval = 3.0
local minResourceThreshold = 1
local resourcesPerFighter = 1000

-- State variables
local enabled = false
local assignedFighters = {}
local asteroidAssignments = {}

-- Client-side cached data (separate from server state)
local cachedFighterCount = 0
local cachedAsteroidCount = 0
```

### Types (Lua - dynamically typed)

Lua is dynamically typed. Use **type checking** for safety:

```lua
local value = tonumber(text)
if value and value > 0 then
    -- Use value
end

if not valid(entity) then return end  -- Avorion's validity check
```

### Comments

```lua
-- Single line comments for brief explanations

-- =====================================================
-- SECTION HEADERS (all caps, separator lines)
-- =====================================================

-- Describe complex logic before implementation
-- Explain WHY, not WHAT (code shows what)
```

### Error Handling

**No exceptions in Lua** - use explicit checks:

```lua
-- Check entity validity before use
if not entity or not valid(entity) then return end

-- Check component existence
if not entity:hasComponent(ComponentType.FighterController) then
    return
end

-- Check function results
local ok, result = entity:invokeFunction("path/script.lua", "functionName")
if ok == 0 and result then
    -- Use result
end

-- Validate numeric input
local value = tonumber(input)
if not value or value <= 0 then
    return  -- or provide default
end
```

### Client-Server Architecture

**CRITICAL:** Avorion uses client-server even in single-player.

```lua
-- Server-side logic
if onServer() then
    -- Game logic, entity management, fighter control
end

-- Client-side logic
if onClient() then
    -- UI updates, user input
end

-- RPC calls (must mark functions callable)
function ModuleName.serverFunction(param)
    if not onServer() then return end
    -- Server logic
end
callable(ModuleName, "serverFunction")

-- Call from client
if onClient() then
    invokeServerFunction("serverFunction", param)
end

-- Broadcast to all clients from server
if onServer() then
    broadcastInvokeClientFunction("updateUI", data)
end
```

### Avorion-Specific Patterns

#### Preventing Duplicate Scripts

```lua
local initFlag = entity:getValue("modname_initialized")
if not initFlag then
    entity:setValue("modname_initialized", true)
    -- Initialize
end

-- Also check for existing scripts
local scripts = entity:getScripts()
for _, scriptPath in pairs(scripts) do
    if scriptPath == "data/scripts/entity/yourscript.lua" then
        -- Already attached
        return
    end
end
```

#### State Persistence (Sector Transitions)

```lua
function ModuleName.secure()
    return {
        enabled = enabled,
        assignedFighters = assignedFighters,
        -- Save all persistent state
    }
end

function ModuleName.restore(data)
    if data then
        enabled = data.enabled or false
        assignedFighters = data.assignedFighters or {}
    end
end
```

#### Fighter Control Pattern

```lua
local ai = FighterAI(fighter.id)
if ai then
    ai.ignoreMothershipOrders = true  -- CRITICAL: prevent ship AI interference
    ai:clearFeedback()                -- Clear previous orders
    ai:setOrders(FighterOrders.Attack, target.index)
end
```

### String Formatting

```lua
-- Use string.format for complex strings
local msg = string.format("Assigned fighter %s to asteroid %s (Resources: %d, Distance: %.0f)", 
    fighterIndex, asteroidId, resources, distance)

-- Use concatenation for simple strings
local status = "Status: " .. (enabled and "Active" or "Inactive")
```

### Iteration Patterns

```lua
-- Iterate table (numeric)
for i = 1, #fighters do
    local fighter = fighters[i]
end

-- Iterate table (backward for removal)
for i = #fighters, 1, -1 do
    table.remove(fighters, i)
end

-- Iterate key-value pairs
for fighterIndex, assignment in pairs(assignedFighters) do
    -- process
end

-- Continue pattern (Lua doesn't have continue)
for _, item in ipairs(items) do
    if condition then
        goto continue
    end
    -- process
    ::continue::
end
```

## File Paths

**Always use forward slashes** in script paths, even on Windows:
```lua
entity:addScript("data/scripts/entity/autominingcontroller.lua")
-- NOT: data\\scripts\\entity\\autominingcontroller.lua
```

## Mod Structure

```
ModName/
├── modinfo.lua              # Metadata, version, dependencies
├── data/
│   ├── scripts/
│   │   ├── commands/        # Chat commands (/command)
│   │   ├── entity/          # Entity controller scripts
│   │   │   └── init.lua     # Auto-attach on spawn (optional)
│   │   └── player/          # Player scripts
│   │       └── init.lua     # Auto-attach on boarding
│   └── icon/                # UI icons
└── thumbnail.png            # Workshop thumbnail
```

## Documentation Reference

The `Documentation/` directory contains YAML-formatted Avorion API documentation. Reference these files when working with Avorion APIs:
- `API-INDEX.yaml` - Master index
- Individual class files (e.g., `FighterAI.yaml`, `Entity.yaml`)
- Callback documentation (`Entity Callbacks.yaml`, `Sector Callbacks.yaml`)

## Common Pitfalls

1. **Forgetting `callable()`** - RPC functions MUST be marked callable
2. **Not checking `onServer()`/`onClient()`** - leads to logic running on wrong side
3. **Entity validity** - always use `valid(entity)` before access
4. **Fighter orders without `ignoreMothershipOrders = true`** - ship AI will override
5. **Duplicate script attachment** - check for existing scripts before `addScript()`
6. **Forward slashes in paths** - backslashes will fail
7. **Client-side game logic** - game state must be managed server-side

## Version Control

- Use semantic versioning in `modinfo.lua`: `major.minor.patch`
- Update version for each Workshop upload
- Commit messages use version numbers: `git commit -m "1.1.7"`

## When Making Changes

1. **Read CLAUDE.md first** - contains architectural patterns and API usage
2. **Check Documentation/** for API reference
3. **Test in-game** with debug prints (no unit tests)
4. **Update version** in `modinfo.lua`
5. **Commit with version number** in message
