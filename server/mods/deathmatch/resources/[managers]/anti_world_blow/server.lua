local ghostMode = false
local vehicleWeapons = false

local function onMapStarting(mapInfo, mapOptions, gameOptions)
	ghostMode = mapOptions.ghostmode
	vehicleWeapons = mapOptions.vehicleweapons

	triggerClientEvent('antiWorldBlow:onMapStarting', resourceRoot, ghostMode, vehicleWeapons)
end
addEvent('onMapStarting', true)
addEventHandler('onMapStarting', root, onMapStarting)

local function onPlayerJoin()
	triggerClientEvent(source, 'antiWorldBlow:onMapStarting', resourceRoot, ghostMode, vehicleWeapons)
end
addEventHandler('onPlayerJoin', resourceRoot, onPlayerJoin)
