local entity = Entity()

if onServer() then
    if entity.isShip then
        if entity.allianceOwned or entity.playerOwned then
            if not entity:hasScript("uisamplecontroller.lua") then
                entity:hasScript("uisamplecontroller.lua")
            end
        end
    end
end
