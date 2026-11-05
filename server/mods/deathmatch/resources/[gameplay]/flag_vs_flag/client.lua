local shaders = {}
local textures = {}

addEventHandler("onClientResourceStart", resourceRoot, function()
	-- Load the flag images into memory
	textures["sk"] = dxCreateTexture("slovakia.png")
	textures["si"] = dxCreateTexture("slovenia.png")

	-- Apply shaders to vehicles that already exist
	for _, vehicle in ipairs(getElementsByType("vehicle")) do
		applyFlagShader(vehicle)
	end
end)

function applyFlagShader(vehicle)
	if getElementType(vehicle) ~= "vehicle" then return end

	local flagType = getElementData(vehicle, "flag_type")
	if not flagType or not textures[flagType] then return end

	-- Remove existing shader to prevent memory leaks if a flag changes
	if shaders[vehicle] then
		engineRemoveShaderFromWorldTexture(shaders[vehicle], "*", vehicle)
		destroyElement(shaders[vehicle])
		shaders[vehicle] = nil
	end

	-- Create new shader and apply it to the vehicle's paintjob/body textures
	local shader = dxCreateShader("shader.fx", 1, 0, true, "vehicle")
	if shader then
		dxSetShaderValue(shader, "Tex0", textures[flagType])

		-- Target the most common GTA SA vehicle body textures
		engineApplyShaderToWorldTexture(shader, "vehiclegrunge256", vehicle)
		engineApplyShaderToWorldTexture(shader, "?emap*", vehicle)

		shaders[vehicle] = shader
	end
end

-- Listen for the server assigning or changing a flag
addEventHandler("onClientElementDataChange", root, function(dataName, oldValue)
	if getElementType(source) == "vehicle" and dataName == "flag_type" then
		applyFlagShader(source)
	end
end)

-- Apply shader when a vehicle streams into the player's view
addEventHandler("onClientElementStreamIn", root, function()
	if getElementType(source) == "vehicle" then
		applyFlagShader(source)
	end
end)

-- Clean up memory when a vehicle is destroyed
addEventHandler("onClientElementDestroy", root, function()
	if getElementType(source) == "vehicle" and shaders[source] then
		destroyElement(shaders[source])
		shaders[source] = nil
	end
end)
