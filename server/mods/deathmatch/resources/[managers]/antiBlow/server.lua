local ghostMode = false

local function onMapStarting(mapInfo, mapOptions, gameOptions)
	ghostMode = mapOptions.ghostmode

	triggerClientEvent('antiBlow:onMapStarting', resourceRoot, ghostMode)
end
addEvent('onMapStarting', true)
addEventHandler('onMapStarting', root, onMapStarting)

local function onPlayerJoin()
	triggerClientEvent(source, 'antiBlow:onMapStarting', resourceRoot, ghostMode)
end
addEventHandler('onPlayerJoin', resourceRoot, onPlayerJoin)

local function onRequestKillPlayer() -- source: player
	triggerEvent('onRequestKillPlayer', source)
end
addEvent('antiBlow:onRequestKillPlayer', true)
addEventHandler('antiBlow:onRequestKillPlayer', resourceRoot, onRequestKillPlayer)
