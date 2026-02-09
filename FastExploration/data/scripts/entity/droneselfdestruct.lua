-- Self-destruct script: destroys the entity after a short delay
package.path = package.path .. ";data/scripts/lib/?.lua"

local timer = 0
local lifetime = 3

function initialize(lt)
    if lt then lifetime = lt end
end

function getUpdateInterval()
    return 0
end

function updateServer(timeStep)
    timer = timer + timeStep
    if timer >= lifetime then
        local entity = Entity()
        local owner = Player(entity.factionIndex)
        if owner then
            owner:setShipDestroyed(entity.name, true)
            owner:removeDestroyedShipInfo(entity.name)
        end
        Sector():deleteEntity(entity)
    end
end
