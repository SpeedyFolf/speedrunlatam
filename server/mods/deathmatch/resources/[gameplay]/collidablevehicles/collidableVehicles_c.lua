addEventHandler("onClientRender", root, function()
	local playerVehicle = getPedOccupiedVehicle(localPlayer)
	if isElement(playerVehicle) then
		for _, veh in ipairs(getElementsByType("vehicle")) do
			if getElementData(veh, "race.collideothers") == 1 then
				local collide = getElementData(veh, "collisions") == "true"
				setElementCollidableWith(playerVehicle, veh, collide)
			end
		end
	else
		for _, veh in ipairs(getElementsByType("vehicle")) do
			if getElementData(veh, "race.collideothers") == 1 then
				local collide = getElementData(veh, "collisions") == "true"
				setElementCollidableWith(localPlayer, veh, collide)
			end
		end
	end
end )
