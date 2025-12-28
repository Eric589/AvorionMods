-- data/scripts/entity/autoscrapingcontroller.lua v2
-- Auto-scraping system with item collection fallback

package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("stringutility")
include("callable")

-- namespace AutoScrapingController
AutoScrapingController = {}

-- =====================================================
-- MODULE-LEVEL FUNCTIONS (REQUIRED FOR AVORION HUD)
-- These MUST be at module level for Avorion to detect them
-- =====================================================

function getIcon(seed, rarity)
    return "mods/ScrapAlgorithm/data/icons/icon.png"
end

function interactionPossible(playerIndex, option)
    if onServer() then return false end
    local player = Player()
    if not player then return false end
    if player.index ~= playerIndex then return false end
    return true
end

function getInteractionText()
    return "Auto Scraper"
end

function initUI()
    return AutoScrapingController.initUI()
end

function initialize()
    return AutoScrapingController.initialize()
end

function getUpdateInterval()
    return AutoScrapingController.getUpdateInterval()
end

function secure()
    return AutoScrapingController.secure()
end

function restore(data)
    return AutoScrapingController.restore(data)
end

function updateServer(timeStep)
    return AutoScrapingController.updateServer(timeStep)
end

function updateClient(timeStep)
    return AutoScrapingController.updateClient(timeStep)
end

-- Configuration
local updateInterval = 1.0
local minValueThreshold = 1  -- Minimum wreckage value to consider
local valuePerFighter = 1000   -- Resource value per fighter
local maxRange = 200000          -- 50km default range
local collectItemsWhenIdle = false  -- Disabled: Fighters can't actually collect loose items

-- State
local enabled = false
local timePassed = 0
local assignedFighters = {}
local wreckageAssignments = {}
local itemAssignments = {}  -- NEW: Track fighters assigned to items

-- Client-side cached stats
local cachedFighterCount = 0
local cachedWreckageCount = 0
local cachedCargoPercent = 0
local cachedTotalWreckageCount = 0  -- Total wreckage in sector

-- Flag to track if this is a duplicate instance
local isDuplicate = false

function AutoScrapingController.initialize()
    if onServer() then
        local entity = Entity()
        if entity then
            -- Use a persistent value to remember initialization across reloads without killing the primary script.
            local initFlag = entity:getValue("autoscraper_initialized")
            if not initFlag then
                entity:setValue("autoscraper_initialized", true)
                print("[AutoScraper] Primary instance initialized on server")
            else
                -- Already initialized (e.g., sector reload); keep this instance running.
                print("[AutoScraper] Instance already initialized on server (reload)")
            end

            -- Clean up duplicates if the script was added multiple times; keep one instance alive.
            local scripts = entity:getScripts()
            local scriptCount = 0
            for _, scriptPath in pairs(scripts) do
                if scriptPath == "data/scripts/entity/autoscrapingcontroller.lua" then
                    scriptCount = scriptCount + 1
                end
            end

            if scriptCount > 1 then
                local duplicates = scriptCount - 1
                print("[AutoScraper] Removing " .. duplicates .. " duplicate script entries...")
                for _ = 1, duplicates do
                    entity:removeScript("data/scripts/entity/autoscrapingcontroller.lua")
                end
            end

            Sector():registerCallback("onDestroyed", "onWreckageDestroyed")
        end
    end

    if onClient() then
        -- Only initialize UI if this isn't a duplicate
        if not isDuplicate then
            AutoScrapingController.initUI()
            invokeServerFunction("requestStateUpdate")
        else
            print("[AutoScraper] Duplicate instance on client, skipping UI initialization")
        end
    end
end

function AutoScrapingController.getUpdateInterval()
    return 1.0
end

-- =====================================================
-- STATE PERSISTENCE
-- =====================================================

function AutoScrapingController.secure()
    return {
        enabled = enabled,
        timePassed = timePassed,
        assignedFighters = assignedFighters,
        wreckageAssignments = wreckageAssignments,
        itemAssignments = itemAssignments,
        valuePerFighter = valuePerFighter,
        maxRange = maxRange,
        collectItemsWhenIdle = collectItemsWhenIdle,
        minValueThreshold = minValueThreshold
    }
end

function AutoScrapingController.restore(data)
    if data then
        enabled = data.enabled or false
        timePassed = data.timePassed or 0
        assignedFighters = data.assignedFighters or {}
        wreckageAssignments = data.wreckageAssignments or {}
        itemAssignments = data.itemAssignments or {}
        valuePerFighter = data.valuePerFighter or 50000
        maxRange = data.maxRange or 50000
        collectItemsWhenIdle = data.collectItemsWhenIdle or true
        minValueThreshold = data.minValueThreshold or 1
    end
end

-- =====================================================
-- UI IMPLEMENTATION
-- =====================================================

-- HUD button: show an icon on the top-left interaction bar to open this UI.
function AutoScrapingController.getIcon()
    return "mods/ScrapAlgorithm/data/icons/recycle.png"
end

-- Always allow the interaction button for the local player while client-side.
function AutoScrapingController.interactionPossible(playerIndex, _)
    if onServer() then return false end
    local player = Player()
    if not player or player.index ~= playerIndex then return false end
    return true
end

-- Optional text shown when hovering the HUD icon.
function AutoScrapingController.getInteractionText()
    return "Auto Scraper"
end

function AutoScrapingController.initUI()
    -- Prevent duplicate UI windows
    if AutoScrapingController.uiInitialized then
        print("[AutoScraper] UI already initialized, skipping duplicate")
        return
    end

    local res = getResolution()
    local size = vec2(500, 600)  -- Increased height for new controls
    local menu = ScriptUI()

    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Auto Scraping Controller"
    window.showCloseButton = 1
    window.moveable = 1

    menu:registerWindow(window, "Auto Scraping Controller")

    AutoScrapingController.uiInitialized = true
    
    local yPos = 10
    local statusLabel = window:createLabel(vec2(10, yPos), "Status:", 16)
    statusLabel.fontSize = 18
    statusLabel.bold = true
    
    yPos = yPos + 30
    AutoScrapingController.statusText = window:createLabel(vec2(20, yPos), "Inactive", 14)
    AutoScrapingController.statusText.color = ColorRGB(1, 0.3, 0.3)
    
    yPos = yPos + 40
    AutoScrapingController.toggleButton = window:createButton(Rect(10, yPos, 240, yPos + 40), "Enable Auto Scraping", "onToggleClicked")

    yPos = yPos + 50
    AutoScrapingController.clearLowValueButton = window:createButton(Rect(10, yPos, 240, yPos + 40), "Clear Low Value Scrap", "onClearLowValueClicked")
    AutoScrapingController.clearLowValueButton.tooltip = "Removes all wreckage below Min Value Threshold"

    yPos = yPos + 60
    local statsLabel = window:createLabel(vec2(10, yPos), "Statistics:", 16)
    statsLabel.fontSize = 18
    statsLabel.bold = true
    
    yPos = yPos + 30
    AutoScrapingController.assignedFightersLabel = window:createLabel(vec2(20, yPos), "Assigned Fighters: 0", 14)

    yPos = yPos + 25
    AutoScrapingController.totalWreckageLabel = window:createLabel(vec2(20, yPos), "Total Wreckage in Sector: 0", 14)

    yPos = yPos + 25
    AutoScrapingController.targetedWreckageLabel = window:createLabel(vec2(20, yPos), "Targeted Wreckage: 0", 14)

    yPos = yPos + 25
    AutoScrapingController.cargoLabel = window:createLabel(vec2(20, yPos), "Cargo: 0%", 14)
    
    yPos = yPos + 40
    local settingsLabel = window:createLabel(vec2(10, yPos), "Settings:", 16)
    settingsLabel.fontSize = 18
    settingsLabel.bold = true
    
    yPos = yPos + 30
    window:createLabel(vec2(20, yPos), "Value per Fighter:", 14)
    AutoScrapingController.valuePerFighterTextBox = window:createTextBox(Rect(250, yPos, 350, yPos + 25), "onValuePerFighterChanged")
    AutoScrapingController.valuePerFighterTextBox.text = tostring(valuePerFighter)
    AutoScrapingController.valuePerFighterTextBox.allowedCharacters = "0123456789"
    
    yPos = yPos + 35
    window:createLabel(vec2(20, yPos), "Max Range (km):", 14)
    AutoScrapingController.maxRangeTextBox = window:createTextBox(Rect(250, yPos, 350, yPos + 25), "onMaxRangeChanged")
    AutoScrapingController.maxRangeTextBox.text = tostring(math.floor(maxRange / 1000))
    AutoScrapingController.maxRangeTextBox.allowedCharacters = "0123456789"

    yPos = yPos + 35
    window:createLabel(vec2(20, yPos), "Min Value Threshold:", 14)
    AutoScrapingController.minValueThresholdTextBox = window:createTextBox(Rect(250, yPos, 350, yPos + 25), "onMinValueThresholdChanged")
    AutoScrapingController.minValueThresholdTextBox.text = tostring(minValueThreshold)
    AutoScrapingController.minValueThresholdTextBox.allowedCharacters = "0123456789"
end

-- =====================================================
-- UI CALLBACKS
-- =====================================================

function AutoScrapingController.onToggleClicked()
    if onClient() then
        invokeServerFunction("toggleAutoScraping")
    end
end

function AutoScrapingController.onClearLowValueClicked()
    if onClient() then
        invokeServerFunction("clearLowValueScrap")
    end
end

function AutoScrapingController.onCollectItemsChanged(checkBox)
    if onClient() then
        invokeServerFunction("setCollectItems", checkBox.checked)
    end
end

function AutoScrapingController.setCollectItems(value)
    if onServer() then
        collectItemsWhenIdle = value
        print("[AutoScraper] Collect items when idle: " .. tostring(value))
    end
end
callable(AutoScrapingController, "setCollectItems")

function AutoScrapingController.toggleAutoScraping()
    if not onServer() then return end
    
    enabled = not enabled
    
    if enabled then
        AutoScrapingController.startAutoScraping()
    else
        AutoScrapingController.stopAutoScraping()
    end
    
    broadcastInvokeClientFunction("updateUIStatus", enabled)
    AutoScrapingController.syncStatsToClient()
end
callable(AutoScrapingController, "toggleAutoScraping")

function AutoScrapingController.startAutoScraping()
    if not onServer() then return end
    
    local entity = Entity()
    if not entity then return end
    
    enabled = true
    assignedFighters = {}
    wreckageAssignments = {}
    itemAssignments = {}
    
    if entity:hasComponent(ComponentType.ShipAI) then
        local shipAI = ShipAI(entity.id)
        if shipAI then
            shipAI:setPassive()
        end
    end
    
    print("[AutoScraper] Auto Scraping started (with item collection)")
end

function AutoScrapingController.stopAutoScraping()
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
                        ai.ignoreMothershipOrders = false
                        ai:setOrders(FighterOrders.None, Uuid())
                    end
                end
            end
        end
    end
    
    assignedFighters = {}
    wreckageAssignments = {}
    itemAssignments = {}
    
    print("[AutoScraper] Auto Scraping stopped")
end

function AutoScrapingController.disableAutoScraping()
    AutoScrapingController.stopAutoScraping()

    -- Clear the initialization flag so the script can be added again later
    local entity = Entity()
    if entity then
        entity:setValue("autoscraper_initialized", nil)
    end

    return 0
end
callable(AutoScrapingController, "disableAutoScraping")

function AutoScrapingController.updateUIStatus(isEnabled)
    if not onClient() then return end
    if not AutoScrapingController.statusText then return end
    
    enabled = isEnabled
    
    if isEnabled then
        AutoScrapingController.statusText.caption = "Active"
        AutoScrapingController.statusText.color = ColorRGB(0.3, 1, 0.3)
        AutoScrapingController.toggleButton.caption = "Disable Auto Scraping"
    else
        AutoScrapingController.statusText.caption = "Inactive"
        AutoScrapingController.statusText.color = ColorRGB(1, 0.3, 0.3)
        AutoScrapingController.toggleButton.caption = "Enable Auto Scraping"
    end
end
callable(AutoScrapingController, "updateUIStatus")

function AutoScrapingController.onValuePerFighterChanged()
    local text = AutoScrapingController.valuePerFighterTextBox.text
    local value = tonumber(text)
    if value and value > 0 then
        invokeServerFunction("setValuePerFighter", value)
    end
end

function AutoScrapingController.setValuePerFighter(value)
    if onServer() then
        valuePerFighter = value
    end
end
callable(AutoScrapingController, "setValuePerFighter")

function AutoScrapingController.onMaxRangeChanged()
    local text = AutoScrapingController.maxRangeTextBox.text
    local value = tonumber(text)
    if value and value > 0 then
        invokeServerFunction("setMaxRange", value * 1000)
    end
end

function AutoScrapingController.setMaxRange(value)
    if onServer() then
        maxRange = value
    end
end
callable(AutoScrapingController, "setMaxRange")

function AutoScrapingController.onMinValueThresholdChanged()
    local text = AutoScrapingController.minValueThresholdTextBox.text
    local value = tonumber(text)
    if value and value >= 0 then
        invokeServerFunction("setMinValueThreshold", value)
    end
end

function AutoScrapingController.setMinValueThreshold(value)
    if onServer() then
        minValueThreshold = value
        print("[AutoScraper] Min value threshold set to: " .. value)
    end
end
callable(AutoScrapingController, "setMinValueThreshold")

function AutoScrapingController.clearLowValueScrap()
    if not onServer() then return end

    local sector = Sector()
    if not sector then return end

    local entity = Entity()
    if not entity then return end

    local clearedCount = 0
    local allWreckages = {sector:getEntitiesByType(EntityType.Wreckage)}

    for _, wreckage in pairs(allWreckages) do
        if valid(wreckage) then
            local value = AutoScrapingController.getWreckageValue(wreckage)
            if value < minValueThreshold then
                sector:deleteEntity(wreckage)
                clearedCount = clearedCount + 1
            end
        end
    end

    print("[AutoScraper] Cleared " .. clearedCount .. " low-value wreckage objects (threshold: " .. minValueThreshold .. ")")

    -- Update the stats after clearing
    AutoScrapingController.syncStatsToClient()
end
callable(AutoScrapingController, "clearLowValueScrap")

-- =====================================================
-- CLIENT/SERVER SYNC
-- =====================================================

function AutoScrapingController.requestStateUpdate()
    if onClient() then
        invokeServerFunction("syncStatsToClient")
    end
end
callable(AutoScrapingController, "requestStateUpdate")

function AutoScrapingController.syncStatsToClient()
    if not onServer() then return end

    local entity = Entity()
    if not entity then return end

    local fighterCount = 0
    for _ in pairs(assignedFighters) do
        fighterCount = fighterCount + 1
    end

    local wreckageCount = 0
    for _ in pairs(wreckageAssignments) do
        wreckageCount = wreckageCount + 1
    end

    -- Count total wreckage in sector
    local totalWreckageCount = 0
    local allWreckages = AutoScrapingController.getNearbyWreckage(entity)
    totalWreckageCount = #allWreckages

    local cargoPercent = 0
    if entity.maxCargoSpace and entity.maxCargoSpace > 0 then
        cargoPercent = math.floor((entity.occupiedCargoSpace / entity.maxCargoSpace) * 100)
    end

    broadcastInvokeClientFunction("updateStats", fighterCount, wreckageCount, cargoPercent, totalWreckageCount)
    -- Sync the enabled status to fix UI not updating when entering sector
    broadcastInvokeClientFunction("updateUIStatus", enabled)
end
callable(AutoScrapingController, "syncStatsToClient")

function AutoScrapingController.updateStats(fighterCount, wreckageCount, cargoPercent, totalWreckageCount)
    if not onClient() then return end

    cachedFighterCount = fighterCount
    cachedWreckageCount = wreckageCount
    cachedCargoPercent = cargoPercent
    cachedTotalWreckageCount = totalWreckageCount or 0

    if AutoScrapingController.assignedFightersLabel then
        AutoScrapingController.assignedFightersLabel.caption = "Assigned Fighters: " .. fighterCount
    end
    if AutoScrapingController.totalWreckageLabel then
        AutoScrapingController.totalWreckageLabel.caption = "Total Wreckage in Sector: " .. cachedTotalWreckageCount
    end
    if AutoScrapingController.targetedWreckageLabel then
        AutoScrapingController.targetedWreckageLabel.caption = "Targeted Wreckage: " .. wreckageCount
    end
    if AutoScrapingController.cargoLabel then
        AutoScrapingController.cargoLabel.caption = "Cargo: " .. cargoPercent .. "%"
    end
end
callable(AutoScrapingController, "updateStats")

function AutoScrapingController.updateClient(_)
    if not onClient() then return end
end

-- =====================================================
-- NEW: ITEM COLLECTION FUNCTIONS
-- =====================================================

function AutoScrapingController.getNearbyCollectibles(entity)
    local sector = Sector()
    if not sector then return {} end

    local items = {}
    local shipPos = entity.translationf
    local mothershipId = entity.index.string

    -- Get all entities in sector
    for _, item in pairs({sector:getEntities()}) do
        if valid(item) then
            -- Exclude the mothership and fighters to prevent self-targeting
            local isFighter = item.type == EntityType.Fighter or item.isFighter
            local isMothership = item.index.string == mothershipId

            if not isFighter and not isMothership then
                -- Check if it's a collectable item (loot, cargo, containers)
                if item.isLoot or item.isContainer or (item:hasComponent(ComponentType.Loot)) then
                    local distance = length(item.translationf - shipPos)

                    if distance <= maxRange then
                        table.insert(items, {
                            entity = item,
                            distance = distance,
                            id = item.index.string
                        })
                    end
                end
            end
        end
    end

    -- Sort by distance (nearest first)
    table.sort(items, function(a, b) return a.distance < b.distance end)

    return items
end

function AutoScrapingController.assignFightersToItems(fighters, items)
    for _, itemData in ipairs(items) do
        if #fighters == 0 then break end
        
        local itemId = itemData.id
        local item = itemData.entity
        
        -- Only assign one fighter per item (items are usually small)
        if not itemAssignments[itemId] then
            local fighter = table.remove(fighters)
            local ai = FighterAI(fighter.id)
            
            if ai then
                ai.ignoreMothershipOrders = true
                ai:clearFeedback()
                
                -- Use Attack order - fighters will automatically collect when they reach the item
                ai:setOrders(FighterOrders.Attack, item.index)
                
                local fighterIndex = fighter.index.string
                assignedFighters[fighterIndex] = {
                    itemId = itemId,
                    timestamp = os.time(),
                    targetType = "item"  -- Mark as item collection
                }
                
                itemAssignments[itemId] = true
                
                print(string.format("[AutoScraper] Assigned fighter %s to collect item %s (Distance: %.0f)", 
                    fighterIndex, itemId, itemData.distance))
            end
        end
    end
end

-- =====================================================
-- HELPER FUNCTIONS
-- =====================================================

function AutoScrapingController.getNearbyWreckage(entity)
    local sector = Sector()
    if not sector then return {} end

    local wreckages = {}
    local shipPos = entity.translationf
    local allWreckages = {sector:getEntitiesByType(EntityType.Wreckage)}

    for _, wreckage in pairs(allWreckages) do
        if valid(wreckage) then
            local distance = length(wreckage.translationf - shipPos)

            if distance <= maxRange then
                local value = AutoScrapingController.getWreckageValue(wreckage)

                if value >= minValueThreshold then
                    table.insert(wreckages, {
                        entity = wreckage,
                        distance = distance,
                        value = value,
                        id = wreckage.index.string
                    })
                end
            end
        end
    end

    -- Sort by distance (nearest first)
    table.sort(wreckages, function(a, b) return a.distance < b.distance end)

    return wreckages
end

function AutoScrapingController.getWreckageValue(wreckage)
    if not wreckage or not valid(wreckage) then return 0 end

    -- Calculate total value of resources in wreckage
    local totalValue = 0
    local plan = wreckage:getPlan()

    if plan then
        local materials = {plan:getMaterialCounts()}
        for i = 1, #materials, 2 do
            local material = materials[i]
            local amount = materials[i + 1]
            if material and amount then
                totalValue = totalValue + (amount * Material(material).costFactor)
            end
        end
    end

    return totalValue
end

function AutoScrapingController.onWreckageDestroyed(index)
    if not onServer() then return end

    local wreckageId = tostring(index)

    -- Clean up assignments when wreckage is destroyed
    if wreckageAssignments[wreckageId] then
        wreckageAssignments[wreckageId] = nil
    end

    -- Clean up fighter assignments that were targeting this wreckage
    for fighterIndex, assignment in pairs(assignedFighters) do
        if assignment.wreckageId == wreckageId then
            assignedFighters[fighterIndex] = nil
        end
    end
end

function AutoScrapingController.getStatus()
    if not onServer() then return 0, nil end

    local entity = Entity()
    if not entity then return 0, "Script not attached to entity" end

    local statusMsg = ""

    if enabled then
        local fighterCount = 0
        for _ in pairs(assignedFighters) do
            fighterCount = fighterCount + 1
        end

        local wreckageCount = 0
        for _ in pairs(wreckageAssignments) do
            wreckageCount = wreckageCount + 1
        end

        statusMsg = string.format("Auto Scraping: ACTIVE\nAssigned Fighters: %d\nTargeted Wreckage: %d",
            fighterCount, wreckageCount)
    else
        statusMsg = "Auto Scraping: INACTIVE"
    end

    return 0, statusMsg
end
callable(AutoScrapingController, "getStatus")

-- =====================================================
-- MAIN SCRAPING LOGIC (SERVER)
-- =====================================================

function AutoScrapingController.updateServer(timeStep)
    if not enabled then return end
    if not onServer() then return end

    timePassed = timePassed + timeStep
    if timePassed < updateInterval then return end
    timePassed = 0

    local entity = Entity()
    if not entity then return end

    -- Check if cargo is full
    if entity.freeCargoSpace and entity.freeCargoSpace < 1 then
        print("[AutoScraper] Cargo full, stopping")
        AutoScrapingController.stopAutoScraping()
        broadcastInvokeClientFunction("updateUIStatus", false)
        return
    end

    if not entity:hasComponent(ComponentType.FighterController) then
        return
    end

    local controller = FighterController(entity.id)

    -- Get wreckage once for efficiency
    local wreckages = AutoScrapingController.getNearbyWreckage(entity)

    -- ACTIVELY MANAGE ALL FIGHTERS - don't wait for them to be "available"
    local availableFighters = {}

    for squad = 0, 9 do
        local fighters = {controller:getDeployedFighters(squad)}
        for _, fighter in pairs(fighters) do
            if valid(fighter) then
                local ai = FighterAI(fighter.id)
                if ai then
                    local fighterIndex = fighter.index.string
                    local targetId = ai.target
                    local hasValidTarget = false

                    -- Check if fighter has a valid target (wreckage ONLY)
                    if targetId and valid(targetId) then
                        local target = Entity(targetId)
                        if target and valid(target) then
                            if target.type == EntityType.Wreckage then
                                hasValidTarget = true
                                -- Ensure this wreckage is still in our assignments
                                local wreckageId = target.index.string
                                if not wreckageAssignments[wreckageId] then
                                    wreckageAssignments[wreckageId] = true
                                end
                            end
                        end
                    end

                    -- If no valid target, make fighter available for reassignment
                    if not hasValidTarget then
                        table.insert(availableFighters, fighter)
                        -- Clear old assignment
                        assignedFighters[fighterIndex] = nil
                    end
                end
            end
        end
    end

    -- Assign available fighters to wreckage
    if #availableFighters > 0 and #wreckages > 0 then
        for _, wreckageData in ipairs(wreckages) do
            if #availableFighters == 0 then break end

            local wreckageId = wreckageData.id
            local wreckage = wreckageData.entity
            local wreckageValue = wreckageData.value

            -- Skip if already assigned
            if wreckageAssignments[wreckageId] then
                goto continue
            end

            -- Calculate how many fighters to assign based on value
            local fightersNeeded = math.max(1, math.ceil(wreckageValue / valuePerFighter))
            fightersNeeded = math.min(fightersNeeded, #availableFighters)

            -- Assign fighters
            for i = 1, fightersNeeded do
                local fighter = table.remove(availableFighters)
                if not fighter then break end

                local ai = FighterAI(fighter.id)
                if ai then
                    ai.ignoreMothershipOrders = true
                    ai:clearFeedback()
                    ai:setOrders(FighterOrders.Salvage, wreckage.index)

                    local fighterIndex = fighter.index.string
                    assignedFighters[fighterIndex] = {
                        wreckageId = wreckageId,
                        timestamp = os.time()
                    }

                    print(string.format("[AutoScraper] Assigned fighter %s to wreckage %s (Value: %.0f, Distance: %.0f)",
                        fighterIndex, wreckageId, wreckageValue, wreckageData.distance))
                end
            end

            wreckageAssignments[wreckageId] = true

            ::continue::
        end
    end

    -- Sync statistics to client periodically
    AutoScrapingController.syncStatsToClient()
end