
local holdingBomb = false
local previousHolder = false
local previousVehicle = false
local bombSwitchTick = 0
local bombTimer = false

addEvent("onRaceStateChanging")
addEventHandler("onRaceStateChanging", root,
    function (newState)
        -- Did the round start?
        if newState ~= "Running" then
            return
        end

        -- The round has started!
        giveSomebodyTheBomb()
    end
)

function giveSomebodyTheBomb(ignore)
    if isTimer(bombTimer) then
        killTimer(bombTimer)
    end

    -- Get a random alive player
    local player = getRandomAlivePlayer(ignore or false)

    -- Nobody found?
    if not player then
        return
    end

    -- Give him the bomb!
    givePlayerBomb(player, true)

    -- Start the timer for the explosion (30 seconds + sync time)
    bombTimer = setTimer(detonateBomb, 30000 + 100, 1)
end

function detonateBomb()
    -- Cache the variables!
    local bombPlayer = holdingBomb
    holdingBomb = false

    -- Syncronize the holder!
    syncronizeBombHolder(false, false)

    -- Is somebody holding the bomb?
    if isElement(bombPlayer) then
        -- Is he in a vehicle?
        local vehicle = getPedOccupiedVehicle(bombPlayer)

        if vehicle then
            -- Switch time difference
            bombSwitchTick = getTickCount() - bombSwitchTick

            -- Detonate him!
            local x, y, z = getElementPosition(vehicle)
            createExplosion(x, y, z, 5, (bombSwitchTick <= 8000) and previousHolder or nil)

            setTimer(
                function()
                    if isElement(vehicle) then
                        blowVehicle(vehicle, false)
                    end
                end,
                150, 1)

            -- Reset the previous holder!
            previousHolder = false
            bombSwitchTick = 0
        end
    end

    -- Wait a little bit and give the bomb to someone!
    setTimer(giveSomebodyTheBomb, 300, 1)
end

function givePlayerBomb(targetPlayer, updateClientTime)
    -- Is the player valid?
    if not isElement(targetPlayer) or getElementType(targetPlayer) ~= "player" then
        return
    end

    -- Did somebody hold the bomb before him?
    if isElement(holdingBomb) then
        previousHolder = holdingBomb
        bombSwitchTick = getTickCount()
        updatePlayerVehicle(previousHolder, previousVehicle or 475)
        previousVehicle = false
    end

    local vehicle = getPedOccupiedVehicle(targetPlayer)
    if not vehicle then
        return
    end

    -- Syncronize the new holder
    holdingBomb = targetPlayer
    syncronizeBombHolder(targetPlayer, updateClientTime)

    local vehicletype = getVehicleType(vehicle)
    previousVehicle = getElementModel(vehicle)

    local nextVehicle = 495 -- Sandking

    if vehicletype == "Helicopter" then
        nextVehicle = 487 -- Maverick
    elseif vehicletype == "Bike" then
        nextVehicle = 522 -- NRG-500
    elseif previousVehicle == 520 then
        nextVehicle = 520 -- Hydra
    elseif vehicletype == "Boat" then
        nextVehicle = 493 -- Jetmax
    elseif vehicletype == "Plane" then
        nextVehicle = 513 -- Stuntplane
    end

    updatePlayerVehicle(holdingBomb, nextVehicle)
end

function updatePlayerVehicle(player, model)
    if isElement(player) then
        local vehicle = getPedOccupiedVehicle(player)
        if isElement(vehicle) then
            local x, y, z = getElementPosition(vehicle)
            setElementModel(vehicle, model)
            setElementPosition(vehicle, x, y, z + 1.5)
            fixVehicle(vehicle)
        end
    end
end

function getRandomAlivePlayer(ignore)
    -- Get the players, who are alive!
    local alivePlayers = getAlivePlayers()

    -- Do we have any alive player?
    if not alivePlayers or #alivePlayers == 0 then
        return
    end

    local chosen = false

    -- Search for a good candidate!
    repeat
        chosen = table.remove(alivePlayers, math.random(#alivePlayers))
    until   (isElement(chosen) and getNetworkStats(chosen) and chosen ~= ignore and getElementData(chosen, "state") == "alive")
            or #alivePlayers == 0

    return chosen
end

addEventHandler("onPlayerQuit", root,
    function ()
        -- Did our bomb holder leave?
        if source == holdingBomb then
            -- Give somebody the bomb!
            giveSomebodyTheBomb(source)
        end
    end
)

addEventHandler("onPlayerWasted", root,
    function ()
        -- Did our bomb holder die?
        if source == holdingBomb then
            -- Give somebody the bomb!
            giveSomebodyTheBomb()
        end
    end
)
