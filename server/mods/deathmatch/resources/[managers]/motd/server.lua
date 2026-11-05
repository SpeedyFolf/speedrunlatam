-- ### Variables
motdSettings = Xml:new("motd.xml","motd") -- New XML object for MOTD (Changelog)
rulesSettings = Xml:new("rules.xml","rules") -- New XML object for Rules

defaultMotdText = "Put your Changelog/MOTD text here."
defaultRulesText = "Put your Rules text here."

--[[
-- clientMessage
--
-- Handles messages received from a client.
-- ]]
function clientMessage(message,parameter)
	local player = client

	if message == "get" then
		sendMotdToClient(player)
	end

	if message == "save" then
		if not hasObjectPermissionTo(player,"resource.motd.edit",false) then
			return
		end

		local tabName = parameter[1] -- "motd" or "rules"
		local text = parameter[2]
		local dontIncreaseVersion = parameter[3]

		-- Select the correct XML file based on the tab name
		local settings
		if tabName == "motd" then
			settings = motdSettings
		elseif tabName == "rules" then
			settings = rulesSettings
		else
			outputDebugString("MOTD/Rules Server: Invalid tab name received for save: "..tostring(tabName))
			return
		end

		settings:open()
		local currentVersion = tonumber(settings:getAttribute("root","version")) or 0
		if not dontIncreaseVersion then
			settings:setAttribute("root","version",currentVersion + 1)
		end
		settings:setAttribute("root","lastChanged",makeCurrentDatetime())
		settings:setValue("root",text)
		settings:save(true)

		-- Send updated data for both tabs to ALL clients to refresh their GUIs
		sendMotdToAllClients()
	end
end
addEvent("onMotdClientMessage",true)
addEventHandler("onMotdClientMessage",root,clientMessage)


--[[
-- sendMotdToClient
--
-- Sends the current motd and rules (from two XML files) to the given player.
--
-- @param   player   player: The player to whom the motd should be sent.
-- ]]
function sendMotdToClient(player)
	-- 1. Get MOTD data
	motdSettings:open()
	local motdText = motdSettings:getValue("root") or defaultMotdText
	local motdVersion = tonumber(motdSettings:getAttribute("root","version")) or 0
	local motdLastChanged = motdSettings:getAttribute("root","lastChanged") or "0000-00-00 00:00:00"
	motdSettings:unload()

	-- 2. Get Rules data
	rulesSettings:open()
	local rulesText = rulesSettings:getValue("root") or defaultRulesText
	local rulesVersion = tonumber(rulesSettings:getAttribute("root","version")) or 0
	local rulesLastChanged = rulesSettings:getAttribute("root","lastChanged") or "0000-00-00 00:00:00"
	rulesSettings:unload()

	-- Send data for BOTH tabs in a structured table
	local data = {
		{motdText, motdVersion, motdLastChanged}, -- MOTD data is index 1
		{rulesText, rulesVersion, rulesLastChanged} -- Rules data is index 2
	}

	sendMessageToClient(player,"get",data)
end

--[[
-- sendMotdToAllClients
--
-- Sends the current motd and rules to all clients to update their GUI.
-- ]]
function sendMotdToAllClients()
	-- Retrieve and send to ALL elements in the root, which includes all players
	motdSettings:open()
	local motdText = motdSettings:getValue("root") or defaultMotdText
	local motdVersion = tonumber(motdSettings:getAttribute("root","version")) or 0
	local motdLastChanged = motdSettings:getAttribute("root","lastChanged") or "0000-00-00 00:00:00"
	motdSettings:unload()

	rulesSettings:open()
	local rulesText = rulesSettings:getValue("root") or defaultRulesText
	local rulesVersion = tonumber(rulesSettings:getAttribute("root","version")) or 0
	local rulesLastChanged = rulesSettings:getAttribute("root","lastChanged") or "0000-00-00 00:00:00"
	rulesSettings:unload()

	local data = {
		{motdText, motdVersion, motdLastChanged},
		{rulesText, rulesVersion, rulesLastChanged}
	}

	triggerClientEvent(root, "onClientMotdServerMessage", root, "get", data)
end


--[[
-- sendMessageToClient
--
-- Sends any message to the given players client.
-- ]]
function sendMessageToClient(player,message,parameter)
	triggerClientEvent(player,"onClientMotdServerMessage",root,message,parameter)
end

--[[
-- edit
--
-- Opens the edit gui for a player on request (if he has permission).
-- **FIX**: This is the handler for /editmotd
-- ]]
function edit(player)
	if hasObjectPermissionTo(player,"resource.motd.edit",false) then
		sendMessageToClient(player,"edit")
	end
end
addCommandHandler("editmotd",edit)

--[[
-- initiate
--
-- Initiates the XML files.
-- ]]
function initiate()
	local function initFile(settings, defaultText)
		settings:open()
		local text = settings:getValue("root")
		local version = tonumber(settings:getAttribute("root","version"))
		local lastChanged = settings:getAttribute("root","lastChanged")
		if text == "" or text == false or text == nil then
			settings:setValue("root",defaultText)
		end
		if type(version) ~= "number" then
			settings:setAttribute("root","version",1)
		end
		if lastChanged == "" or lastChanged == false or lastChanged == nil then
			settings:setAttribute("root","lastChanged","0000-00-00 00:00:00")
		end
		settings:save(true)
	end

	initFile(motdSettings, defaultMotdText)
	initFile(rulesSettings, defaultRulesText)
end
addEventHandler("onResourceStart",resourceRoot,initiate)


------------------
-- Help functions
------------------

--[[
-- makeCurrentDatetime
--
-- Creates date and time (realtime, not ingame time) in the YYYY-MM-DD HH:MM:SS format.
-- ]]
function makeCurrentDatetime()
	local time = getRealTime()
	local year = time.year + 1900
	local month = fillDigits(time.month + 1)
	local day = fillDigits(time.monthday)
	local hour = fillDigits(time.hour)
	local minute = fillDigits(time.minute)
	local second = fillDigits(time.second)
	return year.."-"..month.."-"..day.." "..hour..":"..minute..":"..second
end

--[[
-- fillDigits
--
-- Adds leading zeros to a string, until it reaches a certain length.
-- ]]
function fillDigits(text,min)
	if min == nil then
		min = 2
	end
	local text = tostring(text)
	return string.rep("0",min - text:len())..text
end
