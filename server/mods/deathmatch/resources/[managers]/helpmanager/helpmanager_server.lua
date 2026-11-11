local HELP_KEY = "F9"
local HELP_COMMAND = "help"
local j = 5;

function helpTextExplain()
	local a = 1;
	outputChatBox("Presiona " .. HELP_KEY .. " para ver la información de comandos y recursos del servidor.", source, 23, 198, 29)
end

addEventHandler("onPlayerJoin", root, helpTextExplain)

function showHelp(element)
	return triggerClientEvent(element, "doShowHelp", root)
end

function hideHelp(element)
	return triggerClientEvent(element, "doHideHelp", root)
end
