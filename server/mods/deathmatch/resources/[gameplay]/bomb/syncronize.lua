
function syncronizeBombHolder(targetPlayer, updateClientTime)
    triggerClientEvent("onClientBombSync", resourceRoot, targetPlayer, updateClientTime)
end

addEvent("onBombPlayerCollision", true)
addEventHandler("onBombPlayerCollision", resourceRoot,
    function (targetPlayer)
        -- Is the player valid?
        if not isElement(targetPlayer) or getElementType(targetPlayer) ~= "player" then
            return
        end

        -- Give him the bomb!
        givePlayerBomb(targetPlayer)
    end
)
