-- Keep track of the player's water state to prevent spamming the function
local wasInWater = false

-- Hide the breath bar by default when the resource starts
addEventHandler("onClientResourceStart", resourceRoot, function()
	setPlayerHudComponentVisible("breath", false)
end )

-- Function to check if the player is in water
local function checkWaterState()
	-- Ensure the local player exists
	if not isElement(localPlayer) then
		return
	end

	local isInWater = isElementInWater(localPlayer)

	-- If the player just entered the water
	if isInWater and not wasInWater then
		setPlayerHudComponentVisible("breath", true)
		wasInWater = true

	-- If the player just left the water
	elseif not isInWater and wasInWater then
		setPlayerHudComponentVisible("breath", false)
		wasInWater = false
	end
end

-- Run the check every 250 milliseconds (0.25 seconds)
-- This is fast enough to feel instant without impacting game performance
setTimer(checkWaterState, 250, 0)
