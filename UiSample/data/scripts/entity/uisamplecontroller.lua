-- Simple UI Sample Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace UiSampleController

UiSampleController = {}

-- State (use numbers instead of booleans - booleans don't serialize over Avorion RPC)
local enabled = 0
local pressCount = 0

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
    return {enabled = enabled, pressCount = pressCount}
end

function UiSampleController.restore(data)
    if data then
        enabled = data.enabled or 0
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
    UiSampleController.actionBtn = window:createButton(Rect(10, y, 200, y + 30), "Press Me", "onPress")
end

function UiSampleController.onShowWindow()
    UiSampleController.refreshUI()
end

-- Toggle is client-side only, matching the SampleMods pattern
function UiSampleController.onToggle()
    if enabled == 1 then enabled = 0 else enabled = 1 end
    UiSampleController.refreshUI()
end

-- Press counter uses server round-trip to demonstrate RPC
function UiSampleController.onPress()
    if onClient() then
        invokeServerFunction("incrementPress")
    end
end

function UiSampleController.incrementPress()
    if not onServer() then return end
    pressCount = pressCount + 1
    broadcastInvokeClientFunction("updatePressCount", pressCount)
end
callable(UiSampleController, "incrementPress")

function UiSampleController.updatePressCount(count)
    if not onClient() then return end
    pressCount = count
    UiSampleController.refreshUI()
end
callable(UiSampleController, "updatePressCount")

function UiSampleController.refreshUI()
    if UiSampleController.statusLabel then
        UiSampleController.statusLabel.caption = "Status: " .. (enabled == 1 and "Active" or "Inactive")
    end
    if UiSampleController.toggleBtn then
        UiSampleController.toggleBtn.caption = enabled == 1 and "Disable" or "Enable"
    end
    if UiSampleController.pressLabel then
        UiSampleController.pressLabel.caption = "Presses: " .. pressCount
    end
end
