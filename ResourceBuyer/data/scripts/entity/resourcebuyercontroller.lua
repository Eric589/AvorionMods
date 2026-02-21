-- Resource Buyer Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")
include("goodsindex")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace ResourceBuyerController
ResourceBuyerController = {}

-- Shopping list: array of {name = "Good Name", quantity = 10}
local shoppingList = {}

-- UI elements
local statusLabel = nil
local goodsCombo = nil
local quantityBox = nil
local listBox = nil
local startButton = nil
local stopButton = nil

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
    local size = vec2(500, 400)
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

    -- Row 2: Shopping list
    y = 50
    window:createLabel(vec2(10, y), "Shopping List:", 14)
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
            broadcastInvokeClientFunction("syncList", ResourceBuyerController.serializeList())
            return
        end
    end

    table.insert(shoppingList, {name = name, quantity = quantity})
    broadcastInvokeClientFunction("syncList", ResourceBuyerController.serializeList())
end
callable(ResourceBuyerController, "addGood")

function ResourceBuyerController.removeGood(index)
    if not onServer() then return end
    local luaIndex = index + 1
    if luaIndex >= 1 and luaIndex <= #shoppingList then
        table.remove(shoppingList, luaIndex)
    end
    broadcastInvokeClientFunction("syncList", ResourceBuyerController.serializeList())
end
callable(ResourceBuyerController, "removeGood")

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
    broadcastInvokeClientFunction("syncList", ResourceBuyerController.serializeList())
    broadcastInvokeClientFunction("updateStatus", "Idle")
end
callable(ResourceBuyerController, "requestUIUpdate")

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

-- ============================================================
-- CLIENT FUNCTIONS
-- ============================================================

function ResourceBuyerController.syncList(data)
    if not onClient() then return end

    local items = {}
    if data and data ~= "" then
        for line in string.gmatch(data, "[^\n]+") do
            local parts = {}
            for part in string.gmatch(line, "[^|]+") do
                table.insert(parts, part)
            end
            if #parts >= 2 then
                table.insert(items, {name = parts[1], quantity = tonumber(parts[2]) or 0})
            end
        end
    end

    if not listBox then return end
    listBox:clear()
    for _, item in pairs(items) do
        listBox:addEntry(item.name .. "  x" .. tostring(item.quantity))
    end
end
callable(ResourceBuyerController, "syncList")

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
    }
end

function ResourceBuyerController.restore(data)
    if data then
        shoppingList = data.shoppingList or {}
    else
        shoppingList = {}
    end
end
