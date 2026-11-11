-- Modo espectador: la camara sigue al objetivo que fija el servidor (sr:spectate).
-- Flechas izquierda / derecha piden el jugador anterior / siguiente (sr:spectateNext).
SR = SR or {}

local target = nil

addEvent("sr:spectate", true)

addEventHandler("sr:spectate", resourceRoot, function(newTarget)
    if isElement(newTarget) then
        target = newTarget
        SR.spectating = true
        setCameraTarget(target)
        -- Al pasar a espectar (abandono o fin) el reloj del HUD se apaga.
        if SR.resetRound then SR.resetRound() end
    else
        target = nil
        SR.spectating = false
        setCameraTarget(localPlayer)
    end
end)

local function requestNext(dir)
    if SR.spectating then triggerServerEvent("sr:spectateNext", resourceRoot, dir) end
end

bindKey("arrow_l", "down", function() requestNext(-1) end)
bindKey("arrow_r", "down", function() requestNext(1) end)

-- B: alternar entre jugar (timer desde 0) y espectar.
bindKey("b", "down", function() triggerServerEvent("sr:toggleSpectate", resourceRoot) end)

-- La camara puede soltarse si el objetivo sale del radio de streaming un momento: se reafirma.
setTimer(function()
    if SR.spectating then
        if isElement(target) then
            local cam = getCameraTarget()
            -- Con el objetivo en un vehiculo la camara puede apuntar al vehiculo: eso es correcto.
            if cam ~= target and not (cam and cam == getPedOccupiedVehicle(target)) then setCameraTarget(target) end
        else
            target = nil
        end
    end
end, 500, 0)

addEventHandler("onClientRender", root, function()
    if not SR.spectating then return end
    local sw, sh = guiGetScreenSize()
    local ui, drawText = SR.ui, SR.drawText
    local name = isElement(target) and getPlayerName(target):gsub("#%x%x%x%x%x%x", "") or "..."
    drawText("Espectando: " .. name, 0, sh - ui(120), sw, sh - ui(80), tocolor(255, 255, 255, 255), ui(1.4), "bankgothic")
    drawText("Flecha izquierda / derecha: cambiar de jugador", 0, sh - ui(80), sw, sh - ui(50),
        tocolor(220, 220, 220, 255), ui(1.1), "default-bold")
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if SR.spectating then setCameraTarget(localPlayer) end
end)

-- Seguridad: aunque el ped este congelado en el cielo, cancelar cualquier dano
-- mientras se especta (evita muertes por atropello si algo se desincroniza).
addEventHandler("onClientPlayerDamage", localPlayer, function()
    if SR.spectating then cancelEvent() end
end)
