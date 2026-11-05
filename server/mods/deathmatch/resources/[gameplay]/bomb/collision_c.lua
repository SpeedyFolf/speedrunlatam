
addEventHandler("onClientVehicleCollision", root,
    function (target, force)
        -- Do we have to check the collision?
        if not isPlayerHoldingBomb(localPlayer) then
            return
        end

        -- Is the counter-part a vehicle?
        if not isElement(target) or getElementType(target) ~= "vehicle" then
            return
        end

        -- Is the vehicle blown?
        if isVehicleBlown(source) or isVehicleBlown(target) then
            return
        end

        -- Is this our vehicle?
        local driver = getVehicleOccupant(source)
        if not driver or driver ~= localPlayer or isPedDead(driver) then
            return
        end

        -- Is somebody driving the other vehicle?
        local driver = getVehicleOccupant(target)
        if not driver or isPedDead(driver) then
            return
        end

        -- We collided with somebody!
        syncronizeCollision(driver)
    end
)

addEventHandler("onClientVehicleDamage", root,
    function ()
        -- Does the bomb player drive this car?
        local driver = getVehicleOccupant(source)
        if not driver or not isPlayerHoldingBomb(driver) then
            return
        end

        -- Godmode!
        cancelEvent()
    end
)
