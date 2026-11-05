-- Helper function to safely start a resource by name
local function safelyStartResource(resourceName)
	local res = getResourceFromName(resourceName)
	if res then
		-- Passing 'true' makes it persistent.
		startResource(res, true)
	else
		outputDebugString("[sup] Failed to start: " .. tostring(resourceName) .. " (Resource not found)", 2)
	end
end

-- Helper function to safely restart a resource by name
local function safelyRestartResource(resourceName)
	local res = getResourceFromName(resourceName)
	if res then
		if getResourceState(res) == "running" then
			restartResource(res, true)
		else
			-- If it wasn't running yet, just start it cleanly
			startResource(res, true)
		end
	else
		outputDebugString("[sup] Failed to restart: " .. tostring(resourceName) .. " (Resource not found)", 2)
	end
end

-- Trigger instantly when you manually start this resource
addEventHandler("onResourceStart", resourceRoot, function()
	outputDebugString("[sup] Initializing managed resources...")

	-- Start the Twitch emote resources
	safelyStartResource("twitch_emotes_ext")
	safelyStartResource("twitch_emotes_sub")
	safelyStartResource("twitch_emotes_glob")
	safelyStartResource("twitch_emotes_core")

	-- Restart the race progress UI resources so they hook into the active map correctly
	safelyRestartResource("race_progress")
	safelyRestartResource("race_progress_3d")

	outputDebugString("[sup] All managed resources have been processed.")
end )

local targetAccount = "Joshimuz"
local settingName = "*votemanager.votemap_enabled"

-- Disable votemap when Joshimuz logs in
addEventHandler("onPlayerLogin", root, function(previousAccount, currentAccount)
	local accountName = getAccountName(currentAccount)
	if accountName == targetAccount then
		set(settingName, "false")
		outputDebugString("[sup] Votemap disabled: " .. targetAccount .. " logged in.")
	end
end )

-- Enable votemap when Joshimuz logs out
addEventHandler("onPlayerLogout", root, function(previousAccount, currentAccount)
	local accountName = getAccountName(previousAccount)
	if accountName == targetAccount then
		set(settingName, "true")
		outputDebugString("[sup] Votemap enabled: " .. targetAccount .. " logged out.")
	end
end )

-- Enable votemap when Joshimuz disconnects from the server
addEventHandler("onPlayerQuit", root, function()
	local account = getPlayerAccount(source)
	if not isGuestAccount(account) then
		local accountName = getAccountName(account)
		if accountName == targetAccount then
			set(settingName, "true")
			outputDebugString("[sup] Votemap enabled: " .. targetAccount .. " quit the server.")
		end
	end
end )
