-- Auto-attach UI Sample controller to player ships when boarding
package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function initialize()
    if onClient() then
        Player():registerCallback("onCraftChanged", "onCraftChanged")
    end
end

function onCraftChanged(id, previousId)
    if onClient() then
        invokeServerFunction("addControllerToShip", id)
    end
end

function addControllerToShip(id)
    if not onServer() then return end

    local craft = Entity(id)
    if not craft or not valid(craft) then return end
    if not craft.isShip then return end
    if not craft.playerOwned and not craft.allianceOwned then return end

    -- Check if script already exists
    local scripts = craft:getScripts()
    for _, scriptPath in pairs(scripts) do
        if scriptPath == "data/scripts/entity/uisamplecontroller.lua" then
            return -- Already has the script
        end
    end

    -- Add the controller
    craft:addScriptOnce("data/scripts/entity/uisamplecontroller.lua")
end
callable(nil, "addControllerToShip")
