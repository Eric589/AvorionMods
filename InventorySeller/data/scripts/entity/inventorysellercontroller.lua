-- Inventory Seller Controller
-- Sells goods from ship cargo to nearby stations automatically
package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
include("callable")
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
-- namespace InventorySellerController
InventorySellerController = {}

local RELATIONS_THRESHOLD = -30000

-- Sell list: array of {name = "Good Name"}
local sellList = {}

-- Set of good names that can be sold somewhere nearby (server-side)
local sellableGoods = {}

-- Per-sector scan data: {["x_y"] = {["Good1"] = capacity, ...}} from drones
local sectorGoods = {}

-- Scan state
local scanState = "idle" -- "idle" or "scanning"
local pendingDrones = {}
local droneTargets = {}
local dronesReceived = {}
local dispatchTimer = 0
local scanElapsed = 0
local SCAN_TIMEOUT = 60
local totalDroneCount = 0

-- Sell run state machine
local SELL_IDLE = 0
local SELL_SCOUTING = 1
local SELL_JUMPING = 2
local SELL_SELLING = 3
local SELL_RETURNING = 4

local sellState = SELL_IDLE
local homeSector = nil        -- {x, y}
local sellRoute = {}          -- ordered: {{x, y, goods = {{name="Good1", qty=200}, ...}}, ...}
local sellRouteIndex = 0
local sellWaypoints = {}      -- jump waypoints to current destination
local waypointIndex = 0
local currentGoodIndex = 0
local resolvedStation = nil   -- cached station index for current sell
local resolvedScript = nil    -- cached merchant script path
local sellResults = {}
local sellQuantities = {}     -- {["Good"] = amount at start of sell run}

-- UI elements (client-side only)
local goodsCombo = nil
local comboGoodNames = {}     -- cargo item names for the combo box
local listBox = nil
local statusLabel = nil

-- Client-side data (synced from server)
local clientSellItems = {}    -- list of {name}
local clientSellable = {}     -- set of good names found nearby
local clientCargo = {}        -- {name -> amount} current cargo

-- ============================================================
-- HUD INTEGRATION
-- ============================================================

function InventorySellerController.getIcon()
    return "supply-chain.png"
end

function InventorySellerController.interactionPossible(playerIndex)
    if onServer() then return false end
    local player = Player()
    local entity = Entity()
    if player.craft.index.value == entity.id.value then
        return true, ""
    else
        return false, ""
    end
end

function InventorySellerController.getInteractionText()
    return "Inventory Seller"
end

function InventorySellerController.initialize()
    if onServer() then
        local entity = Entity()
        if entity then
            local initFlag = entity:getValue("inventoryseller_initialized")
            if not initFlag then
                entity:setValue("inventoryseller_initialized", true)
            end
        end
    end
end

function InventorySellerController.initUI()
    local res = getResolution()
    local size = vec2(500, 440)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Inventory Seller"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Inventory Seller")

    -- Row 1: Cargo item selector + Add + Sell All buttons
    local y = 10
    window:createLabel(vec2(10, y + 5), "Item:", 14)
    goodsCombo = window:createComboBox(Rect(60, y, 330, y + 30), "")
    goodsCombo.entriesPerPage = 15
    -- Populated dynamically from cargo when window opens

    window:createButton(Rect(340, y, 415, y + 30), "Add", "onAddItem")
    window:createButton(Rect(420, y, 490, y + 30), "All", "onSellAll")

    -- Row 2: Sell list header + Scan + Remove + Remove All
    y = 50
    window:createLabel(vec2(10, y), "Sell List:", 14)
    window:createButton(Rect(110, y - 5, 200, y + 20), "Scan", "onScan")
    window:createButton(Rect(205, y - 5, 340, y + 20), "Remove", "onRemoveItem")
    window:createButton(Rect(345, y - 5, 490, y + 20), "Remove All", "onRemoveAllItems")

    y = 75
    listBox = window:createListBox(Rect(10, y, 490, y + 230))

    -- Bottom buttons
    y = 320
    window:createButton(Rect(10, y, 240, y + 40), "Start", "onStart")
    window:createButton(Rect(250, y, 490, y + 40), "Stop", "onStop")

    y = 370
    statusLabel = window:createLabel(vec2(10, y), "Status: Idle", 15)
    statusLabel.width = 480
end

function InventorySellerController.onShowWindow()
    InventorySellerController.refreshList()
    invokeServerFunction("requestUIUpdate")
end

-- ============================================================
-- CLIENT CALLBACKS
-- ============================================================

function InventorySellerController.onAddItem()
    if not onClient() then return end
    if not goodsCombo then return end
    local idx = goodsCombo.selectedIndex
    if not idx or idx < 0 then return end
    local name = comboGoodNames[idx + 1] -- 0-indexed combo, 1-indexed Lua table
    if not name or name == "" then return end
    invokeServerFunction("addItem", name)
end

function InventorySellerController.onSellAll()
    if not onClient() then return end
    invokeServerFunction("addAllCargo")
end

function InventorySellerController.onRemoveItem()
    if not onClient() then return end
    if not listBox then return end
    local selected = listBox.selected
    if selected < 0 then return end
    invokeServerFunction("removeItem", selected)
end

function InventorySellerController.onRemoveAllItems()
    if not onClient() then return end
    invokeServerFunction("removeAllItems")
end

function InventorySellerController.onScan()
    if not onClient() then return end
    invokeServerFunction("scanNearbyGoods")
end

function InventorySellerController.onStart()
    if not onClient() then return end
    invokeServerFunction("startSellRun")
end

function InventorySellerController.onStop()
    if not onClient() then return end
    invokeServerFunction("stopSellRun")
end

-- ============================================================
-- SERVER FUNCTIONS
-- ============================================================

function InventorySellerController.addItem(name)
    if not onServer() then return end
    -- Check if already in list
    for _, item in pairs(sellList) do
        if item.name == name then return end
    end
    table.insert(sellList, {name = name})
    InventorySellerController.sendSyncToClients()
end
callable(InventorySellerController, "addItem")

function InventorySellerController.removeItem(index)
    if not onServer() then return end
    local luaIndex = index + 1
    if luaIndex >= 1 and luaIndex <= #sellList then
        table.remove(sellList, luaIndex)
    end
    InventorySellerController.sendSyncToClients()
end
callable(InventorySellerController, "removeItem")

function InventorySellerController.removeAllItems()
    if not onServer() then return end
    sellList = {}
    InventorySellerController.sendSyncToClients()
end
callable(InventorySellerController, "removeAllItems")

function InventorySellerController.addAllCargo()
    if not onServer() then return end
    local entity = Entity()
    if not valid(entity) then return end

    -- Build set of goods currently in cargo
    local inCargo = {}
    for good, amount in pairs(entity:getCargos()) do
        if amount > 0 then inCargo[good.name] = true end
    end

    -- Add goods in cargo that are not yet in the list
    for name, _ in pairs(inCargo) do
        local found = false
        for _, item in pairs(sellList) do
            if item.name == name then found = true; break end
        end
        if not found then
            table.insert(sellList, {name = name})
        end
    end

    -- Remove goods from the list that are no longer in cargo
    for i = #sellList, 1, -1 do
        if not inCargo[sellList[i].name] then
            table.remove(sellList, i)
        end
    end

    InventorySellerController.sendSyncToClients()
end
callable(InventorySellerController, "addAllCargo")

function InventorySellerController.scanNearbyGoods()
    if not onServer() then return end
    if scanState == "scanning" then
        broadcastInvokeClientFunction("updateStatus", "Scan already in progress...")
        return
    end
    if sellState ~= SELL_IDLE then
        broadcastInvokeClientFunction("updateStatus", "Cannot scan during sell run")
        return
    end

    local entity = Entity()
    if not valid(entity) then return end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        broadcastInvokeClientFunction("updateStatus", "No hyperspace drive installed")
        return
    end

    sellableGoods = {}
    InventorySellerController.scanCurrentSectorGoods()

    local sx, sy = Sector():getCoordinates()
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
                if player:knowsSector(tx, ty) and InventorySellerController.sectorHasAnyStation(tx, ty, serverSeed) then
                    Server():setValue("invsell_" .. tx .. "_" .. ty, "")
                    table.insert(pendingDrones, {x = tx, y = ty})
                    table.insert(droneTargets, {x = tx, y = ty})
                end
            end
        end
    end

    totalDroneCount = #droneTargets

    if totalDroneCount == 0 then
        local found = 0
        for _, item in pairs(sellList) do
            if sellableGoods[item.name] then found = found + 1 end
        end
        InventorySellerController.sendSyncToClients()
        broadcastInvokeClientFunction("updateStatus", "Scan complete: " .. found .. "/" .. #sellList .. " goods can be sold")
        print("[InventorySeller] Scan done (no trading posts in range)")
    else
        scanState = "scanning"
        InventorySellerController.sendSyncToClients()
        broadcastInvokeClientFunction("updateStatus", "Scanning " .. totalDroneCount .. " sectors...")
        print("[InventorySeller] Queued " .. totalDroneCount .. " drone(s) for scanning")
    end
end
callable(InventorySellerController, "scanNearbyGoods")

function InventorySellerController.sectorHasAnyStation(x, y, serverSeed)
    local specs = SectorSpecifics()
    specs:initialize(x, y, serverSeed)
    if not specs.generationTemplate then return false end
    if not specs.generationTemplate.contents then return false end
    local ok, contents = pcall(specs.generationTemplate.contents, x, y)
    if not ok or not contents then return false end
    return (contents.stations or 0) > 0
end

function InventorySellerController.scanCurrentSectorGoods()
    -- sellable = goods player can sell TO stations (station demand)
    local sellable, buyable = TradingUtility.detectBuyableAndSellableGoods()
    for _, offer in pairs(sellable) do
        sellableGoods[offer.good.name] = 1
    end
end

function InventorySellerController.startSellRun()
    if not onServer() then return end
    if sellState ~= SELL_IDLE then
        broadcastInvokeClientFunction("updateStatus", "Sell run already in progress")
        return
    end
    if scanState == "scanning" then
        broadcastInvokeClientFunction("updateStatus", "Wait for scan to finish first")
        return
    end
    if #sellList == 0 then
        broadcastInvokeClientFunction("updateStatus", "Sell list is empty")
        return
    end

    local entity = Entity()
    if not valid(entity) then return end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        broadcastInvokeClientFunction("updateStatus", "No hyperspace drive installed")
        return
    end

    -- Build sell quantities from current cargo
    sellQuantities = {}
    for good, amount in pairs(entity:getCargos()) do
        if amount > 0 then
            sellQuantities[good.name] = amount
        end
    end

    local hasAnythingToSell = false
    for _, item in pairs(sellList) do
        if (sellQuantities[item.name] or 0) > 0 then
            hasAnythingToSell = true
            break
        end
    end

    if not hasAnythingToSell then
        broadcastInvokeClientFunction("updateStatus", "No sell list items found in cargo")
        return
    end

    -- Save home sector
    local sx, sy = Sector():getCoordinates()
    homeSector = {x = sx, y = sy}

    -- Reset sell state
    sellRoute = {}
    sellRouteIndex = 0
    sellWaypoints = {}
    waypointIndex = 0
    sectorGoods = {}
    currentGoodIndex = 0
    resolvedStation = nil
    resolvedScript = nil
    sellResults = {}

    -- Scan current sector directly into sectorGoods (max single-station capacity per good)
    local sellable, _ = TradingUtility.detectBuyableAndSellableGoods()
    local currentGoods = {}
    for _, offer in pairs(sellable) do
        local name = offer.good.name
        local freeSpace = (offer.maxStock or 0) - (offer.stock or 0)
        if freeSpace > (currentGoods[name] or 0) then
            currentGoods[name] = freeSpace
        end
    end
    if next(currentGoods) ~= nil then
        sectorGoods[sx .. "_" .. sy] = currentGoods
    end

    -- Build candidate sectors for drone scouting
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
                if player:knowsSector(tx, ty) and InventorySellerController.sectorHasAnyStation(tx, ty, serverSeed) then
                    Server():setValue("invsell_" .. tx .. "_" .. ty, "")
                    table.insert(pendingDrones, {x = tx, y = ty})
                    table.insert(droneTargets, {x = tx, y = ty})
                end
            end
        end
    end

    totalDroneCount = #droneTargets

    if totalDroneCount == 0 then
        sellState = SELL_SCOUTING
        InventorySellerController.onScoutingComplete()
    else
        scanState = "scanning"
        sellState = SELL_SCOUTING
        broadcastInvokeClientFunction("updateStatus", "Scouting sectors... (0/" .. totalDroneCount .. " drones)")
        print("[InventorySeller] Sell run: scouting " .. totalDroneCount .. " sectors")
    end
end
callable(InventorySellerController, "startSellRun")

function InventorySellerController.stopSellRun()
    if not onServer() then return end

    if scanState == "scanning" then
        scanState = "idle"
        pendingDrones = {}
        droneTargets = {}
        dronesReceived = {}
        print("[InventorySeller] Scan aborted by user")
    end

    if sellState ~= SELL_IDLE then
        if sellState == SELL_SELLING then
            DockAI.reset()
        end
        local controller = ControlUnit()
        if controller then
            controller.autoPilotEnabled = false
            controller:stopShip()
        end
        print("[InventorySeller] Sell run stopped (was in state " .. sellState .. ")")
    end

    sellState = SELL_IDLE
    sellRoute = {}
    sellRouteIndex = 0
    sellWaypoints = {}
    waypointIndex = 0
    currentGoodIndex = 0
    resolvedStation = nil
    resolvedScript = nil

    broadcastInvokeClientFunction("updateStatus", "Stopped")
end
callable(InventorySellerController, "stopSellRun")

function InventorySellerController.requestUIUpdate()
    if not onServer() then return end
    InventorySellerController.sendSyncToClients()
    if sellState == SELL_SCOUTING then
        local rc = 0
        for _ in pairs(dronesReceived) do rc = rc + 1 end
        broadcastInvokeClientFunction("updateStatus", "Scouting... (" .. rc .. "/" .. totalDroneCount .. " drones)")
    elseif sellState == SELL_JUMPING then
        broadcastInvokeClientFunction("updateStatus", "Jumping to sell sector " .. sellRouteIndex .. "/" .. #sellRoute .. "...")
    elseif sellState == SELL_SELLING then
        local stop = sellRoute[sellRouteIndex]
        local goodEntry = stop and stop.goods[currentGoodIndex]
        local goodName = goodEntry and goodEntry.name or "?"
        broadcastInvokeClientFunction("updateStatus", "Selling " .. goodName .. " (sector " .. sellRouteIndex .. "/" .. #sellRoute .. ")...")
    elseif sellState == SELL_RETURNING then
        broadcastInvokeClientFunction("updateStatus", "Returning home...")
    elseif scanState == "scanning" then
        local rc = 0
        for _ in pairs(dronesReceived) do rc = rc + 1 end
        broadcastInvokeClientFunction("updateStatus", "Scanning... (" .. rc .. "/" .. totalDroneCount .. " drones)")
    else
        broadcastInvokeClientFunction("updateStatus", "Idle")
    end
end
callable(InventorySellerController, "requestUIUpdate")

function InventorySellerController.sendSyncToClients()
    local listData = InventorySellerController.serializeList()
    local sellableData = InventorySellerController.serializeSellable()
    local cargoData = InventorySellerController.serializeCargo()
    broadcastInvokeClientFunction("syncData", listData, sellableData, cargoData)
end

-- ============================================================
-- UPDATE LOOP (drone dispatch + polling + sell state machine)
-- ============================================================

function InventorySellerController.getUpdateInterval()
    if scanState == "scanning" then return 0 end
    if sellState ~= SELL_IDLE then return 0 end
    return 1
end

function InventorySellerController.updateServer(timeStep)
    local entity = Entity()
    if not valid(entity) then
        scanState = "idle"
        sellState = SELL_IDLE
        return
    end

    -- ==========================================
    -- DRONE DISPATCH + POLLING
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
            local color = Color(0.2, 0.8, 0.5, 1.0)
            dronePlan:addBlock(vec3(0, 0, 0), vec3(1, 1, 1), -1, 1, color, material, Matrix(), 0, nil)

            local droneMatrix = Matrix()
            droneMatrix.translation = entity.translationf + vec3(50, 0, 0)

            local droneName = "InvSeller Scanner " .. target.x .. "_" .. target.y
            local drone = sector:createShip(player, droneName, dronePlan, droneMatrix)

            if valid(drone) then
                drone.crew = Crew()
                drone.crew:add(1, CrewMan(CrewProfessionType.None))
                drone:addScript("data/scripts/entity/inventorysellerscanner.lua", entity.factionIndex)
                sector:transferEntity(drone, target.x, target.y, SectorChangeType.Jump)
            end
        end

        -- Poll for drone results
        for _, sc in pairs(droneTargets) do
            local key = sc.x .. "_" .. sc.y
            if not dronesReceived[key] then
                local data = Server():getValue("invsell_" .. key)
                if data and data ~= "" then
                    dronesReceived[key] = true
                    if data ~= "EMPTY" then
                        local goodsMap = {}
                        for line in string.gmatch(data, "[^\n]+") do
                            local name, cap = string.match(line, "^(.+)|(%d+)$")
                            if name and cap then
                                local capNum = tonumber(cap)
                                sellableGoods[name] = 1
                                if capNum > (goodsMap[name] or 0) then
                                    goodsMap[name] = capNum
                                end
                            end
                        end
                        if next(goodsMap) ~= nil then
                            sectorGoods[key] = goodsMap
                        end
                    end
                end
            end
        end

        local rc = 0
        for _ in pairs(dronesReceived) do rc = rc + 1 end

        -- Timeout check
        if #pendingDrones == 0 then
            scanElapsed = scanElapsed + timeStep
            if scanElapsed >= SCAN_TIMEOUT and rc < totalDroneCount then
                local timedOut = 0
                for _, sc in pairs(droneTargets) do
                    local key = sc.x .. "_" .. sc.y
                    if not dronesReceived[key] then
                        dronesReceived[key] = true
                        timedOut = timedOut + 1
                    end
                end
                rc = rc + timedOut
                print("[InventorySeller] " .. timedOut .. " drone(s) timed out")
            end
        end

        -- Status update
        if sellState == SELL_SCOUTING then
            broadcastInvokeClientFunction("updateStatus", "Scouting sectors... (" .. rc .. "/" .. totalDroneCount .. " drones)")
        else
            broadcastInvokeClientFunction("updateStatus", "Scanning... (" .. rc .. "/" .. totalDroneCount .. " drones)")
        end

        -- All drones returned (or timed out)
        if rc >= totalDroneCount then
            scanState = "idle"

            -- Clean up Server setValue keys
            for _, sc in pairs(droneTargets) do
                Server():setValue("invsell_" .. sc.x .. "_" .. sc.y, nil)
            end
            pendingDrones = {}
            droneTargets = {}
            dronesReceived = {}

            if sellState == SELL_SCOUTING then
                InventorySellerController.onScoutingComplete()
            else
                local found = 0
                for _, item in pairs(sellList) do
                    if sellableGoods[item.name] then found = found + 1 end
                end
                InventorySellerController.sendSyncToClients()
                broadcastInvokeClientFunction("updateStatus", "Scan complete: " .. found .. "/" .. #sellList .. " goods can be sold")
                print("[InventorySeller] Scan complete: " .. found .. "/" .. #sellList)
            end
        end
        return
    end

    -- ==========================================
    -- SELL STATE MACHINE
    -- ==========================================
    if sellState == SELL_IDLE then return end

    local sector = Sector()

    -- JUMPING TO SELL SECTOR
    if sellState == SELL_JUMPING then
        local cx, cy = sector:getCoordinates()
        local wp = sellWaypoints[waypointIndex]
        if cx == wp.x and cy == wp.y then
            if waypointIndex >= #sellWaypoints then
                -- Arrived at sell sector
                print("[InventorySeller] Arrived at sell sector " .. cx .. ":" .. cy .. " (stop " .. sellRouteIndex .. "/" .. #sellRoute .. ")")
                sellState = SELL_SELLING
                currentGoodIndex = 1
                resolvedStation = nil
                resolvedScript = nil
                DockAI.reset()
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                local stop = sellRoute[sellRouteIndex]
                broadcastInvokeClientFunction("updateStatus", "Selling " .. stop.goods[1].name .. " (sector " .. sellRouteIndex .. "/" .. #sellRoute .. ")...")
            else
                -- Advance to next waypoint
                waypointIndex = waypointIndex + 1
                local nextWp = sellWaypoints[waypointIndex]
                print("[InventorySeller] Waypoint " .. waypointIndex .. "/" .. #sellWaypoints .. " -> " .. nextWp.x .. ":" .. nextWp.y)
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                ShipAI():setJump(nextWp.x, nextWp.y)
                broadcastInvokeClientFunction("updateStatus", "Jumping " .. waypointIndex .. "/" .. #sellWaypoints .. " to sector " .. sellRouteIndex .. "/" .. #sellRoute .. "...")
            end
        end
        return
    end

    -- SELLING AT CURRENT SECTOR
    if sellState == SELL_SELLING then
        local stop = sellRoute[sellRouteIndex]
        if not stop then
            InventorySellerController.advanceSellRoute()
            return
        end

        -- Skip goods with nothing to sell
        while currentGoodIndex <= #stop.goods do
            local entry = stop.goods[currentGoodIndex]
            local gn = entry and entry.name
            if not gn then
                currentGoodIndex = currentGoodIndex + 1
            elseif (sellQuantities[gn] or 0) <= 0 then
                print("[InventorySeller] Skipping " .. gn .. " (none in cargo)")
                table.insert(sellResults, gn .. ": skipped (empty)")
                currentGoodIndex = currentGoodIndex + 1
            else
                break
            end
        end

        if currentGoodIndex > #stop.goods then
            InventorySellerController.advanceSellRoute()
            return
        end

        local goodName = stop.goods[currentGoodIndex].name
        local plannedQty = stop.goods[currentGoodIndex].qty

        -- Resolve station with the most free space for the current good
        if not resolvedStation then
            local qty = math.min(plannedQty, sellQuantities[goodName] or 0)
            local station, script, freeSpace = InventorySellerController.findStationForGood(entity, goodName, qty)
            if not valid(station) then
                print("[InventorySeller] No station has space for " .. goodName)
                table.insert(sellResults, goodName .. ": no station has space")
                currentGoodIndex = currentGoodIndex + 1
                return
            end
            resolvedStation = station.index
            resolvedScript = script
            DockAI.reset()
            local controller = ControlUnit()
            if controller then controller.autoPilotEnabled = true end
            print("[InventorySeller] Docking for " .. goodName .. " (have " .. qty .. ", station has " .. freeSpace .. " space)")
        end

        local station = sector:getEntity(resolvedStation)
        if not valid(station) then
            print("[InventorySeller] Station lost")
            resolvedStation = nil
            resolvedScript = nil
            DockAI.reset()
            return
        end

        DockAI.updateDockingUndocking(timeStep, station, 2,
            function(ship, dockStation)
                -- Fetch all offers from this station once
                local playerFaction = Faction(ship.factionIndex)
                local stationSellable = {}
                TradingUtility.getBuyableAndSellableGoods(dockStation, stationSellable, {}, playerFaction)
                local offerByGood = {}
                for _, o in pairs(stationSellable) do
                    if not offerByGood[o.good.name] then
                        offerByGood[o.good.name] = o
                    end
                end

                -- Sell all goods this station will buy in one session
                local curStop = sellRoute[sellRouteIndex]
                while currentGoodIndex <= #curStop.goods do
                    local entry = curStop.goods[currentGoodIndex]
                    local gn = entry.name
                    local qty = math.min(entry.qty, sellQuantities[gn] or 0)
                    if qty <= 0 then
                        currentGoodIndex = currentGoodIndex + 1
                    elseif offerByGood[gn] then
                        local offer = offerByGood[gn]
                        local result = dockStation:invokeFunction(offer.script, "buyFromShip", ship.index, gn, qty, 1)
                        if result == 0 then
                            -- Check actual remaining cargo to detect partial sells
                            local remaining = 0
                            for good, amount in pairs(ship:getCargos()) do
                                if good.name == gn then remaining = amount; break end
                            end
                            local sold = qty - remaining
                            print("[InventorySeller] Sold " .. sold .. "x " .. gn .. (remaining > 0 and " (station full, " .. remaining .. " remaining)" or ""))
                            table.insert(sellResults, gn .. " x" .. sold .. (remaining > 0 and " (partial)" or ": OK"))
                            sellQuantities[gn] = remaining
                            if remaining > 0 then
                                -- Station is full; undock and find one with more space
                                break
                            else
                                currentGoodIndex = currentGoodIndex + 1
                            end
                        else
                            print("[InventorySeller] Sell failed for " .. gn .. ": " .. tostring(result))
                            table.insert(sellResults, gn .. ": sell failed (" .. tostring(result) .. ")")
                            currentGoodIndex = currentGoodIndex + 1
                        end
                    else
                        break -- remaining goods need a different station
                    end
                end

                broadcastInvokeClientFunction("updateStatus", "Sold at stop " .. sellRouteIndex .. "/" .. #sellRoute .. ". Undocking...")
            end,
            function(ship, msg)
                -- Undocked: clear station, will re-resolve for any remaining goods
                print("[InventorySeller] Undocked")
                resolvedStation = nil
                resolvedScript = nil
                DockAI.reset()
            end
        )
        return
    end

    -- RETURNING HOME
    if sellState == SELL_RETURNING then
        local cx, cy = sector:getCoordinates()
        local wp = sellWaypoints[waypointIndex]
        if cx == wp.x and cy == wp.y then
            if waypointIndex >= #sellWaypoints then
                -- Arrived home
                print("[InventorySeller] Arrived home at " .. cx .. ":" .. cy)

                local controller = ControlUnit()
                if controller then
                    controller.autoPilotEnabled = false
                    controller:stopShip()
                end

                local summary = "Sell run complete"
                if #sellResults > 0 then
                    summary = summary .. ": " .. table.concat(sellResults, ", ")
                end

                sellState = SELL_IDLE
                sellRoute = {}
                sellRouteIndex = 0
                sellWaypoints = {}
                waypointIndex = 0
                sectorGoods = {}

                broadcastInvokeClientFunction("updateStatus", summary)
                print("[InventorySeller] " .. summary)
            else
                waypointIndex = waypointIndex + 1
                local nextWp = sellWaypoints[waypointIndex]
                print("[InventorySeller] Return waypoint " .. waypointIndex .. "/" .. #sellWaypoints .. " -> " .. nextWp.x .. ":" .. nextWp.y)
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                ShipAI():setJump(nextWp.x, nextWp.y)
                broadcastInvokeClientFunction("updateStatus", "Returning home " .. waypointIndex .. "/" .. #sellWaypoints .. "...")
            end
        end
        return
    end
end

-- ============================================================
-- SELL ROUTE PLANNING
-- ============================================================

function InventorySellerController.onScoutingComplete()
    local route = InventorySellerController.planSellRoute()

    if #route == 0 then
        print("[InventorySeller] No goods found that can be sold")
        sellState = SELL_IDLE
        broadcastInvokeClientFunction("updateStatus", "No sell list goods found nearby")
        return
    end

    sellRoute = route
    sellRouteIndex = 1
    sellResults = {}

    print("[InventorySeller] Planned route with " .. #route .. " stop(s):")
    for i, stop in ipairs(route) do
        local goodsStr = {}
        for _, g in ipairs(stop.goods) do
            table.insert(goodsStr, g.name .. "x" .. g.qty)
        end
        print("[InventorySeller]   Stop " .. i .. ": (" .. stop.x .. ":" .. stop.y .. ") -> " .. table.concat(goodsStr, ", "))
    end

    InventorySellerController.jumpToRouteStop()
end

function InventorySellerController.planSellRoute()
    -- Build qty remaining to place per good (only sell list items we have in cargo)
    local needed = {}  -- {[name] = qty remaining}
    for _, item in pairs(sellList) do
        local qty = sellQuantities[item.name] or 0
        if qty > 0 then
            needed[item.name] = qty
        end
    end

    -- Mutable copy of sector capacities (map: key -> {name -> capacity})
    local sectors = {}
    for key, goodsMap in pairs(sectorGoods) do
        local copy = {}
        for name, cap in pairs(goodsMap) do
            copy[name] = cap
        end
        sectors[key] = copy
    end

    -- Capacity-aware greedy set cover: each iteration picks the sector that covers
    -- the most total units of still-needed goods (respecting capacity limits).
    local selectedSectors = {}

    while true do
        local anyNeeded = false
        for _ in pairs(needed) do anyNeeded = true; break end
        if not anyNeeded then break end

        local bestKey = nil
        local bestUnits = 0
        local bestAllocation = nil

        for key, goodsMap in pairs(sectors) do
            local units = 0
            local allocation = {}
            for name, remaining in pairs(needed) do
                local cap = goodsMap[name] or 0
                local alloc = math.min(remaining, cap)
                if alloc > 0 then
                    units = units + alloc
                    allocation[name] = alloc
                end
            end
            if units > bestUnits then
                bestUnits = units
                bestKey = key
                bestAllocation = allocation
            end
        end

        if not bestKey or bestUnits == 0 then break end

        -- Build stop.goods = [{name=..., qty=...}, ...]
        local stopGoods = {}
        for name, qty in pairs(bestAllocation) do
            table.insert(stopGoods, {name = name, qty = qty})
        end

        table.insert(selectedSectors, {key = bestKey, goods = stopGoods})

        -- Reduce remaining needs and sector capacities
        for name, alloc in pairs(bestAllocation) do
            needed[name] = needed[name] - alloc
            if needed[name] <= 0 then needed[name] = nil end
            sectors[bestKey][name] = sectors[bestKey][name] - alloc
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
    for i, entry in ipairs(selectedSectors) do remaining[i] = entry end

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

function InventorySellerController.advanceSellRoute()
    if sellRouteIndex < #sellRoute then
        sellRouteIndex = sellRouteIndex + 1
        InventorySellerController.jumpToRouteStop()
    else
        InventorySellerController.startReturnHome()
    end
end

function InventorySellerController.jumpToRouteStop()
    local stop = sellRoute[sellRouteIndex]
    local entity = Entity()
    local cx, cy = Sector():getCoordinates()

    if cx == stop.x and cy == stop.y then
        -- Already in this sector, start selling directly
        sellState = SELL_SELLING
        currentGoodIndex = 1
        resolvedStation = nil
        resolvedScript = nil
        DockAI.reset()
        local controller = ControlUnit()
        if controller then controller.autoPilotEnabled = true end
        broadcastInvokeClientFunction("updateStatus", "Selling " .. stop.goods[1].name .. " (sector " .. sellRouteIndex .. "/" .. #sellRoute .. ")...")
        return
    end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        print("[InventorySeller] Lost hyperspace drive, aborting")
        InventorySellerController.stopSellRun()
        return
    end

    sellWaypoints = InventorySellerController.calculateJumpPath(cx, cy, stop.x, stop.y, math.floor(jumpRange))
    waypointIndex = 1
    sellState = SELL_JUMPING

    local wp = sellWaypoints[1]
    local controller = ControlUnit()
    if controller then controller.autoPilotEnabled = true end
    ShipAI():setJump(wp.x, wp.y)

    local totalJumps = #sellWaypoints
    if totalJumps > 1 then
        broadcastInvokeClientFunction("updateStatus", "Jumping 1/" .. totalJumps .. " to sector " .. sellRouteIndex .. "/" .. #sellRoute .. "...")
    else
        broadcastInvokeClientFunction("updateStatus", "Jumping to sell sector (" .. stop.x .. ":" .. stop.y .. ")...")
    end
end

function InventorySellerController.startReturnHome()
    if not homeSector then
        sellState = SELL_IDLE
        broadcastInvokeClientFunction("updateStatus", "Sell run complete (no return)")
        return
    end

    local entity = Entity()
    local cx, cy = Sector():getCoordinates()

    if cx == homeSector.x and cy == homeSector.y then
        local controller = ControlUnit()
        if controller then
            controller.autoPilotEnabled = false
            controller:stopShip()
        end
        sellState = SELL_IDLE

        local summary = "Sell run complete"
        if #sellResults > 0 then
            summary = summary .. ": " .. table.concat(sellResults, ", ")
        end
        broadcastInvokeClientFunction("updateStatus", summary)
        print("[InventorySeller] " .. summary)
        return
    end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        sellState = SELL_IDLE
        broadcastInvokeClientFunction("updateStatus", "Sell run done (no drive to return)")
        return
    end

    sellWaypoints = InventorySellerController.calculateJumpPath(cx, cy, homeSector.x, homeSector.y, math.floor(jumpRange))
    waypointIndex = 1
    sellState = SELL_RETURNING

    local wp = sellWaypoints[1]
    local controller = ControlUnit()
    if controller then controller.autoPilotEnabled = true end
    ShipAI():setJump(wp.x, wp.y)
    broadcastInvokeClientFunction("updateStatus", "Returning home 1/" .. #sellWaypoints .. "...")
end

-- Calculate a multi-jump path from (fromX, fromY) to (toX, toY) within jumpRange per hop
function InventorySellerController.calculateJumpPath(fromX, fromY, toX, toY, jumpRange)
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

-- Find the station in the current sector with the most free space for a good.
-- Prefers a station that can take the full qty; falls back to the one with max free space.
function InventorySellerController.findStationForGood(entity, goodName, qty)
    local sector = Sector()
    local stations = {sector:getEntitiesByType(EntityType.Station)}
    local playerFaction = Faction(entity.factionIndex)

    local bestStation = nil
    local bestScript = nil
    local bestFreeSpace = 0

    for _, station in pairs(stations) do
        if not valid(station) then goto nextStation end

        if playerFaction then
            local relations = playerFaction:getRelations(station.factionIndex)
            if relations < RELATIONS_THRESHOLD then goto nextStation end
        end

        local sellable = {}
        TradingUtility.getBuyableAndSellableGoods(station, sellable, {}, playerFaction)

        -- sellable = goods player can sell TO station (station demand)
        for _, offer in pairs(sellable) do
            if offer.good.name == goodName then
                local freeSpace = (offer.maxStock or 0) - (offer.stock or 0)
                if freeSpace > bestFreeSpace then
                    bestFreeSpace = freeSpace
                    bestStation = station
                    bestScript = offer.script
                end
                break
            end
        end

        ::nextStation::
    end

    if bestFreeSpace > 0 then
        return bestStation, bestScript, bestFreeSpace
    end
    return nil, nil, 0
end

-- ============================================================
-- SERIALIZATION
-- ============================================================

function InventorySellerController.serializeList()
    local lines = {}
    for _, item in pairs(sellList) do
        table.insert(lines, item.name)
    end
    return table.concat(lines, "\n")
end

function InventorySellerController.serializeSellable()
    local names = {}
    for name, _ in pairs(sellableGoods) do
        table.insert(names, name)
    end
    return table.concat(names, "\n")
end

function InventorySellerController.serializeCargo()
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
-- CLIENT FUNCTIONS (called via RPC from server)
-- ============================================================

function InventorySellerController.syncData(listData, sellableData, cargoData)
    if not onClient() then return end

    -- Parse sell list
    clientSellItems = {}
    if listData and listData ~= "" then
        for name in string.gmatch(listData, "[^\n]+") do
            table.insert(clientSellItems, {name = name})
        end
    end

    -- Parse sellable goods (found by scan)
    clientSellable = {}
    if sellableData and sellableData ~= "" then
        for name in string.gmatch(sellableData, "[^\n]+") do
            clientSellable[name] = 1
        end
    end

    -- Parse cargo and repopulate combo box
    clientCargo = {}
    comboGoodNames = {}
    if cargoData and cargoData ~= "" then
        local rawNames = {}
        for line in string.gmatch(cargoData, "[^\n]+") do
            local parts = {}
            for part in string.gmatch(line, "[^|]+") do
                table.insert(parts, part)
            end
            if #parts >= 2 then
                local name = parts[1]
                local amount = tonumber(parts[2]) or 0
                clientCargo[name] = amount
                table.insert(rawNames, name)
            end
        end
        -- Sort alphabetically by translated name
        table.sort(rawNames, function(a, b) return (a % _t) < (b % _t) end)
        comboGoodNames = rawNames

        -- Repopulate the combo box
        if goodsCombo then
            goodsCombo:clear()
            for _, name in ipairs(comboGoodNames) do
                goodsCombo:addEntry(name % _t .. " (" .. (clientCargo[name] or 0) .. ")")
            end
        end
    end

    InventorySellerController.renderList()
end
callable(InventorySellerController, "syncData")

function InventorySellerController.renderList()
    if not onClient() then return end
    if not listBox then return end

    listBox:clear()

    local hasSellableData = false
    for _ in pairs(clientSellable) do hasSellableData = true; break end

    for i, item in ipairs(clientSellItems) do
        local displayName = item.name % _t
        local text = displayName
        if hasSellableData and not clientSellable[item.name] then
            text = text .. "  [NOT FOUND]"
        end
        listBox:addEntry(text)

        -- Color: red if not found after scan
        if hasSellableData and not clientSellable[item.name] then
            listBox:setEntry(i - 1, text, false, false, ColorRGB(0.8, 0.2, 0.2))
        end
    end
end

function InventorySellerController.updateStatus(msg)
    if not onClient() then return end
    if statusLabel then statusLabel.caption = "Status: " .. msg end
end
callable(InventorySellerController, "updateStatus")

function InventorySellerController.refreshList()
    if not onClient() then return end
    if not listBox then return end
    listBox:clear()
end

-- ============================================================
-- STATE PERSISTENCE
-- ============================================================

function InventorySellerController.secure()
    return {
        sellList = sellList,
        sellableGoods = sellableGoods,
        sellState = sellState,
        homeSector = homeSector,
        sellRoute = sellRoute,
        sellRouteIndex = sellRouteIndex,
        currentGoodIndex = currentGoodIndex,
        sellResults = sellResults,
        sellQuantities = sellQuantities,
    }
end

function InventorySellerController.restore(data)
    if data then
        sellList = data.sellList or {}
        sellableGoods = data.sellableGoods or {}

        local savedState = data.sellState or SELL_IDLE
        if savedState == SELL_SCOUTING then
            -- Drones lost on restore, reset to idle
            sellState = SELL_IDLE
        elseif savedState == SELL_JUMPING or savedState == SELL_SELLING or savedState == SELL_RETURNING then
            sellState = savedState
            homeSector = data.homeSector
            sellRoute = data.sellRoute or {}
            sellRouteIndex = data.sellRouteIndex or 0
            currentGoodIndex = data.currentGoodIndex or 0
            sellResults = data.sellResults or {}
            sellQuantities = data.sellQuantities or {}

            -- Re-derive waypoints on restore
            if sellState == SELL_JUMPING and sellRouteIndex > 0 and sellRouteIndex <= #sellRoute then
                local stop = sellRoute[sellRouteIndex]
                local entity = Entity()
                if valid(entity) then
                    local cx, cy = Sector():getCoordinates()
                    local jumpRange = math.floor(entity.hyperspaceJumpReach or 0)
                    if jumpRange > 0 then
                        sellWaypoints = InventorySellerController.calculateJumpPath(cx, cy, stop.x, stop.y, jumpRange)
                        waypointIndex = 1
                        if #sellWaypoints > 0 then
                            ShipAI():setJump(sellWaypoints[1].x, sellWaypoints[1].y)
                        end
                    end
                end
            elseif sellState == SELL_RETURNING and homeSector then
                local entity = Entity()
                if valid(entity) then
                    local cx, cy = Sector():getCoordinates()
                    local jumpRange = math.floor(entity.hyperspaceJumpReach or 0)
                    if jumpRange > 0 then
                        sellWaypoints = InventorySellerController.calculateJumpPath(cx, cy, homeSector.x, homeSector.y, jumpRange)
                        waypointIndex = 1
                        if #sellWaypoints > 0 then
                            ShipAI():setJump(sellWaypoints[1].x, sellWaypoints[1].y)
                        end
                    end
                end
            elseif sellState == SELL_SELLING then
                DockAI.reset()
                resolvedStation = nil
                resolvedScript = nil
            end
        else
            sellState = SELL_IDLE
        end
    end
end
