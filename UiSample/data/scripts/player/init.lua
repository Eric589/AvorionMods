-- Auto-attach UI Sample controller to player ships
package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function initialize()
    if onClient() then
        Player():registerCallback("onCraftChanged", "onCraftChanged")
    end
end

function onCraftChanged(playerIndex, craftIndex)
    if onClient() then
        invokeServerFunction("addControllerToShip", craftIndex)
    end
end

function addControllerToShip(craftIndex)
    if not onServer() then return end
    local craft = Entity(craftIndex)
    if not craft or not valid(craft) then return end
    if not craft.isShip then return end
    if not craft.playerOwned and not craft.allianceOwned then return end
    
    local initFlag = craft:getValue("uisample_initialized")
    if not initFlag then
        local scripts = craft:getScripts()
        local hasController = false
        for _, scriptPath in pairs(scripts) do
            if scriptPath == "data/scripts/entity/uisamplecontroller.lua" then
                hasController = true
                break
            end
        end
        if not hasController then
            craft:addScriptOnce("data/scripts/entity/uisamplecontroller.lua")
        end
    end
end
callable(nil, "addControllerToShip")
