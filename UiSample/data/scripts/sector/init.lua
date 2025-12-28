-- Auto-attach UI Sample controller to all player ships in sector
package.path = package.path .. ";data/scripts/lib/?.lua"

function initialize()
    if onServer() then
        -- Add controller to all existing player ships when sector loads
        local sector = Sector()
        if sector then
            for _, entity in pairs({sector:getEntitiesByType(EntityType.Ship)}) do
                if valid(entity) and (entity.playerOwned or entity.allianceOwned) then
                    addControllerToShip(entity)
                end
            end
        end
        
        -- Register callback for when new entities are created
        Sector():registerCallback("onEntityCreated", "onEntityCreated")
    end
end

function onEntityCreated(index)
    if not onServer() then return end
    
    local entity = Entity(index)
    if not entity or not valid(entity) then return end
    if not entity.isShip then return end
    if not entity.playerOwned and not entity.allianceOwned then return end
    
    addControllerToShip(entity)
end

function addControllerToShip(entity)
    if not valid(entity) then return end
    
    -- Check if script already exists
    local scripts = entity:getScripts()
    for _, scriptPath in pairs(scripts) do
        if scriptPath == "data/scripts/entity/uisamplecontroller.lua" then
            return -- Already has the script
        end
    end
    
    -- Add the controller
    entity:addScriptOnce("data/scripts/entity/uisamplecontroller.lua")
end
