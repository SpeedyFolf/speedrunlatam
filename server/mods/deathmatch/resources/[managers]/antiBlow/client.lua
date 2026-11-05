local ghostMode = false

local function triggerVisualExplosion(vehicle)
	createEffect('explosion_medium', vehicle.position.x, vehicle.position.y, vehicle.position.z, 0, 0, 0)
	local sound = playSFX3D('genrl', 45, 4, vehicle.position.x, vehicle.position.y, vehicle.position.z)
	if sound then
		sound.volume = 1
	end
end

local function onClientExplosion(x, y, z, theType)
	if not ghostMode then
		return
	end

	if theType < 4 or theType > 5 then -- Not a vehicle explosion
		return
	end

	if source.type == 'player' then
		cancelEvent()
		triggerVisualExplosion(source)
	end
end
addEventHandler('onClientExplosion', root, onClientExplosion)

local function onMapStarting(_ghostMode)
	ghostMode = _ghostMode
end
addEvent('antiBlow:onMapStarting', true)
addEventHandler('antiBlow:onMapStarting', resourceRoot, onMapStarting)
