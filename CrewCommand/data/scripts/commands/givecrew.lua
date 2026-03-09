
local professionMap = {
    pilot     = CrewProfessionType.Pilot,
    engineer  = CrewProfessionType.Engine,
    eng       = CrewProfessionType.Engine,
    mechanic  = CrewProfessionType.Repair,
    mech      = CrewProfessionType.Repair,
    gunner    = CrewProfessionType.Gunner,
    gun       = CrewProfessionType.Gunner,
    miner     = CrewProfessionType.Miner,
    security  = CrewProfessionType.Security,
    sec       = CrewProfessionType.Security,
    attacker  = CrewProfessionType.Attacker,
    boarder   = CrewProfessionType.Attacker,
}

function execute(sender, commandName, crewType, amountStr)
    if not crewType or not amountStr then
        return 1, "", "Usage: /givecrew <type> <amount>\nTypes: pilot, engineer, mechanic, gunner, miner, security, attacker (boarder)"
    end

    local profession = professionMap[crewType:lower()]
    if not profession then
        return 1, "", "Unknown crew type '" .. crewType .. "'. Types: pilot, engineer, mechanic, gunner, miner, security, attacker"
    end

    local amount = tonumber(amountStr)
    if not amount or amount < 1 then
        return 1, "", "Amount must be a positive number."
    end
    amount = math.floor(amount)

    local player = Player()
    if not player then
        return 1, "", "No player found."
    end

    local craft = player.craft
    if not craft then
        return 1, "", "You are not in a ship."
    end

    local crew = craft.crew
    if not crew then
        return 1, "", "This craft has no crew."
    end

    crew:add(amount, CrewMan(profession, false, 1))
    craft.crew = crew

    return 0, "Added " .. amount .. " " .. crewType:lower() .. "(s) to your ship.", ""
end

function getDescription()
    return "Add crew of a specific type to your ship"
end

function getHelp()
    return "Usage: /givecrew <type> <amount>\n" ..
           "Types: pilot, engineer (eng), mechanic (mech), gunner (gun), miner, security (sec), attacker / boarder\n" ..
           "Example: /givecrew boarder 300"
end
