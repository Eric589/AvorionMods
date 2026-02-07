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
local fighterCount = 0
local distributedFighters = 0
local targetedAsteroids = 0

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
    local size = vec2(400, 380)
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

    -- Clear Resources button
    window:createButton(Rect(10, 255, 200, 285), "Clear Resources", "onClearResources")

    -- Separator
    window:createLine(vec2(10, 295), vec2(390, 295))

    -- Status section
    UiSampleController.distributedFightersLabel = window:createLabel(vec2(10, 310), "Distributed Fighters: 0", 14)
    UiSampleController.targetedAsteroidsLabel = window:createLabel(vec2(10, 335), "Targeted Asteroids: 0", 14)
end

function UiSampleController.getUpdateInterval()
    return 1
end

function UiSampleController.updateClient()
    UiSampleController.countAsteroids()
    invokeServerFunction("countFighters")
end

function UiSampleController.onShowWindow()
    UiSampleController.refreshUI()
    UiSampleController.countAsteroids()
    invokeServerFunction("countFighters")
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
        UiSampleController.countAsteroids()
    end
end

function UiSampleController.onResPerFighterChanged()
    if UiSampleController.resPerFighterTextBox then
        local text = UiSampleController.resPerFighterTextBox.text
        if text == "" then text = "0" end
        resPerFighter = text
        UiSampleController.countAsteroids()
    end
end

-- Server-side fighter counting (FighterController is server-only)
function UiSampleController.countFighters()
    if not onServer() then return end
    local entity = Entity()
    if not valid(entity) then return end
    local count = 0
    local controller = FighterController(entity.id)
    if controller then
        for squad = 0, 9 do
            local fighters = {controller:getDeployedFighters(squad)}
            for _, fighter in pairs(fighters) do
                if valid(fighter) then
                    count = count + 1
                end
            end
        end
    end
    broadcastInvokeClientFunction("updateFighterCount", count)
end
callable(UiSampleController, "countFighters")

function UiSampleController.updateFighterCount(count)
    if not onClient() then return end
    fighterCount = count
    if UiSampleController.fighterCountLabel then
        UiSampleController.fighterCountLabel.caption = "Available Fighters: " .. fighterCount
    end
end
callable(UiSampleController, "updateFighterCount")

-- Client-side asteroid counting (Sector queries work on client)
function UiSampleController.countAsteroids()
    local sector = Sector()
    if not sector then return end
    local count = 0
    local fighters = 0
    local limit = tonumber(minResourceLimit) or 0
    local perFighter = tonumber(resPerFighter) or 1000
    if perFighter <= 0 then perFighter = 1 end
    for _, asteroid in pairs({sector:getEntitiesByType(EntityType.Asteroid)}) do
        if valid(asteroid) then
            local total = 0
            for _, amount in pairs({asteroid:getMineableResources()}) do
                total = total + (amount or 0)
            end
            if total >= limit then
                count = count + 1
                fighters = fighters + math.ceil(total / perFighter)
            end
        end
    end
    targetedAsteroids = count
    distributedFighters = fighters
    if UiSampleController.asteroidCountLabel then
        UiSampleController.asteroidCountLabel.caption = "Available Asteroids: " .. count
    end
    if UiSampleController.distributedFightersLabel then
        UiSampleController.distributedFightersLabel.caption = "Distributed Fighters: " .. distributedFighters
    end
    if UiSampleController.targetedAsteroidsLabel then
        UiSampleController.targetedAsteroidsLabel.caption = "Targeted Asteroids: " .. targetedAsteroids
    end
end

function UiSampleController.onClearResources()
    minResourceLimit = "1000"
    UiSampleController.refreshUI()
    UiSampleController.countAsteroids()
end

function UiSampleController.refreshUI()
    if UiSampleController.toggleBtn then
        UiSampleController.toggleBtn.caption = enabled == 1 and "Disable" or "Enable"
    end
    if UiSampleController.fighterCountLabel then
        UiSampleController.fighterCountLabel.caption = "Available Fighters: " .. fighterCount
    end
    if UiSampleController.distributedFightersLabel then
        UiSampleController.distributedFightersLabel.caption = "Distributed Fighters: " .. distributedFighters
    end
    if UiSampleController.targetedAsteroidsLabel then
        UiSampleController.targetedAsteroidsLabel.caption = "Targeted Asteroids: " .. targetedAsteroids
    end
    if UiSampleController.minResourceTextBox then
        UiSampleController.minResourceTextBox.text = minResourceLimit
    end
    if UiSampleController.resPerFighterTextBox then
        UiSampleController.resPerFighterTextBox.text = resPerFighter
    end
end
