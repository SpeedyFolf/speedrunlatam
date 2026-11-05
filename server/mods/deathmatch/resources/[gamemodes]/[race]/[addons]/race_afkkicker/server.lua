local RACE_STATE = ""
local DEFAULT_AFK_TIMER = tonumber(get("afk_timer")) or 30
local currentAfkTimer = DEFAULT_AFK_TIMER
local overrideStack = {} -- mapResName -> seconds
local warningPlayers = {}
local idleTrackers = {}
local cameraTargetStates = {}
local activityTicks = {}
local lastActivityEvents = {}

-- Whitelist: map resource name -> AFK seconds
local MAP_AFK_OVERRIDES = {
	["GTAmonGroveGreen"] = 300, -- 5 minutes
	-- ["another_story_map"] = 600, -- 10 minutes
}

local function recomputeAfkTimer()
	local maxOverride = nil
	for _, seconds in pairs(overrideStack) do
		seconds = tonumber(seconds)
		if seconds and (not maxOverride or seconds > maxOverride) then
			maxOverride = seconds
		end
	end
	currentAfkTimer = maxOverride or DEFAULT_AFK_TIMER
	outputDebugString(("[AFK] Timer now %ds (default %ds)"):format(currentAfkTimer, DEFAULT_AFK_TIMER), 3)
end

local function setAfkWarning(player, shouldWarn)
	local wasWarning = warningPlayers[player] == true
	if not shouldWarn and not wasWarning then
		return
	end

	warningPlayers[player] = shouldWarn and true or nil
	triggerClientEvent(player, "warnAFK", player, shouldWarn)
end

local function suspendAfkChecks()
	for player in pairs(warningPlayers) do
		setAfkWarning(player, false)
	end
	for _, tracker in pairs(idleTrackers) do
		tracker.eligible = false
	end
end

function afkCheck()
	local raceIsActive =
		(RACE_STATE == "Running" or RACE_STATE == "MidMapVote" or RACE_STATE == "SomeoneWon")
	local raceTimePassed = raceIsActive and exports["race"]:getTimePassed()
	if not raceTimePassed or raceTimePassed <= 2000 then
		suspendAfkChecks()
		return
	end

	local AFK_TRIGGER_TIME = currentAfkTimer
	local now = getTickCount()
	for _, player in ipairs(getElementsByType("player")) do
		local idleTime = getPlayerIdleTime(player) / 1000
		local veh = getPedOccupiedVehicle(player)
		local cameraState = cameraTargetStates[player]
		local cameraStateIsCurrent = cameraState and now - cameraState.updatedAt <= 5000
		local cameraTargetsOtherPlayer = cameraStateIsCurrent and cameraState.targetsOtherPlayer
		local isDead = isPedDead(player)
		local isSpectating = getElementData(player, "race.spectating")
		local isNotReady = getElementData(player, "state") == "not ready"
		local isVehicleFrozen = isElement(veh) and isElementFrozen(veh)
		local isPlayerFrozen = isElementFrozen(player)
		local isEligible =
			not isDead
			and not isSpectating
			and not isNotReady
			and not cameraTargetsOtherPlayer
			-- and isPedInVehicle(player) EDIT: We have on-foot maps now, so afk-kicking should also happen when the player is on foot.
			and not isVehicleFrozen
			and not isPlayerFrozen

		local tracker = idleTrackers[player]
		if not isEligible then
			setAfkWarning(player, false)
			if not tracker then
				tracker = { baseline = idleTime, eligibleSince = now }
				idleTrackers[player] = tracker
			end
			tracker.eligible = false
			tracker.lastIdleTime = idleTime
		else
			if not tracker then
				tracker = { baseline = idleTime, eligibleSince = now }
				idleTrackers[player] = tracker
			elseif not tracker.eligible then
				-- Do not count time spent frozen, loading, or in a cutscene toward AFK.
				tracker.baseline = idleTime
				tracker.eligibleSince = now
			elseif idleTime < tracker.lastIdleTime then
				tracker.baseline = 0
			end
			tracker.eligible = true
			tracker.lastIdleTime = idleTime

			local activityTime = math.max(activityTicks[player] or tracker.eligibleSince, tracker.eligibleSince)
			local timeSinceActivity = math.max(now - activityTime, 0) / 1000
			local gameIdleTime = math.max(idleTime - tracker.baseline, 0)
			local eligibleIdleTime = math.max(timeSinceActivity, gameIdleTime)
			setAfkWarning(player, eligibleIdleTime >= AFK_TRIGGER_TIME - 5)

			if eligibleIdleTime >= AFK_TRIGGER_TIME then
				triggerClientEvent(player, "goAFK", player)
			end

			if eligibleIdleTime >= AFK_TRIGGER_TIME + 5 then
				triggerEvent("onRequestKillPlayer", player)
			end
		end
	end
end
setTimer(afkCheck, 1000, 0)

addEvent("race_afkkicker:updateCameraTarget", true)
addEventHandler("race_afkkicker:updateCameraTarget", root, function(targetsOtherPlayer)
	if not client or source ~= client or type(targetsOtherPlayer) ~= "boolean" then
		return
	end

	cameraTargetStates[client] = {
		targetsOtherPlayer = targetsOtherPlayer,
		updatedAt = getTickCount(),
	}
end)

addEvent("race_afkkicker:activity", true)
addEventHandler("race_afkkicker:activity", root, function()
	if not client or source ~= client then
		return
	end

	local now = getTickCount()
	if now - (lastActivityEvents[client] or 0) < 250 then
		return
	end

	activityTicks[client] = now
	lastActivityEvents[client] = now
end)

addEventHandler("onPlayerQuit", root, function()
	warningPlayers[source] = nil
	idleTrackers[source] = nil
	cameraTargetStates[source] = nil
	activityTicks[source] = nil
	lastActivityEvents[source] = nil
end)

function onRaceStateChanging(newStateName)
	RACE_STATE = newStateName
end
addEvent("onRaceStateChanging", true)
addEventHandler("onRaceStateChanging", root, onRaceStateChanging)

local function isMapResource(res)
	if not res then
		return false
	end
	local t = getResourceInfo(res, "type")
	return (t == "map")
end

addEventHandler("onResourceStart", root, function(res)
	if not isMapResource(res) then
		return
	end
	local name = getResourceName(res)
	local override = MAP_AFK_OVERRIDES[name]
	if override then
		overrideStack[name] = override
		recomputeAfkTimer()
	end
end)

addEventHandler("onResourceStop", root, function(res)
	if not isMapResource(res) then
		return
	end
	local name = getResourceName(res)
	if overrideStack[name] then
		overrideStack[name] = nil
		recomputeAfkTimer()
	end
end)

addEventHandler("onResourceStart", resourceRoot, function()
	-- catch maps that are already running when AFK resource starts
	DEFAULT_AFK_TIMER = tonumber(get("afk_timer")) or DEFAULT_AFK_TIMER
	for _, res in ipairs(getResources()) do
		if isMapResource(res) then
			local name = getResourceName(res)
			local override = MAP_AFK_OVERRIDES[name]
			if override and getResourceState(res) == "running" then
				overrideStack[name] = override
			end
		end
	end
	recomputeAfkTimer()
end)

addEvent("onSettingChange")
addEventHandler("onSettingChange", resourceRoot, function()
	DEFAULT_AFK_TIMER = tonumber(get("afk_timer")) or DEFAULT_AFK_TIMER
	recomputeAfkTimer()
end)
