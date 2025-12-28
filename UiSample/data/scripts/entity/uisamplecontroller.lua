-- Simple UI Sample Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

UiSampleController = {}

-- Module-level functions for Avorion
function getIcon()
    return "data/icon/icon.png"
end

function interactionPossible(playerIndex)
    if onServer() then return false end
    local player = Player()
    return player and player.index == playerIndex
end

function getInteractionText()
    return "UI Sample"
end

function initUI()
    return UiSampleController.initUI()
end

function initialize()
    return UiSampleController.initialize()
end

function secure()
    return UiSampleController.secure()
end

function restore(data)
    return UiSampleController.restore(data)
end

-- State
local enabled = false
local pressCount = 0

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
    if onClient() then
        UiSampleController.initUI()
    end
end

function UiSampleController.secure()
    return {enabled = enabled, pressCount = pressCount}
end

function UiSampleController.restore(data)
    if data then
        enabled = data.enabled or false
        pressCount = data.pressCount or 0
    end
end

function UiSampleController.initUI()
    local res = getResolution()
    local size = vec2(300, 200)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "UI Sample"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "UI Sample")
    
    local y = 10
    UiSampleController.statusLabel = window:createLabel(vec2(10, y), "Status: Inactive", 14)
    y = y + 40
    UiSampleController.toggleBtn = window:createButton(Rect(10, y, 200, y + 30), "Enable", "onToggle")
    y = y + 50
    UiSampleController.pressLabel = window:createLabel(vec2(10, y), "Presses: 0", 14)
    y = y + 30
    window:createButton(Rect(10, y, 200, y + 30), "Press Me", "onPress")
end

function UiSampleController.onToggle()
    if onClient() then
        invokeServerFunction("toggleEnabled")
    end
end

function UiSampleController.toggleEnabled()
    if not onServer() then return end
    enabled = not enabled
    broadcastInvokeClientFunction("updateUI", enabled, pressCount)
end
callable(UiSampleController, "toggleEnabled")

function UiSampleController.onPress()
    if onClient() then
        invokeServerFunction("incrementPress")
    end
end

function UiSampleController.incrementPress()
    if not onServer() then return end
    pressCount = pressCount + 1
    broadcastInvokeClientFunction("updateUI", enabled, pressCount)
end
callable(UiSampleController, "incrementPress")

function UiSampleController.updateUI(isEnabled, count)
    if not onClient() then return end
    if UiSampleController.statusLabel then
        UiSampleController.statusLabel.caption = "Status: " .. (isEnabled and "Active" or "Inactive")
    end
    if UiSampleController.toggleBtn then
        UiSampleController.toggleBtn.caption = isEnabled and "Disable" or "Enable"
    end
    if UiSampleController.pressLabel then
        UiSampleController.pressLabel.caption = "Presses: " .. count
    end
end
callable(UiSampleController, "updateUI")

function UiSampleController.disable()
    if not onServer() then return end
    enabled = false
    return 0
end
callable(UiSampleController, "disable")
