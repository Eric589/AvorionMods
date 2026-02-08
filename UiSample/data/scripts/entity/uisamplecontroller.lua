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
local settingsChanged = false

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
        settingsChanged = settingsChanged,
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
        settingsChanged = data.settingsChanged or false
    end
end

function UiSampleController.initUI()
    local res = getResolution()
    local size = vec2(400, 395)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Auto Salvaging"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Auto Salvaging")

    -- Info section
    UiSampleController.fighterCountLabel = window:createLabel(vec2(10, 10), "Available Salvaging Fighters: 0", 14)
    UiSampleController.asteroidCountLabel = window:createLabel(vec2(10, 35), "Available Wrecks: 0", 14)

    -- Separator
    window:createLine(vec2(10, 65), vec2(390, 65))

    -- Enable/Disable button
    UiSampleController.toggleBtn = window:createButton(Rect(10, 80, 390, 115), "Enable", "onToggle")

    -- Minimum Resource Limit
    local label = window:createLabel(vec2(10, 130), "Minimum Wreck Value", 14)
    UiSampleController.minResourceTextBox = window:createTextBox(Rect(10, 155, 200, 185), "onMinResourceChanged")
    UiSampleController.minResourceTextBox.allowedCharacters = "0123456789"
    UiSampleController.minResourceTextBox.text = minResourceLimit

    -- Resources Per Fighter
    label = window:createLabel(vec2(10, 195), "Value Per Fighter", 14)
    UiSampleController.resPerFighterTextBox = window:createTextBox(Rect(10, 220, 200, 250), "onResPerFighterChanged")
    UiSampleController.resPerFighterTextBox.allowedCharacters = "0123456789"
    UiSampleController.resPerFighterTextBox.text = resPerFighter

    -- Clear Resources button with info text
    window:createButton(Rect(10, 255, 250, 285), "Clear Wrecks", "onClearResources")
    local clearInfoLabel = window:createLabel(vec2(10, 290), "(Deletes wrecks < min value)", 12)
    clearInfoLabel.color = ColorRGB(0.7, 0.7, 0.7)

    -- Separator
    window:createLine(vec2(10, 310), vec2(390, 310))

    -- Status section
    UiSampleController.distributedFightersLabel = window:createLabel(vec2(10, 325), "Distributed Fighters: 0", 14)
    UiSampleController.targetedAsteroidsLabel = window:createLabel(vec2(10, 350), "Targeted Wrecks: 0", 14)
end

function UiSampleController.getUpdateInterval()
    return 1
end

-- Helper function to check if a fighter can salvage
-- Check the fighter's actual weapons, not the squad blueprint
function UiSampleController.canFighterMine(fighter)
    if not valid(fighter) then return false end
    
    -- Get the fighter's actual Weapons component to check what it really has equipped
    local weapons = Weapons(fighter.id)
    if not weapons then return false end
    
    -- Check if the fighter's actual weapons are civil and have salvaging efficiency
    -- Salvagers have metalBestEfficiency > 0, Miners have stoneBestEfficiency > 0
    if weapons.civil and weapons.metalBestEfficiency and weapons.metalBestEfficiency > 0 then
        return true
    else
        return false
    end
end

-- Helper function to calculate wreckage value
function UiSampleController.getWreckageValue(wreckage)
    if not wreckage or not valid(wreckage) then return 0 end

    -- Use Entity's built-in getPlanResourceValue which returns material amounts
    -- Returns multiple doubles representing material values
    local values = {wreckage:getPlanResourceValue()}
    
    local totalValue = 0
    for _, value in pairs(values) do
        totalValue = totalValue + (value or 0)
    end

    return totalValue
end

-- Helper function to release a fighter back to mothership
function UiSampleController.releaseFighter(fighter, mothership)
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

function UiSampleController.updateServer()
    if serverEnabled == 0 then return end
    local entity = Entity()
    if not valid(entity) then return end

    -- If settings changed, clear all assignments for full redistribution
    if settingsChanged then
        -- Release all fighters back to orbit mothership
        for fighterIndex, _ in pairs(assignedFighters) do
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                UiSampleController.releaseFighter(fighter, entity)
            end
        end
        assignedFighters = {}
        settingsChanged = false
    end

    -- Cleanup invalid assignments and release fighters back to default AI
    for fighterIndex, wreckageId in pairs(assignedFighters) do
        local fighter = Entity(Uuid(fighterIndex))
        if not valid(fighter) then
            assignedFighters[fighterIndex] = nil
        else
            local needsRelease = false
            local wreckage = Entity(wreckageId)
            if not valid(wreckage) then
                needsRelease = true
            else
                local value = UiSampleController.getWreckageValue(wreckage)
                if value < serverMinResource then
                    needsRelease = true
                end
            end
            if needsRelease then
                assignedFighters[fighterIndex] = nil
                UiSampleController.releaseFighter(fighter, entity)
            end
        end
    end

    -- Get qualifying wreckage with value
    local sector = Sector()
    if not sector then return end
    local wrecks = {}
    local qualifyingWreckIds = {}
    for _, wreckage in pairs({sector:getEntitiesByType(EntityType.Wreckage)}) do
        if valid(wreckage) then
            local value = UiSampleController.getWreckageValue(wreckage)
            if value >= serverMinResource then
                local perFighter = serverResPerFighter
                if perFighter <= 0 then perFighter = 1 end
                local needed = math.max(1, math.ceil(value / perFighter))
                table.insert(wrecks, {entity = wreckage, resources = value, needed = needed})
                qualifyingWreckIds[tostring(wreckage.id)] = true
            end
        end
    end
    
    -- Release fighters assigned to non-qualifying wreckage
    for fighterIndex, wreckageId in pairs(assignedFighters) do
        local wreckageKey = tostring(wreckageId)
        if not qualifyingWreckIds[wreckageKey] then
            assignedFighters[fighterIndex] = nil
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                UiSampleController.releaseFighter(fighter, entity)
            end
        end
    end

    if #wrecks == 0 then
        -- Release all fighters back to default AI
        for fighterIndex, _ in pairs(assignedFighters) do
            local fighter = Entity(Uuid(fighterIndex))
            if valid(fighter) then
                UiSampleController.releaseFighter(fighter, entity)
            end
        end
        assignedFighters = {}
        broadcastInvokeClientFunction("updateStats", 0, 0)
        return
    end

    -- Count how many fighters are already assigned to each wreck
    local wreckFighterCount = {}
    for _, wreckageId in pairs(assignedFighters) do
        local key = tostring(wreckageId)
        wreckFighterCount[key] = (wreckFighterCount[key] or 0) + 1
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
                -- Only use fighters that can salvage and are not already assigned
                if not assignedFighters[fighterIndex] and UiSampleController.canFighterMine(fighter) then
                    table.insert(unassigned, fighter)
                end
            end
        end
    end

    -- FIGHTER-CENTRIC DISTRIBUTION ALGORITHM
    -- Each fighter finds its nearest available wreck (that still needs more fighters)
    for _, fighterData in ipairs(unassigned) do
        local fighterPos = fighterData.translationf
        local assigned = false
        local bestWreck = nil
        local bestDistance = math.huge
        
        -- Find the nearest wreck that still needs more fighters
        for _, wreckData in ipairs(wrecks) do
            local key = tostring(wreckData.entity.id)
            local current = wreckFighterCount[key] or 0
            
            -- Only consider wrecks that still need more fighters
            if current < wreckData.needed then
                local dist = distance(fighterPos, wreckData.entity.translationf)
                if dist < bestDistance then
                    bestDistance = dist
                    bestWreck = wreckData
                end
            end
        end
        
        -- Assign fighter to the nearest available wreck
        if bestWreck then
            local ai = FighterAI(fighterData.id)
            if ai then
                ai.ignoreMothershipOrders = true
                ai:clearFeedback()
                -- Use Attack order - fighters with salvaging equipment will automatically salvage
                ai:setOrders(FighterOrders.Attack, bestWreck.entity.index)
                assignedFighters[fighterData.index.string] = bestWreck.entity.id
                local key = tostring(bestWreck.entity.id)
                wreckFighterCount[key] = (wreckFighterCount[key] or 0) + 1
                assigned = true
            end
        end
        
        -- No wreck needs more fighters, release to default AI
        if not assigned then
            UiSampleController.releaseFighter(fighterData, entity)
        end
    end

    -- Count actual stats
    local distributed = 0
    local targetedSet = {}
    for _, wreckageId in pairs(assignedFighters) do
        distributed = distributed + 1
        targetedSet[tostring(wreckageId)] = true
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
                if valid(fighter) and UiSampleController.canFighterMine(fighter) then
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
        UiSampleController.fighterCountLabel.caption = "Available Salvaging Fighters: " .. fighterCount
    end
end
callable(UiSampleController, "updateFighterCount")

-- Server RPC: sync enable state from client
function UiSampleController.setEnabled(value)
    if not onServer() then return end
    serverEnabled = value
    if serverEnabled == 0 then
        -- Release all fighters back to default AI
        local entity = Entity()
        if valid(entity) then
            for fighterIndex, _ in pairs(assignedFighters) do
                local fighter = Entity(Uuid(fighterIndex))
                if valid(fighter) then
                    UiSampleController.releaseFighter(fighter, entity)
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
    local newMinResource = tonumber(minRes) or 1000
    local newResPerFighter = tonumber(perFighter) or 1000
    
    -- Check if settings actually changed
    if newMinResource ~= serverMinResource or newResPerFighter ~= serverResPerFighter then
        serverMinResource = newMinResource
        serverResPerFighter = newResPerFighter
        settingsChanged = true
    end
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
        UiSampleController.targetedAsteroidsLabel.caption = "Targeted Wrecks: " .. targetedAsteroids
    end
end
callable(UiSampleController, "updateStats")

-- Client-side wreckage counting (Sector queries work on client)
function UiSampleController.countAsteroids()
    local sector = Sector()
    if not sector then return end
    local count = 0
    local minValue = tonumber(minResourceLimit) or 1000
    
    -- Count wreckage that meets minimum value threshold
    for _, wreckage in pairs({sector:getEntitiesByType(EntityType.Wreckage)}) do
        if valid(wreckage) then
            local value = UiSampleController.getWreckageValue(wreckage)
            if value >= minValue then
                count = count + 1
            end
        end
    end
    
    if UiSampleController.asteroidCountLabel then
        UiSampleController.asteroidCountLabel.caption = "Available Wrecks: " .. count
    end
    -- When enabled, server provides real distributed/targeted values via updateStats
    if enabled == 0 then
        distributedFighters = 0
        targetedAsteroids = 0
        if UiSampleController.distributedFightersLabel then
            UiSampleController.distributedFightersLabel.caption = "Distributed Fighters: 0"
        end
        if UiSampleController.targetedAsteroidsLabel then
            UiSampleController.targetedAsteroidsLabel.caption = "Targeted Wrecks: 0"
        end
    end
end

function UiSampleController.onClearResources()
    -- Delete wreckage below current minimum value threshold
    invokeServerFunction("clearLowResourceAsteroids", minResourceLimit)
    UiSampleController.countAsteroids()
end

-- Server RPC: Delete all wreckage with value below threshold
function UiSampleController.clearLowResourceAsteroids(minResStr)
    if not onServer() then return end
    
    local minRes = tonumber(minResStr) or 1000
    local sector = Sector()
    if not sector then return end
    
    local deleted = 0
    for _, wreckage in pairs({sector:getEntitiesByType(EntityType.Wreckage)}) do
        if valid(wreckage) then
            local value = UiSampleController.getWreckageValue(wreckage)
            if value < minRes then
                sector:deleteEntity(wreckage)
                deleted = deleted + 1
            end
        end
    end
    
    print("[UISample] Cleared " .. deleted .. " wreckage with value < " .. minRes)
end
callable(UiSampleController, "clearLowResourceAsteroids")

function UiSampleController.refreshUI()
    if UiSampleController.toggleBtn then
        UiSampleController.toggleBtn.caption = enabled == 1 and "Disable" or "Enable"
    end
    if UiSampleController.fighterCountLabel then
        UiSampleController.fighterCountLabel.caption = "Available Salvaging Fighters: " .. fighterCount
    end
    if UiSampleController.distributedFightersLabel then
        UiSampleController.distributedFightersLabel.caption = "Distributed Fighters: " .. distributedFighters
    end
    if UiSampleController.targetedAsteroidsLabel then
        UiSampleController.targetedAsteroidsLabel.caption = "Targeted Wrecks: " .. targetedAsteroids
    end
    if UiSampleController.minResourceTextBox then
        UiSampleController.minResourceTextBox.text = minResourceLimit
    end
    if UiSampleController.resPerFighterTextBox then
        UiSampleController.resPerFighterTextBox.text = resPerFighter
    end
end
