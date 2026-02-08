-- Fast Exploration Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
include("utility")
include("callable")

-- namespace FastExplorationController
FastExplorationController = {}

local DRONE_LIFETIME = 20 -- seconds before drone is destroyed
local trackedDrones = {} -- {name = string, elapsed = number}

function FastExplorationController.getIcon()
    return "data/scripts/icon/icon.png"
end

function FastExplorationController.interactionPossible(playerIndex)
    if onServer() then return false end
    local player = Player()
    local entity = Entity()
    if player.craft.index.value == entity.id.value then
        return true, ""
    else
        return false, ""
    end
end

function FastExplorationController.getInteractionText()
    return "Fast Exploration"
end

function FastExplorationController.initialize()
    if onServer() then
        local entity = Entity()
        if entity then
            local initFlag = entity:getValue("fastexploration_initialized")
            if not initFlag then
                entity:setValue("fastexploration_initialized", true)
            end
        end
    end
end

function FastExplorationController.initUI()
    local res = getResolution()
    local size = vec2(300, 100)
    local menu = ScriptUI()
    local window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
    window.caption = "Fast Exploration"
    window.showCloseButton = 1
    window.moveable = 1
    menu:registerWindow(window, "Fast Exploration")

    -- Single button to create drone
    window:createButton(Rect(10, 10, 290, 50), "Create Drone", "onCreateDrone")
end

-- Button clicked
function FastExplorationController.onCreateDrone()
    invokeServerFunction("createDrone")
end

-- Server: Create the drone
function FastExplorationController.createDrone()
    if not onServer() then return end
    
    local player = Player()
    local entity = Entity()
    local sector = Sector()

    -- Create a simple BlockPlan with one block
    local plan = BlockPlan()
    local material = Material(MaterialType.Iron)
    local color = Color(0.5, 0.5, 0.5, 1.0)

    plan:addBlock(
        vec3(0, 0, 0),      -- position
        vec3(1, 1, 1),      -- size
        -1,                 -- parentIndex (root)
        1,                  -- block type (hull)
        color,
        material,
        Matrix(),           -- orientation
        0,                  -- blockIndex
        nil                 -- secondaryColor
    )

    -- Position near mothership
    local pos = entity.translationf
    local droneMatrix = Matrix()
    droneMatrix.translation = pos + vec3(50, 0, 0)

    -- Create as player-owned ship
    local drone = sector:createShip(player, "Scout Drone", plan, droneMatrix)

    if valid(drone) then
        print("[FastExploration] Drone created: " .. tostring(drone.id))

        -- Find a random unknown sector within range
        local cx, cy = sector:getCoordinates()
        local range = 5
        local candidates = {}

        for dx = -range, range do
            for dy = -range, range do
                if dx ~= 0 or dy ~= 0 then
                    local tx, ty = cx + dx, cy + dy
                    if not player:knowsSector(tx, ty) then
                        table.insert(candidates, {x = tx, y = ty})
                    end
                end
            end
        end

        if #candidates > 0 then
            local target = candidates[math.random(#candidates)]
            print("[FastExploration] Jumping drone to sector " .. target.x .. ":" .. target.y)
            sector:transferEntity(drone, target.x, target.y, SectorChangeType.Jump)
            table.insert(trackedDrones, {name = drone.name, elapsed = 0})
        else
            print("[FastExploration] No unknown sectors within range, destroying drone")
            sector:deleteEntity(drone)
            player:setShipDestroyed(drone.name, true)
            player:removeDestroyedShipInfo(drone.name)
        end
    else
        print("[FastExploration] Failed to create drone")
    end
end
callable(FastExplorationController, "createDrone")

function FastExplorationController.getUpdateInterval()
    return 1
end

function FastExplorationController.updateServer(timeStep)
    for i = #trackedDrones, 1, -1 do
        local entry = trackedDrones[i]
        entry.elapsed = entry.elapsed + timeStep

        if entry.elapsed >= DRONE_LIFETIME then
            print("[FastExploration] Cleaning up drone: " .. entry.name)
            -- Drone is in another sector, can't delete the entity directly
            -- Just remove it from the player's ship list
            local owner = Player(Entity().factionIndex)
            if owner then
                owner:setShipDestroyed(entry.name, true)
                owner:removeDestroyedShipInfo(entry.name)
            end
            table.remove(trackedDrones, i)
        end
    end
end
