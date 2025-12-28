-- data/scripts/commands/autominer.lua
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
        local initFlag = entity:getValue("autominer_initialized")
        if initFlag then
            return 0, "", "Auto Mining is already active on this ship. Use TAB key to open the UI."
        end

        -- Check thoroughly for existing script to prevent duplicates
        local scripts = entity:getScripts()
        local hasAutoMiner = false
        for _, scriptPath in pairs(scripts) do
            if scriptPath == "data/scripts/entity/autominingcontroller.lua" then
                hasAutoMiner = true
                break
            end
        end

        if not hasAutoMiner then
            entity:addScriptOnce("data/scripts/entity/autominingcontroller.lua")
            return 0, "", "Auto Mining activated. Open the Auto Miner UI (TAB key) to configure."
        else
            return 0, "", "Auto Mining is already active on this ship. Use TAB key to open the UI."
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
            if scriptPath == "data/scripts/entity/autominingcontroller.lua" then
                scriptCount = scriptCount + 1
            end
        end

        if scriptCount == 0 then
            return 0, "", "Auto Mining script not active on this ship."
        end

        -- Disable the mining system first
        local ok, err = entity:invokeFunction("data/scripts/entity/autominingcontroller.lua", "disableAutoMining")

        -- Clear the initialization flag
        entity:setValue("autominer_initialized", nil)

        -- Remove all instances of the script
        for i = 1, scriptCount do
            entity:removeScript("data/scripts/entity/autominingcontroller.lua")
        end

        if scriptCount > 1 then
            return 0, "", "Auto Mining disabled and " .. scriptCount .. " duplicate scripts removed."
        else
            return 0, "", "Auto Mining disabled."
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

        local ok, status = entity:invokeFunction("data/scripts/entity/autominingcontroller.lua", "getStatus")
        if ok == 0 and status then
            return 0, "", status
        else
            return 0, "", "Auto Mining not active on this ship."
        end

    else
        return 0, "", "Usage: /autominer [on|off|status]"
    end
end

function getDescription()
    return "Activates/Deactivates the Auto-Mining system with individual fighter control."
end

function getHelp()
    return [[Usage: /autominer [action]

Actions:
  on/start/enable  - Activates auto-mining on current ship
  off/stop/disable - Deactivates auto-mining
  status           - Shows current status

The system will:
- Assign fighters individually to nearby asteroids
- Allocate 1 fighter per 1000 resources (minimum 1)
- Continue until cargo is full or no asteroids remain
- Prioritize nearest asteroids first

Use the Auto Miner UI (System tab) for detailed control.
]]
end
