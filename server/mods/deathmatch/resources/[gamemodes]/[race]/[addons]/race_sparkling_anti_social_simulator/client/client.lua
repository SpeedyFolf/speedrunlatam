local ACTIVE_PLAYER = nil
local DISTANCE_THRESHOLD = 100

local GHOST_MODE = {
	ENABLED = false,
	ALPHA = 255,
}

local ELEMENT_ALPHAS = {}
local ALPHA_DONE = false

function sendGhostModeData(ghostMode)
	GHOST_MODE = ghostMode
	ELEMENT_ALPHAS = {}
	ALPHA_DONE = false
end
addEvent("sendGhostModeData", true)
addEventHandler("sendGhostModeData", root, sendGhostModeData)

function onClientElementStreamIn()
	if ELEMENT_ALPHAS[source] ~= nil then
		local ignore = getElementData(source, "sass.ignore") == "true"
		if not ignore then
			setElementAlpha(source, ELEMENT_ALPHAS[source])
		end

		ELEMENT_ALPHAS[source] = nil
	end
end
addEventHandler("onClientElementStreamIn", root, onClientElementStreamIn)

function setElementVisible(element, hideType, alpha, setElements)
	if not isElement(element) then
		return
	end

	setElements = setElements or {}

	if setElements[element] then
		return
	end

	if GHOST_MODE.ENABLED then
		alpha = Settings.isAltGhostModeEnabled() and 255 or alpha
	end

	if not GHOST_MODE.ENABLED then
		-- Not ghost mode, override alpha
		hideType = HIDE_TYPES.DISABLED
		alpha = 255
	elseif hideType == HIDE_TYPES.FADE_HIDE and alpha <= 50 then
		-- If the alpha is too low (player is too close), hide them in FADE_HIDE mode
		hideType = HIDE_TYPES.HIDE
	end

	-- Set element alpha in table so we can set their alpha for streaming in again
	if hideType == HIDE_TYPES.HIDE then
		ELEMENT_ALPHAS[element] = alpha
	end

	setElements[element] = true

	local ignore = getElementData(element, "sass.ignore") == "true"
	if ignore then
		return
	end

	local dimension = getElementDimension(ACTIVE_PLAYER)
	dimension = hideType == HIDE_TYPES.HIDE and (dimension + 1) or dimension

	if getElementType(element) == "player" then
		local vehicle = getPedOccupiedVehicle(element)
		if vehicle then
			setElementDimension(vehicle, dimension)
			setElementAlpha(vehicle, alpha)

			-- RC vehicle exception removed here; all peds in vehicles are treated the same
			setElementDimension(element, dimension)
			setElementAlpha(element, alpha)

			local occupants = getVehicleOccupants(vehicle)
			if occupants then
				for _, ped in pairs(occupants) do
					setElementVisible(ped, hideType, alpha, setElements)
				end
			end
		else
			setElementDimension(element, dimension)
			setElementAlpha(element, alpha)
		end
	else
		setElementDimension(element, dimension)
		setElementAlpha(element, alpha)
	end

	local children = getElementChildren(element)
	if #children then
		for _, child in ipairs(children) do
			setElementVisible(child, hideType, alpha, setElements)
		end
	end

	local attachedElements = getAttachedElements(element)
	if #attachedElements then
		for _, attachedElement in ipairs(attachedElements) do
			setElementVisible(attachedElement, hideType, alpha, setElements)
		end
	end
end

function hideElementsByType(elementType)
	if not ACTIVE_PLAYER or not isElement(ACTIVE_PLAYER) then return end
	local playerVehicle = getPedOccupiedVehicle(ACTIVE_PLAYER)

	local hideType = Settings.getHideType()
	if not Settings.isEnabledWhenSpectating() and getElementData(localPlayer, "race.spectating") then
		hideType = HIDE_TYPES.DISABLED
	end

	if (not ALPHA_DONE and not GHOST_MODE.ENABLED) or GHOST_MODE.ENABLED then
		for _, element in pairs(getElementsByType(elementType)) do
			if element ~= ACTIVE_PLAYER and element ~= playerVehicle and element ~= localPlayer then
				local posX, posY, posZ = getElementPosition(ACTIVE_PLAYER)
				local otherPosX, otherPosY, otherPosZ = getElementPosition(element)

				local distance = getDistanceBetweenPoints3D(posX, posY, posZ, otherPosX, otherPosY, otherPosZ)
				if distance then
					local alpha = math.min(math.max(0, ((distance + 2) / DISTANCE_THRESHOLD) * 255), 255)
					if hideType == HIDE_TYPES.DISABLED then
						alpha = GHOST_MODE.ALPHA
					elseif hideType == HIDE_TYPES.FADE then
						alpha = math.max(15, alpha)
					end

					setElementVisible(element, hideType, alpha)
				end
			end
		end

		if not ALPHA_DONE and not GHOST_MODE.ENABLED then ALPHA_DONE = true end
	end
end

-- TODO: Implement `isEnabledWhenSpectating` check and treat it as DISABLED when it's false
function hideOrShowPlayers()
	local cameraTarget = getCameraTarget() -- Usually the player vehicle
	if isElement(cameraTarget) and getElementType(cameraTarget) == "vehicle" then
		ACTIVE_PLAYER = getVehicleOccupant(cameraTarget, 0)
	end

	if not ACTIVE_PLAYER or not isElement(ACTIVE_PLAYER) then
		ACTIVE_PLAYER = localPlayer

		if not ACTIVE_PLAYER or not isElement(ACTIVE_PLAYER) then
			return
		end
	end

	local alpha = Settings.isAltGhostModeEnabled() and 255 or GHOST_MODE.ALPHA

	if ACTIVE_PLAYER == localPlayer then
		setElementVisible(ACTIVE_PLAYER, HIDE_TYPES.DISABLED, alpha)
	end

	if isElement(ACTIVE_PLAYER) and ACTIVE_PLAYER ~= localPlayer then
		local dimension = getElementDimension(localPlayer)

		setElementDimension(ACTIVE_PLAYER, dimension)
		setElementVisible(ACTIVE_PLAYER, HIDE_TYPES.DISABLED, alpha)
	end

	hideElementsByType("player")
end
setTimer(hideOrShowPlayers, 100, 0)
