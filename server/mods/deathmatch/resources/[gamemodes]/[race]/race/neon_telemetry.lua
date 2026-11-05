-- neon_ui / telemetry.lua
-- Tarjeta compacta arriba a la derecha con salud y velocidad del vehiculo.
-- Reemplaza las barras stock del gamemode race (ver docs/RUNBOOK.md).

local enabled = true
local alpha = 0
local lastTick = getTickCount()

local shownHealth = 1
local shownSpeed = 0

local function currentVehicle()
	local vehicle = getPedOccupiedVehicle(localPlayer)
	if vehicle and isElement(vehicle) then
		return vehicle
	end
	return nil
end

-- La tarjeta cian es el unico indicador de vida: las barras vanilla
-- (salud, respiracion y chaleco) se ocultan siempre.
local HIDDEN_COMPONENTS = { "health", "breath", "armour" }

local function hideVanillaBars()
	for _, component in ipairs(HIDDEN_COMPONENTS) do
		setPlayerHudComponentVisible(component, false)
	end
end

hideVanillaBars()
addEventHandler("onClientResourceStart", resourceRoot, hideVanillaBars)
addEventHandler("onClientPlayerSpawn", root, hideVanillaBars)
addEventHandler("onClientPlayerWasted", root, hideVanillaBars)
addEventHandler("onClientRestore", root, hideVanillaBars)
setTimer(hideVanillaBars, 1000, 0)
addEventHandler("onClientResourceStop", resourceRoot, function()
	for _, component in ipairs(HIDDEN_COMPONENTS) do
		setPlayerHudComponentVisible(component, true)
	end
end)

local function healthColor(ratio)
	if ratio <= 0.25 then
		return NeonUI.colors.bad
	elseif ratio <= 0.5 then
		return NeonUI.colors.warn
	end
	return NeonUI.colors.good
end

local function render()
	local now = getTickCount()
	local dt = (now - lastTick) / 1000
	lastTick = now
	if dt > 0.25 then
		dt = 0.25
	end

	local vehicle = currentVehicle()
	local target = enabled and 1 or 0
	NeonUI.telemetryVisible = (target == 1)

	alpha = alpha + (target - alpha) * math.min(1, dt * 12)
	if alpha < 0.01 then
		alpha = 0
		return
	end

	local targetHealth = shownHealth
	local targetSpeed = shownSpeed
	if vehicle then
		targetHealth = math.max(0, math.min(1, getElementHealth(vehicle) / 1000))
		local vx, vy, vz = getElementVelocity(vehicle)
		targetSpeed = math.sqrt(vx * vx + vy * vy + vz * vz) * 180
	else
		-- A pie: salud del jugador, sin velocidad.
		targetHealth = math.max(0, math.min(1, getElementHealth(localPlayer) / 100))
		targetSpeed = 0
	end

	-- Suavizado: la barra persigue el valor real en vez de saltar.
	local smooth = 1 - math.exp(-dt * 9)
	if alpha < 0.05 then
		shownHealth = targetHealth
		shownSpeed = targetSpeed
	else
		shownHealth = shownHealth + (targetHealth - shownHealth) * smooth
		shownSpeed = shownSpeed + (targetSpeed - shownSpeed) * smooth
	end
	local healthAnim = shownHealth

	local s = NeonUI.scale
	local a = alpha
	local w = NeonUI.cardW
	local h = NeonUI.telemetryH
	local x = NeonUI.screenW - NeonUI.margin - w
	local y = NeonUI.margin
	local pad = NeonUI.pad

	NeonUI.card(x, y, w, h, a)

	local color = healthColor(healthAnim)
	dxDrawRectangle(x, y, math.max(2, NeonUI.i(2)), h, NeonUI.tcol(color, a), true)

	local rowTop = y + NeonUI.i(9)
	local rowBottom = y + NeonUI.i(41)

	dxDrawText("SALUD", x + pad, rowTop, x + w - pad, rowBottom,
		NeonUI.tcol(NeonUI.colors.dim, a), NeonUI.px(0.9), "default-bold",
		"left", "center", true, false, false)

	dxDrawText(math.floor(healthAnim * 100 + 0.5) .. "%",
		x + pad + NeonUI.i(64), rowTop, x + w - pad, rowBottom,
		NeonUI.tcol(NeonUI.colors.text, a), NeonUI.px(1.1), "default-bold",
		"left", "center", true, false, false)

	dxDrawText(math.floor(shownSpeed + 0.5) .. " KM/H",
		x + pad, rowTop, x + w - pad, rowBottom,
		NeonUI.tcol(NeonUI.colors.text, a), NeonUI.px(1.15), "default-bold",
		"right", "center", true, false, false)

	local barX = x + pad
	local barY = y + NeonUI.i(50)
	local barW = w - pad * 2
	local barH = math.max(4, NeonUI.i(8))

	NeonUI.track(barX, barY, barW, barH, a)
	dxDrawRectangle(barX, barY, barW * healthAnim, barH, NeonUI.tcol(color, a), true)

	-- Pulso suave cuando el vehiculo esta para explotar.
	if healthAnim <= 0.25 and healthAnim > 0 then
		local pulse = (math.sin(now / 210) + 1) * 0.5
		dxDrawRectangle(barX, barY - NeonUI.i(2), barW * healthAnim, barH + NeonUI.i(4),
			NeonUI.tcol(NeonUI.colors.bad, a * 0.3 * pulse), true)
	end
end

addEventHandler("onClientRender", root, render)

addCommandHandler("hud", function()
	enabled = not enabled
	outputChatBox("[NEON] HUD del vehiculo " .. (enabled and "activado" or "desactivado") .. ".",
		0, 200, 255)
end)
