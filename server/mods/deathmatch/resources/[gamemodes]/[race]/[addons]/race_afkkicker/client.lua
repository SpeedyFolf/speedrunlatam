local SHOW_AFK_WARNING = false

local lastCameraTargetState
local lastCameraStateSentAt = 0
local lastActivitySentAt = 0

local function reportActivity()
	local now = getTickCount()
	if now - lastActivitySentAt < 500 then
		return
	end

	triggerServerEvent("race_afkkicker:activity", localPlayer)
	lastActivitySentAt = now
end

addEventHandler("onClientKey", root, function(_, pressed)
	if pressed then
		reportActivity()
	end
end)

addEventHandler("onClientClick", root, function(_, buttonState)
	if buttonState == "down" then
		reportActivity()
	end
end)

local ACTIVITY_CONTROLS = {
	"forwards",
	"backwards",
	"left",
	"right",
	"jump",
	"sprint",
	"fire",
	"aim_weapon",
	"next_weapon",
	"previous_weapon",
	"enter_exit",
	"vehicle_fire",
	"vehicle_secondary_fire",
	"vehicle_left",
	"vehicle_right",
	"steer_forward",
	"steer_back",
	"accelerate",
	"brake_reverse",
	"handbrake",
	"horn",
	"vehicle_look_left",
	"vehicle_look_right",
	"look_behind",
	"crouch",
	"walk",
}

setTimer(function()
	for _, control in ipairs(ACTIVITY_CONTROLS) do
		if getPedControlState(localPlayer, control) then
			reportActivity()
			return
		end
	end
end, 250, 0)
reportActivity()

local function reportCameraTargetState()
	local cameraTarget = getCameraTarget()
	local vehicle = getPedOccupiedVehicle(localPlayer)
	local targetsOtherPlayer = isElement(cameraTarget)
		and cameraTarget ~= localPlayer
		and (not isElement(vehicle) or cameraTarget ~= vehicle)
	local now = getTickCount()

	if targetsOtherPlayer ~= lastCameraTargetState or now - lastCameraStateSentAt >= 2000 then
		triggerServerEvent("race_afkkicker:updateCameraTarget", localPlayer, targetsOtherPlayer)
		lastCameraTargetState = targetsOtherPlayer
		lastCameraStateSentAt = now
	end
end
setTimer(reportCameraTargetState, 1000, 0)
reportCameraTargetState()

function goAFK()
	executeCommandHandler("spectate")
end
addEvent("goAFK", true)
addEventHandler("goAFK", root, goAFK)

function warnAFK(showWarning)
	if showWarning ~= true then
		SHOW_AFK_WARNING = false
		return
	end

	SHOW_AFK_WARNING = true
	setTimer(function()
		SHOW_AFK_WARNING = false
	end, 500, 1)
end
addEvent("warnAFK", true)
addEventHandler("warnAFK", root, warnAFK)

function onPreRender()
	local screenWidth, screenHeight = guiGetScreenSize()

	if SHOW_AFK_WARNING then
		dxDrawBorderedText(
			1,
			"AFK!",
			(screenWidth / 2),
			(screenHeight / 2),
			(screenWidth / 2),
			(screenHeight / 2),
			tocolor(255, 255, 255, 255),
			10,
			"pricedown",
			"center",
			"center"
		)
	end
end
addEventHandler("onClientPreRender", root, onPreRender)
