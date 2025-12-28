-- UI Sample command
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
        
        local initFlag = entity:getValue("uisample_initialized")
        if initFlag then
            return 0, "", "UI Sample already active. Use TAB to open UI."
        end
        
        local scripts = entity:getScripts()
        local hasScript = false
        for _, scriptPath in pairs(scripts) do
            if scriptPath == "entity/uisamplecontroller.lua" then
                hasScript = true
                break
            end
        end

        if not hasScript then
            entity:addScriptOnce("entity/uisamplecontroller.lua")
            return 0, "", "UI Sample activated. Open UI with TAB."
        else
            return 0, "", "UI Sample already active."
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
            if scriptPath == "entity/uisamplecontroller.lua" then
                scriptCount = scriptCount + 1
            end
        end

        if scriptCount == 0 then
            return 0, "", "UI Sample not active."
        end

        entity:invokeFunction("entity/uisamplecontroller.lua", "disable")
        entity:setValue("uisample_initialized", nil)

        for i = 1, scriptCount do
            entity:removeScript("entity/uisamplecontroller.lua")
        end
        
        return 0, "", "UI Sample disabled."
        
    else
        return 0, "", "Usage: /uisample [on|off]"
    end
end

function getDescription()
    return "Toggles the UI Sample controller"
end

function getHelp()
    return "Usage: /uisample [on|off]\n\nActivates or deactivates the UI Sample controller on your current ship."
end
