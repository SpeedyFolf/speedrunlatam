local hlodsDistance = 500 -- default 500
local hlodsEnabled = true

function changeDistance()
	for i, object in pairs(getElementsByType("object")) do
		if isElement(object) then
			local elementID = getElementModel(object)
			engineSetModelLODDistance(elementID, hlodsDistance)
		end
	end
end
addEvent("onClientMapStarting", true)
addEventHandler("onClientMapStarting", root, function()
	if hlodsEnabled then setTimer(changeDistance, 1000, 1) end
end)

addCommandHandler("hlods", function(cmd, arg)

	local distance = tonumber(arg)

	if distance then
		hlodsDistance = math.max(100, math.min(500, distance)) -- clamp

		if not hlodsEnabled then
			hlodsEnabled = true
			outputChatBox("[hlods] Enabled. High level of detail distance set to " .. hlodsDistance)
		else
			outputChatBox("[hlods] High level of detail distance set to " .. hlodsDistance)
		end
		changeDistance()
		return
	end

	hlodsEnabled = not hlodsEnabled

	if hlodsEnabled then
		outputChatBox("[hlods] Enabled. Usage: /hlods 100-500")
		changeDistance()
	else
		outputChatBox("[hlods] Disabled - will take effect next map")
	end
end)
