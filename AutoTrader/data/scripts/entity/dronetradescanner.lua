-- Drone Trade Scanner
-- Jumps to a sector, waits for it to load, scans all station goods,
-- writes serialized data to Server():setValue(), then self-destructs.
package.path = package.path .. ";data/scripts/lib/?.lua"
package.path = package.path .. ";data/scripts/?.lua"
include("utility")
local TradingUtility = include("tradingutility")

local scanDelay = 5 -- seconds to wait for sector to fully load
local lifetime = 8 -- seconds before self-destruct (must be > scanDelay)
local timer = 0
local scanned = false
local ownerFactionIndex = nil
local RELATIONS_THRESHOLD = -30000 -- minimum relations to trade (matches vanilla factory/consumer)

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
    local key = "autotrade_" .. cx .. "_" .. cy

    local faction = nil
    if ownerFactionIndex then
        faction = Faction(ownerFactionIndex)
    end

    -- Scan all stations and ships for tradeable goods
    local sellable = {} -- stations that BUY (player can sell to)
    local buyable = {}  -- stations that SELL (player can buy from)

    local entities = {sector:getEntitiesByType(EntityType.Station)}
    for _, e in pairs({sector:getEntitiesByType(EntityType.Ship)}) do
        table.insert(entities, e)
    end

    local skipped = 0
    for _, station in pairs(entities) do
        -- Check if the player's faction can trade with this station
        if faction and station.factionIndex then
            local relations = faction:getRelations(station.factionIndex)
            if relations < RELATIONS_THRESHOLD then
                skipped = skipped + 1
                goto skipStation
            end
        end

        TradingUtility.getBuyableAndSellableGoods(station, sellable, buyable, faction)

        ::skipStation::
    end

    -- Serialize to string
    -- Format per line: TYPE|goodName|stock|maxStock|price|goodSize|stationName
    -- B = buyable (station sells, player buys from)
    -- S = sellable (station buys, player sells to)
    local lines = {}

    for _, offer in pairs(buyable) do
        local stationName = ""
        if offer.station then
            stationName = tostring(offer.station)
        end
        local line = string.format("B|%s|%d|%d|%d|%.2f|%s",
            offer.good.name,
            math.floor(offer.stock),
            math.floor(offer.maxStock),
            math.floor(offer.price),
            offer.good.size,
            stationName)
        table.insert(lines, line)
    end

    for _, offer in pairs(sellable) do
        local stationName = ""
        if offer.station then
            stationName = tostring(offer.station)
        end
        local line = string.format("S|%s|%d|%d|%d|%.2f|%s",
            offer.good.name,
            math.floor(offer.stock),
            math.floor(offer.maxStock),
            math.floor(offer.price),
            offer.good.size,
            stationName)
        table.insert(lines, line)
    end

    local data = table.concat(lines, "\n")
    if data == "" then data = "EMPTY" end

    Server():setValue(key, data)
    local skipMsg = ""
    if skipped > 0 then skipMsg = ", " .. skipped .. " stations skipped (bad relations)" end
    print("[DroneScan] Sector " .. cx .. ":" .. cy .. " scanned: " .. #buyable .. " buyable, " .. #sellable .. " sellable" .. skipMsg)
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
