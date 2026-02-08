local entity = Entity()

if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            if not entity:hasScript("data/scripts/entity/fastexplorationcontroller.lua") then
                entity:addScriptOnce("data/scripts/entity/fastexplorationcontroller.lua")
            end
        end
    end
end
