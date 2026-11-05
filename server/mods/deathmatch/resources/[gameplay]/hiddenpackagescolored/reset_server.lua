local WHITE = 1
local GREEN = 2
local BLUE = 3
local ORANGE = 4
local YELLOW = 5
local RED = 6
local BLACK = 7

-- (converts all packages of color and number collected before timestamp
local PACKAGES_TO_RESET = {
	-- For the 'no more grabbing through floors' update 2025-01-08 (first rewrite)
	{ YELLOW, 195, 1 }, -- top of emerald isle, helipad
	{ RED, 43, 1 }, -- Frederick Bridge
	{ BLACK, 263, 1743012000 }, -- CAT CUP - Buccaneer Bay 2025-03-26 19:00:00
	-- { color, number, timestamp }



}

function checkForResets()
	local accounts = getAccounts()
	-- for i, account in ipairs(accounts) do
	-- 	convertAllOldInformation(account)
	-- end
	for _, packToReset in ipairs(PACKAGES_TO_RESET) do
		db_resetPackage( packToReset[1], packToReset[2], packToReset[3] )
	end
end
addEventHandler("onResourceStart", resourceRoot, checkForResets)

function handleResetRequest(packageIds)
	local account = getPlayerAccount(source)
	local accountID = getAccountID(account)
	for i, p in ipairs(packageIds) do
		db_resetPackage ( p[1], p[2], p[3] or 2147483647, accountID)
	end
	sendClientPackageData(source)
end
addEvent("onClientResetRequest", true)
addEventHandler("onClientResetRequest", root, handleResetRequest)

----------------------------------------------
------------------- legacy -------------------
----------------------------------------------

-- local OLD_RESETS = {
--     -- 1: 2024-03-22 Removing too easy black packages after first release feedback
--     {
-- 		{BLACK, 1},{BLACK, 2},{BLACK, 3},{BLACK, 6},{BLACK, 7},{BLACK, 10},{BLACK, 12},
-- 		{BLACK, 17},{BLACK, 21},{BLACK, 44},{BLACK, 46},{BLACK, 52},{BLACK, 54},{BLACK, 59},
-- 	},
--     -- 2: 2024-03-25 Package that sticked out through the floor and was automatically picked up
--     { {BLACK, 7}, },
--     -- 3: 2024-04-29 Package changes to Shanty 8-Track Randomiser
-- 	{ {BLACK, 181},{BLACK, 182}, },
-- 	-- 4: 2024-09-10 Package changes after 10000% difficult got fixed
-- 	{ {BLACK, 430},{BLACK, 431}, },
-- 	-- 5: 2024-10-16 Going Up 3, Luigi Circuit package fix, Bayside green fix
-- 	{ {BLACK, 494},{BLACK, 512},{GREEN, 3}, },
-- 	-- 6: 2024-11-13 Minor tweaks to areas from previous update
-- 	{ {WHITE, 606},{WHITE, 613},{RED, 40},{RED, 15}, },
-- 	-- 7: 2024-11-22 Reset misreset package on Mario Kart map, Mechanic Deadfall II + Build Your Own DD removed
-- 	{ {BLACK, 511},{BLACK, 461},{BLACK, 281}, },
-- }

-- function convertAllOldInformation(account)
-- 	local nonParticipant = getAccountData(account, "coloredPackages.nonParticipant")
-- 	local resetHistory = getAccountData(account, "coloredPackages.resetHistory")
-- 	local collected = getAccountData(account, "coloredPackages.collected")

-- 	local accountID = getAccountID(account)

-- 	if (nonParticipant) then
-- 		db_setAccountNonParticipation(accountID, true)
-- 		setAccountData(account, "coloredPackages.nonParticipant", false)
-- 	end
-- 	if (collected) then
-- 		setAccountData(account, "coloredPackages.collectedBKP", collected)
-- 		local packages = fromJSON(collected)
-- 		if (packages) then
-- 			for package, vehicleUsed in pairs(packages) do
-- 				local packType, packNumber = convertOldName(package)
-- 				if (packType and packNumber) then
-- 					db_writePlayerCollectedPackage ( packType, packNumber, accountID, vehicleUsed, "NULL", -1, 0 )
-- 				end
-- 			end
-- 		end
-- 		if (not resetHistory) then
-- 			resetHistory = 0
-- 		end
-- 		if (resetHistory < 7) then
-- 			for rh = resetHistory + 1, 7 do
-- 				for _, p in ipairs(OLD_RESETS[rh]) do
-- 					db_resetPackage ( p[1], p[2], 1, accountID)
-- 				end
-- 			end
-- 		end

-- 		setAccountData(account, "coloredPackages.collected", false)
-- 		setAccountData(account, "coloredPackages.resetHistory", false)
-- 	end
-- end

-- function convertOldName(str)
-- 	if (str == "") then return false, false end
-- 	local word, number = str:match("([a-zA-Z]+)(%d+)")
-- 	if (word == "packageNormal") then return 1, number end
-- 	if (word == "packageBike") then return 2, number end
-- 	if (word == "packageWater") then return 3, number end
-- 	if (word == "packageHelicopter") then return 4, number end
-- 	if (word == "packageHard") then return 5, number end
-- 	if (word == "packageExtreme") then return 6, number end
-- 	if (word == "packageCustom") then return 7, number end
-- 	iprint("[Hidden Packages Colored] PACKAGE CONVERSION ERROR "..str)
-- 	return false, false
-- end
