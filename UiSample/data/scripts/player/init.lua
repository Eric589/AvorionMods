-- Auto-attach UI Sample controller to player ships when boarding
package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function initialize()
    print("[UiSample Player] initialize() called")
    if onClient() then
        print("[UiSample Player] Client-side initialization")
        local player = Player()
        if player then
            player:registerCallback("onCraftChanged", "onCraftChanged")
            print("[UiSample Player] Registered onCraftChanged callback")
        else
            print("[UiSample Player] ERROR: Player() returned nil")
        end
    end
    if onServer() then
        print("[UiSample Player] Server-side initialization")
    end
end

function onCraftChanged(id, previousId)
    print("[UiSample Player] onCraftChanged triggered! id:", id, "previousId:", previousId)
    if onClient() then
        print("[UiSample Player] Invoking server function")
        invokeServerFunction("addControllerToShip", id)
    end
end

function addControllerToShip(id)
    print("[UiSample Player] addControllerToShip called with id:", id)
    if not onServer() then
        print("[UiSample Player] Not on server")
        return
    end

    local craft = Entity(id)
    if not craft or not valid(craft) then
        print("[UiSample Player] Craft invalid")
        return
    end
    if not craft.isShip then
        print("[UiSample Player] Not a ship")
        return
    end
    if not craft.playerOwned and not craft.allianceOwned then
        print("[UiSample Player] Not owned by player/alliance")
        return
    end

    print("[UiSample Player] Valid ship, checking for existing script...")

    -- Check if script already exists
    local scripts = craft:getScripts()
    for _, scriptPath in pairs(scripts) do
        if scriptPath == "data/scripts/entity/uisamplecontroller.lua" then
            print("[UiSample Player] Script already exists on ship")
            return -- Already has the script
        end
    end

    -- Add the controller
    print("[UiSample Player] Adding script to ship:", craft.name)
    craft:addScriptOnce("data/scripts/entity/uisamplecontroller.lua")
    print("[UiSample Player] Script added successfully!")
end
callable(nil, "addControllerToShip")
