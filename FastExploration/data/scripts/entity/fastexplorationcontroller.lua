-- Fast Exploration Controller
package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
include("callable")
local SectorSpecifics = include("sectorspecifics")

-- namespace FastExplorationController
FastExplorationController = {}

local DRONE_LIFETIME = 3 -- seconds before drone self-destructs
local SCAN_RANGE = 8 -- sectors to scan around current position
local pendingTargets = {} -- queued sectors to send drones to
local dispatchTimer = 0

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

    -- Single button to dispatch drones
    window:createButton(Rect(10, 10, 290, 50), "Dispatch Drones", "onDispatchDrones")
end

-- Button clicked
function FastExplorationController.onDispatchDrones()
    invokeServerFunction("dispatchDrones")
end

-- Server: Queue unknown sectors for drone dispatch (one per tick)
function FastExplorationController.dispatchDrones()
    if not onServer() then return end

    if #pendingTargets > 0 then
        print("[FastExploration] Already dispatching drones")
        return
    end

    local player = Player()
    local entity = Entity()
    local sector = Sector()
    local cx, cy = sector:getCoordinates()
    local serverSeed = Server().seed
    local specs = SectorSpecifics()

    local range = SCAN_RANGE
    local jumpReach = entity.hyperspaceJumpReach
    if jumpReach and jumpReach > 0 then
        range = math.floor(jumpReach)
        print("[FastExploration] Using hyperspaceJumpReach = " .. range)
    end

    local DEEP_SCAN_RANGE = 8
    local yellowCount = 0
    local greenCount = 0

    local rangeSq = range * range
    local deepSq = DEEP_SCAN_RANGE * DEEP_SCAN_RANGE

    for dx = -range, range do
        for dy = -range, range do
            local distSq = dx * dx + dy * dy
            if distSq > 0 and distSq <= rangeSq then
                local tx, ty = cx + dx, cy + dy
                if not player:knowsSector(tx, ty) then
                    local regular, offgrid = specs:determineContent(tx, ty, serverSeed)
                    if offgrid and distSq <= deepSq then
                        yellowCount = yellowCount + 1
                        table.insert(pendingTargets, {x = tx, y = ty})
                    elseif regular then
                        greenCount = greenCount + 1
                        table.insert(pendingTargets, {x = tx, y = ty})
                    end
                end
            end
        end
    end

    print("[FastExploration] Queued " .. #pendingTargets .. " sectors (yellow: " .. yellowCount .. " in range " .. DEEP_SCAN_RANGE .. ", green: " .. greenCount .. " in range " .. range .. ")")
end
callable(FastExplorationController, "dispatchDrones")

function FastExplorationController.getUpdateInterval()
    return 0
end

function FastExplorationController.updateServer(timeStep)
    -- Dispatch one drone every 0.2 seconds
    dispatchTimer = dispatchTimer + timeStep
    if dispatchTimer >= 0.2 and #pendingTargets > 0 then
        dispatchTimer = 0
        local target = table.remove(pendingTargets, 1)
        local player = Player()
        local entity = Entity()
        local sector = Sector()

        local dronePlan = BlockPlan()
        local material = Material(MaterialType.Iron)
        local color = Color(0.5, 0.5, 0.5, 1.0)
        dronePlan:addBlock(
            vec3(0, 0, 0), vec3(1, 1, 1), -1, 1,
            color, material, Matrix(), 0, nil
        )

        local droneMatrix = Matrix()
        droneMatrix.translation = entity.translationf + vec3(50, 0, 0)

        local droneName = "Scout Drone " .. target.x .. "_" .. target.y
        local drone = sector:createShip(player, droneName, dronePlan, droneMatrix)

        if valid(drone) then
            drone.crew = Crew()
            drone.crew:add(1, CrewMan(CrewProfessionType.None))
            drone:addScript("data/scripts/entity/droneselfdestruct.lua", DRONE_LIFETIME)
            sector:transferEntity(drone, target.x, target.y, SectorChangeType.Jump)
        end
    end
end
