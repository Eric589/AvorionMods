-- Resource Buyer Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
include("callable")
include("goodsindex")
local FactoryMap = include("factorymap")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace ResourceBuyerController
ResourceBuyerController = {}

-- Shopping list: array of {name = "Good Name", quantity = 10}
local shoppingList = {}

-- Set of good names available for purchase nearby (server-side)
local availableGoods = {}

-- UI elements
local statusLabel = nil
local goodsCombo = nil
local quantityBox = nil
local listBox = nil
local startButton = nil
local stopButton = nil
local scanButton = nil

-- Client-side: parsed shopping list and availability for coloring
local clientItems = {}
local clientAvailable = {}

function ResourceBuyerController.getIcon()
    return "data/textures/icons/cargo-bay.png"
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

    -- Populate with all goods from goodsindex, sorted alphabetically
    local goodNames = {}
    for name, _ in pairs(goods) do
        table.insert(goodNames, name)
    end
    table.sort(goodNames)
    for _, name in ipairs(goodNames) do
        goodsCombo:addEntry(name)
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
    scanButton = window:createButton(Rect(270, y - 5, 370, y + 20), "Scan", "onScan")
    window:createButton(Rect(380, y - 5, 490, y + 20), "Remove", "onRemoveGood")

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

    local name = goodsCombo.selectedEntry
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

function ResourceBuyerController.onStart()
    if not onClient() then return end
    invokeServerFunction("startBuyRun")
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

    local entity = Entity()
    if not valid(entity) then return end

    local jumpRange = entity.hyperspaceJumpReach or 0
    if jumpRange <= 0 then
        broadcastInvokeClientFunction("updateStatus", "No hyperspace drive installed")
        return
    end

    broadcastInvokeClientFunction("updateStatus", "Scanning nearby sectors...")

    local sx, sy = Sector():getCoordinates()
    local scanRadius = math.ceil(jumpRange)

    local map = FactoryMap()
    local from = {x = sx - scanRadius, y = sy - scanRadius}
    local to = {x = sx + scanRadius, y = sy + scanRadius}
    local productions = map:getProductionsMap(from, to)

    -- Build set of goods available for purchase nearby
    availableGoods = {}

    -- Also scan current sector for actual station goods
    ResourceBuyerController.scanCurrentSectorGoods()

    -- Extract goods from FactoryMap predictions
    local rangeSq = jumpRange * jumpRange
    for _, entry in pairs(productions) do
        local coords = entry.coordinates
        local dx = coords.x - sx
        local dy = coords.y - sy
        if dx * dx + dy * dy <= rangeSq then
            local data = entry.data

            -- Factory results = goods produced and sold by factories
            if data.productions then
                for _, production in pairs(data.productions) do
                    if production.results then
                        for _, good in pairs(production.results) do
                            availableGoods[good.name] = 1
                        end
                    end
                    -- Garbage/byproducts are also sold
                    if production.garbages then
                        for _, good in pairs(production.garbages) do
                            availableGoods[good.name] = 1
                        end
                    end
                end
            end

            -- Consumer/seller goods that are sold
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

    -- Count available goods from shopping list
    local found = 0
    for _, item in pairs(shoppingList) do
        if availableGoods[item.name] then
            found = found + 1
        end
    end

    ResourceBuyerController.sendSyncToClients()
    broadcastInvokeClientFunction("updateStatus", "Scan complete: " .. found .. "/" .. #shoppingList .. " goods found nearby")
end
callable(ResourceBuyerController, "scanNearbyGoods")

function ResourceBuyerController.scanCurrentSectorGoods()
    -- Check actual stations in current sector for buyable goods
    local sector = Sector()
    if not sector then return end

    local stations = {sector:getEntitiesByType(EntityType.Station)}
    for _, station in pairs(stations) do
        if valid(station) then
            -- Try factory script
            local ok, production = station:invokeFunction("data/scripts/entity/merchants/factory.lua", "getProduction")
            if ok == 0 and production then
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

            -- Try seller script
            local ok2, soldGoods = station:invokeFunction("data/scripts/entity/merchants/seller.lua", "getSellableGoods")
            if ok2 == 0 and soldGoods then
                for _, name in pairs(soldGoods) do
                    availableGoods[name] = 1
                end
            end
        end
    end
end

function ResourceBuyerController.startBuyRun()
    if not onServer() then return end
    if #shoppingList == 0 then
        broadcastInvokeClientFunction("updateStatus", "Shopping list is empty")
        return
    end
    broadcastInvokeClientFunction("updateStatus", "Not yet implemented")
end
callable(ResourceBuyerController, "startBuyRun")

function ResourceBuyerController.stopBuyRun()
    if not onServer() then return end
    broadcastInvokeClientFunction("updateStatus", "Stopped")
end
callable(ResourceBuyerController, "stopBuyRun")

function ResourceBuyerController.requestUIUpdate()
    if not onServer() then return end
    ResourceBuyerController.sendSyncToClients()
    broadcastInvokeClientFunction("updateStatus", "Idle")
end
callable(ResourceBuyerController, "requestUIUpdate")

function ResourceBuyerController.sendSyncToClients()
    local listData = ResourceBuyerController.serializeList()
    local availData = ResourceBuyerController.serializeAvailable()
    broadcastInvokeClientFunction("syncListAndAvailability", listData, availData)
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

-- ============================================================
-- CLIENT FUNCTIONS
-- ============================================================

function ResourceBuyerController.syncListAndAvailability(listData, availData)
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

    for i, item in ipairs(clientItems) do
        local text = item.name .. "  x" .. tostring(item.quantity)
        if hasAvailData and not clientAvailable[item.name] then
            text = text .. "  [NOT FOUND]"
        end
        listBox:addEntry(text)

        -- Color the entry red if not available
        if hasAvailData and not clientAvailable[item.name] then
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
    }
end

function ResourceBuyerController.restore(data)
    if data then
        shoppingList = data.shoppingList or {}
        availableGoods = data.availableGoods or {}
    else
        shoppingList = {}
        availableGoods = {}
    end
end
