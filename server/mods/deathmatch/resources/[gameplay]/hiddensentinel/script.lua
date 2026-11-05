SENTINEL = nil

function spawnSentinel()
    local _sentinel = getElementsByType("sentinel")[1]
	local model = getElementData(_sentinel, "model")
	local x, y, z = getElementPosition(_sentinel)
	local u = getElementData(_sentinel, "rotX")
	local v = getElementData(_sentinel, "rotY")
	local w = getElementData(_sentinel, "rotZ")
	local numberplate = getElementData(_sentinel, "plate")
	local color = getElementData(_sentinel, "color")
	local colors = {}
	for token in string.gmatch(color, "([^,]+)") do
		table.insert(colors, token)
	end
	if (SENTINEL) then
		destroyElement(SENTINEL)
	end
	SENTINEL = createVehicle(model, x, y, z, u, v, w, numberplate)
	setVehicleColor(SENTINEL, unpack(colors))
end
addEventHandler("onMapStarting",root,spawnSentinel)
addEventHandler("onResourceStart",resourceRoot,spawnSentinel)
