-- Settings
local STUNT_MIN_DISTANCE = 400.0
local STUNT_MIN_HEIGHT = 40.0
local SPECIAL_STUNT_MIN_DISTANCE = 20.0

-- Screen stuff
local screenX, screenY = guiGetScreenSize()
local stuntTextMode, stuntText = false, nil

-- Stunts
local state = "init"

local stuntPrevPos = {x = 0.0, y = 0.0, z = 0.0}
local stuntPrevRot = {x = 0.0, y = 0.0, z = 0.0}
local stuntCarUpsideDown = false
local stuntRolls, stuntRot = 0, 0
local updateWheelStateTimer = nil

local stuntVehicle

-- Anti-Teleport
local oldPos, DPos

function updateWheelState()
	if not getPedOccupiedVehicle(localPlayer) or getElementData(localPlayer, "state") == "spectating" or stuntTextMode then
		-- Cancel stunt
		state = "init"
		return
	end

	local x, y, z = getElementPosition(getPedOccupiedVehicle(localPlayer))
	local vehicle = getPedOccupiedVehicle(localPlayer)
	local vehicleType = getVehicleType(vehicle)

	-- Teleport prevention
	if not oldPos then
		-- Initialization
		oldPos = {x = x, y = y, z = z}
		DPos = 0
	else
		-- Calculations
		DPos = math.abs(x - oldPos.x) + math.abs(y - oldPos.y) + math.abs(z - oldPos.z)
		oldPos = {x = x, y = y, z = z}

		if DPos > 50 or vehicleType == "Monster Truck" then
			state = "init"
			return
		end
	end

	-- Check for vehicle types
	if getVehicleType(vehicle) == "Train" or getVehicleType(vehicle) == "Plane" or getVehicleType(vehicle) == "Helicopter" or getVehicleType(vehicle) == "Boat" or z > 15000
	or isWorldSpecialPropertyEnabled("aircars") or math.abs(getGravity() - 0.008) > 0.001 or (stuntVehicle and getElementModel(vehicle) ~= stuntVehicle) then
		-- Cancel stunt
		state = "init"
		return
	end

	-- Check wheels
	if not isVehicleWheelsOnGround(vehicle) and state ~= "init" then
		-- Vehicle's wheels not touching the ground

		if state == "ground" and not isVehicleUpsideDown(vehicle) then
			-- First time vehicle in the air, previously vehicle was on wheels
			-- Just an initialization
			stuntPrevPos.x, stuntPrevPos.y, stuntPrevPos.z = getElementPosition(vehicle)
			stuntPrevRot.x, stuntPrevRot.y, stuntPrevRot.z = getElementRotation(vehicle)

			stuntRolls = 0
			stuntRot = 0
			stuntCarUpsideDown = false
			stuntVehicle = getElementModel(vehicle)

			state = "air"
		elseif state == "air" then
			-- Vehicle already in the air, so update stunt data

			-- Update Flips
			if isVehicleUpsideDown(vehicle) and not stuntCarUpsideDown then stuntCarUpsideDown = true end
			if not isVehicleUpsideDown(vehicle) and stuntCarUpsideDown then
				stuntCarUpsideDown = false
				stuntRolls = stuntRolls + 1
			end

			-- Update Rotations
			local rX, rY, rZ = getElementRotation(vehicle)
			local heading_difference = rZ - stuntPrevRot.z
			local heading_difference_temp = 0.0

			if heading_difference > 180.0 then
				heading_difference_temp = heading_difference
				heading_difference = 360.0 - heading_difference_temp
			else
				if heading_difference < -180.0 then
					heading_difference_temp = heading_difference
					heading_difference = 360.0 + heading_difference_temp
				end
			end

			if heading_difference < 0.0 then
				heading_difference_temp = heading_difference
				heading_difference = 0.0 - heading_difference_temp
			end

			stuntRot = stuntRot + heading_difference
		end
	else
		-- Vehicle wheels on ground or initialization happens
		if state == "init" and isVehicleWheelsOnGround(vehicle) then
			-- Vehicle touched ground first time
			state = "ground"
			return
		end

		-- Any wheel of the vehicle on the ground
		if state == "air" then
			-- Vehicle previously was in the air
			-- Finish the stunt
			local sX, sY, sZ = getElementPosition(vehicle)
			local rX, rY, rZ = getElementRotation(vehicle)
			local stunts = 0

			-- Records
			local stuntData = {
				type = 1,
				money = 0,
				[1] = getDistanceBetweenPoints2D(sX, sY, stuntPrevPos.x, stuntPrevPos.y),
				[2] = math.abs(stuntPrevPos.z - sZ),
				[3] = stuntRolls,
				[4] = stuntRot
			}

			--iprint(stuntData[1], stuntData[2], stuntData[3], stuntData[4])

			-- Distance
			if stuntData[1] > STUNT_MIN_DISTANCE then
				stunts = stunts + 1
			end

			-- Height
			if stuntData[2] > STUNT_MIN_HEIGHT then
				stunts = stunts + 1
			end

			-- 2 ROLLS/FLIPS IN MID AIR
			if stuntData[3] > 1 and stunts > 0 then
				stunts = stunts + 1
			end

			-- Rotation > 360 dgr
			if stuntData[4] > 360.0 and stunts > 0 then
				stunts = stunts + 1
			end

			if stunts > 0 then
				-- Money
				local moneyReward = math.abs(math.floor((stuntRolls * 180 + math.floor(stuntRot * 10) / 10 + (math.floor(getDistanceBetweenPoints2D(sX, sY, stuntPrevPos.x, stuntPrevPos.y) * 10) / 10) * 6 + (math.floor((stuntPrevPos.z - sZ) * 10) / 10) * 45) * stunts / 15))
				givePlayerMoney(moneyReward or 0)
				setElementData(localPlayer, "Money", (getElementData(localPlayer, "Money") or 0) + (moneyReward or 0))
				stuntData.money = moneyReward

				-- Process text
				if stunts == 1 then stuntText = "INSANE STUNT BONUS:"
				elseif stunts == 2 then stuntText = "DOUBLE INSANE STUNT BONUS:"
				elseif stunts == 3 then stuntText = "TRIPLE INSANE STUNT BONUS:"
				elseif stunts == 4 then stuntText = "QUADRUPLE INSANE STUNT BONUS:" end

				stuntText = stuntText .. " $" .. moneyReward
				stuntTextMode = true

				setTimer(function()
					stuntText = "Distance: " ..(math.floor(getDistanceBetweenPoints2D(sX, sY, stuntPrevPos.x, stuntPrevPos.y)*10)/10).. "m Height: " ..math.abs((math.floor((stuntPrevPos.z - sZ)*10)/10)).. "m Flips: " ..stuntRolls.. " Rotation: " ..math.floor(stuntRot).. "°"
				end, 3500, 1)
				setTimer(function() stuntTextMode = false end, 7000, 1)

				triggerServerEvent("checkStunt", localPlayer, stuntData)
			end

			stuntVehicle = nil
			state = "init"
		end
	end
end

addEventHandler("onClientResourceStart", root, function()
	if not isTimer(updateWheelStateTimer) then
		updateWheelStateTimer = setTimer(updateWheelState, 200, 0)
	end

	state = "init"
end )

addEventHandler("onClientRender", root, function()
	if not stuntTextMode or not stuntText then return end
	dxDrawBorderedText(2, stuntText, 0, 0, screenX, screenY*0.98, tocolor(240, 240, 240, 255), screenY / 1350, "default-bold", "center", "bottom", true, false)
end )

addEventHandler("onClientPlayerStuntStart", root, function()
	-- Store vehicle model
	if getPedOccupiedVehicle(localPlayer) then
		stuntVehicle = getElementModel(getPedOccupiedVehicle(localPlayer))
	else stuntVehicle = nil end
end )

addEventHandler("onClientPlayerStuntFinish", root, function(stuntType, stuntTime, stuntDistance)
	-- Cancel stunt if distance too small, already showing stunt text or distance > 20000
	if stuntDistance < SPECIAL_STUNT_MIN_DISTANCE or stuntTime < 2000 or stuntTextMode or stuntDistance > 20000 then return end
	local stuntCategory, stuntMoney = nil, 0
	stuntTime = stuntTime / 1000

	if getPedOccupiedVehicle(localPlayer) and getElementModel(getPedOccupiedVehicle(localPlayer)) ~= stuntVehicle then
		-- Fail the stunt if vehicle model has changed
		return
	end

	if stuntType == "stoppie" then
		stuntText = "STOPPIE"
		stuntCategory = 2
		stuntMoney = math.floor(stuntDistance / 2)
	elseif stuntType == "wheelie" then
		stuntText = "WHEELIE"
		stuntCategory = 3
		stuntMoney = math.floor(stuntDistance / 5)
	elseif stuntType == "2wheeler" then
		stuntText = "TWO WHEELS DOUBLE"
		stuntCategory = 4
		stuntMoney = math.floor((stuntTime + stuntDistance) / 2)
	end

	stuntVehicle = nil

	-- Give money
	givePlayerMoney(stuntMoney)

	-- Show stunt text
	stuntText = stuntText.. " BONUS: $" ..stuntMoney.. " Distance: " ..math.floor(stuntDistance).. "m Time: " ..string.format("%.1f", stuntTime).. " seconds"
	stuntTextMode = true
	setTimer(function() stuntTextMode = false end, 3000, 1)

	-- Update leaderboards
	triggerServerEvent("checkStunt", localPlayer, {type = stuntCategory, [1] = stuntDistance, [2] = stuntTime, money = stuntMoney})
end )
