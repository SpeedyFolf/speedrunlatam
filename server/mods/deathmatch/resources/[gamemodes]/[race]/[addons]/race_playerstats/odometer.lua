
local vehicle = nil

g_Odometer = {
	Enabled = false,
	MovementThreshold = 0.05,
	Distance = {
		0, -- foot
		0, -- car
		0, -- bike
		0, -- boat
		0, --aircraft
		0, -- bycicle
		0 -- swimming
	},
	Position = { 0, 0, 0 }
}

Stat = { 3, 4, 5, 6, 8, 27, 26 }

g_NextStatUpdate = 0
g_SyncPeriod = 10000


addEventHandler("onClientPlayerVehicleEnter", localPlayer,
	function(veh, seat)
		if seat == 0 then
			vehicle = veh
		end
	end
)

addEventHandler("onClientPlayerVehicleExit", localPlayer,
	function(veh, seat)
		vehicle = nil
	end
)

addEventHandler("onClientMapStarting", root,
	function()
		vehicle = getPedOccupiedVehicle(localPlayer)
		if not vehicle then
			vehicle = localPlayer
		end

		local x, y, z = getElementPosition(vehicle)
		g_Odometer.Position = { x, y, z }
		g_Odometer.Enabled = true

		g_NextStatUpdate = getTickCount() + g_SyncPeriod
	end
)

addEventHandler("onClientMapStopping", root,
	function()
		vehicle = nil
		g_Odometer.Enabled = false
	end
)


function getDistanceTableIndexOfVehicle(target)
	if getElementType(target) == "vehicle" then
		local modelId = getElementModel(target)
		if ModelID.MotorBikes[modelId] then return 3 end
		if ModelID.Boats[modelId] then return 4 end
		if ModelID.Aircraft[modelId] then return 5 end
		if ModelID.Bikes[modelId] then return 6 end
		if ModelID.Exempt[modelId] then return 0 end
		return 2
	end
	if isElementInWater(target) then
		return 7
	end
	-- on foot
	return 1
end


function SyncStats()
	local playerStats = {}

	local nonZero = false
	local i
	for i = 1,5 do
		if g_Odometer.Distance[i] > g_Odometer.MovementThreshold then nonZero = true end
		playerStats[Stat[i]] = math.floor(g_Odometer.Distance[i]) -- / 1000
		g_Odometer.Distance[i] = 0
	end

	if nonZero then
		triggerServerEvent("onBulkUpdateStats", localPlayer, playerStats)
	end

	g_NextStatUpdate = getTickCount() + g_SyncPeriod
end


function RecordDistance()
	if not g_Odometer.Enabled then return end
	if not vehicle then
		vehicle = localPlayer
	end

	local x, y, z = getElementPosition(vehicle)
	local delta = getDistanceBetweenPoints3D(x, y, z, g_Odometer.Position[1], g_Odometer.Position[2], g_Odometer.Position[3])
	if delta > 30000 then
		-- Warning: delta is too damn high!
		for i = 1,5 do
			g_Odometer.Distance[i] = 0
		end
		return
	end
	g_Odometer.Position = { x, y, z }

	local index = getDistanceTableIndexOfVehicle(vehicle)
	if index ~= 0 then
		g_Odometer.Distance[index] = g_Odometer.Distance[index] + delta
	end

	if getTickCount() > g_NextStatUpdate then
		SyncStats()
	end
end


local function startRecording(softFade)
	if softFade then return end
	g_NextStatUpdate = getTickCount() + g_SyncPeriod
	addEventHandler("onClientRender", root, RecordDistance)
end
addEvent("onClientScreenFadedIn", true)
addEventHandler("onClientScreenFadedIn", root, startRecording)

local function stopRecording (softFade)
	if softFade then return end
	removeEventHandler("onClientRender", root, RecordDistance)
end
addEvent("onClientScreenFadedOut", true)
addEventHandler("onClientScreenFadedOut", root, stopRecording)


-- Legacy events

addEvent("onClientStatsDisplay", true)
addEvent("onClientUpdateStats", true)
addEvent("onClientListPlayers", true)

-- Legacy Exports
function AddStatColumn(statKey, description, category, formatFunction)
	outputDebugString("The function AddStatColumn is deprecated. Use the onClientAddStatColumn event instead.")
end

