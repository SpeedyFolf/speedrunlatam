
local last_sync_tick = 0

function syncronizeCollision(targetPlayer)
    -- Did we wait some time before flooding the server again?
    local tick = getTickCount()

    if tick < (last_sync_tick + 1000) then
        return
    end

    -- Syncronize!
    last_sync_tick = tick
    setPlayerHoldingBomb(false)
    triggerServerEvent("onBombPlayerCollision", resourceRoot, targetPlayer)
end

addEvent("onClientBombSync", true)
addEventHandler("onClientBombSync", resourceRoot,
    function (targetPlayer, updateClientTime)
        last_sync_tick = getTickCount()
        setPlayerHoldingBomb(targetPlayer, updateClientTime)
    end
)
