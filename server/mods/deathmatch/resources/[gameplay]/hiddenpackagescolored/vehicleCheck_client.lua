local helicopters = {
	-- [464] = true,
	[501] = true, [465] = true,
	-- [592] = true, [577] = true, [511] = true, [512] = true, [593] = true, [520] = true, [553] = true, [476] = true, [519] = true, [460] = true, [513] = true,
	[548] = true, [425] = true, [417] = true, [487] = true, [488] = true, [497] = true, [563] = true, [447] = true, [469] = true,
}

local aircraft = {
	[464] = true,
	[501] = true, [465] = true,
	[592] = true, [577] = true, [511] = true, [512] = true, [593] = true, [520] = true, [553] = true, [476] = true, [519] = true, [460] = true, [513] = true,
	[548] = true, [425] = true, [417] = true, [487] = true, [488] = true, [497] = true, [563] = true, [447] = true, [469] = true,
}

local bicycles = {
	[509] = true, [481] = true, [510] = true,
}

function validateVehicle(packType, msg)
	local veh = getPedOccupiedVehicle(localPlayer)
	if (packType == 1) then
		-- white
		return requireVehicle(veh, msg)
	elseif (packType == 2) then
		-- green
		return true
	elseif (packType == 3) then
		-- blue
		return requireVehicle(veh, msg) and noHelicopters(veh, msg)
	elseif (packType == 4) then
		-- orange
		return requireVehicle(veh, msg)
	elseif (packType == 5) then
		-- yellow
		return requireVehicle(veh,msg) and noHelicopters(veh, msg)
	elseif (packType == 6) then
		-- red
		return requireVehicle(veh,msg) and noAircraft(veh, msg) and noBicycles(veh, msg)
	elseif (packType == 7) then
		-- black
		return true
	end
	return false
end

function requireVehicle(veh, msg)
	if (not veh) then
		if (msg) then
			outputChatBox("You plan on carrying that? Find something to transport this with!", 149, 133, 206)
		end
		return false
	end
	return true
end

function noBicycles(veh, msg)
	if (bicycles[getElementModel(veh)]) then
		if (msg) then
			outputChatBox("This package is rated AO. Come back when you're old enough to ride something other than toys!", 149, 133, 206)
		end
		return false
	end
	return true
end

function noAircraft(veh, msg)
	if (aircraft[getElementModel(veh)]) then
		if (msg) then
			outputChatBox("The contents of this package are too heavy to transport by air.", 149, 133, 206)
		end
		return false
	end
	return true
end

function noHelicopters(veh, msg)
	if (helicopters[getElementModel(veh)]) then
		if (msg) then
			outputChatBox("These goods are too hot to handle in a helicopter. The Kernel Union for Rotary Wing Aviation is never going to let that fly!", 149, 133, 206)
		end
		return false
	end
	return true
end
