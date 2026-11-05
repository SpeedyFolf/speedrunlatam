
local info_text = false
local info_off_tick = 0

local screenWidth, screenHeight = guiGetScreenSize()

local holdingBomb = false
local bombExplodeTime = false

function isPlayerHoldingBomb(player)
    return holdingBomb and (holdingBomb == player)
end

function setPlayerHoldingBomb(v, update)
    -- Update the bomb holder!
    holdingBomb = isElement(v) and v or false

    -- Reset the info text and the detonation time!
    info_text = false

    -- Is somebody holding the bomb now?
    if holdingBomb and isElement(holdingBomb) then
        if holdingBomb == localPlayer then
            info_text = "You are holding the bomb!\nRam somebody to pass the bomb to that person!"
        else
            info_text = getPlayerName(holdingBomb):gsub("#%x%x%x%x%x%x", "") .." is now holding the bomb!"
        end

        local now = getTickCount()
        info_off_tick = now + 7500

        if update then
            bombExplodeTime = now + 30000
        end
    end
end

addEventHandler("onClientVehicleExplode", root,
    function ()
        -- Did we drive this vehicle?
        local driver = getVehicleOccupant(source)

        if not driver or driver ~= localPlayer then
            return
        end

        -- We do not carry the bomb anymore!
        setPlayerHoldingBomb(false)
    end
)

addEventHandler("onClientRender", root,
    function ()
        -- Do we have any cached info?
        if not info_text then
            return
        end

        -- Is the info old?
        if getTickCount() > info_off_tick then
            info_text = false
            return
        end

        -- Draw the info!
        dxDrawText(info_text, 0, 1, screenWidth, screenHeight - 99, tocolor(0, 0, 0), 2.5, "default-bold", "center", "bottom", true, false, false, true)
        dxDrawText(info_text, 0, 0, screenWidth, screenHeight - 100, tocolor(255, 255, 255), 2.5, "default-bold", "center", "bottom", true, false, false, true)
    end
)

local camera = getCamera()

addEventHandler("onClientRender", root,
    function ()
        -- Is somebody holding the bomb?
        if not holdingBomb or not isElement(holdingBomb) then
            return
        end

        -- Is the bomb holder far away?
        local cx, cy, cz = getElementPosition(camera)
        local x, y, z = getElementPosition(holdingBomb)
        local distance = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)

        if distance <= 300 then
            -- Is he on the screen?
            local sx, sy = getScreenFromWorldPosition(x, y, z + 2, 0.07)

            if sx and sy then
                -- Draw the bomb image above his car!
                local distance_scale = math.max(0.25, math.min(0.40, 300 / distance))
                local width = 186 * distance_scale
                local height = 256 * distance_scale

                dxDrawImage(sx - width / 2, sy - height / 2, width, height, "bomb.png")

                -- Do we have the detonation tick?
                if not bombExplodeTime then
                    return
                end

                -- Do we have any remaining time?
                local now = getTickCount()
                local remaining = math.max(0, bombExplodeTime - now)

                if remaining <= 0 then
                    bombExplodeTime = false
                    return
                end

                -- Move the sy screen position down!
                sy = sy + 40 * distance_scale

                -- Draw the remaining time!
                local text = ("%d.%03d"):format(remaining / 1000, (remaining % 1000))
                dxDrawText(text, sx, sy + 1, nil, nil, tocolor(0, 0, 0), 1, "default-bold", "center", "bottom", true, false, false, true)
                dxDrawText(text, sx, sy, nil, nil, tocolor(255, 0, 0), 1, "default-bold", "center", "bottom", true, false, false, true)
            end
        end
    end
)
