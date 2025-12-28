-- Auto-attach UI Sample controller to player ships
package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function initialize()
    print("[UiSample] Player script initializing...")
    if onClient() then
        print("[UiSample] Registering onCraftChanged callback")
        Player():registerCallback("onCraftChanged", "onCraftChanged")
    end
    if onServer() then
        print("[UiSample] Player script initialized on server")
    end
end

function onCraftChanged(id, previousId)
    print("[UiSample] onCraftChanged called - id:", id, "previousId:", previousId)
    if onClient() then
        print("[UiSample] Calling server to add controller")
        invokeServerFunction("addControllerToShip", id)
    end
end

function addControllerToShip(id)
    print("[UiSample] addControllerToShip called with id:", id)
    if not onServer() then
        print("[UiSample] Not on server, returning")
        return
    end

    local craft = Entity(id)
    if not craft or not valid(craft) then
        print("[UiSample] Craft not valid")
        return
    end
    if not craft.isShip then
        print("[UiSample] Not a ship")
        return
    end
    if not craft.playerOwned and not craft.allianceOwned then
        print("[UiSample] Not player or alliance owned")
        return
    end

    print("[UiSample] Checking for existing controller...")
    local scripts = craft:getScripts()
    local hasController = false
    for _, scriptPath in pairs(scripts) do
        if scriptPath == "data/scripts/entity/uisamplecontroller.lua" then
            hasController = true
            break
        end
    end

    if not hasController then
        print("[UiSample] Adding controller to ship...")
        craft:addScriptOnce("data/scripts/entity/uisamplecontroller.lua")
        print("[UiSample] Added UI Sample Controller to ship: " .. (craft.name or "unnamed"))
    else
        print("[UiSample] Controller already exists on ship")
    end
end
callable(nil, "addControllerToShip")
