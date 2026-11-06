g_ArmedVehicleIDs = table.create({
	425, -- hunter
	447, -- seaspar
	520, -- hydra
	430, -- predator
	464, -- rcbaron
	432, -- rhino
	476 -- rustler (formerly missing)
}, true)
g_WaterCraftIDs = table.create({ 539, 460, 417, 447, 472, 473, 493, 595, 484, 430, 453, 452, 446, 454 }, true)
g_ModelForPickupType = { nitro = 2221, repair = 2222, vehiclechange = 2223 }
g_HunterID = 425

g_Checkpoints = {}
g_Pickups = {}
g_VisiblePickups = {}
g_Objects = {}

-- Neon UI: estado para el HUD propio de carrera.
g_NeonRaceActive = false
g_NeonRanked = false
g_NeonFinishTick = nil

local function neonShadowText(initial)
	local obj = { strText = initial or '', bVisible = false }

	function obj:text(value)
		if type(value) == 'string' then
			obj.strText = value
		end
		return true
	end

	function obj:visible(value)
		if type(value) == 'boolean' then
			obj.bVisible = value
		end
		return obj.bVisible
	end

	function obj:type() return true end
	function obj:color() return true end
	function obj:position() return true end
	function obj:destroy() end

	return obj
end

local neonHudLastTick = 0

function neonRaceHudTick()
	local now = getTickCount()
	if now - neonHudLastTick < 100 then
		return
	end
	neonHudLastTick = now

	if not g_dxGUI or not g_dxGUI.checkpoint then
		return
	end

	local reached, total = string.match(g_dxGUI.checkpoint.strText or '', '(%d+)%s*/%s*(%d+)')
	reached = tonumber(reached) or 0
	total = tonumber(total) or 0

	local elapsed = 0
	if g_StartTick then
		elapsed = (g_NeonFinishTick or now) - g_StartTick
	end

	local remaining = nil
	if g_Duration then
		remaining = math.max(0, g_Duration - elapsed)
	end

	triggerEvent('neon:raceHud', localPlayer, {
		active = g_NeonRaceActive,
		ranked = g_NeonRanked,
		rank = tonumber(g_dxGUI.ranknum.strText) or 0,
		checkpoint = reached,
		total = total,
		elapsed = elapsed,
		remaining = remaining,
		finished = isPlayerFinished(localPlayer) and true or false,
	})
end

g_KillTimer = nil

-- Number of checkpoint blips to display on the radar / minimap. Default is 2. Can be increased to 3 if desired.
local g_RadarCheckpointBlips = 2
-- Per-player setting stored on everyone's computer.
local RADAR_CP_BLIPS_SETTINGS_FILE = "@cpblips_count.json"

-- Returns true if current map is blacklisted; third checkpoint blip not shown on radar / minimap.
local function isMapBlacklistedFromThirdCpBlip()
	if not g_MapInfo then return false end

	-- Individual map blacklist
	if g_MapInfo.resname and RadarCpBlipsBlacklists.maps[g_MapInfo.resname] then
		return true
	end

	-- Organizational path blacklist
	local org = g_MapInfo.respath
	if type(org) == "string" and org ~= "" then
		org = org:lower()
		for _, folder in ipairs(RadarCpBlipsBlacklists.organizationalFolders) do
			if org == folder:lower() then
				return true
			end
		end
	end

	return false
end

-- Effective number of radar checkpoint blips which falls back to 2 when the current map is blacklisted.
local function effectiveRadarCheckpointBlips()
	if isMapBlacklistedFromThirdCpBlip() then
		return 2
	end
	return g_RadarCheckpointBlips
end

local function loadRadarCheckpointBlipsSetting()
	if not fileExists(RADAR_CP_BLIPS_SETTINGS_FILE) then return end
	local file = fileOpen(RADAR_CP_BLIPS_SETTINGS_FILE)
	if not file then return end
	local content = fileRead(file, fileGetSize(file))
	fileClose(file)
	local data = fromJSON(content)
	if type(data) == "table" and (data.count == 2 or data.count == 3) then
		g_RadarCheckpointBlips = data.count
	end
end

local function saveRadarCheckpointBlipsSetting()
	local file = fileCreate(RADAR_CP_BLIPS_SETTINGS_FILE)
	if not file then return end
	fileWrite(file, toJSON({ count = g_RadarCheckpointBlips }))
	fileClose(file)
end

-- Returns the alpha level to use for the third checkpoint blip on the radar / minimap.
local function getThirdCpBlipAlphaLevel()
	if g_GameOptions and g_GameOptions.thirdcpblipalphalevel then
		return g_GameOptions.thirdcpblipalphalevel
	end
	return 120
end

-- Changes are visible and applied immediately after changing the setting
local function refreshRadarCheckpointBlipsDisplay()
	if not g_Checkpoints or not g_CurrentCheckpoint then return end
	local i = g_CurrentCheckpoint
	if i < 1 or i > #g_Checkpoints then return end

	local blipsToShow = effectiveRadarCheckpointBlips()

	for j = 1, #g_Checkpoints do
		if j < i or j > i + blipsToShow - 1 then
			destroyCheckpoint(j)
		end
	end

	-- Current checkpoint
	if not g_Checkpoints[i].marker then
		createCheckpoint(i)
	end

	-- Next checkpoint
	if i + 1 <= #g_Checkpoints then
		createCheckpoint(i + 1)
		if g_Checkpoints[i].marker then
			setMarkerTarget(g_Checkpoints[i].marker, unpack(g_Checkpoints[i+1].position))
		end
	end

	-- Next next checkpoint
	if blipsToShow >= 3 and i + 2 <= #g_Checkpoints then
		createCheckpointBlip(i + 2, getThirdCpBlipAlphaLevel())
	end
end

local function cpBlipsHandler(_, value)
	local n = tonumber(value)
	if n ~= 2 and n ~= 3 then
		outputChatBox("Usage: /cpblips 2 or /cpblips 3.", 255, 100, 100)
		return
	end

	if n == g_RadarCheckpointBlips then
		outputChatBox("Already displaying " .. n .. " checkpoint blips on the minimap.", 255, 200, 100)
		return
	end

	g_RadarCheckpointBlips = n
	saveRadarCheckpointBlipsSetting()
	refreshRadarCheckpointBlipsDisplay()

	outputChatBox("Now displaying " .. n .. " checkpoint blips on the minimap.", 100, 255, 100)
end
addCommandHandler("cpblips",     cpBlipsHandler)
addCommandHandler("nextcpblips", cpBlipsHandler)

local enterExitKey = next(getBoundKeys"enter_exit")

local function setEnterExitSuicide(enabled)
	if not enterExitKey then return end
	unbindKey(enterExitKey, "down", "Commit suicide")
	unbindKey(enterExitKey, "up", "Commit suicide")
	if enabled then
		bindKey(enterExitKey, "down", "Commit suicide")
		bindKey(enterExitKey, "up", "Commit suicide", "cancel")
	end
end

local function applyBikeFallOption()
	local enabled = g_MapOptions and g_MapOptions.bikefall == true
	setPedCanBeKnockedOffBike(localPlayer, enabled)
	toggleControl('fire', not enabled)
	toggleControl('next_weapon', not enabled)
	toggleControl('previous_weapon', not enabled)
	toggleControl('aim_weapon', not enabled)
	setEnterExitSuicide(not enabled)
end

addEventHandler('onClientResourceStart', resourceRoot,
	function()
		loadRadarCheckpointBlipsSetting()

		g_Players = getElementsByType('player')

		fadeCamera(false,0.0)
		-- create GUI
		local screenWidth, screenHeight = guiGetScreenSize()
		g_dxGUI = {
			-- Neon UI: el HUD propio dibuja posición, checkpoints y tiempo.
			ranknum = neonShadowText(''),
			ranksuffix = neonShadowText('st'),
			checkpoint = neonShadowText('0/0'),
			timepassed = neonShadowText('0:00:00'),
		}

		g_dxGUI.ranknum:type('stroke', 2, 0, 0, 0, 255)
		g_dxGUI.ranksuffix:type('stroke', 2, 0, 0, 0, 255)
		g_dxGUI.checkpoint:type('stroke', 1, 0, 0, 0, 255)
		g_dxGUI.timepassed:type('stroke', 1, 0, 0, 0, 255)
		g_GUI = {
			timeleftbg = guiCreateStaticImage(screenWidth/2-108/2, 15, 108, 24, 'img/timeleft.png', false, nil),
			timeleft = guiCreateLabel(screenWidth/2-108/2, 19, 108, 30, '', false),
			-- Neon UI: telemetría propia reemplaza salud/velocidad stock.
			healthbar = { show = function() end, hide = function() end, setProgress = function() end, destroy = function() end },
			suicidebar = FancyProgress.create(250, 1000, 'img/progress_suicide_bg.png', -65, 60, 123, 30, 'img/progress_suicide.png', 8, 8, 108, 15),
			speedbar = { show = function() end, hide = function() end, setProgress = function() end, destroy = function() end },
		}
		guiSetFont(g_GUI.timeleft, 'default-bold-small')
		guiLabelSetHorizontalAlign(g_GUI.timeleft, 'center')
		g_GUI.speedbar:setProgress(0)

		hideGUIComponents('timeleftbg', 'timeleft', 'healthbar', 'speedbar', 'suicidebar', 'ranknum', 'ranksuffix', 'checkpoint', 'timepassed')
		RankingBoard.precreateLabels(10)

		-- set update handlers
		g_PickupStartTick = getTickCount()
		addEventHandler('onClientRender', root, updateBars)
		setTimer(neonRaceHudTick, 100, 0)
		g_WaterCheckTimer = setTimer(checkWater, 1000, 0)

		-- load pickup models and textures
		for name,id in pairs(g_ModelForPickupType) do
			engineImportTXD(engineLoadTXD('model/' .. name .. '.txd'), id)
			engineReplaceModel(engineLoadDFF('model/' .. name .. '.dff', id), id)
			-- Double draw distance for pickups
			engineSetModelLODDistance( id, 60 )
		end

		if isVersion101Compatible() then
			-- Dont clip vehicles (1.0.1 function)
			setCameraClip ( true, false )
		end

		setPedCanBeKnockedOffBike(localPlayer, false)
	end
)

--- Export function to set checkpoint text
function setCheckpointText(text)
	return g_dxGUI.checkpoint:text(text)
end

-------------------------------------------------------

-- Called from server
function notifyLoadingMap( mapName, authorName, description )
	fadeCamera( false, 0.0, 0,0,0 ) -- fadeout, instant, black
end

-- Called from server
function notifyLoadingMapDetails( details )
	-- fadeCamera( false, 0.0, 0,0,0 ) -- fadeout, instant, black
end


-- Called from server
function initRace(vehicle, checkpoints, objects, pickups, mapoptions, ranked, duration, gameoptions, mapinfo, playerInfo)
	outputDebug( 'MISC', 'initRace start' )
	unloadAll()

	math.randomseed(mapName)
	cpColorRandom = { math.random(0,255), math.random(0,255), math.random(0,255) }

	g_Players = getElementsByType('player')
	g_MapOptions = mapoptions
	applyBikeFallOption()
	g_GameOptions = gameoptions
	g_MapInfo = mapinfo
	g_PlayerInfo = playerInfo
	g_NeonRanked = ranked and true or false
	g_NeonRaceActive = not isEditor()
	g_NeonFinishTick = nil
	triggerEvent('onClientMapStarting', localPlayer, mapinfo )

	fadeCamera(true)
	showHUD(false)

	g_Vehicle = vehicle
	if isElement(g_Vehicle) then
		setVehicleDamageProof(g_Vehicle, true)
	end
	OverrideClient.updateVars(g_Vehicle)

	--local x, y, z = getElementPosition(g_Vehicle)
	setCameraBehindVehicle(vehicle)
	--alignVehicleToGround(vehicle)
	updateVehicleWeapons()
	setCloudsEnabled(g_GameOptions.cloudsenable)
	setBlurLevel(g_GameOptions.blurlevel)

	-- checkpoints
	g_Checkpoints = checkpoints

	-- pickups
	local object
	local pos
	local colshape
	for i,pickup in pairs(pickups) do
		pos = pickup.position

		-- Fallback to model 2222 if the pickup type is missing/unknown
		local pickupModel = g_ModelForPickupType[pickup.type] or 2222

		object = createObject(pickupModel, pos[1], pos[2], pos[3])

		if isElement(object) then
			setElementCollisionsEnabled(object, false)
		end

		colshape = createColSphere(pos[1], pos[2], pos[3], 3.5)
		g_Pickups[colshape] = { object = object }
		for k,v in pairs(pickup) do
			g_Pickups[colshape][k] = v
		end
		local isLoaded = not pickup.isRespawning
		g_Pickups[colshape].load = isLoaded
		if g_Pickups[colshape].type == 'vehiclechange' then
			g_Pickups[colshape].label = dxText:create(getVehicleNameFromModel(g_Pickups[colshape].vehicle), 0.5, 0.5)
			g_Pickups[colshape].label:color(255, 255, 255, 0)
			g_Pickups[colshape].label:type("shadow",2)
		end
	end

	-- objects
	-- LotsOfS CUSTOM EDIT: This was no longer used, and started throwing an error with a small change I made
	-- g_Objects = {}
	-- for i,object2 in ipairs(objects) do
	-- 	local pos2 = object2.position
	-- 	local rot = object2.rotation
	-- 	g_Objects[i] = createObject(object2.model, pos2[1], pos2[2], pos2[3], rot[1], rot[2], rot[3])
	-- end

	if #g_Checkpoints > 0 then
		g_CurrentCheckpoint = 0
		showNextCheckpoint()
	end

	-- GUI
	g_dxGUI.timepassed:text('0:00.00')
	showGUIComponents('healthbar', 'speedbar', 'timepassed')
	hideGUIComponents('timeleftbg', 'timeleft')
	if ranked then
		showGUIComponents('ranknum', 'ranksuffix')
	else
		hideGUIComponents('ranknum', 'ranksuffix')
	end
	if #g_Checkpoints > 0 then
		showGUIComponents('checkpoint')
	else
		hideGUIComponents('checkpoint')
	end

	g_HurryDuration = g_GameOptions.hurrytime
	g_Duration = nil
	if duration then
		launchRace(duration)
	end

	fadeCamera( false, 0.0 )

	-- Editor start
	if isEditor() then
		editorInitRace()
		return
	end

	-- Do fadeup and then tell server client is ready
	setTimer(fadeCamera, 750, 1, true, 10.0)
	setTimer(fadeCamera, 1500, 1, true, 2.0)

	setTimer( function() triggerServerEvent('onNotifyPlayerReady', localPlayer) end, 3500, 1 )
	outputDebug( 'MISC', 'initRace end' )
	setTimer( function() setCameraBehindVehicle( g_Vehicle ) end, 300, 1 )
end

-- Called from the server when settings are changed
function updateOptions ( gameoptions, mapoptions )
	-- Update
	g_GameOptions = gameoptions
	g_MapOptions = mapoptions
	applyBikeFallOption()

	-- Apply
	updateVehicleWeapons()
	setCloudsEnabled(g_GameOptions.cloudsenable)
	setBlurLevel(g_GameOptions.blurlevel)

	refreshRadarCheckpointBlipsDisplay()
end

function launchRace(duration)
	g_Players = getElementsByType('player')
	local playerSkin = getElementModel(localPlayer)

	for k,v in ipairs(getElementsByType("ped")) do
		if ( getElementModel(v) == playerSkin) then
			setElementCollisionsEnabled(v, false)
		end
	end

	if type(duration) == 'number' then
		-- Time left is drawn by neon_racehud.lua, not by the stock GUI label.
		hideGUIComponents('timeleftbg', 'timeleft')
		guiLabelSetColor(g_GUI.timeleft, 255, 255, 255)
		g_Duration = duration
		addEventHandler('onClientRender', root, updateTime)
	end

	if isElement(g_Vehicle) then
		setVehicleDamageProof(g_Vehicle, false)
	end

	g_StartTick = getTickCount()
end


addEventHandler('onClientElementStreamIn', root,
	function()
		local colshape = table.find(g_Pickups, 'object', source)
		if colshape then
			local pickup = g_Pickups[colshape]
			if pickup.label then
				pickup.label:color(255, 255, 255, 0)
				pickup.label:visible(false)
				pickup.labelInRange = false
			end
			g_VisiblePickups[colshape] = source
		end
	end
)

addEventHandler('onClientElementStreamOut', root,
	function()
		local colshape = table.find(g_VisiblePickups, source)
		if colshape then
			local pickup = g_Pickups[colshape]
			if pickup.label then
				pickup.label:color(255, 255, 255, 0)
				pickup.label:visible(false)
				pickup.labelInRange = nil
			end
			g_VisiblePickups[colshape] = nil
		end
	end
)

function updatePickups()
	local angle = math.fmod((getTickCount() - g_PickupStartTick) * 360 / 2000, 360)
	local g_Pickups = g_Pickups
	local pickup, x, y, cX, cY, cZ, pickX, pickY, pickZ
	for colshape,elem in pairs(g_VisiblePickups) do
		pickup = g_Pickups[colshape]
		if pickup.load then
			setElementRotation(elem, 0, 0, angle)
			if pickup.label then
				cX, cY, cZ = getCameraMatrix()
				pickX, pickY, pickZ = unpack(pickup.position)
				x, y = getScreenFromWorldPosition(pickX, pickY, pickZ + 2.85, 0.08 )
				local distanceToPickup = getDistanceBetweenPoints3D(cX, cY, cZ, pickX, pickY, pickZ)
				if distanceToPickup > 80 then
					pickup.labelInRange = false
					pickup.label:visible(false)
				elseif x then
					if distanceToPickup < 60 then
						if isLineOfSightClear(cX, cY, cZ, pickX, pickY, pickZ, true, false, false, true, false) then
							if not pickup.labelInRange then
								if pickup.anim then
									pickup.anim:remove()
								end
								pickup.anim = Animation.createAndPlay(
									pickup.label,
									Animation.presets.dxTextFadeIn(500)
								)
								pickup.labelInRange = true
								pickup.labelVisible = true
							end
							if not pickup.labelVisible then
								pickup.label:color(255, 255, 255, 255)
							end
							pickup.label:visible(true)
						else
							pickup.label:color(255, 255, 255, 0)
							pickup.labelVisible = false
							pickup.label:visible(false)
						end
					else
						if pickup.labelInRange then
							if pickup.anim then
								pickup.anim:remove()
							end
							pickup.anim = Animation.createAndPlay(
								pickup.label,
								Animation.presets.dxTextFadeOut(1000)
							)
							pickup.labelInRange = false
							pickup.labelVisible = false
							pickup.label:visible(true)
						end
					end
					local scale = (60/distanceToPickup)*0.7
					pickup.label:scale(scale)
					pickup.label:position(x, y, false)
				else
					pickup.label:color(255, 255, 255, 0)
					pickup.labelVisible = false
					pickup.label:visible(false)
				end
				if Spectate.fadedout then
					pickup.label:visible(false)	-- Hide pickup labels when screen is black
				end
			end
		else
			if pickup.label then
				pickup.label:visible(false)
				if pickup.labelInRange then
					pickup.label:color(255, 255, 255, 0)
					pickup.labelInRange = false
				end
			end
		end
	end
end
addEventHandler('onClientRender', root, updatePickups)

addEventHandler('onClientColShapeHit', root,
	function(elem)
		local pickup = g_Pickups[source]
		if elem ~= g_Vehicle or not pickup or (isElement(g_Vehicle) and isVehicleBlown(g_Vehicle)) or getElementHealth(localPlayer) == 0 then
			return
		end
		outputDebug( 'CHECKPOINT', 'onClientColShapeHit'
						.. ' elem:' .. tostring(elem)
						.. ' g_Vehicle:' .. tostring(g_Vehicle)
						.. ' isVehicleBlown(g_Vehicle):' .. tostring(isElement(g_Vehicle) and isVehicleBlown(g_Vehicle) or false)
						.. ' localPlayer:' .. tostring(localPlayer)
						.. ' getElementHealth(localPlayer):' .. tostring(getElementHealth(localPlayer))
						.. ' source:' .. tostring(source)
						.. ' pickup:' .. tostring(pickup)
						)
		if pickup.load then
			handleHitPickup(pickup)
		end
	end
)

function handleHitPickup(pickup)
	if pickup.type == 'vehiclechange' then
		if pickup.vehicle == getElementModel(g_Vehicle) then
			return
		end
		local health = nil
		g_PrevVehicleHeight = getElementDistanceFromCentreOfMassToBaseOfModel(g_Vehicle)
		alignVehicleWithUp()
		if checkModelIsAirplane(pickup.vehicle) then -- Hack fix for Issue #4104
			health = getElementHealth(g_Vehicle)
		end
		setElementModel(g_Vehicle, pickup.vehicle)
		if health then
			fixVehicle(g_Vehicle)
			setElementHealth(g_Vehicle, health)
		end
		vehicleChanging(g_MapOptions.classicchangez, pickup.vehicle)
	elseif pickup.type == 'nitro' then
		addVehicleUpgrade(g_Vehicle, 1010)
	elseif pickup.type == 'repair' then
		fixVehicle(g_Vehicle)
	end
	triggerServerEvent('onPlayerPickUpRacePickupInternal', localPlayer, pickup.id, pickup.respawn)
	playSoundFrontEnd(46)
end

function unloadPickup(pickupID)
	for colshape,pickup in pairs(g_Pickups) do
		if pickup.id == pickupID then
			pickup.load = false
			setElementAlpha(pickup.object, 0)
			return
		end
	end
end

function loadPickup(pickupID)
	for colshape,pickup in pairs(g_Pickups) do
		if pickup.id == pickupID then
			setElementAlpha(pickup.object, 255)
			pickup.load = true
			if isElementWithinColShape(g_Vehicle, colshape) then
				handleHitPickup(pickup)
			end
			return
		end
	end
end

function vehicleChanging( changez, newModel )
	if getElementModel(g_Vehicle) ~= newModel then
		outputConsole( "Vehicle change model mismatch (" .. tostring(getElementModel(g_Vehicle)) .. "/" .. tostring(newModel) .. ")" )
	end
	local newVehicleHeight = getElementDistanceFromCentreOfMassToBaseOfModel(g_Vehicle)
	local x, y, z = getElementPosition(g_Vehicle)
	if g_PrevVehicleHeight and newVehicleHeight > g_PrevVehicleHeight then
		z = z - g_PrevVehicleHeight + newVehicleHeight
	end
	if changez then
		z = z + 1
	end
	setElementPosition(g_Vehicle, x, y, z)
	g_PrevVehicleHeight = nil
	updateVehicleWeapons()
	checkVehicleIsHelicopter()
end

function updateVehicleWeapons()
	if g_Vehicle then
		local weapons = not g_ArmedVehicleIDs[getElementModel(g_Vehicle)] or g_MapOptions.vehicleweapons
		toggleControl('vehicle_fire', weapons)
		if getElementModel(g_Vehicle) == g_HunterID and not g_MapOptions.hunterminigun then
			weapons = false
		end
		toggleControl('vehicle_secondary_fire', weapons)
	end
end

function vehicleUnloading()
	g_Vehicle = nil
end

function updateBars()
	if (g_MapOptions and not g_MapOptions.allowonfoot and not g_MapOptions.bikefall and g_Vehicle) then
		-- default bar behavior from non-foot races
		g_GUI.healthbar:setProgress(getElementHealth(g_Vehicle))
		local vx, vy, vz = getElementVelocity(g_Vehicle)
		g_GUI.speedbar:setProgress(math.sqrt(vx*vx + vy*vy + vz*vz))
	else
		local playerOccupiedVehicle = getPedOccupiedVehicle(localPlayer)
		if (playerOccupiedVehicle) then
			-- in vehicle
			g_GUI.healthbar:setProgress(getElementHealth(playerOccupiedVehicle))
			local vx, vy, vz = getElementVelocity(playerOccupiedVehicle)
			g_GUI.speedbar:setProgress(math.sqrt(vx*vx + vy*vy + vz*vz))
		else
			-- on foot
			local maxHealthStat = getPedStat(localPlayer, 24)
			local maxHP  = 100 + (maxHealthStat - 569) / 4.31
			g_GUI.healthbar:setProgress(getElementHealth(localPlayer) / maxHP * 750 + 250) -- health bar goes from 250 - 1000 because it's made for vehicles
			local vx, vy, vz = getElementVelocity(localPlayer)
			g_GUI.speedbar:setProgress(math.sqrt(vx*vx + vy*vy + vz*vz))
		end
	end
	if (g_KillTimer and isTimer(g_KillTimer)) then
		g_GUI.suicidebar:show()
		local timeRemaining, _, timeInterval = getTimerDetails(g_KillTimer)
		g_GUI.suicidebar:setProgress(1000 - (timeRemaining / timeInterval * 750))
	else
		g_GUI.suicidebar:hide()
	end
end

function updateTime()
	local tick = getTickCount()
	local msPassed = tick - g_StartTick
	if not isPlayerFinished(localPlayer) then
		g_dxGUI.timepassed:text(msToTimeStr(msPassed))
	end
	local timeLeft = g_Duration - msPassed
	guiSetText(g_GUI.timeleft, msToTimeStr(timeLeft > 0 and timeLeft or 0))
	if g_HurryDuration and g_GUI.hurry == nil and timeLeft <= g_HurryDuration then
		startHurry()
	end
end

addEventHandler('onClientElementDataChange', localPlayer,
	function(dataName)
		if dataName == 'race rank' and not Spectate.active then
			setRankDisplay( getElementData(localPlayer, 'race rank') )
		end
	end,
	false
)

function setRankDisplay( rank )
	if not tonumber(rank) then
		g_dxGUI.ranknum:text('')
		g_dxGUI.ranksuffix:text('')
		return
	end

	local numPlayers = 0
	if #g_Players > 0 then
		for _,player in ipairs(g_Players) do
			local state = getElementData(player, "state")
			if (state == "alive" or state == "dead" or state == "finished") then
				numPlayers = numPlayers+1
			end
		end
	end

	local text = ((rank < 10 or rank > 20) and ({ [1] = 'st', [2] = 'nd', [3] = 'rd' })[rank % 10] or 'th') .. ' / ' .. numPlayers
	local width = dxGetTextWidth(text, 1, 'bankgothic')
	local screenWidth, screenHeight = guiGetScreenSize()
	g_dxGUI.ranknum:position(screenWidth - width - 15, screenHeight - 95, false)
	g_dxGUI.ranknum:text(tostring(rank))
	g_dxGUI.ranksuffix:text(text)
end
addCommandHandler("rank", function(command,rank) setRankDisplay(tonumber(rank)) end)


addEventHandler('onClientElementDataChange', root,
	function(dataName)
		if dataName == 'race.finished' then
			if isPlayerFinished(source) then
				Spectate.dropCamera( source, 2000 )
			end
		end
		if dataName == 'race.spectating' then
			if isPlayerSpectating(source) then
				Spectate.validateTarget( source )	-- No spectate at this player
			end
		end
	end
)


function checkWater()
	if g_Vehicle and not g_MapOptions.allowonfoot and (not g_MapOptions.bikefall or getPedOccupiedVehicle(localPlayer)) then
		if not g_WaterCraftIDs[getElementModel(g_Vehicle)] then
			local x, y, z = getElementPosition(localPlayer)
			local waterZ = getWaterLevel(x, y, z)
			if waterZ and z < waterZ - 0.5 and not isPlayerRaceDead(localPlayer) and not isPlayerFinished(localPlayer) and g_MapOptions then
				if g_MapOptions.firewater then
					blowVehicle ( g_Vehicle, true )
				else
					setElementHealth(localPlayer,0)
					triggerServerEvent('onRequestKillPlayer',localPlayer)
				end
			end
		end
		-- Check stalled vehicle
		if not getVehicleEngineState( g_Vehicle ) then
			setVehicleEngineState( g_Vehicle, true )
		end
		-- Check dead vehicle
		if getElementHealth( g_Vehicle ) == 0 and not isPlayerRaceDead(localPlayer) and not isPlayerFinished(localPlayer)then
			setElementHealth(localPlayer,0)
			triggerServerEvent('onRequestKillPlayer',localPlayer)
		end
	end
end

function showNextCheckpoint(bOtherPlayer)
	g_CurrentCheckpoint = g_CurrentCheckpoint + 1
	local i = g_CurrentCheckpoint
	local blipsToShow = effectiveRadarCheckpointBlips()
	g_dxGUI.checkpoint:text((i - 1) .. ' / ' .. #g_Checkpoints)

	for j = 1, #g_Checkpoints do
		if j < i or j > i + blipsToShow - 1 then
			destroyCheckpoint(j)
		end
	end

	if not g_Checkpoints[i].marker then
		createCheckpoint(i)
	end
	makeCheckpointCurrent(i, bOtherPlayer)
	if i + 1 <= #g_Checkpoints then
		createCheckpoint(i + 1)
		if g_Checkpoints[i].marker then
			setMarkerTarget(g_Checkpoints[i].marker, unpack(g_Checkpoints[i+1].position))
		end
	end
	if blipsToShow >= 3 and i + 2 <= #g_Checkpoints then
		createCheckpointBlip(i + 2, getThirdCpBlipAlphaLevel())
	end
	if not Spectate.active then
		setElementData(localPlayer, 'race.checkpoint', i)
	end
end

-------------------------------------------------------------------------------
-- Show checkpoints and rank info that is relevant to the player being spectated
local prevWhich = nil
local cpValuePrev = nil
local rankValuePrev = nil

function updateSpectatingCheckpointsAndRank()
	local which = getWhichDataSourceToUse()

	-- Do nothing if we are keeping the last thing displayed
	if which == "keeplast" then
		return
	end

	local dataSourceChangedToLocal = which ~= prevWhich and which=="local"
	local dataSourceChangedFromLocal = which ~= prevWhich and prevWhich=="local"
	prevWhich = which

	if dataSourceChangedFromLocal or dataSourceChangedToLocal then
		cpValuePrev = nil
		rankValuePrev = nil
	end

	if Spectate.active or dataSourceChangedToLocal then
		local watchedPlayer = getWatchedPlayer()

		if g_CurrentCheckpoint and g_Checkpoints and #g_Checkpoints > 0 then
			local cpValue = getElementData(watchedPlayer, 'race.checkpoint') or 0
			if cpValue > 0 and cpValue <= #g_Checkpoints then
				if cpValue ~= cpValuePrev then
					cpValuePrev = cpValue
					setCurrentCheckpoint( cpValue, Spectate.active and watchedPlayer ~= localPlayer )
				end
			end
		end

		local rankValue = getElementData(watchedPlayer, 'race rank') or 0
		if rankValue ~= rankValuePrev then
			rankValuePrev = rankValue
			setRankDisplay( rankValue )
		end
	end
end

-- "local"			If not spectating
-- "spectarget"		If spectating valid target
-- "keeplast"		If spectating nil target and dropcam
-- "local"			If spectating nil target and no dropcam
function getWhichDataSourceToUse()
	if not Spectate.active			then	return "local"			end
	if Spectate.target				then	return "spectarget"		end
	if Spectate.hasDroppedCamera()	then	return "keeplast"		end
	return "local"
end

function getWatchedPlayer()
	if not Spectate.active			then	return localPlayer		end
	if Spectate.target				then	return Spectate.target	end
	if Spectate.hasDroppedCamera()	then	return nil				end
	return localPlayer
end
-------------------------------------------------------------------------------

function checkpointReached(elem)
	outputDebug( 'CP', 'checkpointReached'
					.. ' ' .. tostring(g_CurrentCheckpoint)
					.. ' elem:' .. tostring(elem)
					.. ' g_Vehicle:' .. tostring(g_Vehicle)
					.. ' isVehicleBlown(g_Vehicle):' .. tostring(isElement(g_Vehicle) and isVehicleBlown(g_Vehicle) or false)
					.. ' localPlayer:' .. tostring(localPlayer)
					.. ' getElementHealth(localPlayer):' .. tostring(getElementHealth(localPlayer))
	)
	if (isElement(g_Vehicle) and isVehicleBlown(g_Vehicle)) then
		-- ignore if our main vehicle is destroyed (TODO: this is an odd case with foot races that needs to be handled overall)
		return
	end
	if (Spectate.active or getElementHealth(localPlayer) == 0) then
		-- ignore if we are spectating or dead
		return
	end

	if (g_MapOptions.allowonfoot) then
		local currentVehicle = getPedOccupiedVehicle(localPlayer)
		if (elem ~= g_Vehicle and elem ~= localPlayer and elem ~= currentVehicle) then
			-- ignore anything that isn't us, our main car, or our current car
			return
		end
		if (currentVehicle and elem == localPlayer) then
			-- ignore player model because this should already be triggered by the car we're driving
			return
		end
	else
		if (elem ~= g_Vehicle) then
			-- ignore anything but our main vehicle if this is not a foot race
			return
		end
	end

	if g_Checkpoints[g_CurrentCheckpoint].vehicle and g_Checkpoints[g_CurrentCheckpoint].vehicle ~= getElementModel(g_Vehicle) then
		g_PrevVehicleHeight = getElementDistanceFromCentreOfMassToBaseOfModel(g_Vehicle)
		local health = nil
		alignVehicleWithUp()
		if checkModelIsAirplane(g_Checkpoints[g_CurrentCheckpoint].vehicle) then -- Hack fix for Issue #4104
			health = getElementHealth(g_Vehicle)
		end
		setElementModel(g_Vehicle, g_Checkpoints[g_CurrentCheckpoint].vehicle)
		if health then
			fixVehicle(g_Vehicle)
			setElementHealth(g_Vehicle, health)
		end
		vehicleChanging(g_MapOptions.classicchangez, g_Checkpoints[g_CurrentCheckpoint].vehicle)
	end
	triggerServerEvent('onPlayerReachCheckpointInternal', localPlayer, g_CurrentCheckpoint)
	playSoundFrontEnd(43)
	if g_CurrentCheckpoint < #g_Checkpoints then
		showNextCheckpoint()
	else
		g_dxGUI.checkpoint:text(#g_Checkpoints .. ' / ' .. #g_Checkpoints)
		local rc = getRadioChannel()
		setRadioChannel(0)
		addEventHandler("onClientPlayerRadioSwitch", root, onChange)
		playSound("audio/mission_accomplished.mp3")
		setTimer(changeRadioStation, 8000, 1, rc)
		if g_GUI.hurry then
			Animation.createAndPlay(g_GUI.hurry, Animation.presets.guiFadeOut(500), destroyElement)
			g_GUI.hurry = false
		end
		destroyCheckpoint(#g_Checkpoints)
		triggerEvent('onClientPlayerFinish', localPlayer)
		toggleAllControls(false, true, false)
	end
end

addEventHandler('onClientPlayerFinish', localPlayer, function()
	g_NeonFinishTick = getTickCount()
end)

function onChange()
	cancelEvent()
end

function changeRadioStation(rc)
	removeEventHandler("onClientPlayerRadioSwitch", root, onChange)
	setRadioChannel(tonumber(rc))
end

function startHurry()
	if not isPlayerFinished(localPlayer) then
		local screenWidth, screenHeight = guiGetScreenSize()
		local w, h = resAdjust(370), resAdjust(112)
		g_GUI.hurry = guiCreateStaticImage(screenWidth/2 - w/2, screenHeight - h - 40, w, h, 'img/hurry.png', false, nil)
		guiSetAlpha(g_GUI.hurry, 0)
		Animation.createAndPlay(g_GUI.hurry, Animation.presets.guiFadeIn(800))
		Animation.createAndPlay(g_GUI.hurry, Animation.presets.guiPulse(1000))
	end
	guiLabelSetColor(g_GUI.timeleft, 255, 0, 0)
end

function setTimeLeft(timeLeft)
	g_Duration = (getTickCount() - g_StartTick) + timeLeft
end

-----------------------------------------------------------------------
-- Spectate
-----------------------------------------------------------------------
Spectate = {}
Spectate.active = false
Spectate.target = nil
Spectate.blockUntilTimes = {}
Spectate.savePos = false
Spectate.manual = false
Spectate.droppedCameraTimer = Timer:create()
Spectate.tickTimer = Timer:create()
Spectate.fadedout = true
Spectate.blockManual = false
Spectate.blockManualTimer = nil


-- Request to switch on
function Spectate.start(type)
	outputDebug( 'SPECTATE', 'Spectate.start '..type )
	assert(type=='manual' or type=='auto', "Spectate.start : type == auto or manual")
	Spectate.blockManual = false
	if type == 'manual' then
		if Spectate.active then
			return					-- Ignore if manual request and already on
		end
		Spectate.savePos = true	-- Savepos and start if manual request and was off
	elseif type == 'auto' then
		Spectate.savePos = false	-- Clear restore pos if an auto spectate is requested
	end
	if not Spectate.active then
		Spectate._start()			-- Switch on here, if was off
	end
end


-- Request to switch off
function Spectate.stop(type)
	outputDebug( 'SPECTATE', 'Spectate.stop '..type )
	assert(type=='manual' or type=='auto', "Spectate.stop : type == auto or manual")
	if type == 'auto' then
		Spectate.savePos = false	-- Clear restore pos if an auto spectate is requested
	end
	if Spectate.active then
		Spectate._stop()			-- Switch off here, if was on
	end
end


function Spectate._start()
	outputDebug( 'SPECTATE', 'Spectate._start ' )
	triggerServerEvent('onClientNotifySpectate', localPlayer, true )
	assert(not Spectate.active, "Spectate._start - not Spectate.active")
	local screenWidth, screenHeight = guiGetScreenSize()
	g_GUI.specprev = guiCreateStaticImage(screenWidth/2 - 100 - 58, screenHeight - 123, 58, 82, 'img/specprev.png', false, nil)
	g_GUI.specprevhi = guiCreateStaticImage(screenWidth/2 - 100 - 58, screenHeight - 123, 58, 82, 'img/specprev_hi.png', false, nil)
	g_GUI.specnext = guiCreateStaticImage(screenWidth/2 + 100, screenHeight - 123, 58, 82, 'img/specnext.png', false, nil)
	g_GUI.specnexthi = guiCreateStaticImage(screenWidth/2 + 100, screenHeight - 123, 58, 82, 'img/specnext_hi.png', false, nil)
	g_GUI.speclabel = guiCreateLabel(screenWidth/2 - 100, screenHeight - 100, 200, 70, '', false)
	Spectate.updateGuiFadedOut()
	guiLabelSetHorizontalAlign(g_GUI.speclabel, 'center')
	hideGUIComponents('specprevhi', 'specnexthi')
	if Spectate.savePos then
		savePosition()
	end
	Spectate.setTarget( Spectate.findRandomTarget() )
	MovePlayerAway.start()
	Spectate.setTarget( Spectate.target )
	Spectate.validateTarget(Spectate.target)
	Spectate.tickTimer:setTimer( Spectate.tick, 500, 0 )

	addCommandHandler("Spectate previous", Spectate.previous)
	addCommandHandler("Spectate next", Spectate.next)
end

-- Stop spectating. Will restore position if Spectate.savePos is set
function Spectate._stop()
	Spectate.cancelDropCamera()
	Spectate.tickTimer:killTimer()
	triggerServerEvent('onClientNotifySpectate', localPlayer, false )
	outputDebug( 'SPECTATE', 'Spectate._stop ' )
	assert(Spectate.active, "Spectate._stop - Spectate.active")
	for i,name in ipairs({'specprev', 'specprevhi', 'specnext', 'specnexthi', 'speclabel'}) do
		if g_GUI[name] then
			destroyElement(g_GUI[name])
			g_GUI[name] = nil
		end
	end
	removeCommandHandler("Spectate previous")
	removeCommandHandler("Spectate next")

	MovePlayerAway.stop()
	setCameraTarget(localPlayer)
	Spectate.target = nil
	Spectate.active = false
	if Spectate.savePos then
		Spectate.savePos = false
		restorePosition()
	end
end

function Spectate.previous(bGUIFeedback)
	Spectate.setTarget( Spectate.findNewTarget(Spectate.target,-1) )
	if bGUIFeedback then
		setGUIComponentsVisible({ specprev = false, specprevhi = true })
		setTimer(setGUIComponentsVisible, 100, 1, { specprevhi = false, specprev = true })
	end
end

function Spectate.next(bGUIFeedback)
	Spectate.setTarget( Spectate.findNewTarget(Spectate.target,1) )
	if bGUIFeedback then
		setGUIComponentsVisible({ specnext = false, specnexthi = true })
		setTimer(setGUIComponentsVisible, 100, 1, { specnexthi = false, specnext = true })
	end
end

---------------------------------------------
-- Step along to the next player to spectate
local playersRankSorted = {}
local playersRankSortedTime = 0

function Spectate.findRandomTarget()
	local playersRandomized = {}
	for _,player in ipairs(g_Players) do
		table.insert(playersRandomized, player)
	end
	while #playersRandomized > 0 do
		local randomNo = math.random(1,#playersRandomized)
		if Spectate.isValidTarget(playersRandomized[randomNo]) then
			return playersRandomized[randomNo]
		else
			table.remove(playersRandomized, randomNo)
		end
	end
	return nil
end

function Spectate.findNewTarget(current,dir)

	-- Time to update sorted list?
	local bUpdateSortedList = ( getTickCount() - playersRankSortedTime > 1000 )

	-- Need to update sorted list because g_Players has changed size?
	bUpdateSortedList = bUpdateSortedList or ( #playersRankSorted ~= #g_Players )

	if not bUpdateSortedList then
		-- Check playersRankSorted contains the same elements as g_Players
		for _,item in ipairs(playersRankSorted) do
			if not table.find(g_Players, item.player) then
				bUpdateSortedList = true
				break
			end
		end
	end

	-- Update sorted list if required
	if bUpdateSortedList then
		-- Remake list
		playersRankSorted = {}
		for _,player in ipairs(g_Players) do
			local rank = tonumber(getElementData(player, 'race rank')) or 0
			table.insert( playersRankSorted, {player=player, rank=rank} )
		end
		-- Sort it by rank
		table.sort(playersRankSorted, function(a,b) return(a.rank > b.rank) end)

		playersRankSortedTime = getTickCount()
	end

	-- Find next player in list
	local pos = table.find(playersRankSorted, 'player', current) or 1
	for i=1,#playersRankSorted do
		pos = ((pos + dir - 1) % #playersRankSorted ) + 1
		if Spectate.isValidTarget(playersRankSorted[pos].player) then
			return playersRankSorted[pos].player
		end
	end
	return nil
end
---------------------------------------------

function Spectate.isValidTarget(player)
	if player == nil then
		return true
	end
	if player == localPlayer or isPlayerFinished(player) or isPlayerRaceDead(player) or isPlayerSpectating(player) then
		return false
	end
	if ( Spectate.blockUntilTimes[player] or 0 ) > getTickCount() then
		return false
	end
	if not table.find(g_Players, player) or not isElement(player) then
		return false
	end
	local x,y,z = getElementPosition(player)
	if z > 20000 then
		return false
	end
	if x > -1 and x < 1 and y > -1 and y < 1 then
		return false
	end
	return true
end

-- If player is the current target, check to make sure is valid
function Spectate.validateTarget(player)
	if Spectate.active and player == Spectate.target then
		if not Spectate.isValidTarget(player) then
			Spectate.previous(false)
		end
	end
end

function Spectate.dropCamera( player, time )
	if Spectate.active and player == Spectate.target then
		if not Spectate.hasDroppedCamera() then
			setCameraMatrix( getCameraMatrix() )
			Spectate.target = nil
			Spectate.droppedCameraTimer:setTimer(Spectate.cancelDropCamera, time, 1, player )
		end
	end
end

function Spectate.hasDroppedCamera()
	return Spectate.droppedCameraTimer:isActive()
end

function Spectate.cancelDropCamera()
	if Spectate.hasDroppedCamera() then
		Spectate.droppedCameraTimer:killTimer()
		Spectate.tick()
	end
end


function Spectate.setTarget( player )
	if Spectate.hasDroppedCamera() then
		return
	end

	Spectate.active = true
	Spectate.target = player
	if Spectate.target then
		if Spectate.getCameraTargetPlayer() ~= Spectate.target then
			setCameraTarget(Spectate.target)
		end
		guiSetText(g_GUI.speclabel, 'Currently spectating:\n' .. getPlayerName(Spectate.target))
	else
		local x,y = getElementPosition(localPlayer)
		x = x - ( x % 32 )
		y = y - ( y % 32 )
		local z = getGroundPosition ( x, y, 5000 ) or 40
		setCameraTarget( localPlayer )
		setCameraMatrix( x,y,z+10,x,y+50,z+60)
		guiSetText(g_GUI.speclabel, 'Currently spectating:\n No one to spectate')
	end
	if Spectate.active and Spectate.savePos then
		guiSetText(g_GUI.speclabel, guiGetText(g_GUI.speclabel) .. "\n\nPress 'B' to join")
	end
end

function Spectate.blockAsTarget( player, ticks )
	Spectate.blockUntilTimes[player] = getTickCount() + ticks
	Spectate.validateTarget(player)
end

function Spectate.tick()
	if Spectate.target and Spectate.getCameraTargetPlayer() and Spectate.getCameraTargetPlayer() ~= Spectate.target then
		if Spectate.isValidTarget(Spectate.target) then
			setCameraTarget(Spectate.target)
			return
		end
	end
	if not Spectate.target or ( Spectate.getCameraTargetPlayer() and Spectate.getCameraTargetPlayer() ~= Spectate.target ) or not Spectate.isValidTarget(Spectate.target) then
		Spectate.previous(false)
	end
end

function Spectate.getCameraTargetPlayer()
	local element = getCameraTarget()
	if element and getElementType(element) == "vehicle" then
		element = getVehicleController(element)
	end
	return element
end


g_SavedPos = {}
function savePosition()
	g_SavedPos.x, g_SavedPos.y, g_SavedPos.z = getElementPosition(localPlayer)
	g_SavedPos.rz = getPedRotation(localPlayer)

	if isElement(g_Vehicle) then
		g_SavedPos.vx, g_SavedPos.vy, g_SavedPos.vz = getElementPosition(g_Vehicle)
		g_SavedPos.vrx, g_SavedPos.vry, g_SavedPos.vrz = getElementRotation(g_Vehicle)
	else
		g_SavedPos.vx, g_SavedPos.vy, g_SavedPos.vz = nil, nil, nil
		g_SavedPos.vrx, g_SavedPos.vry, g_SavedPos.vrz = nil, nil, nil
	end
end

function restorePosition()
	setElementPosition( localPlayer, g_SavedPos.x, g_SavedPos.y, g_SavedPos.z )
	setPedRotation( localPlayer, g_SavedPos.rz )

	if isElement(g_Vehicle) and g_SavedPos.vx then
		setElementPosition( g_Vehicle, g_SavedPos.vx, g_SavedPos.vy, g_SavedPos.vz )
		setElementRotation( g_Vehicle, g_SavedPos.vrx, g_SavedPos.vry, g_SavedPos.vrz )
	end
end


addEvent ( "onClientScreenFadedOut", true )
addEventHandler ( "onClientScreenFadedOut", root,
	function()
		Spectate.fadedout = true
		Spectate.updateGuiFadedOut()
	end
)

addEvent ( "onClientScreenFadedIn", true )
addEventHandler ( "onClientScreenFadedIn", root,
	function()
		Spectate.fadedout = false
		Spectate.updateGuiFadedOut()
	end
)

addEvent ( "onClientPreRender", true )
addEventHandler ( "onClientPreRender", root,
	function()
		if isPlayerRaceDead( localPlayer ) then
			setCameraMatrix( getCameraMatrix() )
		end
		updateSpectatingCheckpointsAndRank()
	end
)

function Spectate.updateGuiFadedOut()
	if g_GUI and g_GUI.specprev then
		if Spectate.fadedout then
			setGUIComponentsVisible({ specprev = false, specnext = false, speclabel = false })
		else
			setGUIComponentsVisible({ specprev = true, specnext = true, speclabel = true })
		end
	end
end

-----------------------------------------------------------------------

-----------------------------------------------------------------------
-- MovePlayerAway - Super hack - Fixes the spec cam problem
-----------------------------------------------------------------------
MovePlayerAway = {}
MovePlayerAway.timer = Timer:create()
MovePlayerAway.posX = 0
MovePlayerAway.posY = 0
MovePlayerAway.posZ = 0
MovePlayerAway.rotZ = 0
MovePlayerAway.health = 0

function MovePlayerAway.start()
	local element = g_Vehicle or getPedOccupiedVehicle(localPlayer) or localPlayer
	MovePlayerAway.posX, MovePlayerAway.posY, MovePlayerAway.posZ = getElementPosition(element)
	MovePlayerAway.posZ = 34567 + math.random(0,4000)
	MovePlayerAway.rotZ = 0
	MovePlayerAway.health = math.max(1,getElementHealth(element))
	setElementHealth( element, 2000 )
	setElementHealth( localPlayer, 90 )
	MovePlayerAway.update(true)
	MovePlayerAway.timer:setTimer(MovePlayerAway.update,500,0)
	triggerServerEvent("onRequestMoveAwayBegin", localPlayer)
end


function MovePlayerAway.update(nozcheck)
	-- Move our player far away
	local camTarget = getCameraTarget()
	if not getPedOccupiedVehicle(localPlayer) then
		setElementPosition( localPlayer, MovePlayerAway.posX-10, MovePlayerAway.posY-10, MovePlayerAway.posZ )
	end
	if getPedOccupiedVehicle(localPlayer) then
		if not nozcheck then
			if camTarget then
				MovePlayerAway.posX, MovePlayerAway.posY = getElementPosition(camTarget)
				if getElementType(camTarget) ~= "vehicle" then
					outputDebug( 'SPECTATE', 'camera target type:' .. getElementType(camTarget) )
				end
				if getElementType(camTarget) == 'ped' then
					MovePlayerAway.rotZ = getPedRotation(camTarget)
				else
					_,_, MovePlayerAway.rotZ = getElementRotation(camTarget)
				end
			end
		end
		local vehicle = g_Vehicle
		if vehicle then
			fixVehicle( vehicle )
			setElementFrozen ( vehicle, true )
			setElementPosition( vehicle, MovePlayerAway.posX, MovePlayerAway.posY, MovePlayerAway.posZ )
			setElementVelocity( vehicle, 0,0,0 )
			setElementAngularVelocity( vehicle, 0,0,0 )
			setElementRotation ( vehicle, 0,0,MovePlayerAway.rotZ )
		end
	end
	setElementHealth( localPlayer, 90 )

	if camTarget and camTarget ~= getCameraTarget() then
		setCameraTarget(camTarget)
	end
end

function MovePlayerAway.stop()
	triggerServerEvent("onRequestMoveAwayEnd", localPlayer)
	if MovePlayerAway.timer:isActive() then
		MovePlayerAway.timer:killTimer()
		local vehicle = g_Vehicle
		if vehicle then
			setElementVelocity( vehicle, 0,0,0 )
			setElementAngularVelocity( vehicle, 0,0,0 )
			setElementFrozen ( vehicle, false )
			setVehicleDamageProof ( vehicle, false )
			setElementHealth ( vehicle, MovePlayerAway.health )
		end
		setElementVelocity( localPlayer, 0,0,0 )
	end
end

-----------------------------------------------------------------------
-- Camera transition for our player's respawn
-----------------------------------------------------------------------
function remoteStopSpectateAndBlack()
	Spectate.stop('auto')
	fadeCamera(false,0.0, 0,0,0)			-- Instant black
end

function remoteSoonFadeIn( bNoCameraMove )
	setTimer(fadeCamera,250+500,1,true,1.0)	-- And up
	if not bNoCameraMove then
		setTimer( function() setCameraBehindVehicle( g_Vehicle ) end ,250+500-150,1 )
	end
	setTimer(checkVehicleIsHelicopter,250+500,1)
end
-----------------------------------------------------------------------

function raceTimeout()
	removeEventHandler('onClientRender', root, updateTime)
	if g_CurrentCheckpoint then
		destroyCheckpoint(g_CurrentCheckpoint)
		destroyCheckpoint(g_CurrentCheckpoint + 1)
	end
	guiSetText(g_GUI.timeleft, msToTimeStr(0))
	if g_GUI.hurry then
		Animation.createAndPlay(g_GUI.hurry, Animation.presets.guiFadeOut(500), destroyElement)
		g_GUI.hurry = nil
	end
	triggerEvent("onClientPlayerOutOfTime", localPlayer)
	toggleAllControls(false, true, false)
end

function unloadAll()
	triggerEvent('onClientMapStopping', localPlayer)
	for i=1,#g_Checkpoints do
		destroyCheckpoint(i)
	end
	g_Checkpoints = {}
	g_CurrentCheckpoint = nil

	for colshape,pickup in pairs(g_Pickups) do
		destroyElement(colshape)
		if pickup.object then
			destroyElement(pickup.object)
		end
		if pickup.label then
			pickup.label:destroy()
		end
	end
	g_Pickups = {}
	g_VisiblePickups = {}

	table.each(g_Objects, destroyElement)
	g_Objects = {}

	setElementData(localPlayer, 'race.checkpoint', nil)

	g_Vehicle = nil
	setPedCanBeKnockedOffBike(localPlayer, false)
	toggleControl('fire', true)
	toggleControl('next_weapon', true)
	toggleControl('previous_weapon', true)
	toggleControl('aim_weapon', true)
	setEnterExitSuicide(true)
	removeEventHandler('onClientRender', root, updateTime)

	toggleAllControls(true)

	if g_GUI then
		hideGUIComponents('timeleftbg', 'timeleft', 'healthbar', 'speedbar', 'suicidebar', 'ranknum', 'ranksuffix', 'checkpoint', 'timepassed')
		if g_GUI.hurry then
			Animation.createAndPlay(g_GUI.hurry, Animation.presets.guiFadeOut(500), destroyElement)
			g_GUI.hurry = nil
		end
	end
	TimerManager.destroyTimersFor("map")
	g_StartTick = nil
	g_HurryDuration = nil
	g_NeonRaceActive = false
	g_NeonFinishTick = nil
	if Spectate.active then
		Spectate.stop('auto')
	end
end

-- Creates the third checkpoint blip on the radar / minimap. No "physical" checkpoint, though.
function createCheckpointBlip(i, alpha)
	local checkpoint = g_Checkpoints[i]
	if not checkpoint or checkpoint.blip then return end

	local pos = checkpoint.position
	local color = checkpoint.color or cpColorRandom or { 0, 0, 255 }
	checkpoint.blip = createBlip(pos[1], pos[2], pos[3], 0, 1, color[1], color[2], color[3], alpha or 255)
	setBlipOrdering(checkpoint.blip, 1)
end

function createCheckpoint(i)
	local checkpoint = g_Checkpoints[i]
	if checkpoint.marker then
		return
	end
	local pos = checkpoint.position
	local blipSize = checkpoint.blipsize or 2
	local color = checkpoint.color or cpColorRandom or { 0, 0, 255 }
	local alpha = blipSize <= 0 and 0 or 255
	checkpoint.marker = createMarker(pos[1], pos[2], pos[3], checkpoint.type or 'checkpoint', checkpoint.size, color[1], color[2], color[3])
	if (not checkpoint.type or checkpoint.type == 'checkpoint') and i == #g_Checkpoints then
		setMarkerIcon(checkpoint.marker, 'finish')
	end
	if checkpoint.type == 'ring' and i < #g_Checkpoints then
		setMarkerTarget(checkpoint.marker, unpack(g_Checkpoints[i+1].position))
	end
	if checkpoint.blip then
		setBlipSize(checkpoint.blip, 1)
		setBlipColor(checkpoint.blip, color[1], color[2], color[3], alpha)
	else
		checkpoint.blip = createBlip(pos[1], pos[2], pos[3], 0, 1, color[1], color[2], color[3], alpha)
		setBlipOrdering(checkpoint.blip, 1)
	end
	return checkpoint.marker
end

function makeCheckpointCurrent(i,bOtherPlayer)
	local checkpoint = g_Checkpoints[i]
	local pos = checkpoint.position
	local blipSize = checkpoint.blipsize or 2
	local color = checkpoint.color or { 255, 0, 0 }
	local alpha = blipSize == 0 and 0 or 255
	if not checkpoint.blip then
		checkpoint.blip = createBlip(pos[1], pos[2], pos[3], 0, blipSize, color[1], color[2], color[3], alpha)
		setBlipOrdering(checkpoint.blip, 1)
	else
		setBlipSize(checkpoint.blip, blipSize)
	end

	local extracolshapesize = checkpoint.extracolshapesize or 4
	if not checkpoint.type or checkpoint.type == 'checkpoint' then
		checkpoint.colshape = createColCircle(pos[1], pos[2], checkpoint.size + extracolshapesize)
	elseif checkpoint.type == 'cylinder' then
		checkpoint.colshape = createColTube(pos[1], pos[2], pos[3], checkpoint.size + extracolshapesize, checkpoint.height or 2)
	else
		checkpoint.colshape = createColSphere(pos[1], pos[2], pos[3], checkpoint.size + extracolshapesize)
	end
	if not bOtherPlayer then
		addEventHandler('onClientColShapeHit', checkpoint.colshape, checkpointReached)
	end
end

function destroyCheckpoint(i)
	local checkpoint = g_Checkpoints[i]
	if not checkpoint then return end

	if checkpoint.marker then
		destroyElement(checkpoint.marker)
		checkpoint.marker = nil
	end
	if checkpoint.blip then
		destroyElement(checkpoint.blip)
		checkpoint.blip = nil
	end
	if checkpoint.colshape then
		destroyElement(checkpoint.colshape)
		checkpoint.colshape = nil
	end
end

function setCurrentCheckpoint(i, bOtherPlayer)
	destroyCheckpoint(g_CurrentCheckpoint)
	destroyCheckpoint(g_CurrentCheckpoint + 1)
	createCheckpoint(i)
	g_CurrentCheckpoint = i - 1
	showNextCheckpoint(bOtherPlayer)
end

function isPlayerRaceDead(player)
	return not getElementHealth(player) or getElementHealth(player) < 1e-45 or isPedDead(player)
end

function isPlayerFinished(player)
	return getElementData(player, 'race.finished')
end

function isPlayerSpectating(player)
	return getElementData(player, 'race.spectating')
end

addEventHandler('onClientPlayerJoin', root,
	function()
		table.insertUnique(g_Players, source)
		triggerEvent('onClientElementDataChange', localPlayer, 'race rank') -- Refresh rank display (since total players changed)
	end
)

addEventHandler('onClientPlayerSpawn', root,
	function()
		Spectate.blockAsTarget( source, 2000 ) -- No spectate at this player for 2 seconds
	end
)

addEventHandler('onClientPlayerWasted', root,
	function()
		if not g_StartTick then
			return
		end
		local player = source
		local vehicle = getPedOccupiedVehicle(player)
		if player == localPlayer then
			if #g_Players > 1 and (g_MapOptions.respawn == 'none' or g_MapOptions.respawntime >= 10000) then
				if Spectate.blockManualTimer and isTimer(Spectate.blockManualTimer) then
					killTimer(Spectate.blockManualTimer)
				end
				TimerManager.createTimerFor("map"):setTimer(Spectate.start, 2000, 1, 'auto')
			end
		else
			Spectate.dropCamera( player, 1000 )
		end
	end
)

addEventHandler('onClientPlayerQuit', root,
	function()
		table.removevalue(g_Players, source)
		Spectate.blockUntilTimes[source] = nil
		Spectate.validateTarget(source) -- No spectate at this player
		triggerEvent('onClientElementDataChange', localPlayer, 'race rank') -- Refresh rank display (since total players changed)
	end
)

addEventHandler('onClientResourceStop', resourceRoot,
	function()
		unloadAll()
		removeEventHandler('onClientRender', root, updateBars)
		killTimer(g_WaterCheckTimer)
		showHUD(true)
		setPedCanBeKnockedOffBike(localPlayer, true)
	end
)

------------------------
-- Make vehicle upright

function directionToRotation2D( x, y )
	return rem( math.atan2( y, x ) * (360/6.28) - 90, 360 )
end

function alignVehicleWithUp()
	local vehicle = g_Vehicle
	if not vehicle then return end

	local matrix = getElementMatrix( vehicle )
	local Right = Vector3D:new( matrix[1][1], matrix[1][2], matrix[1][3] )
	local Fwd	= Vector3D:new( matrix[2][1], matrix[2][2], matrix[2][3] )
	local Up	= Vector3D:new( matrix[3][1], matrix[3][2], matrix[3][3] )

	local Velocity = Vector3D:new( getElementVelocity( vehicle ) )
	local rz

	if Velocity:Length() > 0.05 and Up.z < 0.001 then
		-- If velocity is valid, and we are upside down, use it to determine rotation
		rz = directionToRotation2D( Velocity.x, Velocity.y )
	else
		-- Otherwise use facing direction to determine rotation
		rz = directionToRotation2D( Fwd.x, Fwd.y )
	end

	setElementRotation( vehicle, 0, 0, rz )
end


------------------------
-- Script integrity test

setTimer(
	function ()
		if g_Vehicle and not isElement(g_Vehicle) then
			outputChatBox( "Race integrity test fail (client): Your vehicle has been destroyed. Please panic." )
		end
	end,
	1000,0
)

---------------------------------------------------------------------------
--
-- Commands and binds
--
--
--
---------------------------------------------------------------------------


function kill()
	if Spectate.active then
		if Spectate.savePos then
			triggerServerEvent('onClientRequestSpectate', localPlayer, false )
		end
	else
		Spectate.blockManual = true
		triggerServerEvent('onRequestKillPlayer', localPlayer)
		Spectate.blockManualTimer = setTimer(function() Spectate.blockManual = false end, 3000, 1)
	end
end

function killRequest( commandName, arg1 )
	if (arg1 == "cancel") then
		if (g_KillTimer and isTimer(g_KillTimer)) then
			killTimer(g_KillTimer)
			g_KillTimer = nil
		end
		return
	end
	if g_MapOptions and g_MapOptions.bikefall then
		outputChatBox("Suicide is disabled on this map.", 255, 100, 100)
		return
	end
	if (not g_MapOptions.allowonfoot) then
		kill()
		return
	end
	if (arg1 == "immediately") then
		kill()
		return
	end
	g_KillTimer = setTimer(kill, 1000, 1)
end

addCommandHandler('kill',killRequest)
addCommandHandler('Commit suicide',killRequest)
bindKey ( next(getBoundKeys"enter_exit"), "down", "Commit suicide" )
bindKey ( next(getBoundKeys"enter_exit"), "up", "Commit suicide", "cancel" )

function spectate()
	if Spectate.active then
		if Spectate.savePos then
			triggerServerEvent('onClientRequestSpectate', localPlayer, false )
		end
	else
		if not Spectate.blockManual then
			triggerServerEvent('onClientRequestSpectate', localPlayer, true )
		end
	end
end
bindKey("b","down","Toggle spectator")
bindKey('arrow_l', 'down', 'Spectate previous')
bindKey('arrow_r', 'down', 'Spectate next')

addCommandHandler('spectate',spectate)
addCommandHandler('Toggle spectator',spectate)

function setPipeDebug(bOn)
	g_bPipeDebug = bOn
	outputConsole( 'bPipeDebug set to ' .. tostring(g_bPipeDebug) )
end

addEvent('onNextMapSet', true)

-- Custom features --
local checkpointData = {}

local function saveNosLevel(checkpointNum)
	checkpointData[checkpointNum] = {
		nosLevel = getVehicleNitroLevel(g_Vehicle),
		nosCount = getVehicleNitroCount(g_Vehicle),
		nosActivated = isVehicleNitroActivated(g_Vehicle)
	};
end
addEvent('race:saveNosLevel', true)
addEventHandler('race:saveNosLevel', resourceRoot, saveNosLevel)

local function recallNosLevel(checkpointNum)
	local data = checkpointData[checkpointNum]
	if data then
		if data.nosCount then
			setVehicleNitroCount(g_Vehicle, data.nosCount)
		end

		if data.nosLevel then
			setVehicleNitroLevel(g_Vehicle, data.nosLevel)
		end
		setVehicleNitroActivated(g_Vehicle, data.nosActivated)
	end
end
addEvent('race:recallNosLevel', true)
addEventHandler('race:recallNosLevel', resourceRoot, recallNosLevel)
---------------------
