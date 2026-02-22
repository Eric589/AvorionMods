-- Inventory Seller Drone Scanner
-- Jumps to a sector, waits for it to load, scans which goods stations will BUY from players,
-- writes serialized good names to Server():setValue(), then self-destructs.
package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
local TradingUtility = include("tradingutility")

local scanDelay = 5 -- seconds to wait for sector to fully load
local lifetime = 8  -- seconds before self-destruct (must be > scanDelay)
local timer = 0
local scanned = false
local ownerFactionIndex = nil
local RELATIONS_THRESHOLD = -30000

function initialize(factionIndex)
    if onServer() then
        ownerFactionIndex = factionIndex
    end
end

function getUpdateInterval()
    return 0
end

function updateServer(timeStep)
    timer = timer + timeStep

    if not scanned and timer >= scanDelay then
        scanned = true
        doScan()
    end

    if timer >= lifetime then
        local entity = Entity()
        if valid(entity) then
            local owner = Player(entity.factionIndex)
            if owner then
                owner:setShipDestroyed(entity.name, true)
                owner:removeDestroyedShipInfo(entity.name)
            end
            Sector():deleteEntity(entity)
        end
    end
end

function doScan()
    local sector = Sector()
    local cx, cy = sector:getCoordinates()
    local key = "invsell_" .. cx .. "_" .. cy

    local faction = nil
    if ownerFactionIndex then
        faction = Faction(ownerFactionIndex)
    end

    local entities = {sector:getEntitiesByType(EntityType.Station)}
    for _, e in pairs({sector:getEntitiesByType(EntityType.Ship)}) do
        table.insert(entities, e)
    end

    local sellable = {}
    local buyable = {}

    for _, station in pairs(entities) do
        if faction and station.factionIndex then
            local relations = faction:getRelations(station.factionIndex)
            if relations < RELATIONS_THRESHOLD then
                goto skipStation
            end
        end

        TradingUtility.getBuyableAndSellableGoods(station, sellable, buyable, faction)

        ::skipStation::
    end

    -- sellable = goods player can SELL to stations (populated from getBoughtGoods by TradingUtility)
    -- Sum free space across all stations per good so route planner knows total capacity
    local capacities = {}
    for _, offer in pairs(sellable) do
        local name = offer.good.name
        local freeSpace = (offer.maxStock or 0) - (offer.stock or 0)
        if freeSpace > 0 then
            capacities[name] = (capacities[name] or 0) + freeSpace
        end
    end

    -- Format: "goodName|freeSpace\n..."
    local lines = {}
    for name, cap in pairs(capacities) do
        table.insert(lines, name .. "|" .. cap)
    end

    local data = table.concat(lines, "\n")
    if data == "" then data = "EMPTY" end

    Server():setValue(key, data)
    print("[InvSellerScan] Sector " .. cx .. ":" .. cy .. " scanned: " .. #lines .. " goods with capacity")
end

function secure()
    return {timer = timer, scanned = scanned, ownerFactionIndex = ownerFactionIndex}
end

function restore(data)
    if data then
        timer = data.timer or 0
        scanned = data.scanned or false
        ownerFactionIndex = data.ownerFactionIndex
    end
end
