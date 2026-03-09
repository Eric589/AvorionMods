-- Auto Trader Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/entity/?.lua"
include("utility")
include("callable")
local TradingUtility = include("tradingutility")
local DockAI = include("ai/dock")
local FactoryMap = include("factorymap")
local SectorSpecifics = include("sectorspecifics")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace AutoTraderController
AutoTraderController = {}

local RELATIONS_THRESHOLD = -30000 -- minimum relations to trade (matches vanilla factory/consumer)

-- Format number with dot separators: 1234567 -> "1.234.567"
local function formatNum(n)
    local s = tostring(math.floor(n))
    local result = ""
    local len = #s
    for i = 1, len do
        result = result .. s:sub(i, i)
        local remaining = len - i
        if remaining > 0 and remaining % 3 == 0 then
            result = result .. "."
        end
    end
    return result
end

local function getJumpRange(entity)
    local jumpReach = entity.hyperspaceJumpReach
    if jumpReach and jumpReach > 0 then
        return math.floor(jumpReach)
    end
    return SCAN_RANGE_FALLBACK
end

-- States
local STATE_IDLE = 0
local STATE_DOCK_BUY = 1
local STATE_DOCK_SELL = 3
local STATE_SCANNING = 5
local STATE_JUMP_TO_BUY = 6
local STATE_JUMP_TO_SELL = 7

-- Trade state
local state = STATE_IDLE
local trade = nil

-- Scan state
local SCAN_RANGE_FALLBACK = 5
local scannedSectors = {}
local sectorsReceived = {}
local totalExpectedSectors = 0
local pendingDrones = {}
local dispatchTimer = 0
local scanElapsed = 0
local SCAN_TIMEOUT = 60 -- seconds after last drone dispatched before marking missing sectors as empty
local homeSector = nil
local bestRoute = nil

-- UI elements
local statusLabel = nil
local infoLabel1 = nil
local infoLabel2 = nil
local tradeButton = nil

function AutoTraderController.getIcon()
    return "chart.png"
end

function AutoTraderController.interactionPossible(playerIndex)
    if onServer() then return false end
    local player = Player()
    local entity = Entity()
    if player.craft.index.value == entity.id.value then
        return true, ""
    else
        return false, ""
    end
end

function AutoTraderController.getInteractionText()
    return "Auto Trader"
end

function AutoTraderController.initialize()
    if onServer() then
        local entity = Entity()
        if entity then
            local initFlag = entity:getValue("autotrader_initialized")
            if not initFlag then
                entity:setValue("autotrader_initialized", true)
            end
        end
    end
end

function AutoTraderController.initUI()
    local res = getResolution()
    local size = vec2(400, 250)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Auto Trader"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Auto Trader")

    tradeButton = window:createButton(Rect(10, 10, 195, 50), "Local Trade", "onTradeButton")
    window:createButton(Rect(205, 10, 390, 50), "Scan Nearby", "onScanNearby")
    window:createButton(Rect(10, 60, 390, 100), "Stop", "onStop")

    statusLabel = window:createLabel(vec2(10, 110), "Status: Idle", 15)
    statusLabel.width = 380

    infoLabel1 = window:createLabel(vec2(10, 140), "", 15)
    infoLabel1.width = 380

    infoLabel2 = window:createLabel(vec2(10, 165), "", 15)
    infoLabel2.width = 380
end

function AutoTraderController.onShowWindow()
    invokeServerFunction("requestUIUpdate")
end

function AutoTraderController.onTradeButton()
    invokeServerFunction("startTrade")
end

function AutoTraderController.onScanNearby()
    invokeServerFunction("startNearbyScan")
end

function AutoTraderController.onStop()
    invokeServerFunction("stopTrade")
end

-- ============================================================
-- TRADE (local or cross-sector depending on bestRoute)
-- ============================================================

function AutoTraderController.startTrade()
    if not onServer() then return end
    if state ~= STATE_IDLE then
        broadcastInvokeClientFunction("updateStatus", "Already busy...")
        return
    end

    -- If we have a cross-sector route from scanning, execute it
    if bestRoute then
        AutoTraderController.executeCrossSectorRoute()
        return
    end

    -- Otherwise do a local trade
    local entity = Entity()
    local sellable, buyable = TradingUtility.detectBuyableAndSellableGoods()

    print("[AutoTrader] Local scan: " .. #buyable .. " buyable, " .. #sellable .. " sellable")

    local bestTrade = AutoTraderController.findBestLocalTrade(buyable, sellable, entity)

    if not bestTrade then
        print("[AutoTrader] No profitable local trades found")
        broadcastInvokeClientFunction("updateStatus", "No profitable local trades")
        return
    end

    trade = bestTrade

    local line1 = string.format("%dx %s | Profit: %s", trade.amount, trade.goodName, formatNum(trade.totalProfit))
    local line2 = string.format("Buy %d -> Sell %d (have %d, buy %d)", trade.buyPrice, trade.sellPrice, trade.alreadyHave, trade.toBuy)
    print("[AutoTrader] " .. line1 .. " | " .. line2)
    broadcastInvokeClientFunction("updateInfo", line1, line2)

    if trade.toBuy > 0 then
        state = STATE_DOCK_BUY
        DockAI.reset()
        local controller = ControlUnit()
        if controller then controller.autoPilotEnabled = true end
        broadcastInvokeClientFunction("updateStatus", "Flying to buy station...")
    else
        state = STATE_DOCK_SELL
        DockAI.reset()
        local controller = ControlUnit()
        if controller then controller.autoPilotEnabled = true end
        broadcastInvokeClientFunction("updateStatus", "Have cargo, flying to sell...")
    end
end
callable(AutoTraderController, "startTrade")

function AutoTraderController.executeCrossSectorRoute()
    local route = bestRoute
    bestRoute = nil

    trade = {
        goodName = route.goodName,
        amount = route.amount,
        toBuy = route.toBuy,
        alreadyHave = route.alreadyHave,
        buyPrice = route.buyPrice,
        sellPrice = route.sellPrice,
        profitPerUnit = route.profitPerUnit,
        totalProfit = route.totalProfit,
        buySectorX = route.buySectorX,
        buySectorY = route.buySectorY,
        buyStationName = route.buyStationName,
        sellSectorX = route.sellSectorX,
        sellSectorY = route.sellSectorY,
        sellStationName = route.sellStationName,
        goodSize = route.goodSize,
    }

    local cargoInfo = ""
    if trade.alreadyHave > 0 then
        cargoInfo = string.format(" (%d cargo, buy %d)", trade.alreadyHave, trade.toBuy)
    end
    local line1 = string.format("%dx %s%s | Profit: %s", trade.amount, trade.goodName, cargoInfo, formatNum(trade.totalProfit))
    local line2 = string.format("(%d:%d) %d -> (%d:%d) %d",
        trade.buySectorX, trade.buySectorY, trade.buyPrice,
        trade.sellSectorX, trade.sellSectorY, trade.sellPrice)
    print("[AutoTrader] Executing route: " .. line1 .. " | " .. line2)
    broadcastInvokeClientFunction("updateInfo", line1, line2)
    broadcastInvokeClientFunction("updateButtonText", "Local Trade")

    local entity = Entity()
    local controller = ControlUnit()
    if controller then controller.autoPilotEnabled = true end

    local jumpRange = getJumpRange(entity)

    -- Skip buy if we already have all the cargo
    if trade.toBuy > 0 then
        local cx, cy = Sector():getCoordinates()
        if cx == trade.buySectorX and cy == trade.buySectorY then
            state = STATE_DOCK_BUY
            DockAI.reset()
            broadcastInvokeClientFunction("updateStatus", "Docking to buy...")
        else
            trade.buyWaypoints = AutoTraderController.calculateJumpPath(cx, cy, trade.buySectorX, trade.buySectorY, jumpRange)
            trade.waypointIndex = 1
            state = STATE_JUMP_TO_BUY
            local wp = trade.buyWaypoints[1]
            ShipAI():setJump(wp.x, wp.y)
            local totalJumps = #trade.buyWaypoints
            if totalJumps > 1 then
                broadcastInvokeClientFunction("updateStatus", "Jumping to buy 1/" .. totalJumps .. "...")
            else
                broadcastInvokeClientFunction("updateStatus", "Jumping to buy (" .. trade.buySectorX .. ":" .. trade.buySectorY .. ")...")
            end
        end
    else
        local cx, cy = Sector():getCoordinates()
        if cx == trade.sellSectorX and cy == trade.sellSectorY then
            state = STATE_DOCK_SELL
            DockAI.reset()
            broadcastInvokeClientFunction("updateStatus", "Docking to sell...")
        else
            trade.sellWaypoints = AutoTraderController.buildSellWaypoints(entity, cx, cy, trade.sellSectorX, trade.sellSectorY, jumpRange)
            if not trade.sellWaypoints or #trade.sellWaypoints == 0 then
                print("[AutoTrader] Cannot reach sell sector (rift/blocked)")
                broadcastInvokeClientFunction("updateStatus", "Sell sector unreachable")
                AutoTraderController.stopTrade()
                return
            end
            trade.waypointIndex = 1
            state = STATE_JUMP_TO_SELL
            local wp = trade.sellWaypoints[1]
            ShipAI():setJump(wp.x, wp.y)
            local totalJumps = #trade.sellWaypoints
            if totalJumps > 1 then
                broadcastInvokeClientFunction("updateStatus", "Jumping to sell 1/" .. totalJumps .. " (via home)...")
            else
                broadcastInvokeClientFunction("updateStatus", "Jumping to sell (" .. trade.sellSectorX .. ":" .. trade.sellSectorY .. ")...")
            end
        end
    end
end

function AutoTraderController.findBestLocalTrade(buyable, sellable, entity)
    local bestTrade = nil
    local bestProfit = 0
    local playerFaction = Faction(entity.factionIndex)
    local credits = playerFaction and playerFaction.money or 0
    local cargoSpace = entity.freeCargoSpace or 0

    local existingCargo = {}
    for good, amount in pairs(entity:getCargos()) do
        if amount > 0 then
            existingCargo[good.name] = amount
        end
    end

    for _, buyOffer in pairs(buyable) do
        for _, sellOffer in pairs(sellable) do
            if buyOffer.good.name == sellOffer.good.name
                and buyOffer.stationIndex ~= sellOffer.stationIndex then

                if playerFaction then
                    local buyStation = Entity(buyOffer.stationIndex)
                    local sellStation = Entity(sellOffer.stationIndex)
                    if valid(buyStation) and playerFaction:getRelations(buyStation.factionIndex) < RELATIONS_THRESHOLD then
                        goto nextPair
                    end
                    if valid(sellStation) and playerFaction:getRelations(sellStation.factionIndex) < RELATIONS_THRESHOLD then
                        goto nextPair
                    end
                end
                local priceDiff = sellOffer.price - buyOffer.price
                if priceDiff > 0 then
                    local alreadyHave = existingCargo[buyOffer.good.name] or 0
                    local maxBuy = buyOffer.stock
                    local maxSell = sellOffer.maxStock - sellOffer.stock
                    local maxCargo = 0
                    if buyOffer.good.size > 0 then
                        maxCargo = math.floor(cargoSpace / buyOffer.good.size) + alreadyHave
                    end
                    local maxAfford = math.floor(credits / buyOffer.price) + alreadyHave
                    local amount = math.min(maxBuy + alreadyHave, maxSell, maxCargo, maxAfford)
                    local toBuy = math.max(0, amount - alreadyHave)
                    if amount > 0 then
                        local totalProfit = priceDiff * amount
                        if totalProfit > bestProfit then
                            bestProfit = totalProfit
                            bestTrade = {
                                goodName = buyOffer.good.name,
                                amount = amount,
                                toBuy = toBuy,
                                alreadyHave = alreadyHave,
                                buyStationIndex = buyOffer.stationIndex,
                                buyScript = buyOffer.script,
                                buyPrice = buyOffer.price,
                                sellStationIndex = sellOffer.stationIndex,
                                sellScript = sellOffer.script,
                                sellPrice = sellOffer.price,
                                profitPerUnit = priceDiff,
                                totalProfit = totalProfit,
                            }
                        end
                    end
                end
            end
            ::nextPair::
        end
    end

    return bestTrade
end

-- ============================================================
-- NEARBY SCAN (cross-sector with drones)
-- ============================================================

local function sectorHasAnyStation(x, y, serverSeed)
    local specs = SectorSpecifics()
    specs:initialize(x, y, serverSeed)
    if not specs.generationTemplate then return false end
    if not specs.generationTemplate.contents then return false end
    local ok, contents = pcall(specs.generationTemplate.contents, x, y)
    if not ok or not contents then return false end
    return (contents.stations or 0) > 0
end

function AutoTraderController.startNearbyScan()
    if not onServer() then return end
    if state ~= STATE_IDLE then
        broadcastInvokeClientFunction("updateStatus", "Already busy...")
        return
    end

    local entity = Entity()
    local player = Player()
    local sector = Sector()
    local cx, cy = sector:getCoordinates()
    homeSector = {x = cx, y = cy}

    local range = getJumpRange(entity)
    local rangeSq = range * range

    scannedSectors = {}
    sectorsReceived = {}
    pendingDrones = {}
    bestRoute = nil
    dispatchTimer = 0
    scanElapsed = 0

    for dx = -range, range do
        for dy = -range, range do
            if dx * dx + dy * dy <= rangeSq then
                local tx, ty = cx + dx, cy + dy
                Server():setValue("autotrade_" .. tx .. "_" .. ty, "")
            end
        end
    end

    AutoTraderController.scanCurrentSector(cx, cy, entity)
    table.insert(scannedSectors, {x = cx, y = cy})
    sectorsReceived[cx .. "_" .. cy] = true

    local serverSeed = Server().seed
    for dx = -range, range do
        for dy = -range, range do
            local distSq = dx * dx + dy * dy
            if distSq > 0 and distSq <= rangeSq then
                local tx, ty = cx + dx, cy + dy
                if player:knowsSector(tx, ty) and sectorHasAnyStation(tx, ty, serverSeed) then
                    table.insert(pendingDrones, {x = tx, y = ty})
                    table.insert(scannedSectors, {x = tx, y = ty})
                end
            end
        end
    end

    totalExpectedSectors = #scannedSectors
    state = STATE_SCANNING

    print("[AutoTrader] Range " .. range .. ", queued " .. #pendingDrones .. " drones (trading post sectors only) + current sector")
    broadcastInvokeClientFunction("updateStatus", "Scanning 1/" .. totalExpectedSectors .. "...")
    broadcastInvokeClientFunction("updateInfo", "", "")
end
callable(AutoTraderController, "startNearbyScan")

function AutoTraderController.scanCurrentSector(cx, cy, entity)
    local sellable, buyable = TradingUtility.detectBuyableAndSellableGoods()
    local playerFaction = Faction(entity.factionIndex)
    local lines = {}

    for _, offer in pairs(buyable) do
        if playerFaction and valid(offer.station) then
            if playerFaction:getRelations(offer.station.factionIndex) < RELATIONS_THRESHOLD then
                goto skipBuy
            end
        end
        local stationName = offer.station and tostring(offer.station) or ""
        table.insert(lines, string.format("B|%s|%d|%d|%d|%.2f|%s",
            offer.good.name, math.floor(offer.stock), math.floor(offer.maxStock),
            math.floor(offer.price), offer.good.size, stationName))
        ::skipBuy::
    end

    for _, offer in pairs(sellable) do
        if playerFaction and valid(offer.station) then
            if playerFaction:getRelations(offer.station.factionIndex) < RELATIONS_THRESHOLD then
                goto skipSell
            end
        end
        local stationName = offer.station and tostring(offer.station) or ""
        table.insert(lines, string.format("S|%s|%d|%d|%d|%.2f|%s",
            offer.good.name, math.floor(offer.stock), math.floor(offer.maxStock),
            math.floor(offer.price), offer.good.size, stationName))
        ::skipSell::
    end

    local data = table.concat(lines, "\n")
    if data == "" then data = "EMPTY" end
    Server():setValue("autotrade_" .. cx .. "_" .. cy, data)
    print("[AutoTrader] Sector " .. cx .. ":" .. cy .. ": " .. #lines .. " offers")
end

function AutoTraderController.collectScanResults()
    local allBuyable = {}
    local allSellable = {}

    for _, sc in pairs(scannedSectors) do
        local key = "autotrade_" .. sc.x .. "_" .. sc.y
        local data = Server():getValue(key)

        if data and data ~= "" and data ~= "EMPTY" then
            for line in string.gmatch(data, "[^\n]+") do
                local parts = {}
                for part in string.gmatch(line, "[^|]+") do
                    table.insert(parts, part)
                end

                if #parts >= 6 then
                    local offerType = parts[1]
                    local offer = {
                        goodName = parts[2],
                        stock = tonumber(parts[3]) or 0,
                        maxStock = tonumber(parts[4]) or 0,
                        price = tonumber(parts[5]) or 0,
                        goodSize = tonumber(parts[6]) or 1,
                        stationName = parts[7] or "",
                        sectorX = sc.x,
                        sectorY = sc.y,
                    }

                    if offerType == "B" then
                        table.insert(allBuyable, offer)
                    elseif offerType == "S" then
                        table.insert(allSellable, offer)
                    end
                end
            end
        end
    end

    return allBuyable, allSellable
end

function AutoTraderController.findBestCrossSectorRoute(allBuyable, allSellable, entity)
    local best = nil
    local bestProfit = 0

    local cargoSpace = entity.freeCargoSpace or 0
    local faction = Faction(entity.factionIndex)
    local credits = faction and faction.money or 0

    local existingCargo = {}
    for good, amount in pairs(entity:getCargos()) do
        if amount > 0 then
            existingCargo[good.name] = amount
        end
    end

    for _, buyOffer in pairs(allBuyable) do
        for _, sellOffer in pairs(allSellable) do
            if buyOffer.goodName == sellOffer.goodName then
                local sameSector = (buyOffer.sectorX == sellOffer.sectorX and buyOffer.sectorY == sellOffer.sectorY)
                local sameStation = sameSector and (buyOffer.stationName == sellOffer.stationName)

                if not sameStation then
                    local priceDiff = sellOffer.price - buyOffer.price
                    if priceDiff > 0 then
                        local alreadyHave = existingCargo[buyOffer.goodName] or 0
                        local maxBuy = buyOffer.stock
                        local maxSell = sellOffer.maxStock - sellOffer.stock
                        local maxCargo = 0
                        if buyOffer.goodSize > 0 then
                            maxCargo = math.floor(cargoSpace / buyOffer.goodSize) + alreadyHave
                        end
                        local maxAfford = math.floor(credits / buyOffer.price) + alreadyHave

                        local amount = math.min(maxBuy + alreadyHave, maxSell, maxCargo, maxAfford)
                        local toBuy = math.max(0, amount - alreadyHave)

                        if amount > 0 then
                            local totalProfit = priceDiff * amount
                            if totalProfit > bestProfit then
                                bestProfit = totalProfit
                                best = {
                                    goodName = buyOffer.goodName,
                                    amount = amount,
                                    toBuy = toBuy,
                                    alreadyHave = alreadyHave,
                                    buyPrice = buyOffer.price,
                                    sellPrice = sellOffer.price,
                                    profitPerUnit = priceDiff,
                                    totalProfit = totalProfit,
                                    buySectorX = buyOffer.sectorX,
                                    buySectorY = buyOffer.sectorY,
                                    buyStationName = buyOffer.stationName,
                                    sellSectorX = sellOffer.sectorX,
                                    sellSectorY = sellOffer.sectorY,
                                    sellStationName = sellOffer.stationName,
                                    goodSize = buyOffer.goodSize,
                                }
                            end
                        end
                    end
                end
            end
        end
    end

    return best
end

-- Build sell waypoints from current position, routing via home sector if not reachable in 1 jump
-- Returns list of {x,y} waypoints
function AutoTraderController.buildSellWaypoints(entity, cx, cy, sellX, sellY, jumpRange)
    local dx = sellX - cx
    local dy = sellY - cy
    local distSq = dx * dx + dy * dy

    -- Can we jump directly?
    if distSq <= jumpRange * jumpRange then
        return {{x = sellX, y = sellY}}
    end

    -- Not reachable in 1 jump — route via home sector if available
    if homeSector then
        local waypoints = {}
        if cx ~= homeSector.x or cy ~= homeSector.y then
            table.insert(waypoints, {x = homeSector.x, y = homeSector.y})
        end
        table.insert(waypoints, {x = sellX, y = sellY})
        return waypoints
    end

    -- No home sector, try straight-line path
    return AutoTraderController.calculateJumpPath(cx, cy, sellX, sellY, jumpRange)
end

-- Calculate a multi-jump path from (fromX,fromY) to (toX,toY) within jumpRange per hop
-- Returns list of {x,y} waypoints (empty if already at destination)
function AutoTraderController.calculateJumpPath(fromX, fromY, toX, toY, jumpRange)
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

        -- Step toward destination, slightly under jump range to account for rounding
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

-- ============================================================
-- STOP
-- ============================================================

function AutoTraderController.stopTrade()
    if not onServer() then return end
    state = STATE_IDLE
    trade = nil
    bestRoute = nil
    DockAI.reset()

    local controller = ControlUnit()
    if controller then
        controller.autoPilotEnabled = false
        controller:stopShip()
    end

    print("[AutoTrader] Stopped")
    broadcastInvokeClientFunction("updateStatus", "Stopped")
    broadcastInvokeClientFunction("updateInfo", "", "")
    broadcastInvokeClientFunction("updateButtonText", "Local Trade")
end
callable(AutoTraderController, "stopTrade")

-- ============================================================
-- UI CALLBACKS
-- ============================================================

function AutoTraderController.requestUIUpdate()
    if not onServer() then return end

    if state == STATE_IDLE then
        if bestRoute then
            local cargoInfo = ""
            if bestRoute.alreadyHave and bestRoute.alreadyHave > 0 then
                cargoInfo = string.format(" (%d cargo, buy %d)", bestRoute.alreadyHave, bestRoute.toBuy)
            end
            local line1 = string.format("%dx %s%s | Profit: %s", bestRoute.amount, bestRoute.goodName, cargoInfo, formatNum(bestRoute.totalProfit))
            local line2 = string.format("(%d:%d) %d -> (%d:%d) %d",
                bestRoute.buySectorX, bestRoute.buySectorY, bestRoute.buyPrice,
                bestRoute.sellSectorX, bestRoute.sellSectorY, bestRoute.sellPrice)
            broadcastInvokeClientFunction("updateStatus", "Route ready")
            broadcastInvokeClientFunction("updateInfo", line1, line2)
            broadcastInvokeClientFunction("updateButtonText", "Execute Route")
        else
            broadcastInvokeClientFunction("updateStatus", "Idle")
            broadcastInvokeClientFunction("updateInfo", "", "")
            broadcastInvokeClientFunction("updateButtonText", "Local Trade")
        end
    elseif state == STATE_SCANNING then
        local receivedCount = 0
        for _ in pairs(sectorsReceived) do receivedCount = receivedCount + 1 end
        broadcastInvokeClientFunction("updateStatus", "Scanning " .. receivedCount .. "/" .. totalExpectedSectors .. "...")
    elseif trade then
        local cargoInfo = ""
        if trade.alreadyHave and trade.alreadyHave > 0 then
            cargoInfo = string.format(" (%d cargo, buy %d)", trade.alreadyHave, trade.toBuy)
        end
        local line1 = string.format("%dx %s%s | Profit: %s", trade.amount, trade.goodName, cargoInfo, formatNum(trade.totalProfit))
        local line2 = ""
        if trade.buySectorX then
            line2 = string.format("(%d:%d) %d -> (%d:%d) %d",
                trade.buySectorX, trade.buySectorY, trade.buyPrice,
                trade.sellSectorX, trade.sellSectorY, trade.sellPrice)
        else
            line2 = string.format("Buy %d -> Sell %d", trade.buyPrice, trade.sellPrice)
        end
        broadcastInvokeClientFunction("updateInfo", line1, line2)
        broadcastInvokeClientFunction("updateButtonText", "Local Trade")

        if state == STATE_JUMP_TO_BUY then
            local jumpInfo = ""
            if trade.buyWaypoints and #trade.buyWaypoints > 1 then
                jumpInfo = " " .. (trade.waypointIndex or 1) .. "/" .. #trade.buyWaypoints
            end
            broadcastInvokeClientFunction("updateStatus", "Jumping to buy" .. jumpInfo .. "...")
        elseif state == STATE_DOCK_BUY then
            broadcastInvokeClientFunction("updateStatus", "Buying...")
        elseif state == STATE_JUMP_TO_SELL then
            local jumpInfo = ""
            if trade.sellWaypoints and #trade.sellWaypoints > 1 then
                jumpInfo = " " .. (trade.waypointIndex or 1) .. "/" .. #trade.sellWaypoints
            end
            broadcastInvokeClientFunction("updateStatus", "Jumping to sell" .. jumpInfo .. "...")
        elseif state == STATE_DOCK_SELL then
            broadcastInvokeClientFunction("updateStatus", "Selling...")
        end
    end
end
callable(AutoTraderController, "requestUIUpdate")

function AutoTraderController.updateStatus(msg)
    if not onClient() then return end
    if statusLabel then statusLabel.caption = "Status: " .. msg end
end
callable(AutoTraderController, "updateStatus")

function AutoTraderController.updateInfo(line1, line2)
    if not onClient() then return end
    if infoLabel1 then infoLabel1.caption = line1 end
    if infoLabel2 then infoLabel2.caption = line2 end
end
callable(AutoTraderController, "updateInfo")

function AutoTraderController.updateButtonText(text)
    if not onClient() then return end
    if tradeButton then tradeButton.caption = text end
end
callable(AutoTraderController, "updateButtonText")

-- ============================================================
-- UPDATE LOOP
-- ============================================================

function AutoTraderController.getUpdateInterval()
    if state ~= STATE_IDLE then return 0 end
    return 1
end

function AutoTraderController.updateServer(timeStep)
    if state == STATE_IDLE then return end

    local entity = Entity()
    local sector = Sector()

    -- SCANNING: dispatch drones from queue, poll for results
    if state == STATE_SCANNING then
        dispatchTimer = dispatchTimer + timeStep
        if dispatchTimer >= 1.0 and #pendingDrones > 0 then
            dispatchTimer = 0
            local target = table.remove(pendingDrones, 1)
            local player = Player()

            local dronePlan = BlockPlan()
            local material = Material(MaterialType.Iron)
            local color = Color(0.2, 0.8, 0.2, 1.0)
            dronePlan:addBlock(vec3(0, 0, 0), vec3(1, 1, 1), -1, 1, color, material, Matrix(), 0, nil)

            local droneMatrix = Matrix()
            droneMatrix.translation = entity.translationf + vec3(50, 0, 0)

            local droneName = "Trade Scanner " .. target.x .. "_" .. target.y
            local drone = sector:createShip(player, droneName, dronePlan, droneMatrix)

            if valid(drone) then
                drone.crew = Crew()
                drone.crew:add(1, CrewMan(CrewProfessionType.None))
                drone:addScript("data/scripts/entity/dronetradescanner.lua", entity.factionIndex)
                sector:transferEntity(drone, target.x, target.y, SectorChangeType.Jump)
            end
        end

        for _, sc in pairs(scannedSectors) do
            local key = sc.x .. "_" .. sc.y
            if not sectorsReceived[key] then
                local data = Server():getValue("autotrade_" .. key)
                if data and data ~= "" then
                    sectorsReceived[key] = true
                end
            end
        end

        local receivedCount = 0
        for _ in pairs(sectorsReceived) do receivedCount = receivedCount + 1 end

        -- Timeout: if all drones dispatched and we've waited long enough, mark missing sectors as empty (drone was likely destroyed)
        if #pendingDrones == 0 then
            scanElapsed = scanElapsed + timeStep
            if scanElapsed >= SCAN_TIMEOUT and receivedCount < totalExpectedSectors then
                local timedOut = 0
                for _, sc in pairs(scannedSectors) do
                    local key = sc.x .. "_" .. sc.y
                    if not sectorsReceived[key] then
                        Server():setValue("autotrade_" .. key, "EMPTY")
                        sectorsReceived[key] = true
                        timedOut = timedOut + 1
                    end
                end
                receivedCount = receivedCount + timedOut
                print("[AutoTrader] " .. timedOut .. " sectors timed out (drone destroyed?), marked empty")
            end
        end

        broadcastInvokeClientFunction("updateStatus", "Scanning " .. receivedCount .. "/" .. totalExpectedSectors .. "...")

        if receivedCount >= totalExpectedSectors then
            local allBuyable, allSellable = AutoTraderController.collectScanResults()
            print("[AutoTrader] " .. #allBuyable .. " buy, " .. #allSellable .. " sell across " .. receivedCount .. " sectors")

            bestRoute = AutoTraderController.findBestCrossSectorRoute(allBuyable, allSellable, entity)

            if bestRoute then
                local cargoInfo = ""
                if bestRoute.alreadyHave and bestRoute.alreadyHave > 0 then
                    cargoInfo = string.format(" (%d cargo, buy %d)", bestRoute.alreadyHave, bestRoute.toBuy)
                end
                local line1 = string.format("%dx %s%s | Profit: %s", bestRoute.amount, bestRoute.goodName, cargoInfo, formatNum(bestRoute.totalProfit))
                local line2 = string.format("(%d:%d) %d -> (%d:%d) %d",
                    bestRoute.buySectorX, bestRoute.buySectorY, bestRoute.buyPrice,
                    bestRoute.sellSectorX, bestRoute.sellSectorY, bestRoute.sellPrice)
                print("[AutoTrader] Best: " .. line1 .. " | " .. line2)
                broadcastInvokeClientFunction("updateStatus", "Route found!")
                broadcastInvokeClientFunction("updateInfo", line1, line2)
                broadcastInvokeClientFunction("updateButtonText", "Execute Route")
            else
                print("[AutoTrader] No profitable routes")
                broadcastInvokeClientFunction("updateStatus", "No profitable routes")
                broadcastInvokeClientFunction("updateInfo", "", "")
            end

            state = STATE_IDLE
        end
        return
    end

    -- JUMP TO BUY SECTOR (multi-jump waypoints)
    if state == STATE_JUMP_TO_BUY then
        local cx, cy = sector:getCoordinates()
        local wp = trade.buyWaypoints[trade.waypointIndex]
        if cx == wp.x and cy == wp.y then
            if trade.waypointIndex >= #trade.buyWaypoints then
                print("[AutoTrader] Arrived at buy sector " .. cx .. ":" .. cy)
                state = STATE_DOCK_BUY
                DockAI.reset()
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                broadcastInvokeClientFunction("updateStatus", "Arrived, docking to buy...")
            else
                trade.waypointIndex = trade.waypointIndex + 1
                local nextWp = trade.buyWaypoints[trade.waypointIndex]
                print("[AutoTrader] Waypoint " .. trade.waypointIndex .. "/" .. #trade.buyWaypoints .. " -> " .. nextWp.x .. ":" .. nextWp.y)
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                ShipAI():setJump(nextWp.x, nextWp.y)
                broadcastInvokeClientFunction("updateStatus", "Jumping to buy " .. trade.waypointIndex .. "/" .. #trade.buyWaypoints .. "...")
            end
        end
        return
    end

    -- JUMP TO SELL SECTOR (multi-jump waypoints)
    if state == STATE_JUMP_TO_SELL then
        local cx, cy = sector:getCoordinates()
        local wp = trade.sellWaypoints[trade.waypointIndex]
        if cx == wp.x and cy == wp.y then
            if trade.waypointIndex >= #trade.sellWaypoints then
                print("[AutoTrader] Arrived at sell sector " .. cx .. ":" .. cy)
                state = STATE_DOCK_SELL
                DockAI.reset()
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                broadcastInvokeClientFunction("updateStatus", "Arrived, docking to sell...")
            else
                trade.waypointIndex = trade.waypointIndex + 1
                local nextWp = trade.sellWaypoints[trade.waypointIndex]
                print("[AutoTrader] Waypoint " .. trade.waypointIndex .. "/" .. #trade.sellWaypoints .. " -> " .. nextWp.x .. ":" .. nextWp.y)
                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end
                ShipAI():setJump(nextWp.x, nextWp.y)
                broadcastInvokeClientFunction("updateStatus", "Jumping to sell " .. trade.waypointIndex .. "/" .. #trade.sellWaypoints .. "...")
            end
        end
        return
    end

    -- DOCKING STATES
    if not trade then return end

    if state == STATE_DOCK_BUY then
        -- Resolve buy station once and cache in trade table
        if not trade.resolvedBuyStation then
            local buyStation = nil
            local buyScript = trade.buyScript
            if trade.buyStationIndex then
                buyStation = sector:getEntity(trade.buyStationIndex)
            end
            if not valid(buyStation) then
                buyStation, buyScript = AutoTraderController.findBestTradingStation(entity, trade.goodName, "sell", trade.toBuy)
            end

            if not valid(buyStation) or not buyScript then
                print("[AutoTrader] No station sells " .. trade.goodName .. " in this sector")
                AutoTraderController.stopTrade()
                return
            end

            trade.resolvedBuyStation = buyStation.index
            trade.resolvedBuyScript = buyScript
            print("[AutoTrader] Buying from: " .. tostring(buyStation))
        end

        local buyStation = sector:getEntity(trade.resolvedBuyStation)
        if not valid(buyStation) then
            print("[AutoTrader] Buy station lost")
            AutoTraderController.stopTrade()
            return
        end

        DockAI.updateDockingUndocking(timeStep, buyStation, 5,
            function(ship, station)
                local result = station:invokeFunction(trade.resolvedBuyScript, "sellToShip", entity.index, trade.goodName, trade.toBuy, 1)
                if result == 0 then
                    print("[AutoTrader] Bought " .. trade.toBuy .. "x " .. trade.goodName)
                    broadcastInvokeClientFunction("updateStatus", "Bought! Undocking...")
                else
                    print("[AutoTrader] Buy failed: " .. tostring(result))
                    broadcastInvokeClientFunction("updateStatus", "Buy failed (" .. tostring(result) .. ")")
                end
            end,
            function(ship, msg)
                print("[AutoTrader] Buy done, moving to sell")
                DockAI.reset()

                local controller = ControlUnit()
                if controller then controller.autoPilotEnabled = true end

                -- Cross-sector: jump to sell sector if needed
                if trade.sellSectorX then
                    local cx, cy = Sector():getCoordinates()
                    if cx == trade.sellSectorX and cy == trade.sellSectorY then
                        state = STATE_DOCK_SELL
                        broadcastInvokeClientFunction("updateStatus", "Flying to sell station...")
                    else
                        local ent = Entity()
                        local jumpRange = getJumpRange(ent)
                        trade.sellWaypoints = AutoTraderController.buildSellWaypoints(ent, cx, cy, trade.sellSectorX, trade.sellSectorY, jumpRange)
                        if not trade.sellWaypoints or #trade.sellWaypoints == 0 then
                            print("[AutoTrader] Cannot reach sell sector (rift/blocked)")
                            broadcastInvokeClientFunction("updateStatus", "Sell sector unreachable")
                            AutoTraderController.stopTrade()
                            return
                        end
                        trade.waypointIndex = 1
                        state = STATE_JUMP_TO_SELL
                        local wp = trade.sellWaypoints[1]
                        ShipAI():setJump(wp.x, wp.y)
                        local totalJumps = #trade.sellWaypoints
                        if totalJumps > 1 then
                            broadcastInvokeClientFunction("updateStatus", "Jumping to sell 1/" .. totalJumps .. " (via home)...")
                        else
                            broadcastInvokeClientFunction("updateStatus", "Jumping to sell (" .. trade.sellSectorX .. ":" .. trade.sellSectorY .. ")...")
                        end
                    end
                else
                    state = STATE_DOCK_SELL
                    broadcastInvokeClientFunction("updateStatus", "Flying to sell station...")
                end
            end
        )

    elseif state == STATE_DOCK_SELL then
        -- Resolve sell station once and cache in trade table
        if not trade.resolvedSellStation then
            local sellStation = nil
            local sellScript = trade.sellScript
            if trade.sellStationIndex then
                sellStation = sector:getEntity(trade.sellStationIndex)
            end
            if not valid(sellStation) then
                sellStation, sellScript = AutoTraderController.findBestTradingStation(entity, trade.goodName, "buy", trade.amount)
            end

            if not valid(sellStation) or not sellScript then
                print("[AutoTrader] No station buys " .. trade.goodName .. " in this sector")
                AutoTraderController.stopTrade()
                return
            end

            trade.resolvedSellStation = sellStation.index
            trade.resolvedSellScript = sellScript
            print("[AutoTrader] Selling to: " .. tostring(sellStation))
        end

        local sellStation = sector:getEntity(trade.resolvedSellStation)
        if not valid(sellStation) then
            print("[AutoTrader] Sell station lost")
            AutoTraderController.stopTrade()
            return
        end

        DockAI.updateDockingUndocking(timeStep, sellStation, 5,
            function(ship, station)
                local result = station:invokeFunction(trade.resolvedSellScript, "buyFromShip", entity.index, trade.goodName, trade.amount, 1)
                if result == 0 then
                    print("[AutoTrader] Sold " .. trade.goodName .. "!")
                    broadcastInvokeClientFunction("updateStatus", "Sold! Undocking...")
                else
                    print("[AutoTrader] Sell failed: " .. tostring(result))
                    broadcastInvokeClientFunction("updateStatus", "Sell failed (" .. tostring(result) .. ")")
                end
            end,
            function(ship, msg)
                print("[AutoTrader] Trade complete! Profit: " .. formatNum(trade.totalProfit))
                broadcastInvokeClientFunction("updateStatus", "Done! Profit: " .. formatNum(trade.totalProfit))
                state = STATE_IDLE
                trade = nil

                local controller = ControlUnit()
                if controller then
                    controller.autoPilotEnabled = false
                    controller:stopShip()
                end
            end
        )
    end
end

-- Find the best station in current sector for trading the given good
-- tradeType: "sell" = station sells to ship (player buys) -> pick lowest price
-- tradeType: "buy" = station buys from ship (player sells) -> pick highest price
-- amount: required stock (for "sell") or required free space (for "buy")
-- Returns station entity, script path, or nil
function AutoTraderController.findBestTradingStation(entity, goodName, tradeType, amount)
    local sector = Sector()
    local stations = {sector:getEntitiesByType(EntityType.Station)}
    local playerFaction = Faction(entity.factionIndex)

    local bestStation = nil
    local bestScript = nil
    local bestPrice = nil

    for _, station in pairs(stations) do
        if not valid(station) then goto nextStation end

        -- Check relations
        if playerFaction then
            local relations = playerFaction:getRelations(station.factionIndex)
            if relations < RELATIONS_THRESHOLD then goto nextStation end
        end

        local sellable = {}
        local buyable = {}
        TradingUtility.getBuyableAndSellableGoods(station, sellable, buyable, playerFaction)

        if tradeType == "sell" then
            -- Station sells to ship (player buys from): pick lowest price with enough stock
            for _, offer in pairs(buyable) do
                if offer.good.name == goodName and offer.stock >= (amount or 1) then
                    if not bestPrice or offer.price < bestPrice then
                        bestPrice = offer.price
                        bestStation = station
                        bestScript = offer.script
                    end
                end
            end
        else
            -- Station buys from ship (player sells to): pick highest price with enough space
            for _, offer in pairs(sellable) do
                if offer.good.name == goodName then
                    local freeSpace = offer.maxStock - offer.stock
                    if freeSpace >= (amount or 1) then
                        if not bestPrice or offer.price > bestPrice then
                            bestPrice = offer.price
                            bestStation = station
                            bestScript = offer.script
                        end
                    end
                end
            end
        end

        ::nextStation::
    end

    if bestStation then
        print("[AutoTrader] Best station for " .. tradeType .. " " .. goodName .. ": " .. tostring(bestStation) .. " @ " .. tostring(bestPrice))
    end

    return bestStation, bestScript
end

function AutoTraderController.secure()
    local securedTrade = nil
    if trade then
        securedTrade = {}
        for k, v in pairs(trade) do
            -- Skip resolved entity references (invalid across sectors)
            if k ~= "resolvedBuyStation" and k ~= "resolvedSellStation" then
                securedTrade[k] = v
            end
        end
    end
    return {
        state = state,
        trade = securedTrade,
        bestRoute = bestRoute,
        homeSector = homeSector,
    }
end

function AutoTraderController.restore(data)
    if data then
        state = data.state or STATE_IDLE
        trade = data.trade
        bestRoute = data.bestRoute
        homeSector = data.homeSector
    else
        state = STATE_IDLE
        trade = nil
        bestRoute = nil
        homeSector = nil
    end
end
