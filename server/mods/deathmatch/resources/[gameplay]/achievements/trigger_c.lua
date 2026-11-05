local currentMap = "no map"

local showAchiText = false

-- Water turret vars
local sprayedPlayers = {}
local newSprayedPlayers = {}

-- Honk on every player
local honkSphere = {}
local honkedPlayers = {}
local newHonkedPlayers = {}

-- Paparazzi
local photographedPlayers = {}
local newPhotographedPlayers = {}

local startHonkingTime = 0 -- Honk for a whole race

-- Drive on every material
local materials = {}

-- Timers
local stufftimer

-- Backwards Compatible
local usedAccelerate = false

-- "In Control", "Easy to Drive?"
local spinoutMap = false

-- Function inserts value in the table if value doesn't exists in the table
function insertValueNonexistent(tableSource, value)
	local found = false
	for _, v in ipairs(tableSource) do
		if v == value then
			found = true
			break
		end
	end

	if not found then
		table.insert(tableSource, value)
	end
end

-- Function returns the table of values of table A that are doesn't exist in table B
function differenceTable(tableA, tableB)
	local outTable = {}
	for _, v in ipairs(tableA) do
		local found = false
		for __, j in ipairs(tableB) do
			if v == j then
				found = true
				break
			end
		end

		if not found then
			table.insert(outTable, v)
		end
	end

	return outTable
end

-- Function inserts values from table A into table B
function transferTable(tableA, tableB)
	for _, v in ipairs(tableA) do
		table.insert(tableB, v)
	end
end

-- Update stuff every 5 seconds
function updateStuff()
	-- Every material check
	if getPedOccupiedVehicle(localPlayer) and getVehicleOccupant(getPedOccupiedVehicle(localPlayer)) == localPlayer then
		local x, y, z = getElementPosition(getPedOccupiedVehicle(localPlayer))
		local hit, hitX, hitY, hitZ, hitElement, normalX, normalY, normalZ, material = processLineOfSight(x, y, z + 1, x, y, -20, true, false, false, false, false)
		if hit and material then
			local sendTable = differenceTable({material}, materials)
			if #sendTable > 0 then
				triggerServerEvent("updateCollectedMaterials", localPlayer, material)
			end
		end
	end
end

addEvent("onClientMapStarting", true)
addEventHandler("onClientMapStarting", root, function(mapInfo)

	currentMap = mapInfo.resname

	setElementData(localPlayer, "timesDied", 0)
	setElementData(localPlayer, "ach_oldcar", 0)
	setElementData(localPlayer, "ach_oldoldcar", 0)
	setElementData(localPlayer, "ach_keyPresses", 0)
	setElementData(localPlayer, "achs_attackedBy", false)
	setElementData(localPlayer, "achs_kills", 0) -- Kills on derbies or on Rustler Dog Fight (Hydra dog Fight)
	setElementData(localPlayer, "achs_honkingTime", 0) -- Honk for 1h and honk for whole race
	setElementData(localPlayer, "achs_spinout", false) -- Spinout check

	startHonkingTime = 0

	-- Update stuff
	if isTimer(stufftimer) then
		killTimer(stufftimer)
	end
	stufftimer = setTimer(updateStuff, 5000, 0)

	-- Backwards Compatible
	usedAccelerate = false
	local function accelerateUsed()
		if not usedAccelerate then
			usedAccelerate = true
--			iprint("[Achievements] Accelerate used - Backwards Compatible false")
			triggerServerEvent("usedAccelerate", localPlayer)
		end
	end
	bindKey("accelerate", "down", accelerateUsed)

	setTimer(function() -- already holding down accelerate before map loaded
		if getPedControlState("accelerate") then
			accelerateUsed()
		end
	end, 1000, 1)

	-- ============================================
	-- Client map achievement stuff creation things
	-- ============================================
	-- Parent everything created in here to this suicidal element
	destroyMePlease = createElement("destroyMePlease")

	setElementData(localPlayer, "ach_boolean", nil)

	-- Dash 'n' Dunk
	if currentMap == "DiscoDash" then
		local colAch = createColSphere(1625.5, -3668, 56, 18)
		setElementParent(colAch, destroyMePlease)

		addEventHandler("onClientColShapeHit", colAch, function(element)
			if element ~= localPlayer then
				return
			end
			triggerServerEvent("achievement", localPlayer, "discodach")
		end )
	end

	-- Hunter-gatherer
	if currentMap == "61Towers" then
		local colAch = createColSphere(701.09998, -2432, 23.4, 6)
		setElementParent(colAch, destroyMePlease)

		addEventHandler("onClientColShapeHit", colAch, function(element)
			if element ~= localPlayer then
				return
			end
			local vehicle = getPedOccupiedVehicle(localPlayer)
			local vehicleType = getVehicleType(vehicle)
			if vehicleType ~= "Plane" and vehicleType ~= "Helicopter" then
				setElementData(localPlayer, "ach_boolean", true)
				iprint("[Achievements] Hunter-gatherer true")
			end
		end )
	end

	-- Trial by Fire
	if currentMap == "LeapTowers" then
		local colAch = createColSphere(5758.93359, -1404.0686, 22.2995, 5)
		setElementParent(colAch, destroyMePlease)

		addEventHandler("onClientColShapeHit", colAch, function(element)
			if element ~= localPlayer then
				return
			end
			local vehicle = getPedOccupiedVehicle(localPlayer)
			local model = getElementModel(vehicle)
			if model == 411 then
				setTimer(function()
					if isElement(vehicle) and getElementModel(vehicle) == 520 then
						triggerServerEvent("achievement", localPlayer, "infernusjump")
					end
				end, 500, 3)
			end
		end )
	end
	if currentMap == "JumpTowers" then
		local colAch = createColSphere(6214.7002, -1386.09998, 121.3, 5)
		setElementParent(colAch, destroyMePlease)

		addEventHandler("onClientColShapeHit", colAch, function(element)
			if element ~= localPlayer then
				return
			end
			local vehicle = getPedOccupiedVehicle(localPlayer)
			local model = getElementModel(vehicle)
			if model == 411 then
				setTimer(function()
					if isElement(vehicle) and getElementModel(vehicle) == 520 then
						triggerServerEvent("achievement", localPlayer, "infernusjump")
					end
				end, 500, 3)
			end
		end )
	end
	if currentMap == "RandomizerDerby2" then
		local colAch = createColSphere(5679.7998, -969.09998, 39.5, 5)
		setElementParent(colAch, destroyMePlease)

		addEventHandler("onClientColShapeHit", colAch, function(element)
			if element ~= localPlayer then
				return
			end
			local vehicle = getPedOccupiedVehicle(localPlayer)
			local model = getElementModel(vehicle)
			if model == 411 then
				setTimer(function()
					if isElement(vehicle) and getElementModel(vehicle) == 425 then
						triggerServerEvent("achievement", localPlayer, "infernusjump")
					end
				end, 500, 3)
			end
		end )
	end
	if currentMap == "BobcatMadness" then
		local function onColAchHit(element)
			if element ~= localPlayer then
				return
			end
			local vehicle = getPedOccupiedVehicle(localPlayer)
			local model = getElementModel(vehicle)
			if model == 411 then
				setTimer(function()
					if isElement(vehicle) and getElementModel(vehicle) == 425 then
						triggerServerEvent("achievement", localPlayer, "infernusjump")
					end
				end, 500, 3)
			end
		end

		local colAch = createColSphere(1549.5, -4426.7998, 2.2, 5)
		setElementParent(colAch, destroyMePlease)
		addEventHandler("onClientColShapeHit", colAch, onColAchHit)
		local colAch = createColSphere(1549.5, -3900.8, 2.2, 5)
		setElementParent(colAch, destroyMePlease)
		addEventHandler("onClientColShapeHit", colAch, onColAchHit)
	end

	-- To Infinity and Beyond
	if currentMap == "SollerStreetRace" then
		local colAch = createColSphere(3761.7, -2510.5, 62.7, 3.5)
		setElementParent(colAch, destroyMePlease)

		addEventHandler("onClientColShapeHit", colAch, function(element)
			if element ~= localPlayer then
				return
			end
			triggerServerEvent("achievement", localPlayer, "sollernitro")
		end)
	end

	-- Spinout achievement ("In Control", "Easy to Drive?") maps
	if currentMap == "OutOfControl1" or currentMap == "OutOfControl2" or currentMap == "OutOfControl3" or currentMap == "DozerousTurns" then
		spinoutMap = true
	end
end )

-- Clean-up for client map achievement stuff creation things
addEventHandler("onClientMapStopping", root, function()
	if isElement(destroyMePlease) then
		destroyElement(destroyMePlease)
		destroyMePlease = nil
	end
end )

-- Detector of shooting vehicles damage
addEventHandler("onClientVehicleDamage", root, function(theAttacker, theWeapon)
	-- Guns that shoot bullets
	if theAttacker and getElementType(theAttacker) == "vehicle" and getVehicleOccupant(theAttacker, 0) == localPlayer then
		local shootingVehicles = {476, 447, 425, 430, 464}
		local found = false
		for i = 1, #shootingVehicles do
			if getElementModel(theAttacker) == shootingVehicles[i] then
				found = true
				break
			end
		end

		local occupant = getVehicleOccupant(source, 0)
		-- Ensure the occupant is a player, not a clientside ped (like a ghost)
		if occupant and found and getElementType(occupant) == "player" then
			triggerServerEvent("getAttacker", localPlayer, occupant)
		end

	-- Rockets (hydra, hunter and rhino)
	elseif theAttacker and getElementType(theAttacker) == "player" and theAttacker == localPlayer and getPedOccupiedVehicle(theAttacker) and (getElementModel(getPedOccupiedVehicle(theAttacker)) == 425 or getElementModel(getPedOccupiedVehicle(theAttacker)) == 520 or getElementModel(getPedOccupiedVehicle(theAttacker)) == 432) then
		local occupant = getVehicleOccupant(source, 0)
		-- Ensure the occupant is a player, not a clientside ped (like a ghost)
		if occupant and getElementType(occupant) == "player" then
			triggerServerEvent("getAttacker", localPlayer, occupant)
		end
	end
end )

addEventHandler("onClientVehicleCollision", root, function(hitElement)
	-- Derbies check
	if hitElement and getElementType(hitElement) == "vehicle" and getPedOccupiedVehicle(localPlayer) and source == getPedOccupiedVehicle(localPlayer) then
		-- If localPlayer collided with other vehicle
		setElementData(localPlayer, "achs_attackedBy", getVehicleOccupant(hitElement))
	end
end )

-- Minesweeper
addEventHandler("onClientObjectDamage", root, function(loss, attacker)
	if source and getElementModel(source) == 2918 and loss > 150 and getElementType(attacker) == "vehicle" and getPedOccupiedVehicle(localPlayer) and attacker == getPedOccupiedVehicle(localPlayer) then
		triggerServerEvent("achievement", localPlayer, "minesweeper")
	end
end )

-- Paparazzi
addEventHandler("onClientPlayerWeaponFire", root, function(weapon)
	if source == localPlayer and weapon and weapon == 43 then
		-- Add player
		for _, v in ipairs(getElementsByType("player")) do
			if isElementOnScreen(v) and v ~= localPlayer then
				insertValueNonexistent(newPhotographedPlayers, v)
			end
		end

		-- Send data
		local sendTable = differenceTable(newPhotographedPlayers, photographedPlayers)
		if #sendTable > 0 then
			triggerServerEvent("photographUpdatePlayers", localPlayer, sendTable)
			transferTable(newPhotographedPlayers, photographedPlayers)
			newPhotographedPlayers = {}
		end
	end
end )

addEventHandler("onClientKey", root, function(button, press)
	if not isChatBoxInputActive() then
		setElementData(localPlayer, "ach_keyPresses", (getElementData(localPlayer, "ach_keyPresses") or 0) + 1)
	end

	-- "Water Procedures"
	if getPedOccupiedVehicle(localPlayer) and (getElementModel(getPedOccupiedVehicle(localPlayer)) == 601 or getElementModel(getPedOccupiedVehicle(localPlayer)) == 407) and not isCursorShowing() then
		-- Player inside the vehicle with water turrent (firetruck and S.W.A.T, also Betsy counts but we don't use it)
		for key, state in pairs(getBoundKeys("vehicle_fire")) do
			if button == key and press and not waterTurretActive then
				-- Enable water scan function in onClientRender
				waterTurretActive = true
				break
			elseif button == key and not press and waterTurretActive then
				-- Disable water scan function in onClientRender
				waterTurretActive = false

				-- Send data to the server
				local sendTable = differenceTable(newSprayedPlayers, sprayedPlayers)
				if #sendTable > 0 then
					triggerServerEvent("waterCannonUpdatePlayers", localPlayer, sendTable)
					transferTable(newSprayedPlayers, sprayedPlayers)
					newSprayedPlayers = {}
				end
				break
			end
		end
	end

	-- "Howdy!" (honk on every player)
	if getPedOccupiedVehicle(localPlayer) and not isChatBoxInputActive() then
		for key, state in pairs(getBoundKeys("horn")) do
			if button == key and press then
				local v_type = getVehicleType(getPedOccupiedVehicle(localPlayer))
				if v_type ~= "Plane" and v_type ~= "Train" and v_type ~= "Helicopter" and v_type ~= "Boat" and v_type ~= "Trailer" then
					local x, y, z = getElementPosition(getPedOccupiedVehicle(localPlayer))
					honkSphere = createColSphere(x, y, z, getElementRadius(getPedOccupiedVehicle(localPlayer)) + 5)
					attachElements(honkSphere, getPedOccupiedVehicle(localPlayer))
				end
				break
			elseif button == key and not press and isElement(honkSphere) then
				destroyElement(honkSphere)
				-- Send data to the server
				local sendTable = differenceTable(newHonkedPlayers, honkedPlayers)
				if #sendTable > 0 then
					triggerServerEvent("honkUpdatePlayers", localPlayer, sendTable)
					transferTable(newHonkedPlayers, honkedPlayers)
					newHonkedPlayers = {}
				end
			end
		end
	end

	-- Honk
	if getPedOccupiedVehicle(localPlayer) and not isChatBoxInputActive() then
		local vehicleType = getVehicleType(getPedOccupiedVehicle(localPlayer))
		if vehicleType == "Automobile" or vehicleType == "Bike" or vehicleType == "Monster Truck" or vehicleType == "Quad" then
			if getPedControlState(localPlayer, "horn") and startHonkingTime == 0 and not isElementFrozen(getPedOccupiedVehicle(localPlayer)) then
				-- Player pressed horn
				startHonkingTime = getTickCount()
			elseif not getPedControlState(localPlayer, "horn") and startHonkingTime ~= 0 then
				-- Player released horn
				local honkTime = getElementData(localPlayer, "achs_honkingTime") or 0
				setElementData(localPlayer, "achs_honkingTime", honkTime + getTickCount() - startHonkingTime)
				startHonkingTime = 0
			end
		end
	end
end )

addEventHandler("onClientRender", root, function()
	if waterTurretActive then
		-- Get water nozzle location for the vehicle, and its rotation
		local startX, startY, startZ, rotX, rotY
		local rx, ry, rz = getElementRotation(getPedOccupiedVehicle(localPlayer))
		if getElementModel(getPedOccupiedVehicle(localPlayer)) == 601 then -- S.W.A.T.
			startX, startY, startZ = getVehicleComponentPosition(getPedOccupiedVehicle(localPlayer), "misc_c", "world")
		elseif getElementModel(getPedOccupiedVehicle(localPlayer)) == 407 then -- Firetruck
			startX, startY, startZ = getVehicleComponentPosition(getPedOccupiedVehicle(localPlayer), "misc_a", "world")
		else
			-- Exit - Player not in the vehicle so player can't spray
			waterTurretActive = false

			-- Send data to the server
			local sendTable = differenceTable(newSprayedPlayers, sprayedPlayers)
			if #sendTable > 0 then
				triggerServerEvent("waterCannonUpdatePlayers", localPlayer, sendTable)
				transferTable(newSprayedPlayers, sprayedPlayers)
				newSprayedPlayers = {}
			end
			return
		end

		rotX, rotY = getVehicleTurretPosition(getPedOccupiedVehicle(localPlayer))
		rotX = math.deg(rotX) + rz
		rotY = math.deg(rotY) + rx

		-- Calculate matrix, ooh so fancy math here
		local nozzleMatrix = Matrix(Vector3(startX, startY, startZ), Vector3(rotY, 0, rotX))
		local vectorForward = nozzleMatrix:getForward() * 25 -- is the lenght of scanline
		local hit, hitX, hitY, hitZ, hitElement = processLineOfSight(startX, startY, startZ, startX + vectorForward.x, startY + vectorForward.y, startZ + vectorForward.z, true, true, true, true, false)
		if hit and hitElement and getElementType(hitElement) == "vehicle" then
			if getPedOccupiedVehicle(localPlayer) ~= hitElement and getVehicleOccupant(hitElement) and getElementType(getVehicleOccupant(hitElement)) == "player" then
				insertValueNonexistent(newSprayedPlayers, getVehicleOccupant(hitElement))
			end
		end
	end

	if isElement(honkSphere) then
		if getPedOccupiedVehicle(localPlayer) then
			for _, v in ipairs(getElementsByType("player")) do
				if getPedOccupiedVehicle(v) and isElementWithinColShape(getPedOccupiedVehicle(v), honkSphere) and v ~= localPlayer and not isElementFrozen(getPedOccupiedVehicle(v)) then
					insertValueNonexistent(newHonkedPlayers, v)
				end
			end
		else
			-- Player stopped honking
			destroyElement(honkSphere)

			-- Send data to the server
			local sendTable = differenceTable(newHonkedPlayers, honkedPlayers)
			if #sendTable > 0 then
				triggerServerEvent("honkUpdatePlayers", localPlayer, sendTable)
				transferTable(newHonkedPlayers, honkedPlayers)
				newHonkedPlayers = {}
			end
		end
	end

	-- Spin out check
	if spinoutMap then
		if getPedOccupiedVehicle(localPlayer) then
			local x, y, z = getElementAngularVelocity(getPedOccupiedVehicle(localPlayer))
			if math.abs(z) > 0.045 then
				setElementData(localPlayer, "achs_spinout", true)
			end
		end
	end
end )
