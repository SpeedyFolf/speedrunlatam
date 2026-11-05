addEvent("overrideLights", true)
addEventHandler("overrideLights", root, function(vehicle, state)
	if isElement(vehicle) then
		setVehicleOverrideLights(vehicle, state)
	end
end )
