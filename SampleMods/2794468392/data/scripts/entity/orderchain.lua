function OrderChain.addJumpOrder(x, y)
    if onClient() then
        invokeServerFunction("addJumpOrder", x, y)
        return
    end
	
    -- this command needs a captain or a player as it changes sector
    local entity = Entity()
	entity:addScriptOnce("ai/landfighters.lua")
    local pilots = {entity:getPilotIndices()}
    if #pilots == 0 and not checkCaptain() then return end

    if callingPlayer then
        local player = Player(callingPlayer)
        local owner = checkEntityInteractionPermissions(entity, AlliancePrivilege.ManageShips)
        if not owner then
            player:sendChatMessage("", ChatMessageType.Error, "You don't have permission to do that."%_T)
            return
        end

        if not OrderChain.canReceivePlayerOrder() then return end

    end

    -- if we have a long distance destination clear it, because we now jump per map jumps
    for _, pilotIndex in pairs(pilots) do
        local pilot = Player(pilotIndex)
        if pilot and pilot.isPlayer then
            pilot:resetHyperspaceCalculation()
        end
    end

    local shipX, shipY = Sector():getCoordinates()

    for _, action in pairs(OrderChain.chain) do
        if action.action == OrderType.Jump or action.action == OrderType.FlyThroughWormhole then
            shipX = action.x
            shipY = action.y
        end
    end

    -- prefer jumping over wormholes / gates
    local jumpValid, error = entity:isJumpRouteValid(shipX, shipY, x, y)
    if jumpValid then
        local order = {action = OrderType.Jump, x = x, y = y}

        if OrderChain.canEnchain(order) then
            OrderChain.enchain(order)
        end
        return
    end

    -- jump not possible, if a player enqueued this, they might want the ship to fly through a wormhole / gate
    if not callingPlayer then return end

    local player = Player(callingPlayer)
    local sectorViewsToCheck = {}

    local view = player:getKnownSector(shipX, shipY)
    if view then
        table.insert(sectorViewsToCheck, view)
    end

    local alliance = Alliance()
    if alliance then
        local view = alliance:getKnownSector(shipX, shipY)
        if view then
            table.insert(sectorViewsToCheck, view)
        end
    end

    for _, sectorView in pairs(sectorViewsToCheck) do
        local wormholeDestinations = {sectorView:getWormHoleDestinations()}
        for _, dest in pairs(wormholeDestinations) do
            if dest.x == x and dest.y == y then
                local order = {action = OrderType.FlyThroughWormhole, x = x, y = y, gate = false}
                if OrderChain.canEnchain(order) then
                    OrderChain.enchain(order)
                end
                return
            end
        end

        local gateDestinations = {sectorView:getGateDestinations()}
        for _, dest in pairs(gateDestinations) do
            if dest.x == x and dest.y == y then
                local order = {action = OrderType.FlyThroughWormhole, x = x, y = y, gate = true}
                if OrderChain.canEnchain(order) then
                    OrderChain.enchain(order)
                end
                return
            end
        end
    end

    player:sendChatMessage("", ChatMessageType.Error, error)
end
callable(OrderChain, "addJumpOrder")