local emotes = {}
local screenWidth, screenHeight = guiGetScreenSize()
local chatxoffset, chatyoffset = screenWidth * 0.0145, screenHeight * 0.0145
local emotesVisible = true
local settingsFile = "@emotes_setting.xml" -- The '@' means it saves to the user's PC securely

function getImageOffsets(text)
	local layout = getChatboxLayout()
	local font = ({[1] = "clear", [2] = "default-bold", [3] = "arial"})[layout["chat_font"]] or "default"
	local height = dxGetFontHeight(layout["text_scale"], font)
	local scale = layout["chat_scale"]
	local sx, sy
	if type(scale) == "table" then
		sx = scale[1] or 1
		sy = scale[2] or sx
	else
		sx = tonumber(scale) or 1
		sy = sx
	end

	local width = (dxGetTextWidth(text, layout["text_scale"], font) + chatxoffset) * sx
	return width, height, sx, sy
end

-- Load settings when the core starts clientside
addEventHandler("onClientResourceStart", resourceRoot, function()
	local xml = xmlLoadFile(settingsFile)
	if xml then
		local val = xmlNodeGetValue(xml)
		emotesVisible = (val ~= "false") -- Defaults to true unless explicitly false
		xmlUnloadFile(xml)
	else
		-- Create the file if it doesn't exist
		xml = xmlCreateFile(settingsFile, "emotes")
		if xml then
			xmlNodeSetValue(xml, "true")
			xmlSaveFile(xml)
			xmlUnloadFile(xml)
		end
	end
	-- Sync state to server immediately
	setElementData(localPlayer, "twitchemotes:disabled", not emotesVisible)
end)

addEvent("triggerChat", true)
addEventHandler("triggerChat", root, function(originaltext, emote, emoteID, emotePath)
	local width, height, sx, sy = getImageOffsets(originaltext)
	local chatwidth = getChatboxLayout()["chat_width"] * 317 * sx
	local originalmultiplier = math.floor(width / chatwidth)

	local escapedID = string.gsub(tostring(emoteID), "%-", "%%-")
	local text = string.gsub(originaltext, escapedID .. ".*", "")
	local posWidth = getImageOffsets(text)
	local multiplier = math.floor(posWidth / chatwidth)

	table.insert(emotes, {emotePath, posWidth - (multiplier * chatwidth), getChatboxLayout()["chat_lines"] - (originalmultiplier - multiplier), false})

	local _, count = string.gsub(originaltext, escapedID, escapedID)
	if count > 1 then
		triggerEvent("triggerChat", source, string.gsub(originaltext, escapedID, string.rep("-", #emoteID), 1), emote, emoteID, emotePath)
	end
end)

addEventHandler("onClientRender", root, function()
	-- If emotes are toggled off OR the chat itself is hidden, stop right here
	if not emotesVisible or not isChatVisible() then
		return
	end

	local _, fHeight, _, sy = getImageOffsets("")
	for i = #emotes, 1, -1 do
		local item = emotes[i]
		if item[3] < 1 then
			table.remove(emotes, i)
		else
			dxDrawImage(item[2], (chatyoffset + (item[3] - 1) * fHeight) * sy, 22, 22, item[1], 0, 0, 0, tocolor(255, 255, 255, 255), true)
		end
	end
end)

addEventHandler("onClientChatMessage", root, function(text)
	local width, _, sx = getImageOffsets(text)
	local mult = math.floor(width / (getChatboxLayout()["chat_width"] * 317 * sx)) + 1
	for _, item in ipairs(emotes) do
		if item[4] then
			item[3] = item[3] - mult
		end
		item[4] = true
	end
end)

addCommandHandler("twitchemotes", function()
	emotesVisible = not emotesVisible

	-- Save the new setting to the XML file
	local xml = xmlLoadFile(settingsFile) or xmlCreateFile(settingsFile, "emotes")
	if xml then
		xmlNodeSetValue(xml, tostring(emotesVisible))
		xmlSaveFile(xml)
		xmlUnloadFile(xml)
	end

	-- Sync the new setting to the server
	setElementData(localPlayer, "twitchemotes:disabled", not emotesVisible)

	outputChatBox("Twitch emotes are now " .. (emotesVisible and "ENABLED" or "DISABLED") .. ".", 255, 255, 0)
end, false)

-- Register the clear event
addEvent("clearEmotes", true)
addEventHandler("clearEmotes", root, function()
	emotes = {} -- Empty the active emotes table
end)
