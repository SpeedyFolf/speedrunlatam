-- #######################################
-- ## Project: MTA FlappyBird			##
-- ## Name: cStart.lua				   ##
-- #######################################



local flappy		  = false	  -- open/closed state
local flappyKeyBound  = true	  -- we track the L keybind ourselves

-- =========================
-- Background music handling
-- =========================
local bgMusic	 = nil
local bgMuted	 = false
local bgVolume	= 0.6


local function stopBgMusic()
	if isElement(bgMusic) then
		destroyElement(bgMusic)
	end
	bgMusic = nil
end

local function startBgMusic()
	if bgMuted then return end
	if isElement(bgMusic) then return end

	bgMusic = playSound("files/sounds/flappy.mp3", true) -- loop
	if isElement(bgMusic) then
		setSoundVolume(bgMusic, bgVolume)
	end
end

local function applyMuteState()
	if bgMuted then
		-- Ensure silence (and free the handle to guarantee "stop" behavior)
		stopBgMusic()
	else
		-- If game is currently open, resume music
		if flappy == true then
			startBgMusic()
		end
	end
end

local function toggleFlappy()
	if not getElementData(localPlayer, "flappy:unlocked") then
		outputChatBox("[Flappy Baron] Not unlocked yet.", 255, 100, 100)
		return
	end

	if flappy then
		-- CLOSE (currently open)
		if flappyBirdGame and flappyBirdGame.Destructor then
			flappyBirdGame:Destructor()
		end
		showCursor(false)
		stopBgMusic()
		flappy = false
	else
		-- OPEN (currently closed)
		if type(FlappyBirdGame) ~= "table" or type(FlappyBirdGame.New) ~= "function" then
			outputDebugString("[flappy_baron] FlappyBirdGame not ready", 1)
			return
		end
		flappyBirdGame = FlappyBirdGame:New()
		startBgMusic()
		flappy = true
	end
end


addCommandHandler("flappy", function()
	toggleFlappy()
end, false)


bindKey("n", "down", function()
	-- Only allow muting while the minigame is open
	if flappy == true then
		bgMuted = not bgMuted
		applyMuteState()
		outputChatBox("[Flappy Baron] Music " .. (bgMuted and "muted" or "unmuted") .. ".", 255, 255, 255)
	end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
	-- Reset score at every map start
	setElementData(localPlayer, "flappy_baron:highscore", 0, true)
	bestScore = 0
	playerScore = 0

	outputDebugString("[flappy_baron] Highscore reset to 0 at resource start")
	for _, p in ipairs(getElementsByType("player")) do
		setElementData(p, "flappy:unlocked", true)
	end

	-- Ensure game starts locked unless story unlocks it
	setElementData(localPlayer, "flappy:unlocked", true, false)

	-- Prevent leftover UI/game state
	if flappy and flappyBirdGame and flappyBirdGame.Destructor then
		flappyBirdGame:Destructor()
		showCursor(false)
		flappy = false
	end
	stopBgMusic()
end)

addEventHandler("onPlayerJoin", root, function()
	setElementData(source, "flappy:unlocked", true) -- synced
end)

addEvent("flappy:unlock", true)
addEventHandler("flappy:unlock", root, function()
	outputDebugString("[flappy_baron] received flappy:unlock", 0)
	setElementData(localPlayer, "flappy:unlocked", true)
	outputChatBox("[Flappy Baron] You can now use /flappy", 0, 255, 255)
end)

-- Optional: re-lock again later if needed
addEvent("flappy:lock", true)
addEventHandler("flappy:lock", root, function()
	outputDebugString("[flappy_baron] received flappy:lock", 0)
	setElementData(localPlayer, "flappy:unlocked", false)

	if flappy and flappyBirdGame and flappyBirdGame.Destructor then
		flappyBirdGame:Destructor()
		showCursor(false)
		flappy = false
	end

	stopBgMusic()
end)
