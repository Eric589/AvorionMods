-- SectorSelector: attach the galaxy-map player script once per player login

if onServer() then
    local player = Player()
    player:addScriptOnce("data/scripts/player/sectorselect.lua")
end
