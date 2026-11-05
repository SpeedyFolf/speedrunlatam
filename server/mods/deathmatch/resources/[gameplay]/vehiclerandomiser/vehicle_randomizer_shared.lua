-- Default list is loaded if there is no setting as "randomvehicles" in the map settings
local defaultList = {
	-- Automobiles
	400, 401, 402, 403, 404, 405, 407, 408, 409, 410,
	411, 412, 413, 414, 415, 416, 418, 419, 420, 421,
	422, 423, 424, 426, 427, 428, 429, 431, 432, 433,
	434, 436, 437, 438, 439, 440, 442, 443, 445,
	451, 455, 456, 457, 458, 459, 466, 467, 470, 474,
	475, 477, 478, 479, 480, 482, 483, 485, 486, 489,
	490, 491, 492, 494, 495, 496, 498, 499, 500, 502,
	503, 504, 505, 506, 507, 508, 514, 515, 516, 517,
	518, 524, 525, 526, 527, 528, 529, 530, 531, 532,
	533, 534, 535, 536, 540, 541, 542, 543, 544, 545,
	546, 547, 549, 550, 551, 552, 554, 555, 558, 559,
	560, 561, 562, 565, 566, 567, 568, 571, 572,
	574, 575, 576, 578, 579, 580, 582, 583, 585, 587,
	588, 589, 596, 597, 598, 599, 600, 601, 602,
	603, 604, 605, 609,

	-- RC
	--441, 594, 564, 464, 501, 465

	-- Bikes
	448, 461, 462, 463, 468, 521, 522, 523, 581, 586,

	-- Push bikes
	481, 509, 510,

	-- Monster Trucks
	406, 444, 556, 557, 573,

	-- Quad
	471,

	-- Planes
	--460, 476, 511, 512, 513, 519, 520, 539, 553, 577, 592, 593,

	-- Helicopters
	--417, 425, 447, 469, 487, 488, 497, 548, 563,

	-- Boats
	--430, 446, 452, 453, 454, 472, 473, 484, 493, 595,

	-- Trains
	--449, 537, 538, 569, 570, 590,

	-- Trailers
	--435, 450, 584, 591, 606, 607, 608, 610, 611
}

-- List of vehicles loaded from map settings
local availableVehicles = {}

local oldZ
local function modifyPosition(correctOffset)
	if getElementType(source) == "vehicle" and source == getPedOccupiedVehicle(localPlayer) then
		local newZ = getElementDistanceFromCentreOfMassToBaseOfModel(getPedOccupiedVehicle(localPlayer))
		if oldZ == nil then oldZ = newZ end
		if getVehicleType(getPedOccupiedVehicle(localPlayer)) == "Monster Truck" then newZ = newZ + (getElementModel(getPedOccupiedVehicle(localPlayer)) == 573 and 0.5 or 1) end

		if correctOffset then
			local x, y, z = getElementPosition(getPedOccupiedVehicle(localPlayer))
			setElementPosition(getPedOccupiedVehicle(localPlayer), x, y, z + (newZ - oldZ))
		end

		--iprint(correctOffset and ("old: " ..oldZ.. "; new: " ..newZ) or ("new: " ..newZ)) -- debug
		oldZ = newZ
	end
end

function changeModel(player)
	if getPedOccupiedVehicle(player) then
		setElementModel(getPedOccupiedVehicle(player), availableVehicles[math.random(#availableVehicles)])
	end
end

-- Client events
addEventHandler("onClientElementModelChange", root, function() modifyPosition(true) end )
addEventHandler("onClientVehicleEnter", root, function() modifyPosition(false) end )

-- Server event
addEvent("onPlayerReachCheckpoint")
addEventHandler("onPlayerReachCheckpoint", root, function()
	changeModel(source)
end )

addEvent("onRaceStateChanging")
addEventHandler("onRaceStateChanging", root, function(newState, oldState)
	if oldState == "LoadingMap" and newState == "PreGridCountdown" then
		local currentMapRunning = getResourceName(call(getResourceFromName("mapmanager"), "getRunningGamemodeMap"))
		local randomvehicles = get(currentMapRunning..'.randomvehicles')
		if randomvehicles then
			randomvehicles:gsub("%s", "") -- removes spaces
			for _, model in ipairs(split(randomvehicles, ",")) do
				table.insert(availableVehicles, model)
			end
		else availableVehicles = defaultList end
	end
end )
