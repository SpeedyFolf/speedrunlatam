addEventHandler("onResourceStart", resourceRoot, function()
	for _, veh in ipairs(getElementsByType("vehicle")) do
		setVehicleDamageProof(veh, true)
		local collide = getElementData(veh, "collisions") == "true"
		setElementData(veh, "race.collideothers", 1, collide)
	end
end )
