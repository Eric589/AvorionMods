package.path = package.path .. ";data/scripts/lib/?.lua"
include ("callable")

-- Don't remove or alter the following comment, it tells the game the namespace this script lives in. If you remove it, the script will break.
-- namespace LootCleaner

LootCleaner = {}

--quick version, extremely ugly code, need to redo almost ALL OF IT
local buttons = {}
buttons[1] = {}
buttons[2] = {}
buttons[3] = {}
buttons[4] = {}
buttons[20] = {}
buttons[21] = {}
buttons[23] = {}
buttons[101] = {}
buttons[120] = {}
buttons[121] = {}
buttons[123] = {}
local window
local settings = {}

function LootCleaner.initialize()
	if onClient() then
		LootCleaner.configCheck()
		local config = LootCleaner.configUpdate()
		for k, v in pairs(config) do
			buttons[tonumber(k)].state = v
		end
	end
end

function LootCleaner.getIcon()
	return "data/textures/icons/mark-as-trash.png"
end

function LootCleaner.interactionPossible()
	local player = Player()
	local entity = Entity()
	if player.craft.index.value == entity.id.value then
		return true, ""
	else
		return false, ""
	end
end

function LootCleaner.initUI()
	local res = getResolution()

	local size = vec2(878, 534)

	local menu = ScriptUI()

	window = menu:createWindow(Rect(res * 0.5 - size * 0.5, res * 0.5 + size * 0.5))
	window.caption = "Sector cleaner"%_t
	window.showCloseButton = 1
	window.moveable = 1
	window.shadeBackground = true

	menu:registerWindow(window, "Sector cleaner"%_t)
	
	local button = window:createButton(Rect(vec2(320, 64)), "Clean loot"%_t, "scan1")
	button.position = button.position + vec2(10, 10)
	button.tooltip = "Delete insignificant loot listed below"%_t
	
	button = window:createButton(Rect(vec2(320, 64)), "Clean wreckages"%_t, "scan2")
	button.position = button.position + vec2(340, 10)
	button.tooltip = "Delete wreckages that meets criteria below\nIf you select several options, the wreckage will be deleted if at least one of the requirements is met"%_t
	
	button = window:createButton(Rect(vec2(128, 64)), "Auto"%_t, "button3")
	button.position = button.position + vec2(670, 10)
	button.tooltip = "Sets a timer in seconds for the cleaning\n60 is recommended. Values below 10 are almost pointless and will do more harm than good"%_t
	
	local picture = window:createPicture(Rect(vec2(64, 64)), "data/textures/ui/misc/redButton.png")
	picture.flipped = true
	picture.position = picture.position + vec2(808, 10)
	
	buttons[1].button = button
	buttons[1].picture = picture
	
	textBox = window:createTextBox(Rect(vec2(96, 48)), "tb1")
	textBox.position = button.position + vec2(0, 58+38)
	textBox.allowedCharacters = "0123456789"
	textBox.text = 0
	textBox.maxCharacters = 9
	buttons[1].textBox = textBox

	local text = window:createTextField(Rect(vec2(128, 32)), "Filters:"%_t)
	text.padding = 0
	text.fontSize = 22
	text.position = text.position + vec2(10, 74)
	
	text = window:createTextField(Rect(vec2(128, 32)), "Filters:"%_t)
	text.padding = 0
	text.fontSize = 22
	text.position = text.position + vec2(340, 74)
	
	text = window:createTextField(Rect(vec2(256, 32)), "Frequency(sec):"%_t)
	text.padding = 0
	text.fontSize = 22
	text.position = text.position + vec2(670, 74)
	
	local line = window:createLine(vec2(330, 10), vec2(330, 454))
	line = window:createLine(vec2(660, 10), vec2(660, 454))
	line = window:createLine(vec2(330, 215), vec2(660, 215))
	line = window:createLine(vec2(330, 332), vec2(660, 332))
	line = window:createLine(vec2(0, 454), vec2(878, 454))

	button = window:createButton(Rect(vec2(196, 48)), "Money"%_t, "")
	button.position = button.position + vec2(10, 84+22)
	picture = window:createPicture(Rect(vec2(48, 48)), "data/textures/ui/misc/redButton.png")
	picture.flipped = true
	picture.position = button.position + vec2(206, 0)
	button.tooltip = "Delete money loot"%_t
	buttons[2].button = button
	buttons[2].picture = picture

	button = window:createButton(Rect(vec2(196, 48)), "Scrap metals"%_t, "")
	button.position = button.position + vec2(10, 84+58+22)
	local picture = window:createPicture(Rect(vec2(48, 48)), "data/textures/ui/misc/redButton.png")
	picture.flipped = true
	picture.position = button.position + vec2(206, 0)
	button.tooltip = "Delete scrap metals loot"%_t
	buttons[3].button = button
	buttons[3].picture = picture
	
	button = window:createButton(Rect(vec2(196, 48)), "Resources"%_t, "")
	button.position = button.position + vec2(10, 84+58+ 58+22)
	button.tooltip = "Delete resource loot, if its floating more than 30 seconds (protection from accidental deletion of mined resouces)"%_t
	local picture = window:createPicture(Rect(vec2(48, 48)), "data/textures/ui/misc/redButton.png")
	picture.flipped = true
	picture.position = button.position + vec2(206, 0)
	buttons[4].button = button
	buttons[4].picture = picture
	
	button = window:createButton(Rect(vec2(262, 48)), "Size"%_t, "")
	button.position = button.position + vec2(340, 84+22)
	button.tooltip = "Every wreckage smaller than this value will be deleted"%_t
	local picture = window:createPicture(Rect(vec2(48, 48)), "data/textures/ui/misc/redButton.png")
	picture.flipped = true
	picture.position = button.position + vec2(270, 0)
	buttons[20].button = button
	buttons[20].picture = picture
	
	textBox = window:createTextBox(Rect(vec2(96, 48)), "tb20")
	textBox.position = button.position + vec2(0, 58)
	textBox.allowedCharacters = "0123456789"
	textBox.text = 0
	textBox.maxCharacters = 9
	buttons[20].textBox = textBox
	
	button = window:createButton(Rect(vec2(262, 48)), "Money value"%_t, "")
	button.position = button.position + vec2(340, 84+58+22+58)
	button.tooltip = "Every wreckage cheaper than this value will be deleted"%_t
	local picture = window:createPicture(Rect(vec2(48, 48)), "data/textures/ui/misc/redButton.png")
	picture.flipped = true
	picture.position = button.position + vec2(270, 0)
	buttons[21].button = button
	buttons[21].picture = picture
	
	textBox = window:createTextBox(Rect(vec2(96, 48)), "tb21")
	textBox.position = button.position + vec2(0, 58)
	textBox.allowedCharacters = "0123456789"
	textBox.text = 0
	textBox.maxCharacters = 9
	buttons[21].textBox = textBox
	
	button = window:createButton(Rect(vec2(262, 48)), "Resources value"%_t, "")
	button.position = button.position + vec2(340, 84+58+58+22+58+58)
	button.tooltip = "Every wreckage cheaper(in resources) than this value will be deleted"%_t
	local picture = window:createPicture(Rect(vec2(48, 48)), "data/textures/ui/misc/redButton.png")
	picture.flipped = true
	picture.position = button.position + vec2(270, 0)
	buttons[23].button = button
	buttons[23].picture = picture
	
	textBox = window:createTextBox(Rect(vec2(96, 48)), "tb23")
	textBox.position = button.position + vec2(0, 58)
	textBox.allowedCharacters = "0123456789"
	textBox.text = 0
	textBox.maxCharacters = 9
	buttons[23].textBox = textBox
	
	button = window:createButton(Rect(vec2(192, 48)), "Reset settings"%_t, "reset")
	button.tooltip = "Restore default settings"%_t
	button.position = button.position + vec2(350, 470)
	
	for i, v in pairs(buttons) do
		if i < 100 then
			v.button.onPressedFunction = "button" .. i
			LootCleaner["button" .. i] = function()
				if buttons[i].state == "true" then
					buttons[i].state = "false"
					buttons[i].picture.picture = "data/textures/ui/misc/redButton.png"
				else
					buttons[i].state = "true"
					buttons[i].picture.picture = "data/textures/ui/misc/greenButton.png"
				end
			end
		end
	end	
end

function LootCleaner.onShowWindow()
	for k, v in pairs(buttons) do
		if k < 100 then
			if v.state == "true" then
				v.picture.picture = "data/textures/ui/misc/greenButton.png"
			else
				v.picture.picture = "data/textures/ui/misc/redButton.png"
			end
		else
			if k == 101 then
				buttons[1].textBox.text = v.state
			elseif k == 120 then
				buttons[20].textBox.text = v.state
			elseif k == 121 then
				buttons[21].textBox.text = v.state
			elseif k == 123 then
				buttons[23].textBox.text = v.state
			end
		end
	end
end

function LootCleaner.onCloseWindow()
	local file = io.open("/moddata/Sector Cleaner/userConfig.lua", 'w')
	for k, v in pairs(buttons) do
		file:write(k .. " " .. v.state .. '\n')
	end
    io.close(file)	
end

function LootCleaner.getUpdateInterval()
    return tonumber(buttons[101].state)
end

function LootCleaner.updateClient()
	if not Entity().hasPilot then return end
	if buttons[1].state == "true" then
		LootCleaner.scan1()
		LootCleaner.scan2()
	end
end

function LootCleaner.tb1()
	if buttons[1].textBox.text == "" then
		buttons[1].textBox.text = 1
	end
	buttons[101].state = buttons[1].textBox.text
end

function LootCleaner.tb20()
	if buttons[20].textBox.text == "" then
		buttons[20].textBox.text = 1
	end
	buttons[120].state = buttons[20].textBox.text
end

function LootCleaner.tb21()
	if buttons[21].textBox.text == "" then
		buttons[21].textBox.text = 1
	end
	buttons[121].state = buttons[21].textBox.text
end

function LootCleaner.tb23()
	if buttons[23].textBox.text == "" then
		buttons[23].textBox.text = 1
	end
	buttons[123].state = buttons[23].textBox.text
end

function LootCleaner.reset()
	local config = LootCleaner.configUpdate("defaults")
	for k, v in pairs(config) do
		buttons[tonumber(k)].state = v
	end	
	for k, v in pairs(buttons) do
		if k < 100 then
			if v.state == "true" then
				v.picture.picture = "data/textures/ui/misc/greenButton.png"
			else
				v.picture.picture = "data/textures/ui/misc/redButton.png"
			end
		else
			if k == 101 then
				buttons[1].textBox.text = v.state
			elseif k == 120 then
				buttons[20].textBox.text = v.state
			elseif k == 121 then
				buttons[21].textBox.text = v.state
			elseif k == 123 then
				buttons[23].textBox.text = v.state
			end
		end
	end
end

function LootCleaner.scan1()
	local sector = Sector()	
	local sectorLoot = {sector:getEntitiesByType(EntityType.Loot)}
	local taggedLoot = {}
	for _, item in pairs(sectorLoot) do
		--if money drop
		if item:hasComponent(ComponentType.MoneyLoot) then
			if buttons[2].state == "true" then
				table.insert(taggedLoot, item)
			end
	--if cargo drop			
		elseif item:hasComponent(ComponentType.CargoLoot) then
			if buttons[3].state == "true" then
				local loot = CargoLoot(item)
				if loot:matches("Scrap") then
					if not loot:matches("Metal") then
						table.insert(taggedLoot, item)
					end
				end
			end
		--if resource drop
		elseif item:hasComponent(ComponentType.ResourceLoot) then
			if buttons[4].state == "true" then
				if item.timeAlive > 30 then
					table.insert(taggedLoot, item)
				end
			end
		end
	end
	invokeServerFunction("clean", taggedLoot)
end

function LootCleaner.scan2()
	local sector = Sector()	
	local sectorWreckages = {sector:getEntitiesByType(EntityType.Wreckage)}
	local taggedWreckages = {}
	for _, wreckage in pairs(sectorWreckages) do
		local isTagged = false
		local wreckPlan = Plan(wreckage.id)
		if buttons[23].state == "true" then
			local resources = {wreckPlan:getResourceValue()}
			local totalRes = 0
			for _, v in pairs(resources) do
				totalRes = totalRes + v
			end
			if totalRes < tonumber(buttons[23].textBox.text) then
				table.insert(taggedWreckages, wreckage)
				isTagged = true
			end
		end
		if isTagged == false then
			if buttons[21].state == "true" then
				if wreckPlan:getMoneyValue() < tonumber(buttons[21].textBox.text) then
					table.insert(taggedWreckages, wreckage)
					isTagged = true
				end
			end
			if isTagged == false then
				if buttons[20].state == "true" then
					if wreckPlan.numBlocks < tonumber(buttons[20].textBox.text) then
						table.insert(taggedWreckages, wreckage)
						isTagged = true
					end
				end
			end			
		end
	end
	invokeServerFunction("clean", taggedWreckages)
end

function LootCleaner.clean(taggedLoot, taggedWreckages)
	local sector = Sector()
	
	if taggedLoot then
		for _, loot in pairs(taggedLoot) do
			if valid(loot) then
				sector:deleteEntity(loot)
			end
		end
	end

	if taggedWreckages then 
		for _, wreckage in pairs(taggedWreckages) do
			if valid(wreckage) then
				sector:deleteEntity(wreckage)
			end
		end
	end
end

callable(LootCleaner, "clean")

local version = "1.0"
function LootCleaner.configCheck()
	local check = io.open("/moddata/Sector Cleaner/version.lua", 'r')
	if not check then
		LootCleaner.CreateFolder()
		LootCleaner.configCreate(true) 
	else
		local file = io.open("/moddata/Sector Cleaner/version.lua", 'r')
		if file:read() ~= version then
			LootCleaner.configCreate(false)
		end		
		io.close(file)
		io.close(check)
	end
end

function LootCleaner.CreateFolder()
	local dir = "moddata"
	if onServer() then
		dir = Server().folder.."/"..dir
	end
	dir = dir.."/".."Sector Cleaner"
	createDirectory(dir)
end

function LootCleaner.configCreate(fresh)
	local defaultConf = {
		"1 true",
		"2 true",
		"3 true",
		"4 true",
		"20 false",
		"21 false",
		"23 true",
		"101 60",
		"120 10",
		"121 2000",
		"123 200",
	}

	local file = io.open("/moddata/Sector Cleaner/version.lua", 'w')
	file:write(version)
	io.close(file)
	
	local file = io.open("/moddata/Sector Cleaner/defaultConfig.lua", 'w')
	for _, line in pairs(defaultConf) do
		file:write(line..'\n')
	end
	io.close(file)
	
	if fresh == false then
		local oldUserConf = LootCleaner.configUpdate()
		local newDefaultConf = LootCleaner.configUpdate("defaults")
		for k, v in pairs(newDefaultConf) do 
			if not oldUserConf[k] then
				oldUserConf[k] = v
			end
		end
		local file = io.open("/moddata/Sector Cleaner/userConfig.lua", 'w')
		for k, v in pairs(oldUserConf) do
			file:write(k .. " " .. v .. '\n')
		end
		io.close(file)
	else
		local file = io.open("/moddata/Sector Cleaner/userConfig.lua", 'w')
		for _, line in pairs(defaultConf) do
		file:write(line..'\n')
		end
		io.close(file)
	end			
end

function LootCleaner.configUpdate(loadDefaults)
	local path
	if loadDefaults == "defaults" then
		path = "default"
	else
		path = "user"
	end
	local readConf = {}
	local file = io.open("/moddata/Sector Cleaner/" .. path .. "Config.lua", "r")	
	for line in file:lines() do
		local key
		local value
		for word in string.gmatch(line, "%S+") do
			if key == nil then 
				key = word
			else
				value = word
				readConf[key] = value
			end
		end
	end
	io.close(file)
	return readConf
end




