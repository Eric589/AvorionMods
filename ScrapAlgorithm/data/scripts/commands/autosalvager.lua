-- Auto Salvager command
package.path = package.path .. ";data/scripts/lib/?.lua"

function execute(sender, commandName, action)
    local player = Player(sender)
    if not player then
        return 1, "Player not found.", ""
    end
    
    action = string.lower(action or "")
    
    if action == "on" or action == "enable" then
        local craft = player.craft
        if not craft or not valid(craft) then
            return 0, "", "No craft selected. Board a ship first."
        end
        
        local entity = Entity(craft.index)
        if not entity then
            return 0, "", "Could not access craft."
        end
        
        local initFlag = entity:getValue("autosalvager_initialized")
        if initFlag then
            return 0, "", "Auto Salvager already active. Use TAB to open UI."
        end
        
        local scripts = entity:getScripts()
        local hasScript = false
        for _, scriptPath in pairs(scripts) do
            if scriptPath == "../entity/autosalvagercontroller.lua" then
                hasScript = true
                break
            end
        end

        if not hasScript then
            entity:addScriptOnce("../entity/autosalvagercontroller.lua")
            return 0, "", "Auto Salvager activated. Open UI with TAB."
        else
            return 0, "", "Auto Salvager already active."
        end
        
    elseif action == "off" or action == "disable" then
        local craft = player.craft
        if not craft or not valid(craft) then
            return 0, "", "No craft selected."
        end
        
        local entity = Entity(craft.index)
        if not entity then
            return 0, "", "Could not access craft."
        end
        
        local scripts = entity:getScripts()
        local scriptCount = 0
        for _, scriptPath in pairs(scripts) do
            if scriptPath == "../entity/autosalvagercontroller.lua" then
                scriptCount = scriptCount + 1
            end
        end

        if scriptCount == 0 then
            return 0, "", "Auto Salvager not active."
        end

        entity:invokeFunction("../entity/autosalvagercontroller.lua", "disable")
        entity:setValue("autosalvager_initialized", nil)

        for i = 1, scriptCount do
            entity:removeScript("../entity/autosalvagercontroller.lua")
        end
        
        return 0, "", "Auto Salvager disabled."
        
    else
        return 0, "", "Usage: /autosalvager [on|off]"
    end
end

function getDescription()
    return "Toggles the Auto Salvager controller"
end

function getHelp()
    return "Usage: /autosalvager [on|off]\n\nActivates or deactivates the Auto Salvager controller on your current ship."
end
