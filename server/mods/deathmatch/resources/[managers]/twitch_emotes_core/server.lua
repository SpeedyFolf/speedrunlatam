local registeredPacks = {}
local activeEmotes = {}
local idCounter = 1

function escapePattern(text)
	return text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
end

function buildActiveEmotes()
	activeEmotes = {}
	idCounter = 1
	for resName, packData in pairs(registeredPacks) do
		for _, emote in ipairs(packData) do
			local hiddenId = string.format("-%04d", idCounter)
			-- Format: {Name, HiddenID, MatchCount, Path, EscapedName}
			table.insert(activeEmotes, {emote.name, hiddenId, 0, emote.path, escapePattern(emote.name)})
			idCounter = idCounter + 1
		end
	end
	-- Longest names first to prevent "KappaPride" being eaten by "Kappa"
	table.sort(activeEmotes, function(a, b)
		return string.len(a[1]) > string.len(b[1])
	end)
end

function registerEmotes(resName, emotesList)
	registeredPacks[resName] = emotesList
	buildActiveEmotes()
	outputDebugString("[Emotes Core] Loaded " .. #emotesList .. " emotes from " .. resName)
end

addEventHandler("onResourceStop", root, function(res)
	local name = getResourceName(res)
	if registeredPacks[name] then
		registeredPacks[name] = nil
		buildActiveEmotes()
	end
end)

function removeHEXColorCode(name)
	return name:gsub('#%x%x%x%x%x%x', '') or name
end

addEventHandler("onPlayerChat", root, function(text, messageType)
	if messageType > 1 and messageType ~= 3 then
		return
	end
	cancelEvent()

	local originalText = text
	local name = getPlayerName(source)

	-- Log to server console since we cancelled the event
	outputServerLog("CHAT: " .. name .. ": " .. text)

	-- Step 1: Detect emotes (Case-Sensitive)
	for i, item in ipairs(activeEmotes) do
		text, item[3] = string.gsub(text, item[5], item[2])
	end

	local chatLine = (string.gsub(name .. ":#EBDDB2 " .. text, "#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]", ""))

	-- Step 2: Tell clients to draw images
	for i, item in ipairs(activeEmotes) do
		if item[3] > 0 then
			triggerClientEvent(root, "triggerChat", source, chatLine, item[1], item[2], item[4])
		end
	end

	-- Step 3: Create the spaced-out version of the text
	local spacedText = originalText
	for i, item in ipairs(activeEmotes) do
		spacedText = string.gsub(spacedText, item[5], "      ")
	end

	-- Step 4: Output to players based on their personal settings
	-- Type 0 is a normal message
	-- Type 3 is a private message
	if (messageType == 0) or (messageType == 3) then
		for _, p in ipairs(getElementsByType("player")) do
			-- If the player disabled emotes, show originalText. Otherwise, show spacedText.
			local disabled = getElementData(p, "twitchemotes:disabled")
			local textToDisplay = disabled and originalText or spacedText

			outputChatBox(name .. ":#EBDDB2 " .. textToDisplay, p, 255, 255, 255, true)
		end
	end

	-- Fix for server built-in me command handling player color tags
	-- Type 1 is an action (/me) message
	if (messageType == 1) then
		cancelEvent()
		for _, p in ipairs(getElementsByType("player")) do
			local disabled = getElementData(p, "twitchemotes:disabled")
			local textToDisplay = disabled and originalText or spacedText
			outputChatBox("* " .. removeHEXColorCode(name) .. " " .. textToDisplay, p, 162, 25, 255) -- #A219FF
		end
	end

-- Message type 2 is a team message and message type 4 is an internal message. These are left untouched for now.
end)

-- Diagnostic command
addCommandHandler("emotelist", function(player)
	outputChatBox("Emotes Loaded: " .. #activeEmotes, player, 0, 255, 0)
end, false, false)

-- Broadcast to all clients to wipe their emote tables when chat is cleared
addCommandHandler("clearchat", function(player)
	-- We don't cancel the event here so your existing admin script still clears the text
	triggerClientEvent(root, "clearEmotes", root)
end)
