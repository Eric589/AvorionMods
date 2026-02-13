local entity = Entity()

if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            if not entity:hasScript("data/scripts/entity/autotradercontroller.lua") then
                entity:addScriptOnce("data/scripts/entity/autotradercontroller.lua")
            end
        end
    end
end
