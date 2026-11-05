iprint("[Anti World Blow] Functional")

EXPLOSION_DESIRE_TIMER_LENGTH = 100

VEHICLE_EXPLOSIONS = {
	[4] = true, -- Car explosion
	[5] = true, -- RC Tiger Bandit Explosion
	[6] = true, -- Boat explosion
	[7] = true, -- Heli or plane explosion
	-- [9] = true, -- Barrel, Pump explosion (world)
	-- [12] = true, -- Other RC explosion
	-- [51] = true, -- Barrel, Pump explosion (custom)
}

EXPLOSIVE_PROPS = {
	[1244] = true, -- petrolpump
	[1225] = true, -- barrel4
	[1370] = true, -- CJ_FLAME_Drum_(F)
	[1676] = true, -- washgaspump
	[1686] = true, -- petrolpumpnew
}

EXPLOSIVE_PROPS_BROKEN_COL_DETECTION = {
	[1225] = true, -- barrel4
	[1370] = true, -- CJ_FLAME_Drum_(F)
}

local iWantToExplodeTimer = 0
local nearBarrel4 = false
local fuelImpact = false
local ghostMode = false
local vehicleWeapons = false

addEventHandler("onClientExplosion", root,
	function(x,y,z, theType)
		if not ghostMode or not vehicleWeapons then return end -- Everything goes in collision races
		if (VEHICLE_EXPLOSIONS[theType]) then
			-- Car explosion. Cancel this, and play a dummy explosion in its place.
			createExplosion(x,y,z,0,true,-1.0,false)
			cancelEvent()
		elseif (theType == 12) then
			-- RC vehicles (not Bandit or Tiger), smaller explosions
			createExplosion(x,y,z,12,true,-1.0,false)
			cancelEvent()
		elseif (theType == 9) then
			-- Gas pumps, explosive barrels, etc. BASE GTASA WORLD PROPS ONLY. Custom placed ones trigger 51 instead.
			-- Only blow us up if we touched a gas pump recently (<100ms ago), this means we likely are the ones who triggered it
			iprint("[Anti World Blow] Sensing world gas pump explosion. Time since last impact: "..iWantToExplodeTimer)
			if (iWantToExplodeTimer <= 0) then
				cancelEvent()
			end
		elseif (theType == 51) then
			-- Custom gas pumps, etc.
			-- Unlike 9, this gets called first. Then the collision detection happens, and then the damage is applied.
			local veh = getPedOccupiedVehicle(localPlayer)
			if not veh then return end
			local xp,yp,zp = getElementPosition(veh)
			local range = RADII[getElementModel(veh)]/2
			local distance = getDistanceBetweenPoints3D(x,y,z,xp,yp,zp)

			-- we need to do a manual check for nearby red barrels, since they don't trigger a collision detection...
			-- this will trigger false positives, but it's better than having everyone explode.
			local objects = getElementsWithinRange(xp,yp,zp,range,"object")
			local barrel4found = false
			for i, o in pairs(objects) do
				local m = getElementModel(objects[i])
				if EXPLOSIVE_PROPS_BROKEN_COL_DETECTION[m] then
					iprint("[Anti World Blow] Explosion: Explosive barrel or propane flask at range "..distance.." out of "..range.." from vehicle model"..m..". Threshold: "..distance)
					barrel4found = true
					break
				end
			end
			if (not barrel4found) then
				-- cancelEvent()
			else
				nearBarrel4 = true
			end
		end
	end
)

addEventHandler("onClientVehicleDamage", root,
	function(theAttacker, theWeapon, loss, damagePosX, damagePosY, damagePosZ, tireID)
		if not ghostMode or not vehicleWeapons then return end -- Everything goes in collision races
		if (theWeapon == 37) then return end -- Stop spamming us with fire damage
		if (not theWeapon) then return end
		if (source ~= getPedOccupiedVehicle(localPlayer)) then return end -- Dont care about calculating other people's stuff
		local players = getElementsByType("player")
		local playerCars = {}
		local localPlayerIndex = 0
		for i, p in pairs(players) do
			if (p == localPlayer) then
				localPlayerIndex = i
			else
				local playerCar = getPedOccupiedVehicle(p)
				if (playerCar) then
					table.insert(playerCars, playerCar)
				end
			end
		end
		table.remove(players, localPlayerIndex)
		local localVehicle = getPedOccupiedVehicle(localPlayer)

		if (players[theAttacker] or playerCars[theAttacker]) then
			-- Cancel damage from other players, including tanks, hunters, etc. on Ghost Mode.
			-- This should still allow damage taken by AIs, scripts, etc.
			cancelEvent()
		end
		if (theWeapon == 51) then
			if (nearBarrel4) then
				-- We are near a red barrel, we probably hit it. Maybe. IDK.
				-- cancelEvent()
				iprint("[Anti World Blow] KABOOM! You got blown by a nearby barrel4 or propane flask")
				nearBarrel4 = false
				return
			elseif (fuelImpact) then
				-- We just hit a pump, don't cancel the damage.
				iprint("[Anti World Blow] KERBLAM! Caught in an explosion after a collision with a pump")
				fuelImpact = false
				return
			else
				cancelEvent()
			end
		end
	end
)

addEventHandler("onClientVehicleCollision", root,
	function(collider, damageImpulseMag, bodyPart, x, y, z, nx, ny, nz, force, model)
		if not ghostMode or not vehicleWeapons then return end -- Everything goes in collision races
		if (source ~= getPedOccupiedVehicle(localPlayer)) then return end -- Ignore when others hit shit
		if (EXPLOSIVE_PROPS[model]) then
			iprint("[Anti World Blow] Made collision with explosive prop numbered "..model)
			fuelImpact = true
			iWantToExplodeTimer = EXPLOSION_DESIRE_TIMER_LENGTH + getPlayerPing(localPlayer)*2
		end
	end
)

function explodeTimer(deltaTime)
	iWantToExplodeTimer = iWantToExplodeTimer - deltaTime
end
addEventHandler("onClientPreRender", root, explodeTimer)

local function onMapStarting(_ghostMode, _vehicleWeapons)
	ghostMode = _ghostMode
	vehicleWeapons = _vehicleWeapons
end
addEvent('antiWorldBlow:onMapStarting', true)
addEventHandler('antiWorldBlow:onMapStarting', resourceRoot, onMapStarting)
