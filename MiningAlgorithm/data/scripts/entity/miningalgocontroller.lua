-- Simple UI Sample Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace MiningAlgoController

MiningAlgoController = {}

-- Client state (use numbers instead of booleans - booleans don't serialize over Avorion RPC)
local enabled = 0
local minResourceLimit = "1"
local resPerFighter = "100"
local fighterCount = 0
local distributedFighters = 0
local targetedAsteroids = 0

-- Server state
local assignedFighters = {}
local serverEnabled = 0
local serverMinResource = 1000
local serverResPerFighter = 1000
local settingsChanged = false

function MiningAlgoController.getIcon()
    return "r-mining-laser.png"
end

function MiningAlgoController.interactionPossible(playerIndex)
    if onServer() then return false end
    local player = Player()
    local entity = Entity()
    if player.craft.index.value == entity.id.value then
        return true, ""
    else
        return false, ""
    end
end

function MiningAlgoController.getInteractionText()
    return "UI Sample"
end

function MiningAlgoController.initialize()
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

function MiningAlgoController.secure()
    return {
        enabled = enabled,
        minResourceLimit = minResourceLimit,
        resPerFighter = resPerFighter,
        serverEnabled = serverEnabled,
        serverMinResource = serverMinResource,
        serverResPerFighter = serverResPerFighter,
        assignedFighters = assignedFighters,
        settingsChanged = settingsChanged,
    }
end

function MiningAlgoController.restore(data)
    if data then
        enabled = data.enabled or 0
        minResourceLimit = data.minResourceLimit or "1"
        resPerFighter = data.resPerFighter or "100"
        serverEnabled = data.serverEnabled or 0
        serverMinResource = data.serverMinResource or 1000
        serverResPerFighter = data.serverResPerFighter or 1000
        assignedFighters = data.assignedFighters or {}
        settingsChanged = data.settingsChanged or false
    end
end

function MiningAlgoController.initUI()
    local res = getResolution()
    local size = vec2(400, 395)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Auto Mining"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Auto Mining")

    -- Info section
    MiningAlgoController.fighterCountLabel = window:createLabel(vec2(10, 10), "Available Mining Fighters: 0", 14)
    MiningAlgoController.asteroidCountLabel = window:createLabel(vec2(10, 35), "Available Asteroids: 0", 14)

    -- Separator
    window:createLine(vec2(10, 65), vec2(390, 65))

    -- Enable/Disable button
    MiningAlgoController.toggleBtn = window:createButton(Rect(10, 80, 390, 115), "Enable", "onToggle")

    -- Minimum Resource Limit
    local label = window:createLabel(vec2(10, 130), "Minimum Resource Limit", 14)
    MiningAlgoController.minResourceTextBox = window:createTextBox(Rect(10, 155, 200, 185), "onMinResourceChanged")
    MiningAlgoController.minResourceTextBox.allowedCharacters = "0123456789"
    MiningAlgoController.minResourceTextBox.text = minResourceLimit

    -- Resources Per Fighter
    label = window:createLabel(vec2(10, 195), "Resources Per Fighter", 14)
    MiningAlgoController.resPerFighterTextBox = window:createTextBox(Rect(10, 220, 200, 250), "onResPerFighterChanged")
    MiningAlgoController.resPerFighterTextBox.allowedCharacters = "0123456789"
    MiningAlgoController.resPerFighterTextBox.text = resPerFighter

    -- Clear Resources button with info text
    window:createButton(Rect(10, 255, 250, 285), "Clear Resources", "onClearResources")
    local clearInfoLabel = window:createLabel(vec2(10, 290), "(Deletes asteroids < min resource limit)", 12)
    clearInfoLabel.color = ColorRGB(0.7, 0.7, 0.7)

    -- Separator
    window:createLine(vec2(10, 310), vec2(390, 310))

    -- Status section
    MiningAlgoController.distributedFightersLabel = window:createLabel(vec2(10, 325), "Distributed Fighters: 0", 14)
    MiningAlgoController.targetedAsteroidsLabel = window:createLabel(vec2(10, 350), "Targeted Asteroids: 0", 14)
end

function MiningAlgoController.getUpdateInterval()
    return 1
end

-- Helper function to check if a fighter can mine
-- Check the fighter's actual weapons, not the squad blueprint
function MiningAlgoController.canFighterMine(fighter)
    if not valid(fighter) then return false end
    
    -- Get the fighter's actual Weapons component to check what it really has equipped
    local weapons = Weapons(fighter.id)
    if not weapons then return false end
    
    local entity = Entity()
    if not valid(entity) then return false end
    
    -- Check if the fighter's actual weapons are civil and have mining efficiency
    -- Miners have stoneBestEfficiency > 0, Salvagers have metalBestEfficiency > 0
    if weapons.civil and weapons.stoneBestEfficiency and weapons.stoneBestEfficiency > 0 then
        return true
    else
        return false
    end
end

-- Helper function to release a fighter back to mothership
-- If fighter is >3km away, it will actively fly to ship for faster return
function MiningAlgoController.releaseFighter(fighter, mothership)
    if not valid(fighter) or not valid(mothership) then return end

    local ai = FighterAI(fighter.id)
    if not ai then return end

    -- Set ignoreMothershipOrders to false so fighter returns to default AI
    ai.ignoreMothershipOrders = false
    ai:clearFeedback()

    -- Set fighter to harvest mode at mothership location
    -- This makes fighters return and orbit the mothership
    ai:setOrders(FighterOrders.Harvest, mothership.index)
end

function MiningAlgoController.updateServer()
    if serverEnabled == 0 then return end
    local entity = Entity()
    if not valid(entity) then return end

    -- If settings changed, clear all assignments for full redistribution
    if settingsChanged then
        -- Release all fighters back to orbit mothership
        for fighterIndex, _ in pairs(assignedFighters) do
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                MiningAlgoController.releaseFighter(fighter, entity)
            end
        end
        assignedFighters = {}
        settingsChanged = false
    end

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
                MiningAlgoController.releaseFighter(fighter, entity)
            end
        end
    end

    -- Get qualifying asteroids with resource counts
    local sector = Sector()
    if not sector then return end
    local asteroids = {}
    local qualifyingAsteroidIds = {}
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
                table.insert(asteroids, {entity = asteroid, resources = total, needed = needed})
                qualifyingAsteroidIds[tostring(asteroid.id)] = true
            end
        end
    end
    
    -- Release fighters assigned to non-qualifying asteroids
    for fighterIndex, asteroidId in pairs(assignedFighters) do
        local asteroidKey = tostring(asteroidId)
        if not qualifyingAsteroidIds[asteroidKey] then
            assignedFighters[fighterIndex] = nil
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                MiningAlgoController.releaseFighter(fighter, entity)
            end
        end
    end

    if #asteroids == 0 then
        -- Release all fighters back to default AI
        for fighterIndex, _ in pairs(assignedFighters) do
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                MiningAlgoController.releaseFighter(fighter, entity)
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
                -- Only use fighters that can mine and are not already assigned
                if not assignedFighters[fighterIndex] and MiningAlgoController.canFighterMine(fighter) then
                    table.insert(unassigned, fighter)
                end
            end
        end
    end

    -- FIGHTER-CENTRIC DISTRIBUTION ALGORITHM
    -- Each fighter finds its nearest available asteroid (that still needs more fighters)
    for _, fighterData in ipairs(unassigned) do
        local fighterPos = fighterData.translationf
        local assigned = false
        local bestAsteroid = nil
        local bestDistance = math.huge
        
        -- Find the nearest asteroid that still needs more fighters
        for _, asteroidData in ipairs(asteroids) do
            local key = tostring(asteroidData.entity.id)
            local current = asteroidFighterCount[key] or 0
            
            -- Only consider asteroids that still need more fighters
            if current < asteroidData.needed then
                local dist = distance(fighterPos, asteroidData.entity.translationf)
                if dist < bestDistance then
                    bestDistance = dist
                    bestAsteroid = asteroidData
                end
            end
        end
        
        -- Assign fighter to the nearest available asteroid
        if bestAsteroid then
            local ai = FighterAI(fighterData.id)
            if ai then
                ai.ignoreMothershipOrders = true
                ai:clearFeedback()
                ai:setOrders(FighterOrders.Attack, bestAsteroid.entity.index)
                assignedFighters[fighterData.index.string] = bestAsteroid.entity.id
                local key = tostring(bestAsteroid.entity.id)
                asteroidFighterCount[key] = (asteroidFighterCount[key] or 0) + 1
                assigned = true
            end
        end
        
        -- No asteroid needs more fighters, release to default AI
        if not assigned then
            MiningAlgoController.releaseFighter(fighterData, entity)
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

function MiningAlgoController.updateClient()
    MiningAlgoController.countAsteroids()
    invokeServerFunction("countFighters")
end

function MiningAlgoController.onShowWindow()
    MiningAlgoController.refreshUI()
    MiningAlgoController.countAsteroids()
    invokeServerFunction("countFighters")
end

-- Toggle is client-side only, matching the SampleMods pattern
function MiningAlgoController.onToggle()
    if enabled == 1 then enabled = 0 else enabled = 1 end
    invokeServerFunction("setEnabled", enabled)
    invokeServerFunction("syncSettings", minResourceLimit, resPerFighter)
    MiningAlgoController.refreshUI()
end

-- TextBox callbacks - store values when user types
function MiningAlgoController.onMinResourceChanged()
    if MiningAlgoController.minResourceTextBox then
        local text = MiningAlgoController.minResourceTextBox.text
        if text == "" then text = "0" end
        minResourceLimit = text
        MiningAlgoController.countAsteroids()
        invokeServerFunction("syncSettings", minResourceLimit, resPerFighter)
    end
end

function MiningAlgoController.onResPerFighterChanged()
    if MiningAlgoController.resPerFighterTextBox then
        local text = MiningAlgoController.resPerFighterTextBox.text
        if text == "" then text = "0" end
        resPerFighter = text
        MiningAlgoController.countAsteroids()
        invokeServerFunction("syncSettings", minResourceLimit, resPerFighter)
    end
end

-- Server-side fighter counting (FighterController is server-only)
function MiningAlgoController.countFighters()
    if not onServer() then return end
    local entity = Entity()
    if not valid(entity) then return end
    local count = 0
    local controller = FighterController(entity.id)
    if controller then
        for squad = 0, 9 do
            local fighters = {controller:getDeployedFighters(squad)}
            for _, fighter in pairs(fighters) do
                if valid(fighter) and MiningAlgoController.canFighterMine(fighter) then
                    count = count + 1
                end
            end
        end
    end
    broadcastInvokeClientFunction("updateFighterCount", count)
end
callable(MiningAlgoController, "countFighters")

function MiningAlgoController.updateFighterCount(count)
    if not onClient() then return end
    fighterCount = count
    if MiningAlgoController.fighterCountLabel then
        MiningAlgoController.fighterCountLabel.caption = "Available Mining Fighters: " .. fighterCount
    end
end
callable(MiningAlgoController, "updateFighterCount")

-- Server RPC: sync enable state from client
function MiningAlgoController.setEnabled(value)
    if not onServer() then return end
    serverEnabled = value
    if serverEnabled == 0 then
        -- Release all fighters back to default AI
        local entity = Entity()
        if valid(entity) then
            for fighterIndex, _ in pairs(assignedFighters) do
                local fighter = Entity(Uuid(fighterIndex))
                if valid(fighter) then
                    MiningAlgoController.releaseFighter(fighter, entity)
                end
            end
        end
        assignedFighters = {}
    end
end
callable(MiningAlgoController, "setEnabled")

-- Server RPC: sync settings from client
function MiningAlgoController.syncSettings(minRes, perFighter)
    if not onServer() then return end
    local newMinResource = tonumber(minRes) or 1000
    local newResPerFighter = tonumber(perFighter) or 1000
    
    -- Check if settings actually changed
    if newMinResource ~= serverMinResource or newResPerFighter ~= serverResPerFighter then
        serverMinResource = newMinResource
        serverResPerFighter = newResPerFighter
        settingsChanged = true
    end
end
callable(MiningAlgoController, "syncSettings")

-- Client RPC: receive actual assignment stats from server
function MiningAlgoController.updateStats(distributed, targeted)
    if not onClient() then return end
    distributedFighters = distributed
    targetedAsteroids = targeted
    if MiningAlgoController.distributedFightersLabel then
        MiningAlgoController.distributedFightersLabel.caption = "Distributed Fighters: " .. distributedFighters
    end
    if MiningAlgoController.targetedAsteroidsLabel then
        MiningAlgoController.targetedAsteroidsLabel.caption = "Targeted Asteroids: " .. targetedAsteroids
    end
end
callable(MiningAlgoController, "updateStats")

-- Client-side asteroid counting (Sector queries work on client)
function MiningAlgoController.countAsteroids()
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
    if MiningAlgoController.asteroidCountLabel then
        MiningAlgoController.asteroidCountLabel.caption = "Available Asteroids: " .. count
    end
    -- When enabled, server provides real distributed/targeted values via updateStats
    if enabled == 0 then
        distributedFighters = 0
        targetedAsteroids = 0
        if MiningAlgoController.distributedFightersLabel then
            MiningAlgoController.distributedFightersLabel.caption = "Distributed Fighters: 0"
        end
        if MiningAlgoController.targetedAsteroidsLabel then
            MiningAlgoController.targetedAsteroidsLabel.caption = "Targeted Asteroids: 0"
        end
    end
end

function MiningAlgoController.onClearResources()
    -- Delete asteroids below current minimum resource threshold
    invokeServerFunction("clearLowResourceAsteroids", minResourceLimit)
    MiningAlgoController.countAsteroids()
end

-- Server RPC: Delete all asteroids with resources below threshold
function MiningAlgoController.clearLowResourceAsteroids(minResStr)
    if not onServer() then return end
    
    local minRes = tonumber(minResStr) or 1000
    local sector = Sector()
    if not sector then return end
    
    local deleted = 0
    for _, asteroid in pairs({sector:getEntitiesByType(EntityType.Asteroid)}) do
        if valid(asteroid) then
            local total = 0
            for _, amount in pairs({asteroid:getMineableResources()}) do
                total = total + (amount or 0)
            end
            if total < minRes then
                sector:deleteEntity(asteroid)
                deleted = deleted + 1
            end
        end
    end
    
end
callable(MiningAlgoController, "clearLowResourceAsteroids")

function MiningAlgoController.refreshUI()
    if MiningAlgoController.toggleBtn then
        MiningAlgoController.toggleBtn.caption = enabled == 1 and "Disable" or "Enable"
    end
    if MiningAlgoController.fighterCountLabel then
        MiningAlgoController.fighterCountLabel.caption = "Available Mining Fighters: " .. fighterCount
    end
    if MiningAlgoController.distributedFightersLabel then
        MiningAlgoController.distributedFightersLabel.caption = "Distributed Fighters: " .. distributedFighters
    end
    if MiningAlgoController.targetedAsteroidsLabel then
        MiningAlgoController.targetedAsteroidsLabel.caption = "Targeted Asteroids: " .. targetedAsteroids
    end
    if MiningAlgoController.minResourceTextBox then
        MiningAlgoController.minResourceTextBox.text = minResourceLimit
    end
    if MiningAlgoController.resPerFighterTextBox then
        MiningAlgoController.resPerFighterTextBox.text = resPerFighter
    end
end
