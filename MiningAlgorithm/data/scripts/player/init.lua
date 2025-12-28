-- data/scripts/player/init.lua
-- Auto-adds mining controller to ships when player boards them

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function initialize()
    if onClient() then
        -- Register callback for when player boards a new craft
        Player():registerCallback("onStartDialog", "onPlayerBoardsShip")
    end
end

function onPlayerBoardsShip()
    if onClient() then
        -- Small delay to ensure ship is fully loaded
        deferredCallback(0.5, "checkAndAddController")
    end
end

function deferredCallback(delay, funcName)
    invokeServerFunction("addControllerToCurrentShip")
end

function addControllerToCurrentShip()
    if not onServer() then return end
    
    -- Get the calling player
    local player = Player(callingPlayer)
    if not player then return end
    
    -- Get their current craft
    local craft = player.craft
    if not craft or not valid(craft) then return end
    
    local entity = Entity(craft.index)
    if not entity or not valid(entity) then return end
    
    -- Only add to ships (not stations)
    if not entity.isShip then return end
    
    -- Only add to player-owned or alliance-owned ships
    if not entity.playerOwned and not entity.allianceOwned then return end
    
    -- Check if ship has FighterController component (required for mining)
    if not entity:hasComponent(ComponentType.FighterController) then 
        print("[AutoMiner] Ship has no FighterController - skipping")
        return 
    end
    
    -- Add the controller script if not already present
    if not entity:hasScript("data/scripts/entity/autominingcontroller.lua") then
        entity:addScriptOnce("data/scripts/entity/autominingcontroller.lua")
        print("[AutoMiner] Added Auto Mining Controller to: " .. (entity.name or "unnamed ship"))
    end
end
callable(nil, "addControllerToCurrentShip")