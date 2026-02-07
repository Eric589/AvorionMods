-- Simple UI Sample Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace UiSampleController

UiSampleController = {}

-- State (use numbers instead of booleans - booleans don't serialize over Avorion RPC)
local enabled = 0
local minResourceLimit = "1000"
local resPerFighter = "1000"

function UiSampleController.getIcon()
    return "data/icon/icon.png"
end

function UiSampleController.interactionPossible(playerIndex)
    if onServer() then return false end
    local player = Player()
    local entity = Entity()
    if player.craft.index.value == entity.id.value then
        return true, ""
    else
        return false, ""
    end
end

function UiSampleController.getInteractionText()
    return "UI Sample"
end

function UiSampleController.initialize()
    if onServer() then
        local entity = Entity()
        if entity then
            local initFlag = entity:getValue("uisample_initialized")
            if not initFlag then
                entity:setValue("uisample_initialized", true)
            end
        end
    end
end

function UiSampleController.secure()
    return {enabled = enabled, minResourceLimit = minResourceLimit, resPerFighter = resPerFighter}
end

function UiSampleController.restore(data)
    if data then
        enabled = data.enabled or 0
        minResourceLimit = data.minResourceLimit or "1000"
        resPerFighter = data.resPerFighter or "1000"
    end
end

function UiSampleController.initUI()
    local res = getResolution()
    local size = vec2(400, 340)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Auto Mining"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Auto Mining")

    -- Info section
    UiSampleController.fighterCountLabel = window:createLabel(vec2(10, 10), "Available Fighters: 0", 14)
    UiSampleController.asteroidCountLabel = window:createLabel(vec2(10, 35), "Available Asteroids: 0", 14)

    -- Separator
    window:createLine(vec2(10, 65), vec2(390, 65))

    -- Enable/Disable button
    UiSampleController.toggleBtn = window:createButton(Rect(10, 80, 390, 115), "Enable", "onToggle")

    -- Minimum Resource Limit
    local label = window:createLabel(vec2(10, 130), "Minimum Resource Limit", 14)
    UiSampleController.minResourceTextBox = window:createTextBox(Rect(10, 155, 200, 185), "onMinResourceChanged")
    UiSampleController.minResourceTextBox.allowedCharacters = "0123456789"
    UiSampleController.minResourceTextBox.text = minResourceLimit

    -- Resources Per Fighter
    label = window:createLabel(vec2(10, 195), "Resources Per Fighter", 14)
    UiSampleController.resPerFighterTextBox = window:createTextBox(Rect(10, 220, 200, 250), "onResPerFighterChanged")
    UiSampleController.resPerFighterTextBox.allowedCharacters = "0123456789"
    UiSampleController.resPerFighterTextBox.text = resPerFighter

    -- Separator
    window:createLine(vec2(10, 260), vec2(390, 260))

    -- Status section
    UiSampleController.distributedFightersLabel = window:createLabel(vec2(10, 275), "Distributed Fighters: 0", 14)
    UiSampleController.targetedAsteroidsLabel = window:createLabel(vec2(10, 300), "Targeted Asteroids: 0", 14)
end

function UiSampleController.onShowWindow()
    UiSampleController.refreshUI()
end

-- Toggle is client-side only, matching the SampleMods pattern
function UiSampleController.onToggle()
    if enabled == 1 then enabled = 0 else enabled = 1 end
    UiSampleController.refreshUI()
end

-- TextBox callbacks - store values when user types
function UiSampleController.onMinResourceChanged()
    if UiSampleController.minResourceTextBox then
        local text = UiSampleController.minResourceTextBox.text
        if text == "" then text = "0" end
        minResourceLimit = text
    end
end

function UiSampleController.onResPerFighterChanged()
    if UiSampleController.resPerFighterTextBox then
        local text = UiSampleController.resPerFighterTextBox.text
        if text == "" then text = "0" end
        resPerFighter = text
    end
end

function UiSampleController.refreshUI()
    if UiSampleController.toggleBtn then
        UiSampleController.toggleBtn.caption = enabled == 1 and "Disable" or "Enable"
    end
    if UiSampleController.fighterCountLabel then
        UiSampleController.fighterCountLabel.caption = "Available Fighters: 0"
    end
    if UiSampleController.asteroidCountLabel then
        UiSampleController.asteroidCountLabel.caption = "Available Asteroids: 0"
    end
    if UiSampleController.distributedFightersLabel then
        UiSampleController.distributedFightersLabel.caption = "Distributed Fighters: 0"
    end
    if UiSampleController.targetedAsteroidsLabel then
        UiSampleController.targetedAsteroidsLabel.caption = "Targeted Asteroids: 0"
    end
    if UiSampleController.minResourceTextBox then
        UiSampleController.minResourceTextBox.text = minResourceLimit
    end
    if UiSampleController.resPerFighterTextBox then
        UiSampleController.resPerFighterTextBox.text = resPerFighter
    end
end
