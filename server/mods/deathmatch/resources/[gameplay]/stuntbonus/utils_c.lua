local stunt_font = dxCreateFont("font.ttf", 30, true, "proof")

local WORLD_DOWN = {0, 0, -1}
local UPSIDE_DOWN_THRESHOLD = math.cos(math.rad(80))

function isVehicleUpsideDown(vehicle)
    local matrix = getElementMatrix(vehicle)
    local vehicleUp = {matrix_rotate (matrix, 0, 0, 1)}
    local dotP = math.dotP (vehicleUp, WORLD_DOWN)
    return (dotP >= UPSIDE_DOWN_THRESHOLD)
end

function matrix_rotate(matrix, x, y, z)
    local tx = x * matrix[1][1] + y * matrix[2][1] + z * matrix[3][1]
    local ty = x * matrix[1][2] + y * matrix[2][2] + z * matrix[3][2]
    local tz = x * matrix[1][3] + y * matrix[2][3] + z * matrix[3][3]
    return tx, ty, tz
end

function math.dotP(v1, v2)
    return v1[1]*v2[1] + v1[2]*v2[2] + v1[3]*v2[3]
end

function dxDrawBorderedText(outline, text, left, top, right, bottom, color, scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
    if type(scaleY) == "string" then
        scaleY, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY = scaleX, scaleY, font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX
    end

	-- Shadow
	dxDrawText(text, left, top, right * 1.0035, bottom * 1.0035, tocolor(0, 0, 0, 225), scaleX, scaleY, stunt_font, alignX, alignY, clip, wordBreak, postGUI, false, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)

	-- Actual Text
    dxDrawText(text, left, top, right, bottom, color, scaleX, scaleY, stunt_font, alignX, alignY, clip, wordBreak, postGUI, colorCoded, subPixelPositioning, fRotation, fRotationCenterX, fRotationCenterY)
end

function isVehicleWheelsOnGround(vehicle)
	if getVehicleType(vehicle) == "Automobile" and (isVehicleWheelOnGround(vehicle, "front_left") or isVehicleWheelOnGround(vehicle, "rear_left") or isVehicleWheelOnGround(vehicle, "front_right") or isVehicleWheelOnGround(vehicle, "rear_right")) then
		return true
	elseif (getVehicleType(vehicle) == "Bike" or getVehicleType(vehicle) == "BMX") and (isVehicleWheelOnGround(vehicle, "front_left") or isVehicleWheelOnGround(vehicle, "rear_left")) then
		return true
	else return false end
end
