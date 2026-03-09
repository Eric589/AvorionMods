-- Resource Buyer Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
include("callable")
include("goodsindex")
local FactoryMap = include("factorymap")
local SectorSpecifics = include("sectorspecifics")
local TradingUtility = include("tradingutility")

-- Inline docking state machine (ai/dock doesn't exist as a vanilla module)
local DockAI = {}
local DOCK_NONE = 0
local DOCK_FLYING = 1
local DOCK_PULLING = 2
local DOCK_DOCKED = 3
local DOCK_UNDOCKING = 4

local dockPhase = DOCK_NONE
local dockTimer = 0
local dockCallbackDone = false

function DockAI.reset()
    dockPhase = DOCK_NONE
    dockTimer = 0
    dockCallbackDone = false
end

function DockAI.updateDockingUndocking(timeStep, station, waitTime, dockedCB, undockCB)
    local entity = Entity()
    if not valid(entity) or not valid(station) then return end

    if dockPhase == DOCK_NONE then
        dockPhase = DOCK_FLYING
        dockCallbackDone = false
        dockTimer = 0
        ShipAI():setFly(station.translationf, 0)
    end

    if dockPhase == DOCK_FLYING then
        local dp = DockingPositions(station)
        if dp and dp:isInDockingArea(entity) then
            local dockIdx = dp:getFreeDock(entity)
            if dockIdx then
                dp:startPulling(entity, dockIdx)
                dockPhase = DOCK_PULLING
                dockTimer = 0
            end
        elseif not ShipAI().isBusy then
            ShipAI():setFly(station.translationf, 0)
        end
        return
    end

    if dockPhase == DOCK_PULLING then
        dockTimer = dockTimer + timeStep
        local dc = DockingClamps(station)
        if dc and dc:isDocked(entity) then
            dockPhase = DOCK_DOCKED
            dockTimer = 0
        elseif dockTimer > 15 then
            -- Timeout: assume close enough to trade
            dockPhase = DOCK_DOCKED
            dockTimer = 0
        end
        return
    end

    if dockPhase == DOCK_DOCKED then
        if not dockCallbackDone then
            dockCallbackDone = true
            dockedCB(entity, station)
        end
        dockTimer = dockTimer + timeStep
        if dockTimer >= waitTime then
            -- Undock
            local dc = DockingClamps(station)
            if dc then dc:undock(entity) end
            local dp = DockingPositions(station)
            if dp then dp:stopPulling(entity) end
            dockPhase = DOCK_UNDOCKING
        end
        return
    end

    if dockPhase == DOCK_UNDOCKING then
        undockCB(entity, "done")
        dockPhase = DOCK_NONE
    end
end

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace ResourceBuyerController
ResourceBuyerController = {}

-- Shopping list: array of {name = "Good Name", quantity = 10}
local shoppingList = {}

-- Set of good names available for purchase nearby (server-side)
local availableGoods = {}

-- Scan state
local scanState = "idle" -- "idle", "scanning", "done"
local pendingDrones = {} -- sectors queued for drone dispatch
local droneTargets = {} -- all sectors drones were sent to
local dronesReceived = {} -- set of sector keys that returned data
local dispatchTimer = 0
local scanElapsed = 0
local SCAN_TIMEOUT = 60
local totalDroneCount = 0

-- Buy run state machine
local BUY_IDLE = 0
local BUY_SCOUTING = 1
local BUY_JUMPING = 2
local BUY_BUYING = 3
local BUY_RETURNING = 4

local buyState = BUY_IDLE
local homeSector = nil        -- {x, y}
local buyRoute = {}           -- ordered: {{x, y, goods = {"Aluminum", ...}}, ...}
local buyRouteIndex = 0
local buyWaypoints = {}       -- jump waypoints to current destination
local waypointIndex = 0
local sectorGoods = {}        -- {["x_y"] = {"Good1", "Good2"}} from drones
local currentGoodIndex = 0    -- which good we're buying at current stop
local resolvedStation = nil   -- cached station index for current buy
local resolvedScript = nil    -- cached merchant script path
local buyResults = {}         -- {"Bought 10x Aluminum", "Steel not found", ...}
local buyQuantities = {}      -- {["Aluminum"] = 5} adjusted quantities for this run

local RELATIONS_THRESHOLD = -30000

-- UI elements
local statusLabel = nil
local goodsCombo = nil
local quantityBox = nil
local listBox = nil
local startButton = nil
local stopButton = nil
local scanButton = nil
local useInventoryBox = nil
local useInventoryChecked = false -- tracked locally since CheckBox.checked is write-only

-- Client-side: parsed shopping list and availability for coloring
local clientItems = {}
local clientAvailable = {}
local clientInventory = {} -- {goodName = amount} from cargo hold

-- Client-side: sorted internal good names, indexed by combo box position
local comboGoodNames = {}

function ResourceBuyerController.getIcon()
    return "cargo-bay.png"
end

function ResourceBuyerController.interactionPossible(playerIndex)
    if onServer() then return false end
    local player = Player()
    local entity = Entity()
    if player.craft.index.value == entity.id.value then
        return true, ""
    else
        return false, ""
    end
end

function ResourceBuyerController.getInteractionText()
    return "Resource Buyer"
end

function ResourceBuyerController.initialize()
    if onServer() then
        local entity = Entity()
        if entity then
            local initFlag = entity:getValue("resourcebuyer_initialized")
            if not initFlag then
                entity:setValue("resourcebuyer_initialized", true)
            end
        end
    end
end

function ResourceBuyerController.initUI()
    local res = getResolution()
    local size = vec2(500, 440)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Resource Buyer"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Resource Buyer")

    -- Row 1: Good selector + quantity input + add button
    local y = 10
    window:createLabel(vec2(10, y + 5), "Good:", 14)
    goodsCombo = window:createComboBox(Rect(60, y, 340, y + 30), "")
    goodsCombo.entriesPerPage = 15

    -- Populate with tradeable goods
    -- level ~= nil filters out ores, scrap, drugs, slaves, etc.
    -- name == good.name filters out backwards-compat aliases (Aluminium->Aluminum, Silicium->Silicon)
    comboGoodNames = {}
    for name, good in pairs(goods) do
        if good.level ~= nil and name == good.name then
            table.insert(comboGoodNames, name)
        end
    end
    table.sort(comboGoodNames, function(a, b) return (a % _t) < (b % _t) end)
    for _, name in ipairs(comboGoodNames) do
        goodsCombo:addEntry(name % _t)
    end

    window:createLabel(vec2(350, y + 5), "Qty:", 14)
    quantityBox = window:createTextBox(Rect(390, y, 440, y + 30), "")
    quantityBox.allowedCharacters = "0123456789"
    quantityBox.maxCharacters = 6
    quantityBox.text = "1"

    window:createButton(Rect(450, y, 490, y + 30), "Add", "onAddGood")

    -- Row 2: Shopping list header + buttons
    y = 50
    window:createLabel(vec2(10, y), "Shopping List:", 14)
    scanButton = window:createButton(Rect(160, y - 5, 260, y + 20), "Scan", "onScan")
    window:createButton(Rect(270, y - 5, 390, y + 20), "Remove", "onRemoveGood")
    useInventoryBox = window:createCheckBox(Rect(395, y - 5, 490, y + 20), "Inventory", "onUseInventoryChanged")

    y = 75
    listBox = window:createListBox(Rect(10, y, 490, y + 230))

    -- Bottom buttons
    y = 320
    startButton = window:createButton(Rect(10, y, 240, y + 40), "Start", "onStart")
    stopButton = window:createButton(Rect(250, y, 490, y + 40), "Stop", "onStop")

    y = 370
    statusLabel = window:createLabel(vec2(10, y), "Status: Idle", 15)
    statusLabel.width = 480
end

function ResourceBuyerController.onShowWindow()
    ResourceBuyerController.refreshList()
    invokeServerFunction("requestUIUpdate")
end

function ResourceBuyerController.onAddGood()
    if not onClient() then return end
    if not goodsCombo then return end

    local idx = goodsCombo.selectedIndex
    if not idx or idx < 0 then return end
    local name = comboGoodNames[idx + 1] -- combo is 0-indexed, Lua table is 1-indexed
    if not name or name == "" then return end

    local qtyText = quantityBox.text
    local qty = tonumber(qtyText)
    if not qty or qty <= 0 then return end

    invokeServerFunction("addGood", name, math.floor(qty))
    quantityBox.text = "1"
end

function ResourceBuyerController.onRemoveGood()
    if not onClient() then return end
    if not listBox then return end
    local selected = listBox.selected
    if selected < 0 then return end
    invokeServerFunction("removeGood", selected)
end

function ResourceBuyerController.onScan()
    if not onClient() then return end
    invokeServerFunction("scanNearbyGoods")
end

function ResourceBuyerController.onUseInventoryChanged(checkBox, checkedStr)
    if not onClient() then return end
    useInventoryChecked = not useInventoryChecked
    -- Refresh cargo data from server and re-render list
    invokeServerFunction("requestUIUpdate")
end

function ResourceBuyerController.onStart()
    if not onClient() then return end
    local useInv = useInventoryChecked
    -- Booleans don't serialize over RPC, use string
    invokeServerFunction("startBuyRun", useInv and "1" or "0")
end

function ResourceBuyerController.onStop()
    if not onClient() then return end
    invokeServerFunction("stopBuyRun")
end

-- ============================================================
-- SERVER FUNCTIONS
-- ============================================================

function ResourceBuyerController.addGood(name, quantity)
    if not onServer() then return end

    -- Resolve canonical name (handles aliases like Aluminium->Aluminum)
    local goodData = goods[name]
    if goodData then name = goodData.name end

    -- Check if good already in list, merge quantities
    for _, item in pairs(shoppingList) do
        if item.name == name then
            item.quantity = item.quantity + quantity
            ResourceBuyerController.sendSyncToClients()
            return
        end
    end

    table.insert(shoppingList, {name = name, quantity = quantity})
    ResourceBuyerController.sendSyncToClients()
end
callable(ResourceBuyerController, "addGood")

function ResourceBuyerController.removeGood(index)
    if not onServer() then return end
    local luaIndex = index + 1
    if luaIndex >= 1 and luaIndex <= #shoppingList then
        table.remove(shoppingList, luaIndex)
    end
    ResourceBuyerController.sendSyncToClients()
end
callable(ResourceBuyerController, "removeGood")

function ResourceBuyerController.scanNearbyGoods()
    if not onServer() then return end
    if scanState == "scanning" then
        broadcastInvokeClientFunction("updateStatus", "Scan already in progress...")
        return
    end
    if buyState ~= BUY_IDLE then
        broadcastInvokeClientFunction("updateStatus", "Cannot scan during buy run")
        return
    end

    local entity = Entity()
    if not valid(entity) then return end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        broadcastInvokeClientFunction("updateStatus", "No hyperspace drive installed")
        return
    end

    broadcastInvokeClientFunction("updateStatus", "Scanning (FactoryMap)...")

    local sx, sy = Sector():getCoordinates()
    local scanRadius = math.ceil(jumpRange)
    local rangeSq = jumpRange * jumpRange

    local map = FactoryMap()
    local from = {x = sx - scanRadius, y = sy - scanRadius}
    local to = {x = sx + scanRadius, y = sy + scanRadius}
    local productions = map:getProductionsMap(from, to)

    -- Build set of goods available for purchase nearby
    availableGoods = {}

    -- Scan current sector for actual station goods
    ResourceBuyerController.scanCurrentSectorGoods()

    -- Extract goods from FactoryMap predictions
    for _, entry in pairs(productions) do
        local coords = entry.coordinates
        local dx = coords.x - sx
        local dy = coords.y - sy
        if dx * dx + dy * dy <= rangeSq then
            local data = entry.data

            if data.productions then
                for _, production in pairs(data.productions) do
                    if production.results then
                        for _, good in pairs(production.results) do
                            availableGoods[good.name] = 1
                        end
                    end
                    if production.garbages then
                        for _, good in pairs(production.garbages) do
                            availableGoods[good.name] = 1
                        end
                    end
                end
            end

            if data.sold then
                for _, sold in pairs(data.sold) do
                    if sold.goods then
                        for _, name in pairs(sold.goods) do
                            availableGoods[name] = 1
                        end
                    end
                end
            end
        end
    end

    -- Debug: log all found goods and shopping list
    local sortedGoods = {}
    for name, _ in pairs(availableGoods) do table.insert(sortedGoods, name) end
    table.sort(sortedGoods)
    print("[ResourceBuyer] Available goods (" .. #sortedGoods .. "): " .. table.concat(sortedGoods, ", "))
    for _, item in pairs(shoppingList) do
        local status = availableGoods[item.name] and "FOUND" or "NOT FOUND"
        print("[ResourceBuyer] Shopping: '" .. item.name .. "' -> " .. status)
    end

    -- Use SectorSpecifics to find sectors with trading posts that need drone scans
    local serverSeed = Server().seed
    local player = Player()
    pendingDrones = {}
    droneTargets = {}
    dronesReceived = {}
    dispatchTimer = 0
    scanElapsed = 0
    totalDroneCount = 0

    for dx = -scanRadius, scanRadius do
        for dy = -scanRadius, scanRadius do
            local distSq = dx * dx + dy * dy
            if distSq > 0 and distSq <= rangeSq then
                local tx, ty = sx + dx, sy + dy
                if player:knowsSector(tx, ty) then
                    local hasTradingPost = ResourceBuyerController.sectorHasTradingPosts(tx, ty, serverSeed)
                    if hasTradingPost then
                        -- Clear any previous value for this key
                        Server():setValue("resbuy_" .. tx .. "_" .. ty, "")
                        table.insert(pendingDrones, {x = tx, y = ty})
                        table.insert(droneTargets, {x = tx, y = ty})
                    end
                end
            end
        end
    end

    totalDroneCount = #droneTargets

    if totalDroneCount == 0 then
        -- No drones needed, finish immediately
        local found = 0
        for _, item in pairs(shoppingList) do
            if availableGoods[item.name] then
                found = found + 1
            end
        end
        ResourceBuyerController.sendSyncToClients()
        broadcastInvokeClientFunction("updateStatus", "Scan complete: " .. found .. "/" .. #shoppingList .. " goods found nearby")
        print("[ResourceBuyer] Scan done (FactoryMap only, no trading posts in range)")
    else
        -- Start drone scanning phase
        scanState = "scanning"
        ResourceBuyerController.sendSyncToClients()
        broadcastInvokeClientFunction("updateStatus", "FactoryMap done, sending " .. totalDroneCount .. " drones...")
        print("[ResourceBuyer] FactoryMap done, queued " .. totalDroneCount .. " drone(s) for trading post sectors")
    end
end
callable(ResourceBuyerController, "scanNearbyGoods")

function ResourceBuyerController.sectorHasTradingPosts(x, y, serverSeed)
    local specs = SectorSpecifics()
    specs:initialize(x, y, serverSeed)

    if not specs.generationTemplate then return false end
    if not specs.generationTemplate.contents then return false end

    local ok, contents = pcall(specs.generationTemplate.contents, x, y)
    if not ok or not contents then return false end

    if (contents.tradingPosts or 0) > 0 then return true end
    if (contents.neighborTradingPosts or 0) > 0 then return true end
    if (contents.planetaryTradingPosts or 0) > 0 then return true end
    if (contents.smugglersMarkets or 0) > 0 then return true end

    return false
end

function ResourceBuyerController.scanCurrentSectorGoods()
    -- Use TradingUtility to find all buyable goods from stations in current sector
    local sellable, buyable = TradingUtility.detectBuyableAndSellableGoods()

    -- buyable = goods stations sell (player can buy from)
    for _, offer in pairs(buyable) do
        availableGoods[offer.good.name] = 1
    end
end

function ResourceBuyerController.startBuyRun(useInventoryStr)
    if not onServer() then return end
    if buyState ~= BUY_IDLE then
        broadcastInvokeClientFunction("updateStatus", "Buy run already in progress")
        return
    end
    if scanState == "scanning" then
        broadcastInvokeClientFunction("updateStatus", "Wait for scan to finish first")
        return
    end
    if #shoppingList == 0 then
        broadcastInvokeClientFunction("updateStatus", "Shopping list is empty")
        return
    end

    local entity = Entity()
    if not valid(entity) then return end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        broadcastInvokeClientFunction("updateStatus", "No hyperspace drive installed")
        return
    end

    -- Build adjusted buy quantities (subtract inventory if requested)
    local useInv = (useInventoryStr == "1")
    buyQuantities = {}
    local existingCargo = {}
    if useInv then
        for good, amount in pairs(entity:getCargos()) do
            if amount > 0 then
                existingCargo[good.name] = amount
            end
        end
    end

    local hasAnythingToBuy = false
    for _, item in pairs(shoppingList) do
        local have = existingCargo[item.name] or 0
        local toBuy = math.max(0, item.quantity - have)
        buyQuantities[item.name] = toBuy
        if toBuy > 0 then
            hasAnythingToBuy = true
        end
        if useInv and have > 0 then
            print("[ResourceBuyer] " .. item.name .. ": need " .. item.quantity .. ", have " .. have .. ", buy " .. toBuy)
        end
    end

    if not hasAnythingToBuy then
        broadcastInvokeClientFunction("updateStatus", "All goods already in inventory")
        return
    end

    -- Save home position for return
    local sx, sy = Sector():getCoordinates()
    homeSector = {x = sx, y = sy}

    -- Reset buy state
    buyRoute = {}
    buyRouteIndex = 0
    buyWaypoints = {}
    waypointIndex = 0
    sectorGoods = {}
    currentGoodIndex = 0
    resolvedStation = nil
    resolvedScript = nil
    buyResults = {}

    -- Scan current sector directly into sectorGoods
    local sellable, buyable = TradingUtility.detectBuyableAndSellableGoods()
    local currentGoods = {}
    local seen = {}
    for _, offer in pairs(buyable) do
        if not seen[offer.good.name] then
            seen[offer.good.name] = true
            table.insert(currentGoods, offer.good.name)
        end
    end
    if #currentGoods > 0 then
        sectorGoods[sx .. "_" .. sy] = currentGoods
    end

    -- Build candidate sectors for drone scanning
    local scanRadius = math.ceil(jumpRange)
    local rangeSq = jumpRange * jumpRange
    local serverSeed = Server().seed
    local player = Player()

    pendingDrones = {}
    droneTargets = {}
    dronesReceived = {}
    dispatchTimer = 0
    scanElapsed = 0
    totalDroneCount = 0

    for dx = -scanRadius, scanRadius do
        for dy = -scanRadius, scanRadius do
            local distSq = dx * dx + dy * dy
            if distSq > 0 and distSq <= rangeSq then
                local tx, ty = sx + dx, sy + dy
                if player:knowsSector(tx, ty) then
                    local hasTradingPost = ResourceBuyerController.sectorHasTradingPosts(tx, ty, serverSeed)
                    if hasTradingPost then
                        Server():setValue("resbuy_" .. tx .. "_" .. ty, "")
                        table.insert(pendingDrones, {x = tx, y = ty})
                        table.insert(droneTargets, {x = tx, y = ty})
                    end
                end
            end
        end
    end

    totalDroneCount = #droneTargets

    if totalDroneCount == 0 then
        -- No drones needed, proceed directly to route planning
        buyState = BUY_SCOUTING
        ResourceBuyerController.onScoutingComplete()
    else
        scanState = "scanning"
        buyState = BUY_SCOUTING
        broadcastInvokeClientFunction("updateStatus", "Scouting sectors... (0/" .. totalDroneCount .. " drones)")
        print("[ResourceBuyer] Buy run: scouting " .. totalDroneCount .. " sectors")
    end
end
callable(ResourceBuyerController, "startBuyRun")

function ResourceBuyerController.stopBuyRun()
    if not onServer() then return end

    -- Abort any in-progress scan/scouting
    if scanState == "scanning" then
        scanState = "idle"
        pendingDrones = {}
        droneTargets = {}
        dronesReceived = {}
        print("[ResourceBuyer] Scan aborted by user")
    end

    -- Reset buy state
    if buyState ~= BUY_IDLE then
        if buyState == BUY_BUYING then
            DockAI.reset()
        end

        local controller = ControlUnit()
        if controller then
            controller.autoPilotEnabled = false
            controller:stopShip()
        end

        print("[ResourceBuyer] Buy run stopped (was in state " .. buyState .. ")")
    end

    buyState = BUY_IDLE
    buyRoute = {}
    buyRouteIndex = 0
    buyWaypoints = {}
    waypointIndex = 0
    sectorGoods = {}
    currentGoodIndex = 0
    resolvedStation = nil
    resolvedScript = nil

    broadcastInvokeClientFunction("updateStatus", "Stopped")
end
callable(ResourceBuyerController, "stopBuyRun")

function ResourceBuyerController.requestUIUpdate()
    if not onServer() then return end
    ResourceBuyerController.sendSyncToClients()
    if buyState == BUY_SCOUTING then
        local receivedCount = 0
        for _ in pairs(dronesReceived) do receivedCount = receivedCount + 1 end
        broadcastInvokeClientFunction("updateStatus", "Scouting... (" .. receivedCount .. "/" .. totalDroneCount .. " drones)")
    elseif buyState == BUY_JUMPING then
        broadcastInvokeClientFunction("updateStatus", "Jumping to buy sector " .. buyRouteIndex .. "/" .. #buyRoute .. "...")
    elseif buyState == BUY_BUYING then
        local stop = buyRoute[buyRouteIndex]
        local goodName = stop and stop.goods[currentGoodIndex] or "?"
        broadcastInvokeClientFunction("updateStatus", "Buying " .. goodName .. " (sector " .. buyRouteIndex .. "/" .. #buyRoute .. ")...")
    elseif buyState == BUY_RETURNING then
        broadcastInvokeClientFunction("updateStatus", "Returning home...")
    elseif scanState == "scanning" then
        local receivedCount = 0
        for _ in pairs(dronesReceived) do receivedCount = receivedCount + 1 end
        broadcastInvokeClientFunction("updateStatus", "Scanning... (" .. receivedCount .. "/" .. totalDroneCount .. " drones)")
    else
        broadcastInvokeClientFunction("updateStatus", "Idle")
    end
end
callable(ResourceBuyerController, "requestUIUpdate")

function ResourceBuyerController.sendSyncToClients()
    local listData = ResourceBuyerController.serializeList()
    local availData = ResourceBuyerController.serializeAvailable()
    local cargoData = ResourceBuyerController.serializeCargo()
    broadcastInvokeClientFunction("syncListAndAvailability", listData, availData, cargoData)
end

-- ============================================================
-- UPDATE LOOP (drone dispatch + polling)
-- ============================================================

function ResourceBuyerController.getUpdateInterval()
    if scanState == "scanning" then return 0 end
    if buyState ~= BUY_IDLE then return 0 end
    return 1
end

function ResourceBuyerController.updateServer(timeStep)
    local entity = Entity()
    if not valid(entity) then
        scanState = "idle"
        buyState = BUY_IDLE
        return
    end

    -- ==========================================
    -- DRONE DISPATCH + POLLING (scan or scouting)
    -- ==========================================
    if scanState == "scanning" then
        local sector = Sector()

        -- Dispatch one drone per second
        dispatchTimer = dispatchTimer + timeStep
        if dispatchTimer >= 1.0 and #pendingDrones > 0 then
            dispatchTimer = 0
            local target = table.remove(pendingDrones, 1)
            local player = Player()

            local dronePlan = BlockPlan()
            local material = Material(MaterialType.Iron)
            local color = Color(0.2, 0.6, 0.9, 1.0)
            dronePlan:addBlock(vec3(0, 0, 0), vec3(1, 1, 1), -1, 1, color, material, Matrix(), 0, nil)

            local droneMatrix = Matrix()
            droneMatrix.translation = entity.translationf + vec3(50, 0, 0)

            local droneName = "ResBuyer Scanner " .. target.x .. "_" .. target.y
            local drone = sector:createShip(player, droneName, dronePlan, droneMatrix)

            if valid(drone) then
                drone.crew = Crew()
                drone.crew:add(1, CrewMan(CrewProfessionType.None))
                drone:addScript("data/scripts/entity/resbuyerscanner.lua", entity.factionIndex)
                sector:transferEntity(drone, target.x, target.y, SectorChangeType.Jump)
            end
        end

        -- Poll for drone results
        for _, sc in pairs(droneTargets) do
            local key = sc.x .. "_" .. sc.y
            if not dronesReceived[key] then
                local data = Server():getValue("resbuy_" .. key)
                if data and data ~= "" then
                    dronesReceived[key] = true

                    -- Merge drone results into availableGoods
                    if data ~= "EMPTY" then
                        local goodsList = {}
                        for name in string.gmatch(data, "[^\n]+") do
                            availableGoods[name] = 1
                            table.insert(goodsList, name)
                        end
                        -- Store per-sector data for buy route planning
                        if #goodsList > 0 then
                            sectorGoods[key] = goodsList
                        end
                    end
                end
            end
        end

        local receivedCount = 0
        for _ in pairs(dronesReceived) do receivedCount = receivedCount + 1 end

        -- Timeout: if all drones dispatched and waited long enough
        if #pendingDrones == 0 then
            scanElapsed = scanElapsed + timeStep
            if scanElapsed >= SCAN_TIMEOUT and receivedCount < totalDroneCount then
                local timedOut = 0
                for _, sc in pairs(droneTargets) do
                    local key = sc.x .. "_" .. sc.y
                    if not dronesReceived[key] then
                        dronesReceived[key] = true
                        timedOut = timedOut + 1
                    end
                end
                receivedCount = receivedCount + timedOut
                print("[ResourceBuyer] " .. timedOut .. " drone(s) timed out (destroyed?)")
            end
        end

        -- Status update
        if buyState == BUY_SCOUTING then
            broadcastInvokeClientFunction("updateStatus", "Scouting sectors... (" .. receivedCount .. "/" .. totalDroneCount .. " drones)")
        else
            broadcastInvokeClientFunction("updateStatus", "Scanning... (" .. receivedCount .. "/" .. totalDroneCount .. " drones)")
        end

        -- All drones returned (or timed out)
        if receivedCount >= totalDroneCount then
            scanState = "idle"

            -- Clean up Server setValue keys
            for _, sc in pairs(droneTargets) do
                Server():setValue("resbuy_" .. sc.x .. "_" .. sc.y, nil)
            end
            pendingDrones = {}
            droneTargets = {}
            dronesReceived = {}

            if buyState == BUY_SCOUTING then
                -- Transition to route planning
                ResourceBuyerController.onScoutingComplete()
            else
                -- Regular scan completion
                local found = 0
                for _, item in pairs(shoppingList) do
                    if availableGoods[item.name] then
                        found = found + 1
                    end
                end

                ResourceBuyerController.sendSyncToClients()
                broadcastInvokeClientFunction("updateStatus", "Scan complete: " .. found .. "/" .. #shoppingList .. " goods found nearby")
                print("[ResourceBuyer] Scan complete: " .. found .. "/" .. #shoppingList .. " goods found")
            end
        end
        return
    end

    -- ==========================================
    -- BUY STATE MACHINE
    -- ==========================================
    if buyState == BUY_IDLE then return end

    local sector = Sector()

    -- JUMPING TO BUY SECTOR
    if buyState == BUY_JUMPING then
        local cx, cy = sector:getCoordinates()
        local wp = buyWaypoints[waypointIndex]
        if cx == wp.x and cy == wp.y then
            if waypointIndex >= #buyWaypoints then
                -- Arrived at buy sector
                print("[ResourceBuyer] Arrived at buy sector " .. cx .. ":" .. cy .. " (stop " .. buyRouteIndex .. "/" .. #buyRoute .. ")")
                buyState = BUY_BUYING
                currentGoodIndex = 1
                resolvedStation = nil
                resolvedScript = nil
                DockAI.reset()
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                local stop = buyRoute[buyRouteIndex]
                broadcastInvokeClientFunction("updateStatus", "Buying " .. stop.goods[1] .. " (sector " .. buyRouteIndex .. "/" .. #buyRoute .. ")...")
            else
                -- Advance to next waypoint
                waypointIndex = waypointIndex + 1
                local nextWp = buyWaypoints[waypointIndex]
                print("[ResourceBuyer] Waypoint " .. waypointIndex .. "/" .. #buyWaypoints .. " -> " .. nextWp.x .. ":" .. nextWp.y)
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                ShipAI():setJump(nextWp.x, nextWp.y)
                broadcastInvokeClientFunction("updateStatus", "Jumping " .. waypointIndex .. "/" .. #buyWaypoints .. " to sector " .. buyRouteIndex .. "/" .. #buyRoute .. "...")
            end
        end
        return
    end

    -- BUYING AT CURRENT SECTOR
    if buyState == BUY_BUYING then
        local stop = buyRoute[buyRouteIndex]
        if not stop or currentGoodIndex > #stop.goods then
            -- Done with this stop, advance
            ResourceBuyerController.advanceBuyRoute()
            return
        end

        local goodName = stop.goods[currentGoodIndex]

        -- Resolve station for this good
        if not resolvedStation then
            local station, script, stock = ResourceBuyerController.findStationForGood(entity, goodName)
            if not valid(station) then
                print("[ResourceBuyer] No station sells " .. goodName .. " in sector " .. stop.x .. ":" .. stop.y)
                table.insert(buyResults, goodName .. ": not found in sector")
                currentGoodIndex = currentGoodIndex + 1
                resolvedStation = nil
                resolvedScript = nil
                DockAI.reset()
                return
            end
            resolvedStation = station.index
            resolvedScript = script
            DockAI.reset()
            local controller = ControlUnit()
            if controller then controller.autoPilotEnabled = true end
            print("[ResourceBuyer] Buying " .. goodName .. " from " .. tostring(station))
        end

        local station = sector:getEntity(resolvedStation)
        if not valid(station) then
            print("[ResourceBuyer] Station lost for " .. goodName)
            table.insert(buyResults, goodName .. ": station lost")
            currentGoodIndex = currentGoodIndex + 1
            resolvedStation = nil
            resolvedScript = nil
            DockAI.reset()
            return
        end

        -- Get adjusted quantity (accounts for inventory if enabled)
        local qty = buyQuantities[goodName] or 0
        if qty <= 0 then
            -- Already have enough from inventory, skip
            print("[ResourceBuyer] Skipping " .. goodName .. " (inventory sufficient)")
            table.insert(buyResults, goodName .. ": skipped (have enough)")
            currentGoodIndex = currentGoodIndex + 1
            resolvedStation = nil
            resolvedScript = nil
            DockAI.reset()
            return
        end

        DockAI.updateDockingUndocking(timeStep, station, 5,
            function(ship, dockStation)
                -- Docked callback: buy the good
                local result = dockStation:invokeFunction(resolvedScript, "sellToShip", entity.index, goodName, qty, 1)
                if result == 0 then
                    print("[ResourceBuyer] Bought " .. qty .. "x " .. goodName)
                    table.insert(buyResults, goodName .. " x" .. qty .. ": OK")
                    broadcastInvokeClientFunction("updateStatus", "Bought " .. goodName .. "! Undocking...")
                else
                    print("[ResourceBuyer] Buy failed for " .. goodName .. ": " .. tostring(result))
                    table.insert(buyResults, goodName .. ": buy failed (" .. tostring(result) .. ")")
                    broadcastInvokeClientFunction("updateStatus", "Buy failed for " .. goodName .. " (" .. tostring(result) .. ")")
                end
            end,
            function(ship, msg)
                -- Undock callback: advance to next good
                print("[ResourceBuyer] Undocked after buying " .. goodName)
                currentGoodIndex = currentGoodIndex + 1
                resolvedStation = nil
                resolvedScript = nil
                DockAI.reset()

                local nextStop = buyRoute[buyRouteIndex]
                if nextStop and currentGoodIndex <= #nextStop.goods then
                    local nextGood = nextStop.goods[currentGoodIndex]
                    broadcastInvokeClientFunction("updateStatus", "Buying " .. nextGood .. " (sector " .. buyRouteIndex .. "/" .. #buyRoute .. ")...")
                end
            end
        )
        return
    end

    -- RETURNING HOME
    if buyState == BUY_RETURNING then
        local cx, cy = sector:getCoordinates()
        local wp = buyWaypoints[waypointIndex]
        if cx == wp.x and cy == wp.y then
            if waypointIndex >= #buyWaypoints then
                -- Arrived home
                print("[ResourceBuyer] Arrived home at " .. cx .. ":" .. cy)

                local controller = ControlUnit()
                if controller then
                    controller.autoPilotEnabled = false
                    controller:stopShip()
                end

                -- Build result summary
                local summary = "Buy run complete"
                if #buyResults > 0 then
                    summary = summary .. ": " .. table.concat(buyResults, ", ")
                end

                buyState = BUY_IDLE
                buyRoute = {}
                buyRouteIndex = 0
                buyWaypoints = {}
                waypointIndex = 0
                sectorGoods = {}

                broadcastInvokeClientFunction("updateStatus", summary)
                print("[ResourceBuyer] " .. summary)
            else
                waypointIndex = waypointIndex + 1
                local nextWp = buyWaypoints[waypointIndex]
                print("[ResourceBuyer] Return waypoint " .. waypointIndex .. "/" .. #buyWaypoints .. " -> " .. nextWp.x .. ":" .. nextWp.y)
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                ShipAI():setJump(nextWp.x, nextWp.y)
                broadcastInvokeClientFunction("updateStatus", "Returning home " .. waypointIndex .. "/" .. #buyWaypoints .. "...")
            end
        end
        return
    end
end

-- ============================================================
-- BUY ROUTE PLANNING
-- ============================================================

function ResourceBuyerController.onScoutingComplete()
    -- Build the buy route from sectorGoods
    local route = ResourceBuyerController.planBuyRoute()

    if #route == 0 then
        print("[ResourceBuyer] No goods found in any sector")
        buyState = BUY_IDLE
        broadcastInvokeClientFunction("updateStatus", "No shopping list goods found nearby")
        return
    end

    buyRoute = route
    buyRouteIndex = 1
    buyResults = {}

    -- Log the planned route
    print("[ResourceBuyer] Planned route with " .. #route .. " stop(s):")
    for i, stop in ipairs(route) do
        print("[ResourceBuyer]   Stop " .. i .. ": (" .. stop.x .. ":" .. stop.y .. ") -> " .. table.concat(stop.goods, ", "))
    end

    -- Start jumping to first stop (or buy directly if already there)
    ResourceBuyerController.jumpToRouteStop()
end

function ResourceBuyerController.planBuyRoute()
    -- Build set of needed good names from shopping list (skip zero-quantity)
    local needed = {}
    for _, item in pairs(shoppingList) do
        local qty = buyQuantities[item.name] or item.quantity
        if qty > 0 then
            needed[item.name] = true
        end
    end

    -- Filter sectorGoods to only goods on the shopping list
    -- filtered[key] = {list of needed good names available in this sector}
    local filtered = {}
    for key, goodsList in pairs(sectorGoods) do
        local matching = {}
        for _, name in pairs(goodsList) do
            if needed[name] then
                table.insert(matching, name)
            end
        end
        if #matching > 0 then
            filtered[key] = matching
        end
    end

    -- Greedy set cover: pick sectors covering the most uncovered goods
    local uncovered = {}
    for name, _ in pairs(needed) do
        uncovered[name] = true
    end

    local selectedSectors = {} -- ordered list of sector keys

    while true do
        -- Check if anything is still uncovered
        local hasUncovered = false
        for _ in pairs(uncovered) do
            hasUncovered = true
            break
        end
        if not hasUncovered then break end

        -- Find sector covering the most uncovered goods
        local bestKey = nil
        local bestCount = 0
        local bestGoods = nil

        for key, goodsList in pairs(filtered) do
            local count = 0
            local coveredGoods = {}
            for _, name in pairs(goodsList) do
                if uncovered[name] then
                    count = count + 1
                    table.insert(coveredGoods, name)
                end
            end
            if count > bestCount then
                bestCount = count
                bestKey = key
                bestGoods = coveredGoods
            end
        end

        if not bestKey or bestCount == 0 then break end

        -- Select this sector
        table.insert(selectedSectors, {key = bestKey, goods = bestGoods})

        -- Mark goods as covered
        for _, name in pairs(bestGoods) do
            uncovered[name] = nil
        end
    end

    if #selectedSectors == 0 then return {} end

    -- Parse sector coordinates from keys
    for _, entry in pairs(selectedSectors) do
        local x, y = string.match(entry.key, "^(-?%d+)_(-?%d+)$")
        entry.x = tonumber(x)
        entry.y = tonumber(y)
    end

    -- Nearest-neighbor ordering starting from home sector
    local hx = homeSector and homeSector.x or 0
    local hy = homeSector and homeSector.y or 0

    local ordered = {}
    local remaining = {}
    for i, entry in ipairs(selectedSectors) do
        remaining[i] = entry
    end

    local cx, cy = hx, hy
    while true do
        local bestIdx = nil
        local bestDistSq = math.huge
        for i, entry in pairs(remaining) do
            local dx = entry.x - cx
            local dy = entry.y - cy
            local distSq = dx * dx + dy * dy
            if distSq < bestDistSq then
                bestDistSq = distSq
                bestIdx = i
            end
        end
        if not bestIdx then break end

        local entry = remaining[bestIdx]
        table.insert(ordered, {x = entry.x, y = entry.y, goods = entry.goods})
        cx, cy = entry.x, entry.y
        remaining[bestIdx] = nil
    end

    return ordered
end

function ResourceBuyerController.advanceBuyRoute()
    if buyRouteIndex < #buyRoute then
        buyRouteIndex = buyRouteIndex + 1
        ResourceBuyerController.jumpToRouteStop()
    else
        -- All stops complete, return home
        ResourceBuyerController.startReturnHome()
    end
end

function ResourceBuyerController.jumpToRouteStop()
    local stop = buyRoute[buyRouteIndex]
    local entity = Entity()
    local cx, cy = Sector():getCoordinates()

    if cx == stop.x and cy == stop.y then
        -- Already in this sector, start buying
        buyState = BUY_BUYING
        currentGoodIndex = 1
        resolvedStation = nil
        resolvedScript = nil
        DockAI.reset()
        local controller = ControlUnit()
        if controller then controller.autoPilotEnabled = true end
        broadcastInvokeClientFunction("updateStatus", "Buying " .. stop.goods[1] .. " (sector " .. buyRouteIndex .. "/" .. #buyRoute .. ")...")
        return
    end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        print("[ResourceBuyer] Lost hyperspace drive, aborting")
        ResourceBuyerController.stopBuyRun()
        return
    end

    buyWaypoints = ResourceBuyerController.calculateJumpPath(cx, cy, stop.x, stop.y, math.floor(jumpRange))
    waypointIndex = 1
    buyState = BUY_JUMPING

    local wp = buyWaypoints[1]
    local controller = ControlUnit()
    if controller then controller.autoPilotEnabled = true end
    ShipAI():setJump(wp.x, wp.y)

    local totalJumps = #buyWaypoints
    if totalJumps > 1 then
        broadcastInvokeClientFunction("updateStatus", "Jumping 1/" .. totalJumps .. " to sector " .. buyRouteIndex .. "/" .. #buyRoute .. "...")
    else
        broadcastInvokeClientFunction("updateStatus", "Jumping to buy sector (" .. stop.x .. ":" .. stop.y .. ")...")
    end
end

function ResourceBuyerController.startReturnHome()
    if not homeSector then
        -- No home, just finish here
        buyState = BUY_IDLE
        broadcastInvokeClientFunction("updateStatus", "Buy run complete (no return)")
        return
    end

    local entity = Entity()
    local cx, cy = Sector():getCoordinates()

    if cx == homeSector.x and cy == homeSector.y then
        -- Already home
        local controller = ControlUnit()
        if controller then
            controller.autoPilotEnabled = false
            controller:stopShip()
        end
        buyState = BUY_IDLE

        local summary = "Buy run complete"
        if #buyResults > 0 then
            summary = summary .. ": " .. table.concat(buyResults, ", ")
        end
        broadcastInvokeClientFunction("updateStatus", summary)
        print("[ResourceBuyer] " .. summary)
        return
    end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        buyState = BUY_IDLE
        broadcastInvokeClientFunction("updateStatus", "Buy run done (no drive to return)")
        return
    end

    buyWaypoints = ResourceBuyerController.calculateJumpPath(cx, cy, homeSector.x, homeSector.y, math.floor(jumpRange))
    waypointIndex = 1
    buyState = BUY_RETURNING

    local wp = buyWaypoints[1]
    local controller = ControlUnit()
    if controller then controller.autoPilotEnabled = true end
    ShipAI():setJump(wp.x, wp.y)
    broadcastInvokeClientFunction("updateStatus", "Returning home 1/" .. #buyWaypoints .. "...")
end

-- Calculate a multi-jump path from (fromX,fromY) to (toX,toY) within jumpRange per hop
function ResourceBuyerController.calculateJumpPath(fromX, fromY, toX, toY, jumpRange)
    local waypoints = {}
    if fromX == toX and fromY == toY then return waypoints end

    local cx, cy = fromX, fromY
    while true do
        local dx = toX - cx
        local dy = toY - cy
        local distSq = dx * dx + dy * dy

        if distSq <= jumpRange * jumpRange then
            table.insert(waypoints, {x = toX, y = toY})
            break
        end

        local dist = math.sqrt(distSq)
        local effectiveRange = math.max(1, jumpRange - 0.7)
        local stepX = dx / dist * effectiveRange
        local stepY = dy / dist * effectiveRange

        local nextX = math.floor(cx + stepX + 0.5)
        local nextY = math.floor(cy + stepY + 0.5)

        -- Safety: ensure we always make progress
        if nextX == cx and nextY == cy then
            nextX = cx + (dx > 0 and 1 or (dx < 0 and -1 or 0))
            nextY = cy + (dy > 0 and 1 or (dy < 0 and -1 or 0))
        end

        table.insert(waypoints, {x = nextX, y = nextY})
        cx, cy = nextX, nextY
    end

    return waypoints
end

-- Find a station in the current sector that sells a specific good
-- Returns station entity, script path, stock amount (or nil)
function ResourceBuyerController.findStationForGood(entity, goodName)
    local sector = Sector()
    local stations = {sector:getEntitiesByType(EntityType.Station)}
    local playerFaction = Faction(entity.factionIndex)

    for _, station in pairs(stations) do
        if not valid(station) then goto nextStation end

        if playerFaction then
            local relations = playerFaction:getRelations(station.factionIndex)
            if relations < RELATIONS_THRESHOLD then goto nextStation end
        end

        local sellable = {}
        local buyable = {}
        TradingUtility.getBuyableAndSellableGoods(station, sellable, buyable, playerFaction)

        for _, offer in pairs(buyable) do
            if offer.good.name == goodName and offer.stock > 0 then
                return station, offer.script, offer.stock
            end
        end

        ::nextStation::
    end

    return nil, nil, 0
end

-- ============================================================
-- SERIALIZATION
-- ============================================================

function ResourceBuyerController.serializeList()
    local lines = {}
    for _, item in pairs(shoppingList) do
        table.insert(lines, item.name .. "|" .. item.quantity)
    end
    return table.concat(lines, "\n")
end

function ResourceBuyerController.serializeAvailable()
    local names = {}
    for name, _ in pairs(availableGoods) do
        table.insert(names, name)
    end
    return table.concat(names, "\n")
end

function ResourceBuyerController.serializeCargo()
    local entity = Entity()
    if not valid(entity) then return "" end
    local lines = {}
    for good, amount in pairs(entity:getCargos()) do
        if amount > 0 then
            table.insert(lines, good.name .. "|" .. amount)
        end
    end
    return table.concat(lines, "\n")
end

-- ============================================================
-- CLIENT FUNCTIONS
-- ============================================================

function ResourceBuyerController.syncListAndAvailability(listData, availData, cargoData)
    if not onClient() then return end

    -- Parse shopping list
    clientItems = {}
    if listData and listData ~= "" then
        for line in string.gmatch(listData, "[^\n]+") do
            local parts = {}
            for part in string.gmatch(line, "[^|]+") do
                table.insert(parts, part)
            end
            if #parts >= 2 then
                table.insert(clientItems, {name = parts[1], quantity = tonumber(parts[2]) or 0})
            end
        end
    end

    -- Parse available goods
    clientAvailable = {}
    if availData and availData ~= "" then
        for name in string.gmatch(availData, "[^\n]+") do
            clientAvailable[name] = 1
        end
    end

    -- Parse cargo inventory
    clientInventory = {}
    if cargoData and cargoData ~= "" then
        for line in string.gmatch(cargoData, "[^\n]+") do
            local parts = {}
            for part in string.gmatch(line, "[^|]+") do
                table.insert(parts, part)
            end
            if #parts >= 2 then
                clientInventory[parts[1]] = tonumber(parts[2]) or 0
            end
        end
    end

    ResourceBuyerController.renderList()
end
callable(ResourceBuyerController, "syncListAndAvailability")

function ResourceBuyerController.renderList()
    if not onClient() then return end
    if not listBox then return end

    listBox:clear()

    local hasAvailData = false
    for _ in pairs(clientAvailable) do
        hasAvailData = true
        break
    end

    local useInv = useInventoryChecked

    for i, item in ipairs(clientItems) do
        local displayName = item.name % _t
        local have = clientInventory[item.name] or 0
        local remaining = math.max(0, item.quantity - (useInv and have or 0))

        local text = displayName .. "  x" .. tostring(item.quantity)
        if useInv then
            text = text .. "  (inv: " .. have .. ", buy: " .. remaining .. ")"
        end
        if hasAvailData and not clientAvailable[item.name] then
            text = text .. "  [NOT FOUND]"
        end
        listBox:addEntry(text)

        -- Color: green if fully covered by inventory, red if not found, default otherwise
        if useInv and remaining == 0 then
            listBox:setEntry(i - 1, text, false, false, ColorRGB(0.2, 0.8, 0.2))
        elseif hasAvailData and not clientAvailable[item.name] then
            listBox:setEntry(i - 1, text, false, false, ColorRGB(0.8, 0.2, 0.2))
        end
    end
end

function ResourceBuyerController.updateStatus(msg)
    if not onClient() then return end
    if statusLabel then statusLabel.caption = "Status: " .. msg end
end
callable(ResourceBuyerController, "updateStatus")

function ResourceBuyerController.refreshList()
    if not onClient() then return end
    if not listBox then return end
    listBox:clear()
end

-- ============================================================
-- STATE PERSISTENCE
-- ============================================================

function ResourceBuyerController.secure()
    return {
        shoppingList = shoppingList,
        availableGoods = availableGoods,
        buyState = buyState,
        homeSector = homeSector,
        buyRoute = buyRoute,
        buyRouteIndex = buyRouteIndex,
        currentGoodIndex = currentGoodIndex,
        buyResults = buyResults,
        buyQuantities = buyQuantities,
    }
end

function ResourceBuyerController.restore(data)
    if data then
        shoppingList = data.shoppingList or {}
        availableGoods = data.availableGoods or {}

        -- Restore buy state (if was jumping/buying/returning, can resume)
        local savedBuyState = data.buyState or BUY_IDLE
        if savedBuyState == BUY_SCOUTING then
            -- Drones are lost on restore, reset to idle
            buyState = BUY_IDLE
        elseif savedBuyState == BUY_JUMPING or savedBuyState == BUY_BUYING or savedBuyState == BUY_RETURNING then
            buyState = savedBuyState
            homeSector = data.homeSector
            buyRoute = data.buyRoute or {}
            buyRouteIndex = data.buyRouteIndex or 0
            currentGoodIndex = data.currentGoodIndex or 0
            buyResults = data.buyResults or {}
            buyQuantities = data.buyQuantities or {}

            -- Re-derive waypoints and re-issue jump commands on restore
            if buyState == BUY_JUMPING and buyRouteIndex > 0 and buyRouteIndex <= #buyRoute then
                local stop = buyRoute[buyRouteIndex]
                local entity = Entity()
                if valid(entity) then
                    local cx, cy = Sector():getCoordinates()
                    local jumpRange = math.floor(entity.hyperspaceJumpReach or 0)
                    if jumpRange > 0 then
                        buyWaypoints = ResourceBuyerController.calculateJumpPath(cx, cy, stop.x, stop.y, jumpRange)
                        waypointIndex = 1
                        if #buyWaypoints > 0 then
                            ShipAI():setJump(buyWaypoints[1].x, buyWaypoints[1].y)
                        end
                    end
                end
            elseif buyState == BUY_RETURNING and homeSector then
                local entity = Entity()
                if valid(entity) then
                    local cx, cy = Sector():getCoordinates()
                    local jumpRange = math.floor(entity.hyperspaceJumpReach or 0)
                    if jumpRange > 0 then
                        buyWaypoints = ResourceBuyerController.calculateJumpPath(cx, cy, homeSector.x, homeSector.y, jumpRange)
                        waypointIndex = 1
                        if #buyWaypoints > 0 then
                            ShipAI():setJump(buyWaypoints[1].x, buyWaypoints[1].y)
                        end
                    end
                end
            elseif buyState == BUY_BUYING then
                DockAI.reset()
                resolvedStation = nil
                resolvedScript = nil
            end
        else
            buyState = BUY_IDLE
        end
    else
        shoppingList = {}
        availableGoods = {}
        buyState = BUY_IDLE
    end

    -- Reset scan state on restore (don't persist mid-scan)
    scanState = "idle"
    pendingDrones = {}
    droneTargets = {}
    dronesReceived = {}
    sectorGoods = {}
end
