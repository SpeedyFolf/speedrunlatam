-- Function to assign a random flag to a vehicle
function assignRandomFlag(vehicle)
	if getElementType(vehicle) == "vehicle" and not getElementData(vehicle, "flag_type") then
		local flags = {"sk", "si"}
		local randomFlag = flags[math.random(1, #flags)]
		setElementData(vehicle, "flag_type", randomFlag)
	end
end

-- Assign flags to all vehicles when the script starts
addEventHandler("onResourceStart", resourceRoot, function()
	for _, vehicle in ipairs(getElementsByType("vehicle")) do
		assignRandomFlag(vehicle)
	end
end)

-- Assign flags to new vehicles when someone gets in
addEventHandler("onVehicleEnter", root, function(thePlayer, seat, jacked)
	assignRandomFlag(source)
end)
