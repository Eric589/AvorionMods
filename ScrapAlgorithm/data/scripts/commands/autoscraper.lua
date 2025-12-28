-- data/scripts/commands/autoscraper.lua
--- Chat command to toggle/setup the autoscraping controller on the currently boarded ship (server side attach/remove/status).
package.path = package.path .. ";data/scripts/lib/?.lua"
include("stringutility")

function execute(sender, commandName, action, ...)
    local player = Player(sender)
    if not player then
        return 1, "Player not found.", ""
    end

    action = string.lower(action or "status")

    if action == "on" or action == "start" or action == "enable" then
        -- Add script to player's craft
        local craft = player.craft
        if not craft or not valid(craft) then
            return 0, "", "No craft selected. Please board a ship first."
        end

        local entity = Entity(craft.index)
        if not entity then
            return 0, "", "Could not access craft entity."
        end

        -- Check if already initialized using the flag
        local initFlag = entity:getValue("autoscraper_initialized")
        if initFlag then
            return 0, "", "Auto Scraping is already active on this ship. Use TAB key to open the UI."
        end

        -- Check thoroughly for existing script to prevent duplicates
        local scripts = entity:getScripts()
        local hasAutoScraper = false
        for _, scriptPath in pairs(scripts) do
            if scriptPath == "data/scripts/entity/autoscrapingcontroller.lua" then
                hasAutoScraper = true
                break
            end
        end

        if not hasAutoScraper then
            entity:addScriptOnce("data/scripts/entity/autoscrapingcontroller.lua")
            return 0, "", "Auto Scraping activated. Open the Auto Scraper UI (TAB key) to configure."
        else
            return 0, "", "Auto Scraping is already active on this ship. Use TAB key to open the UI."
        end

    elseif action == "off" or action == "stop" or action == "disable" then
        local craft = player.craft
        if not craft or not valid(craft) then
            return 0, "", "No craft selected."
        end

        local entity = Entity(craft.index)
        if not entity then
            return 0, "", "Could not access craft entity."
        end

        -- Check if script exists
        local scripts = entity:getScripts()
        local scriptCount = 0
        for _, scriptPath in pairs(scripts) do
            if scriptPath == "data/scripts/entity/autoscrapingcontroller.lua" then
                scriptCount = scriptCount + 1
            end
        end

        if scriptCount == 0 then
            return 0, "", "Auto Scraping script not active on this ship."
        end

        -- Disable the scraping system first
        local ok, err = entity:invokeFunction("data/scripts/entity/autoscrapingcontroller.lua", "disableAutoScraping")

        -- Clear the initialization flag
        entity:setValue("autoscraper_initialized", nil)

        -- Remove all instances of the script
        for i = 1, scriptCount do
            entity:removeScript("data/scripts/entity/autoscrapingcontroller.lua")
        end

        if scriptCount > 1 then
            return 0, "", "Auto Scraping disabled and " .. scriptCount .. " duplicate scripts removed."
        else
            return 0, "", "Auto Scraping disabled."
        end

    elseif action == "status" then
        local craft = player.craft
        if not craft or not valid(craft) then
            return 0, "", "No craft selected."
        end

        local entity = Entity(craft.index)
        if not entity then
            return 0, "", "Could not access craft entity."
        end

        local ok, status = entity:invokeFunction("data/scripts/entity/autoscrapingcontroller.lua", "getStatus")
        if ok == 0 and status then
            return 0, "", status
        else
            return 0, "", "Auto Scraping not active on this ship."
        end

    else
        return 0, "", "Usage: /autoscraper [on|off|status]"
    end
end

function getDescription()
    return "Activates/Deactivates the Auto-Scraping system with individual fighter control."
end

function getHelp()
    return [[Usage: /autoscraper [action]

Actions:
  on/start/enable  - Activates auto-scraping on current ship
  off/stop/disable - Deactivates auto-scraping
  status           - Shows current status

The system will:
- Assign salvaging fighters individually to nearby wreckage
- Allocate 1 fighter per 50000 resource value (minimum 1)
- Continue until cargo is full or no wreckage remains
- Prioritize nearest wreckage first

Use the Auto Scraper UI (System tab) for detailed control.
]]
end