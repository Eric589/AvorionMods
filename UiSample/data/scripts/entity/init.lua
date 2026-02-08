local entity = Entity()

if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            if not entity:hasScript("data/scripts/entity/uisamplecontroller.lua") then
                entity:addScriptOnce("data/scripts/entity/uisamplecontroller.lua")
            end
        end
    end
end
