local entity = Entity()

if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            if not entity:hasScript("lib/lootCleaner.lua") then
                entity:addScriptOnce("lib/lootCleaner.lua")
            end
        end
    end
end
