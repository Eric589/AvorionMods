function AIHarvest:initialize(initialObjectId)
    if initialObjectId then
        self.objectToHarvest = Entity(initialObjectId)
    end

    if onServer() then
        Sector():registerCallback("onDestroyed", "onDestroyed")
        Sector():registerCallback("onLootCollected", "onLootCollected")
        self:updateServer(1)
    end
end

function AIHarvest:onDestroyed(index)
    if valid(self.objectToHarvest) and self.objectToHarvest.index == index then
        self.objectToHarvest = nil
        self:updateServer(1)
    end
end

function AIHarvest:onLootCollected(collector, index)
    if valid(self.harvestLoot) and self.harvestLoot.index == index then
        self.harvestLoot = nil
        self:updateServer(1)
    end
end

function AIHarvest:updateHarvesting(timeStep) --overriden
    local ship = Entity()

    if self.hasRawLasers == true then
        if ship.freeCargoSpace < 1 then
            if self.noCargoSpace == false then
                ShipAI():setPassive()

                local faction = Faction(ship.factionIndex)
                local x, y = Sector():getCoordinates()
                local coords = tostring(x) .. ":" .. tostring(y)

                local ores, totalOres = getOreAmountsOnShip(ship)
                local scraps, totalScraps = getScrapAmountsOnShip(ship)
                if totalOres + totalScraps == 0 then
                    ShipAI():setStatusMessage(self.getNoSpaceStatus(), {})
                    if faction then faction:sendChatMessage(ship.name or "", ChatMessageType.Normal, self.getNoSpaceMessage(), coords) end
                    self.noCargoSpace = true
                else
                    local ret, moreOrders = ship:invokeFunction("data/scripts/entity/orderchain.lua", "hasMoreOrders")
                    if ret == 0 and moreOrders == true then
                        -- harvest order fulfilled, another order is queued
                        -- don't send a message
                        terminate()
                        return
                    end

                    -- harvest order fulfilled, no other order is queued
                    if faction then faction:sendChatMessage(ship.name or "", ChatMessageType.Normal, self.getNoMoreSpaceMessage(), coords) end
                    terminate()
                end

                if faction then faction:sendChatMessage(ship.name or "", ChatMessageType.Error, self.getNoMoreSpaceError(), coords) end
            end

            return
        else
            self.noCargoSpace = false
        end
    end

    -- switch away from the current object if it has insignificant amounts of resources left
    if valid(self.objectToHarvest) then
        local resources = 0
        for _, value in pairs({self.objectToHarvest:getMineableResources()}) do
            resources = resources + value
        end

        if resources < 10 then
            self.objectToHarvest = nil
        end
    end

    -- highest priority is harvesting
    if not valid(self.objectToHarvest) and not valid(self.harvestLoot) then

        -- first, check if there is an object to mine
        self:findObjectToHarvest()

        -- then, if there's no object to harvest, check if there is loot to collect
        if not valid(self.objectToHarvest) then
          self:findHarvestLoot()
        end

    end

    local ai = ShipAI()

    if valid(self.harvestLoot) then
        ai:setStatusMessage(self.getCollectLootStatus(), {})

        -- there is loot to collect, fly there
        self.collectCounter = self.collectCounter + timeStep
        if self.collectCounter > 3 then
            self.collectCounter = self.collectCounter - 3

            if ai.isStuck then
                self.stuckLoot[self.harvestLoot.index.string] = true
                self:findHarvestLoot()
                self.collectCounter = self.collectCounter + 2
            end

            if valid(self.harvestLoot) then
                -- set fighters to harvest while flying to pick up loot
                ai:setFly(self.harvestLoot.translationf, 0, nil, FighterOrders.Harvest)
            end
        end

    elseif valid(self.objectToHarvest) then
        ai:setStatusMessage(self.getNormalStatus(), {})

        -- if there is an object, harvest it
        if ship.selectedObject == nil
            or ship.selectedObject.index ~= self.objectToHarvest.index
            or ai.state ~= AIState.Harvest then

            ai:setHarvest(self.objectToHarvest)
            self.stuckLoot = {}
        end

        self.lastHarvestPosition = self.objectToHarvest.translationf
    else
        ai:setStatusMessage(self.getAllHarvestedStatus(), {})
    end

end
