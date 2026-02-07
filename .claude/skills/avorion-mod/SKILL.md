---
name: avorion-mod
description: Specialized skill for creating and debugging Avorion game mods in Lua. Use when building, patching, or fixing Avorion mod scripts. Handles client-server architecture, UI scripting, fighter control, namespace resolution, RPC calls, and iterative patch development.
argument-hint: "[task description]"
---

# Avorion Mod Development Skill

You are an expert Avorion mod developer. Avorion mods are written in Lua and follow a strict client-server architecture with specific scripting conventions. Getting these conventions wrong causes silent failures that are extremely difficult to debug.

## Task

$ARGUMENTS

## Workflow: Iterative Patch Development

Each invocation builds on previous working results. Follow this process:

### Step 1: Understand Context
- Read all relevant mod files before making changes
- Check git status/diff to understand what has changed recently
- Identify the current working state as the baseline

### Step 2: Plan the Change
- Identify exactly which files need modification
- Determine if changes affect client, server, or both sides
- Check the Documentation/ directory for any API classes you need to use

### Step 3: Implement
- Make minimal, focused changes
- Follow all mandatory patterns listed below

### Step 4: Verify (MANDATORY)
After every change, run through this checklist and fix any issues before reporting completion:

**Namespace Verification:**
- [ ] Every entity/lib script has `-- namespace NamespaceName` comment near the top
- [ ] The namespace comment matches the table name exactly (case-sensitive)
- [ ] ALL functions including lifecycle callbacks (getIcon, interactionPossible, initUI, initialize, secure, restore, onShowWindow, onCloseWindow, getUpdateInterval) are defined as `Namespace.functionName()`, NOT as global `function functionName()`
- [ ] There are NO global forwarding functions - the namespace handles everything

**Client-Server Verification:**
- [ ] UI creation (initUI, window creation, buttons, labels) only runs on client
- [ ] Game logic (entity modification, fighter orders, sector changes) only runs on server
- [ ] `onClient()` / `onServer()` guards are used correctly
- [ ] `invokeServerFunction()` calls reference function names that exist on the namespace table
- [ ] `broadcastInvokeClientFunction()` calls reference function names that exist on the namespace table
- [ ] Every function called via RPC has `callable(Namespace, "functionName")` after its definition

**Entity Verification:**
- [ ] `valid(entity)` is called before accessing entity properties that could be invalidated
- [ ] Entity values use `entity:getValue()` / `entity:setValue()` for persistent flags
- [ ] Script attachment uses `entity:addScriptOnce()` with forward-slash paths

**UI Verification:**
- [ ] Button callbacks reference function names as strings: `"functionName"` (not `"Namespace.functionName"`)
- [ ] With namespace set, Avorion automatically looks up callbacks in the namespace table
- [ ] `interactionPossible()` uses the pattern: `player.craft.index.value == entity.id.value`
- [ ] Window is created with `ScriptUI()`, registered with `menu:registerWindow(window, "Title")`

**State Persistence Verification:**
- [ ] `secure()` returns a serializable table of all state that needs to survive sector transitions
- [ ] `restore(data)` properly handles nil data and restores all state variables
- [ ] State variables are declared as `local` at module scope

## Mandatory Avorion Script Patterns

### Script Template (Entity Script with UI)

```lua
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace MyModName

MyModName = {}

local someState = false

function MyModName.getIcon()
    return "data/icon/icon.png"
end

function MyModName.interactionPossible(playerIndex)
    if onServer() then return false end
    local player = Player()
    local entity = Entity()
    if player.craft.index.value == entity.id.value then
        return true, ""
    else
        return false, ""
    end
end

function MyModName.getInteractionText()
    return "My Mod"
end

function MyModName.initialize()
    if onServer() then
        -- server-side init
    end
end

function MyModName.secure()
    return {someState = someState}
end

function MyModName.restore(data)
    if data then
        someState = data.someState or false
    end
end

function MyModName.initUI()
    local res = getResolution()
    local size = vec2(400, 300)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "My Mod"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "My Mod")

    -- Buttons use string callback names - namespace resolves them automatically
    MyModName.myButton = window:createButton(Rect(10, 10, 200, 40), "Click", "onButtonPress")
end

function MyModName.onShowWindow()
    -- Update UI elements when window opens
end

function MyModName.onButtonPress()
    if onClient() then
        invokeServerFunction("doServerAction")
    end
end

function MyModName.doServerAction()
    if not onServer() then return end
    -- server logic here
    broadcastInvokeClientFunction("updateClientUI", someState)
end
callable(MyModName, "doServerAction")

function MyModName.updateClientUI(state)
    if not onClient() then return end
    -- update UI elements here
end
callable(MyModName, "updateClientUI")
```

### Script Template (init.lua - Script Attachment)

```lua
local entity = Entity()

if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            if not entity:hasScript("path/to/controller.lua") then
                entity:addScriptOnce("path/to/controller.lua")
            end
        end
    end
end
```

### Script Template (Chat Command)

```lua
function execute(sender, commandName, ...)
    local args = {...}
    -- command logic
    return 0, "", ""
end

function getDescription()
    return "Description of the command"
end

function getHelp()
    return "Usage: /commandname [args]"
end
```

## Critical Pitfalls to Avoid

1. **NEVER define global functions when using `-- namespace`** - Avorion ignores globals when a namespace is set. Every function must be `Namespace.functionName()`.

2. **NEVER use `Namespace.functionName` in button callback strings** - Just use `"functionName"`. The namespace resolution handles the lookup.

3. **NEVER forget `callable()`** - Without it, `invokeServerFunction` and `broadcastInvokeClientFunction` silently fail with no error message.

4. **NEVER mix client and server logic** - UI operations on server crash. Entity modifications on client are ignored.

5. **NEVER use backslashes in script paths** - Always use forward slashes: `"data/scripts/entity/controller.lua"`

6. **NEVER assume entities persist** - Always check `valid(entity)` before use. Entities can be destroyed between update frames.

7. **NEVER forget `secure()`/`restore()`** - State is lost on sector transitions without these.

## API Reference

When you need to look up Avorion API details, read the relevant YAML files from the `Documentation/` directory:
- `Documentation/API-INDEX.yaml` - Master index of all classes
- `Documentation/Entity.yaml` - Entity properties and methods
- `Documentation/FighterAI.yaml` - Fighter control
- `Documentation/FighterController.yaml` - Fighter hangar management
- `Documentation/ScriptUI.yaml` - UI system (if available)
- `Documentation/Button [Client] [Client].yaml` - Button properties
- Individual class files for specific API needs

## Reference Mods

Working examples exist in these directories:
- `SampleMods/3359665253/` - Sector Cleaner with full UI (toggle buttons, text inputs, visual state indicators)
- `MiningAlgorithm/` - Automated fighter mining with UI
- `ScrapAlgorithm/` - Automated fighter salvaging with UI

When unsure about a pattern, check these working mods for reference.
