local entity = Entity()

if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            if not entity:hasScript("data/scripts/entity/miningalgocontroller.lua") then
                entity:addScriptOnce("data/scripts/entity/miningalgocontroller.lua")
            end
        end
    end
end
