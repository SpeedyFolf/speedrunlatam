g_Resource = getThisResource()
g_ResName = getResourceName(getThisResource())

--
-- DEBUG
--

function alert(message, channel, recipient)
	local prefix = getResourceInfo(g_Resource, "name") or g_ResName
	local text = string.format("[%s] %s", prefix, message)

	if channel == "console" then
		outputConsole(text)
		return
	end

	if channel == "chat" then
		recipient = recipient or root
		local messageColor = tostring(Settings["messageColor"].value or "")
		text = string.format("#A0FFA0[%s] %s%s", prefix, messageColor, message)
		outputChatBox(text, recipient, 255, 255, 255, true)
		return
	end

	outputDebugString(text)
end


--
-- PLAYERS
--

function getActivePlayers()
	local ret = {}
	for _,player in ipairs(getAlivePlayers()) do
		local state = getElementData(player, "state", false)
		if state == "alive" then
			ret[#ret + 1] = player
		end
	end
	return ret
end

function findPlayer(name)
	if not name then return end
	local player = getPlayerFromName(name)
	if not player then
		for _,p in ipairs(getElementsByType("player")) do
			if string.find(string.lower(getPlayerName(p)), string.lower(name)) then
				player = p
				break
			end
		end
	end
	return player
end
