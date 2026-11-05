local cachedLeaderboard = {}
local isUpdating = false

-- Config: How many accounts to process per server tick/frame
-- Increase if too slow, decrease if it causes lag spikes.
local PROCESS_CHUNK_SIZE = 500

function refreshLeaderboard()
	if isUpdating then
		return
	end
	isUpdating = true

	-- Start a coroutine to process accounts without freezing the server
	local co = coroutine.create(function()
		local accounts = getAccounts()
		local tempTable = {}

		outputDebugString("[Playtime] Starting processing of " .. #accounts .. " accounts...")

		for i, account in ipairs(accounts) do
			-- Account name is usually the login name.
			-- If you store RP names in account data, change 'getPlayerAccount(account)' accordingly.
			local name = getAccountName(account)

			-- We only care about accounts that actually have playtime data
			-- "Time Played-hours" is the raw number string like '1328'
			local hours = getAccountData(account, "Time Played-hours")

			if hours then
				local mins = getAccountData(account, "Time Played-min") or 0

				-- Convert to numbers for math
				hours = tonumber(hours) or 0
				mins = tonumber(mins) or 0

				local totalMinutes = (hours * 60) + mins

				table.insert(tempTable, {
					name = name,
					hours = hours,
					mins = mins,
					totalScore = totalMinutes
				})
			end

			-- Yield every X accounts to let the server breathe
			if i % PROCESS_CHUNK_SIZE == 0 then
				coroutine.yield()
			end
		end

		-- Sort the table (Highest score first)
		table.sort(tempTable, function(a, b)
			return a.totalScore > b.totalScore
		end )

		cachedLeaderboard = tempTable
		isUpdating = false
		outputDebugString("[Playtime] Leaderboard updated. Total entries: " .. #cachedLeaderboard)
	end )

	-- Resume the coroutine continuously until finished
	local function resume()
		if coroutine.status(co) ~= "dead" then
			coroutine.resume(co)
			setTimer(resume, 50, 1)
		end
	end
	resume()
end

-- Refresh on resource start
addEventHandler("onResourceStart", resourceRoot, refreshLeaderboard)

-- Allow manual refresh via command (Admin only)
addCommandHandler("refreshtime", function(player)
	if isObjectInACLGroup("user."..getAccountName(getPlayerAccount(player)), aclGetGroup("Admin")) then
		refreshLeaderboard()
		outputChatBox("Playtime leaderboard refresh started...", player)
	end
end, false, false )

-- Send data to client when they request it
addEvent("requestPlaytimeData", true)
addEventHandler("requestPlaytimeData", root, function()
	-- Get the requesting player's account name so they can highlight themselves
	local account = getPlayerAccount(client)
	local myAccName = isGuestAccount(account) and "" or getAccountName(account)

	triggerClientEvent(client, "receivePlaytimeData", client, cachedLeaderboard, myAccName)
end )
