replytable = {}

function pmHandler(player, cmd, target, ...)
	local message = table.concat({...}, " ")

	if not target or message == "" then
		outputChatBox("Syntax: /pm [player name] [message]", player, 255, 165, 0)
		return
	end

	local recipient = getPlayerFromName(target)
	if recipient then
		local recipientName = getPlayerName(recipient)
		local playerName = getPlayerName(player)
		replytable[recipient] = playerName

		outputChatBox("[PM to " .. removeColorCodes(recipientName) .. "]: #FFFFFF " .. message, player, 255, 255, 0, true)
		outputChatBox("[PM from " .. removeColorCodes(playerName) .. "]: #FFFFFF " .. message, recipient, 255, 255, 0, true)
	else
		outputChatBox("Sorry, there isn't a person called '" .. target .. "'. Please check your spelling and/or include the color codes in the name.", player, 255, 0, 0)
	end
end
addCommandHandler("pm", pmHandler, false, false)

function removeColorCodes(str)
	return (string.gsub(str, "#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]", ""))
end

function replytomessage(player, cmd, ...)
	local message = table.concat({...}, " ")

	if message == "" then
		outputChatBox("Syntax: /reply [message]", player, 255, 165, 0)
		return
	end

	if replytable[player] then
		local recipient = getPlayerFromName(replytable[player])
		if recipient then
			local recipientName = getPlayerName(recipient)
			local playerName = getPlayerName(player)
			replytable[recipient] = playerName

			outputChatBox("[PM to " .. removeColorCodes(recipientName) .. "]: #FFFFFF " .. message, player, 255, 255, 0, true)
			outputChatBox("[PM from " .. removeColorCodes(playerName) .. "]: #FFFFFF " .. message, recipient, 255, 255, 0, true)
		else
			outputChatBox("The player you want to message to is no longer online.", player, 255, 0, 0)
		end
	else
		outputChatBox("You have not received any messages.", player, 255, 0, 0)
	end
end
addCommandHandler("reply", replytomessage, false, false)
