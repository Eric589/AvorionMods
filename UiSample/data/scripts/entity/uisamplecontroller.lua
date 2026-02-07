-- Simple UI Sample Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace UiSampleController

UiSampleController = {}

-- Client state (use numbers instead of booleans - booleans don't serialize over Avorion RPC)
local enabled = 0
local minResourceLimit = "1000"
local resPerFighter = "1000"
local fighterCount = 0
local distributedFighters = 0
local targetedAsteroids = 0

-- Server state
local assignedFighters = {}
local serverEnabled = 0
local serverMinResource = 1000
local serverResPerFighter = 1000

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
    return {
        enabled = enabled,
        minResourceLimit = minResourceLimit,
        resPerFighter = resPerFighter,
        serverEnabled = serverEnabled,
        serverMinResource = serverMinResource,
        serverResPerFighter = serverResPerFighter,
        assignedFighters = assignedFighters,
    }
end

function UiSampleController.restore(data)
    if data then
        enabled = data.enabled or 0
        minResourceLimit = data.minResourceLimit or "1000"
        resPerFighter = data.resPerFighter or "1000"
        serverEnabled = data.serverEnabled or 0
        serverMinResource = data.serverMinResource or 1000
        serverResPerFighter = data.serverResPerFighter or 1000
        assignedFighters = data.assignedFighters or {}
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

function UiSampleController.updateServer()
    if serverEnabled == 0 then return end
    local entity = Entity()
    if not valid(entity) then return end

    -- Cleanup invalid assignments and release fighters back to default AI
    for fighterIndex, asteroidId in pairs(assignedFighters) do
        local fighter = Entity(Uuid(fighterIndex))
        if not valid(fighter) then
            assignedFighters[fighterIndex] = nil
        else
            local needsRelease = false
            local asteroid = Entity(asteroidId)
            if not valid(asteroid) then
                needsRelease = true
            else
                local res = 0
                for _, amount in pairs({asteroid:getMineableResources()}) do
                    res = res + (amount or 0)
                end
                if res < serverMinResource then
                    needsRelease = true
                end
            end
            if needsRelease then
                assignedFighters[fighterIndex] = nil
                local ai = FighterAI(fighter.id)
                if ai then
                    ai.ignoreMothershipOrders = false
                    ai:clearFeedback()
                end
            end
        end
    end

    -- Get qualifying asteroids with resource counts and distance
    local sector = Sector()
    if not sector then return end
    local entityPos = entity.translationf
    local asteroids = {}
    for _, asteroid in pairs({sector:getEntitiesByType(EntityType.Asteroid)}) do
        if valid(asteroid) then
            local total = 0
            for _, amount in pairs({asteroid:getMineableResources()}) do
                total = total + (amount or 0)
            end
            if total >= serverMinResource then
                local perFighter = serverResPerFighter
                if perFighter <= 0 then perFighter = 1 end
                local needed = math.max(1, math.ceil(total / perFighter))
                local distance = distance(entityPos, asteroid.translationf)
                table.insert(asteroids, {entity = asteroid, resources = total, needed = needed, distance = distance})
            end
        end
    end
    
    -- Sort asteroids by distance (nearest first)
    table.sort(asteroids, function(a, b) return a.distance < b.distance end)

    if #asteroids == 0 then
        -- Release all fighters back to default AI
        for fighterIndex, _ in pairs(assignedFighters) do
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                local ai = FighterAI(fighter.id)
                if ai then
                    ai.ignoreMothershipOrders = false
                    ai:clearFeedback()
                end
            end
        end
        assignedFighters = {}
        broadcastInvokeClientFunction("updateStats", 0, 0)
        return
    end

    -- Count how many fighters are already assigned to each asteroid
    local asteroidFighterCount = {}
    for _, asteroidId in pairs(assignedFighters) do
        local key = tostring(asteroidId)
        asteroidFighterCount[key] = (asteroidFighterCount[key] or 0) + 1
    end

    -- Get all deployed fighters
    local controller = FighterController(entity.id)
    if not controller then return end
    local unassigned = {}
    for squad = 0, 9 do
        local fighters = {controller:getDeployedFighters(squad)}
        for _, fighter in pairs(fighters) do
            if valid(fighter) then
                local fighterIndex = fighter.index.string
                if not assignedFighters[fighterIndex] then
                    table.insert(unassigned, fighter)
                end
            end
        end
    end

    -- Assign unassigned fighters to asteroids that still need more
    for _, fighterData in ipairs(unassigned) do
        local assigned = false
        for _, asteroidData in ipairs(asteroids) do
            local key = tostring(asteroidData.entity.id)
            local current = asteroidFighterCount[key] or 0
            if current < asteroidData.needed then
                local ai = FighterAI(fighterData.id)
                if ai then
                    ai.ignoreMothershipOrders = true
                    ai:clearFeedback()
                    ai:setOrders(FighterOrders.Attack, asteroidData.entity.index)
                    assignedFighters[fighterData.index.string] = asteroidData.entity.id
                    asteroidFighterCount[key] = current + 1
                    assigned = true
                end
                break
            end
        end
        -- No asteroid needs more fighters, release to default AI
        if not assigned then
            local ai = FighterAI(fighterData.id)
            if ai then
                ai.ignoreMothershipOrders = false
                ai:clearFeedback()
            end
        end
    end

    -- Count actual stats
    local distributed = 0
    local targetedSet = {}
    for _, asteroidId in pairs(assignedFighters) do
        distributed = distributed + 1
        targetedSet[tostring(asteroidId)] = true
    end
    local targeted = 0
    for _ in pairs(targetedSet) do targeted = targeted + 1 end

    broadcastInvokeClientFunction("updateStats", distributed, targeted)
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
    invokeServerFunction("setEnabled", enabled)
    invokeServerFunction("syncSettings", minResourceLimit, resPerFighter)
    UiSampleController.refreshUI()
end

-- TextBox callbacks - store values when user types
function UiSampleController.onMinResourceChanged()
    if UiSampleController.minResourceTextBox then
        local text = UiSampleController.minResourceTextBox.text
        if text == "" then text = "0" end
        minResourceLimit = text
        UiSampleController.countAsteroids()
        invokeServerFunction("syncSettings", minResourceLimit, resPerFighter)
    end
end

function UiSampleController.onResPerFighterChanged()
    if UiSampleController.resPerFighterTextBox then
        local text = UiSampleController.resPerFighterTextBox.text
        if text == "" then text = "0" end
        resPerFighter = text
        UiSampleController.countAsteroids()
        invokeServerFunction("syncSettings", minResourceLimit, resPerFighter)
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

-- Server RPC: sync enable state from client
function UiSampleController.setEnabled(value)
    if not onServer() then return end
    serverEnabled = value
    if serverEnabled == 0 then
        -- Release all fighters back to default AI
        for fighterIndex, _ in pairs(assignedFighters) do
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                local ai = FighterAI(fighter.id)
                if ai then
                    ai.ignoreMothershipOrders = false
                    ai:clearFeedback()
                end
            end
        end
        assignedFighters = {}
    end
end
callable(UiSampleController, "setEnabled")

-- Server RPC: sync settings from client
function UiSampleController.syncSettings(minRes, perFighter)
    if not onServer() then return end
    serverMinResource = tonumber(minRes) or 1000
    serverResPerFighter = tonumber(perFighter) or 1000
end
callable(UiSampleController, "syncSettings")

-- Client RPC: receive actual assignment stats from server
function UiSampleController.updateStats(distributed, targeted)
    if not onClient() then return end
    distributedFighters = distributed
    targetedAsteroids = targeted
    if UiSampleController.distributedFightersLabel then
        UiSampleController.distributedFightersLabel.caption = "Distributed Fighters: " .. distributedFighters
    end
    if UiSampleController.targetedAsteroidsLabel then
        UiSampleController.targetedAsteroidsLabel.caption = "Targeted Asteroids: " .. targetedAsteroids
    end
end
callable(UiSampleController, "updateStats")

-- Client-side asteroid counting (Sector queries work on client)
function UiSampleController.countAsteroids()
    local sector = Sector()
    if not sector then return end
    local count = 0
    local limit = tonumber(minResourceLimit) or 0
    for _, asteroid in pairs({sector:getEntitiesByType(EntityType.Asteroid)}) do
        if valid(asteroid) then
            local total = 0
            for _, amount in pairs({asteroid:getMineableResources()}) do
                total = total + (amount or 0)
            end
            if total >= limit then
                count = count + 1
            end
        end
    end
    if UiSampleController.asteroidCountLabel then
        UiSampleController.asteroidCountLabel.caption = "Available Asteroids: " .. count
    end
    -- When enabled, server provides real distributed/targeted values via updateStats
    if enabled == 0 then
        distributedFighters = 0
        targetedAsteroids = 0
        if UiSampleController.distributedFightersLabel then
            UiSampleController.distributedFightersLabel.caption = "Distributed Fighters: 0"
        end
        if UiSampleController.targetedAsteroidsLabel then
            UiSampleController.targetedAsteroidsLabel.caption = "Targeted Asteroids: 0"
        end
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
