-- data/scripts/player/init.lua
--- Auto-adds the autoscraping entity script to any player/alliance ship when you board/switch crafts (client asks server to attach once).

package.path = package.path .. ";data/scripts/lib/?.lua"
include("callable")

function initialize()
    if onClient() then
        Player():registerCallback("onCraftChanged", "onCraftChanged")
    end
end

function onCraftChanged(playerIndex, craftIndex)
    if onClient() then
        -- Request server to add scripts
        invokeServerFunction("addControllersToShip", craftIndex)
    end
end

function addControllersToShip(craftIndex)
    if not onServer() then return end

    local craft = Entity(craftIndex)
    if not craft or not valid(craft) then return end

    -- Check if it's a ship
    if not craft.isShip then return end

    -- Check if it belongs to the player
    if not craft.playerOwned and not craft.allianceOwned then return end

    -- Add Auto Scraping Controller
    local scraperInitFlag = craft:getValue("autoscraper_initialized")
    if not scraperInitFlag then
        -- Check more thoroughly for existing script to prevent duplicates
        local scripts = craft:getScripts()
        local hasAutoScraper = false
        for _, scriptPath in pairs(scripts) do
            if scriptPath == "data/scripts/entity/autoscrapingcontroller.lua" then
                hasAutoScraper = true
                break
            end
        end

        -- Add the auto-scraping controller if not already present
        if not hasAutoScraper then
            craft:addScriptOnce("data/scripts/entity/autoscrapingcontroller.lua")
            print("[AutoScraper] Added Auto Scraping Controller to ship: " .. (craft.name or "unnamed"))
        end
    end
end
callable(nil, "addControllersToShip")