-- data/scripts/entity/autominingcontroller.lua v3
-- Fixed: Fighters now ignore mothership orders + proper state management
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("callable")

-- namespace AutoMiningController
AutoMiningController = {}

-- Configuration
local updateInterval = 3.0
local minResourceThreshold = 1
local resourcesPerFighter = 1000
local maxRange = 200000

-- State
local enabled = false
local timePassed = 0
local assignedFighters = {}
local asteroidAssignments = {}

-- Client-side cached stats
local cachedFighterCount = 0
local cachedAsteroidCount = 0
local cachedCargoPercent = 0

function AutoMiningController.initialize()
    if onClient() then
        AutoMiningController.initUI()
        invokeServerFunction("requestStateUpdate")
    end
    
    if onServer() then
        local entity = Entity()
        if entity then
            Sector():registerCallback("onDestroyed", "onAsteroidDestroyed")
        end
    end
end

function AutoMiningController.getUpdateInterval()
    return 1.0
end

-- =====================================================
-- STATE PERSISTENCE
-- =====================================================

function AutoMiningController.secure()
    return {
        enabled = enabled,
        timePassed = timePassed,
        assignedFighters = assignedFighters,
        asteroidAssignments = asteroidAssignments,
        resourcesPerFighter = resourcesPerFighter,
        maxRange = maxRange
    }
end

function AutoMiningController.restore(data)
    if data then
        enabled = data.enabled or false
        timePassed = data.timePassed or 0
        assignedFighters = data.assignedFighters or {}
        asteroidAssignments = data.asteroidAssignments or {}
        resourcesPerFighter = data.resourcesPerFighter or 1000
        maxRange = data.maxRange or 50000
    end
end

-- =====================================================
-- UI IMPLEMENTATION
-- =====================================================

function AutoMiningController.initUI()
    local res = getResolution()
    local size = vec2(500, 350)
    local menu = ScriptUI()
    
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Auto Mining Controller"
    window.showCloseButton = 1
    window.moveable = 1
    
    menu:registerWindow(window, "Auto Mining Controller")
    
    local yPos = 10
    local statusLabel = window:createLabel(vec2(10, yPos), "Status:", 16)
    statusLabel.fontSize = 18
    statusLabel.bold = true
    
    yPos = yPos + 30
    AutoMiningController.statusText = window:createLabel(vec2(20, yPos), "Inactive", 14)
    AutoMiningController.statusText.color = ColorRGB(1, 0.3, 0.3)
    
    yPos = yPos + 40
    AutoMiningController.toggleButton = window:createButton(Rect(10, yPos, 240, yPos + 40), "Enable Auto Mining", "onToggleClicked")
    
    yPos = yPos + 60
    local statsLabel = window:createLabel(vec2(10, yPos), "Statistics:", 16)
    statsLabel.fontSize = 18
    statsLabel.bold = true
    
    yPos = yPos + 30
    AutoMiningController.assignedFightersLabel = window:createLabel(vec2(20, yPos), "Assigned Fighters: 0", 14)
    
    yPos = yPos + 25
    AutoMiningController.targetedAsteroidsLabel = window:createLabel(vec2(20, yPos), "Targeted Asteroids: 0", 14)
    
    yPos = yPos + 25
    AutoMiningController.cargoLabel = window:createLabel(vec2(20, yPos), "Cargo: 0%", 14)
    
    yPos = yPos + 40
    local settingsLabel = window:createLabel(vec2(10, yPos), "Settings:", 16)
    settingsLabel.fontSize = 18
    settingsLabel.bold = true
    
    yPos = yPos + 30
    window:createLabel(vec2(20, yPos), "Resources per Fighter:", 14)
    AutoMiningController.resourcesPerFighterTextBox = window:createTextBox(Rect(250, yPos, 350, yPos + 25), "onResourcesPerFighterChanged")
    AutoMiningController.resourcesPerFighterTextBox.text = tostring(resourcesPerFighter)
    AutoMiningController.resourcesPerFighterTextBox.allowedCharacters = "0123456789"
    
    yPos = yPos + 35
    window:createLabel(vec2(20, yPos), "Max Range (km):", 14)
    AutoMiningController.maxRangeTextBox = window:createTextBox(Rect(250, yPos, 350, yPos + 25), "onMaxRangeChanged")
    AutoMiningController.maxRangeTextBox.text = tostring(math.floor(maxRange / 1000))
    AutoMiningController.maxRangeTextBox.allowedCharacters = "0123456789"
end

function AutoMiningController.onToggleClicked()
    if onClient() then
        invokeServerFunction("toggleAutoMining")
    end
end

function AutoMiningController.toggleAutoMining()
    if not onServer() then return end
    
    enabled = not enabled
    
    if enabled then
        AutoMiningController.startAutoMining()
    else
        AutoMiningController.stopAutoMining()
    end
    
    broadcastInvokeClientFunction("updateUIStatus", enabled)
    AutoMiningController.syncStatsToClient()
end
callable(AutoMiningController, "toggleAutoMining")

function AutoMiningController.startAutoMining()
    if not onServer() then return end
    
    local entity = Entity()
    if not entity then return end
    
    enabled = true
    assignedFighters = {}
    asteroidAssignments = {}
    
    -- Clear any mothership-level mining AI that might interfere
    if entity:hasComponent(ComponentType.ShipAI) then
        local shipAI = ShipAI(entity.id)
        if shipAI then
            -- Set to passive to prevent ship AI from controlling fighters
            shipAI:setPassive()
        end
    end
    
    print("[AutoMiner] Auto Mining started")
end

function AutoMiningController.stopAutoMining()
    if not onServer() then return end
    
    enabled = false
    
    local entity = Entity()
    if entity and entity:hasComponent(ComponentType.FighterController) then
        local controller = FighterController(entity.id)
        for squad = 0, 9 do
            local fighters = {controller:getDeployedFighters(squad)}
            for _, fighter in pairs(fighters) do
                if valid(fighter) then
                    local ai = FighterAI(fighter.id)
                    if ai then
                        -- Re-enable mothership orders
                        ai.ignoreMothershipOrders = false
                        ai:setOrders(FighterOrders.None, Uuid())
                    end
                end
            end
        end
    end
    
    assignedFighters = {}
    asteroidAssignments = {}
    
    print("[AutoMiner] Auto Mining stopped")
end

function AutoMiningController.disableAutoMining()
    AutoMiningController.stopAutoMining()
    return 0
end
callable(AutoMiningController, "disableAutoMining")

function AutoMiningController.updateUIStatus(isEnabled)
    if not onClient() then return end
    if not AutoMiningController.statusText then return end
    
    enabled = isEnabled
    
    if isEnabled then
        AutoMiningController.statusText.caption = "Active"
        AutoMiningController.statusText.color = ColorRGB(0.3, 1, 0.3)
        AutoMiningController.toggleButton.caption = "Disable Auto Mining"
    else
        AutoMiningController.statusText.caption = "Inactive"
        AutoMiningController.statusText.color = ColorRGB(1, 0.3, 0.3)
        AutoMiningController.toggleButton.caption = "Enable Auto Mining"
    end
end
callable(AutoMiningController, "updateUIStatus")

function AutoMiningController.onResourcesPerFighterChanged()
    local text = AutoMiningController.resourcesPerFighterTextBox.text
    local value = tonumber(text)
    if value and value > 0 then
        invokeServerFunction("setResourcesPerFighter", value)
    end
end

function AutoMiningController.setResourcesPerFighter(value)
    if onServer() then
        resourcesPerFighter = value
    end
end
callable(AutoMiningController, "setResourcesPerFighter")

function AutoMiningController.onMaxRangeChanged()
    local text = AutoMiningController.maxRangeTextBox.text
    local value = tonumber(text)
    if value and value > 0 then
        invokeServerFunction("setMaxRange", value * 1000)
    end
end

function AutoMiningController.setMaxRange(value)
    if onServer() then
        maxRange = value
    end
end
callable(AutoMiningController, "setMaxRange")

-- =====================================================
-- CLIENT/SERVER SYNC
-- =====================================================

function AutoMiningController.requestStateUpdate()
    if onClient() then
        invokeServerFunction("syncStatsToClient")
    end
end
callable(AutoMiningController, "requestStateUpdate")

function AutoMiningController.syncStatsToClient()
    if not onServer() then return end
    
    local entity = Entity()
    if not entity then return end
    
    local fighterCount = 0
    for _ in pairs(assignedFighters) do
        fighterCount = fighterCount + 1
    end
    
    local asteroidCount = 0
    for _ in pairs(asteroidAssignments) do
        asteroidCount = asteroidCount + 1
    end
    
    local cargoPercent = 0
    if entity.maxCargoSpace and entity.maxCargoSpace > 0 then
        cargoPercent = math.floor((entity.occupiedCargoSpace / entity.maxCargoSpace) * 100)
    end
    
    broadcastInvokeClientFunction("updateStats", fighterCount, asteroidCount, cargoPercent)
end
callable(AutoMiningController, "syncStatsToClient")

function AutoMiningController.updateStats(fighterCount, asteroidCount, cargoPercent)
    if not onClient() then return end
    
    cachedFighterCount = fighterCount
    cachedAsteroidCount = asteroidCount
    cachedCargoPercent = cargoPercent
    
    if AutoMiningController.assignedFightersLabel then
        AutoMiningController.assignedFightersLabel.caption = "Assigned Fighters: " .. fighterCount
    end
    if AutoMiningController.targetedAsteroidsLabel then
        AutoMiningController.targetedAsteroidsLabel.caption = "Targeted Asteroids: " .. asteroidCount
    end
    if AutoMiningController.cargoLabel then
        AutoMiningController.cargoLabel.caption = "Cargo: " .. cargoPercent .. "%"
    end
end
callable(AutoMiningController, "updateStats")

function AutoMiningController.updateClient(timeStep)
    if not onClient() then return end
end

-- =====================================================
-- MAIN MINING LOGIC (SERVER)
-- =====================================================

function AutoMiningController.updateServer(timeStep)
    if not enabled then return end
    if not onServer() then return end
    
    timePassed = timePassed + timeStep
    if timePassed < updateInterval then return end
    timePassed = 0
    
    local entity = Entity()
    if not entity then return end
    
    -- Check if cargo is full
    if entity.freeCargoSpace and entity.freeCargoSpace < 1 then
        print("[AutoMiner] Cargo full, stopping")
        AutoMiningController.stopAutoMining()
        broadcastInvokeClientFunction("updateUIStatus", false)
        return
    end
    
    -- Check if entity has fighter controller
    if not entity:hasComponent(ComponentType.FighterController) then
        return
    end
    
    local controller = FighterController(entity.id)
    
    -- Clean up invalid assignments and reassign
    AutoMiningController.cleanupAssignments()
    
    -- Get available fighters
    local availableFighters = AutoMiningController.getAvailableFighters(controller)
    
    if #availableFighters == 0 then
        AutoMiningController.syncStatsToClient()
        return
    end
    
    -- Get nearby asteroids sorted by distance
    local asteroids = AutoMiningController.getNearbyAsteroids(entity)
    
    if #asteroids == 0 then
        print("[AutoMiner] No asteroids found")
        AutoMiningController.syncStatsToClient()
        return
    end
    
    -- Assign fighters to asteroids
    AutoMiningController.assignFightersToAsteroids(availableFighters, asteroids)
    
    -- Sync stats to clients
    AutoMiningController.syncStatsToClient()
end

function AutoMiningController.getAvailableFighters(controller)
    local available = {}
    
    for squad = 0, 9 do
        local fighters = {controller:getDeployedFighters(squad)}
        for _, fighter in pairs(fighters) do
            if valid(fighter) then
                local fighterIndex = fighter.index.string
                if not assignedFighters[fighterIndex] or not AutoMiningController.isFighterBusy(fighter) then
                    table.insert(available, fighter)
                end
            end
        end
    end
    
    return available
end

function AutoMiningController.isFighterBusy(fighter)
    local ai = FighterAI(fighter.id)
    if not ai then return false end
    
    -- Check if fighter has valid target
    local targetId = ai.target
    if not targetId or not valid(targetId) then
        return false
    end
    
    -- Check if target is an asteroid with resources
    local targetEntity = Entity(targetId)
    if not targetEntity or not targetEntity.isAsteroid then
        return false
    end
    
    local resources = 0
    for _, amount in pairs({targetEntity:getMineableResources()}) do
        resources = resources + (amount or 0)
    end
    
    return resources >= minResourceThreshold
end

function AutoMiningController.getNearbyAsteroids(entity)
    local sector = Sector()
    if not sector then return {} end
    
    local asteroids = {}
    local shipPos = entity.translationf
    
    for _, asteroid in pairs({sector:getEntitiesByType(EntityType.Asteroid)}) do
        if valid(asteroid) then
            local resources = 0
            local resourceList = {asteroid:getMineableResources()}
            for _, amount in pairs(resourceList) do
                resources = resources + (amount or 0)
            end
            
            if resources >= minResourceThreshold then
                local distance = length(asteroid.translationf - shipPos)
                
                if distance <= maxRange then
                    table.insert(asteroids, {
                        entity = asteroid,
                        distance = distance,
                        resources = resources,
                        id = asteroid.index.string
                    })
                end
            end
        end
    end
    
    table.sort(asteroids, function(a, b) return a.distance < b.distance end)
    
    return asteroids
end

function AutoMiningController.findNearestAsteroidForFighter(fighter, allAsteroids)
    if not valid(fighter) or #allAsteroids == 0 then
        return nil
    end
    
    local fighterPos = fighter.translationf
    local nearest = nil
    local nearestDist = math.huge
    
    for _, asteroidData in ipairs(allAsteroids) do
        local asteroidId = asteroidData.id
        local assignment = asteroidAssignments[asteroidId]
        
        if assignment then
            local neededFighters = math.max(1, math.ceil(asteroidData.resources / resourcesPerFighter))
            if assignment.fighterCount >= neededFighters then
                goto continue
            end
        end
        
        local dist = length(asteroidData.entity.translationf - fighterPos)
        if dist < nearestDist then
            nearest = asteroidData
            nearestDist = dist
        end
        
        ::continue::
    end
    
    return nearest
end

function AutoMiningController.assignFightersToAsteroids(fighters, asteroids)
    for _, asteroidData in ipairs(asteroids) do
        if #fighters == 0 then break end
        
        local asteroidId = asteroidData.id
        local resources = asteroidData.resources
        local asteroid = asteroidData.entity
        
        local neededFighters = math.max(1, math.ceil(resources / resourcesPerFighter))
        
        local currentAssignment = asteroidAssignments[asteroidId] or {fighterCount = 0, totalResources = resources}
        local stillNeeded = neededFighters - currentAssignment.fighterCount
        
        if stillNeeded > 0 then
            local assigned = 0
            
            for i = #fighters, 1, -1 do
                if assigned >= stillNeeded then break end
                
                local fighter = fighters[i]
                local ai = FighterAI(fighter.id)
                
                if ai then
                    -- CRITICAL FIX: Make fighter ignore mothership orders
                    ai.ignoreMothershipOrders = true
                    
                    -- Clear any existing feedback that might interfere
                    ai:clearFeedback()
                    
                    -- Use Attack order (most reliable for mining)
                    ai:setOrders(FighterOrders.Attack, asteroid.index)
                    
                    local fighterIndex = fighter.index.string
                    assignedFighters[fighterIndex] = {
                        asteroidId = asteroidId,
                        timestamp = os.time()
                    }
                    
                    assigned = assigned + 1
                    currentAssignment.fighterCount = currentAssignment.fighterCount + 1
                    
                    table.remove(fighters, i)
                    
                    print(string.format("[AutoMiner] Assigned fighter %s to asteroid %s (ignoreMothershipOrders=true, Resources: %d, Distance: %.0f)", 
                        fighterIndex, asteroidId, resources, asteroidData.distance))
                end
            end
            
            asteroidAssignments[asteroidId] = currentAssignment
        end
    end
end

function AutoMiningController.cleanupAssignments()
    local sector = Sector()
    if not sector then return end
    
    local entity = Entity()
    if not entity then return end
    
    local allAsteroids = AutoMiningController.getNearbyAsteroids(entity)
    if #allAsteroids == 0 then
        for fighterIndex, _ in pairs(assignedFighters) do
            assignedFighters[fighterIndex] = nil
        end
        asteroidAssignments = {}
        return
    end
    
    for fighterIndex, assignment in pairs(assignedFighters) do
        local asteroidId = assignment.asteroidId
        
        local asteroid = nil
        for _, a in pairs({sector:getEntitiesByType(EntityType.Asteroid)}) do
            if valid(a) and a.index.string == asteroidId then
                asteroid = a
                break
            end
        end
        
        local needsReassignment = false
        
        if asteroid then
            local resources = 0
            for _, amount in pairs({asteroid:getMineableResources()}) do
                resources = resources + (amount or 0)
            end
            
            if resources < minResourceThreshold then
                needsReassignment = true
            end
        else
            needsReassignment = true
        end
        
        if needsReassignment then
            assignedFighters[fighterIndex] = nil
            if asteroidAssignments[asteroidId] then
                asteroidAssignments[asteroidId].fighterCount = asteroidAssignments[asteroidId].fighterCount - 1
                if asteroidAssignments[asteroidId].fighterCount <= 0 then
                    asteroidAssignments[asteroidId] = nil
                end
            end
            
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                local nearestAsteroid = AutoMiningController.findNearestAsteroidForFighter(fighter, allAsteroids)
                
                if nearestAsteroid then
                    local ai = FighterAI(fighter.id)
                    if ai then
                        -- Ensure fighter ignores mothership orders
                        ai.ignoreMothershipOrders = true
                        ai:clearFeedback()
                        
                        -- Use Attack order
                        ai:setOrders(FighterOrders.Attack, nearestAsteroid.entity.index)
                        
                        assignedFighters[fighterIndex] = {
                            asteroidId = nearestAsteroid.id,
                            timestamp = os.time()
                        }
                        
                        local newAssignment = asteroidAssignments[nearestAsteroid.id] or {fighterCount = 0, totalResources = nearestAsteroid.resources}
                        newAssignment.fighterCount = newAssignment.fighterCount + 1
                        asteroidAssignments[nearestAsteroid.id] = newAssignment
                        
                        print(string.format("[AutoMiner] Reassigned fighter %s to nearest asteroid %s (Distance: %.0f)", 
                            fighterIndex, nearestAsteroid.id, 
                            length(nearestAsteroid.entity.translationf - fighter.translationf)))
                    end
                end
            end
        end
    end
end

function AutoMiningController.onAsteroidDestroyed(index)
    if not onServer() then return end
    
    local indexString = index.string
    
    for fighterIndex, assignment in pairs(assignedFighters) do
        if assignment.asteroidId == indexString then
            assignedFighters[fighterIndex] = nil
        end
    end
    
    asteroidAssignments[indexString] = nil
end

function AutoMiningController.getStatus()
    local entity = Entity()
    if not entity then return "No entity" end
    
    local fighterCount = 0
    for _ in pairs(assignedFighters) do
        fighterCount = fighterCount + 1
    end
    
    local asteroidCount = 0
    for _ in pairs(asteroidAssignments) do
        asteroidCount = asteroidCount + 1
    end
    
    local status = string.format("Auto Mining: %s\nFighters: %d\nAsteroids: %d", 
        enabled and "ACTIVE" or "INACTIVE",
        fighterCount,
        asteroidCount)
    
    return status
end
callable(AutoMiningController, "getStatus")

function AutoMiningController.getIcon()
    return "data/textures/icons/pixel/pick.png"
end

function AutoMiningController.interactionPossible()
    local player = Player()
    local entity = Entity()
    if player and entity and player.craft and player.craft.index.value == entity.id.value then
        return true, ""
    end
    return false, ""
end