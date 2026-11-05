local timers = {}


--[[
-- check Nick
--
-- Checks if the nick currently used by the given player
-- is protected and if he is allowed to use it.
--
-- @param   player   player: The player whose nick should be checked
-- @return
-- ]]
function checkNick(player)
	-- player changed nick, just joined or timer ran out (possible running timer is no longer necessary)
	killTimerForPlayer(player)

	-- fetch information about the player's nick
	local nick = removeHex(getPlayerName(player))

	if isPlayerAllowedToUseNick(player,nick) then
		return
	end

	-- # nick is protected and player has (currently) no right to use it

	--outputDebugString("tell player "..removeHex(getPlayerName(player)).." to login or change nick")

	local secondsForLogin = tonumber(get("timeForLogin"))

	if toboolean(get("useTextDisplays")) then
		warnPlayer(player,"Your nick '"..nick.."' is protected. Please login or change nick within "..secondsForLogin.." seconds.")
	end
	outputMessage("Your nick '"..nick.."' is protected. Please login or change nick within "..secondsForLogin.." seconds.",player,0)

	timers[player] = setTimer(checkNickAgain,secondsForLogin*1000,1,player)

end

--[[
-- checkNickAgain
--
-- Called by the timer to check if the player is now allowed to use the nick,
-- or otherwise take action.
--
-- @param   player   player: The Player
-- @return
-- ]]
function checkNickAgain(player)
	if isPlayerAllowedToUseNick(player,removeHex(getPlayerName(player))) then
		return
	end

	if toboolean(get("changeNickInsteadOfKicking")) then
		changeNickToRandom(player)
		if toboolean(get("useTextDisplays")) then
			warnPlayer(player,"Your nick has been changed because you used a protected nick.")
		end
		outputMessage("Your nick has been changed because you used a protected nick.",player,0)
	else
		kickPlayer(player,"Used protected nick.")
	end

	outputDebugString("take action on "..removeHex(getPlayerName(player)).." (change nick or kick)")
end



--[[
-- changeNickToRandom
--
-- Creates a random nick which is not currently used and sets it as
-- new nick for the given player.
--
-- @param   player   player: The player who's nick should be changed.
-- @return
-- ]]
function changeNickToRandom(player)
	local randomNick = "Player"..math.random(100,999)
	while getPlayerFromName(randomNick) do
		randomNick = "Player"..math.random(100,999)
	end
	setPlayerName(player,randomNick)
end






---------------------------------------------------
-- ### Getting and modifying data from the database
---------------------------------------------------

--[[
-- getProtectedNickData
--
-- Gets the data for a protected nick from the database
--
-- @param   string   nick: The nick you want to get the data from
-- @return  mixed	false/result: Returns either false if no result was found or a table with the desired data
-- ]]
function getProtectedNickData(nick)
	local result = executeSQLQuery("SELECT *, ((JULIANDAY('now') - JULIANDAY(lastUsed))) AS lastUsedDaysPassed FROM nickProtection WHERE protectedNick = ?",nick)

	if #result == 0 then
		return false
	end

	return result[1]
end

--[[
-- removeExpiredNicks
--
-- Removes expired nicks (depending on the mode set in the settings)
-- ]]
function removeExpiredNicks()
	local expireMode = tonumber(get("protectedNicksExpireMode"))
	if expireMode == 0 then
		return
	end
	local expiresAfterDays = tonumber(get("protectedNicksExpireAfterDays"))
	local expiredNicks = executeSQLQuery("SELECT rowid, * FROM nickProtection WHERE (JULIANDAY('now') - JULIANDAY(lastUsed)) > ?",expiresAfterDays)
	for k,v in ipairs(expiredNicks) do
		local accountString = "user."..v.accountName
		if expireMode == 2 or not hasObjectPermissionTo(accountString,"resource.nickProtection.extended",false) then
			outputDebugString("Removing expired nick: "..tostring(v.protectedNick).." (last used "..tostring(v.lastUsed)..")")
			executeSQLQuery("DELETE FROM nickProtection WHERE rowid = ?",v.rowid)
		end
	end
end

--[[
-- updateLastUsed
--
-- Updates the lastUsed field when the nick is used.
--
-- @param   string   nick: The nick.
-- ]]
function updateLastUsed(nick)
	executeSQLQuery("UPDATE nickProtection SET lastUsed = DATETIME('now') WHERE protectedNick = ?",nick)
end

--[[
-- isNickProtected
--
-- Checks if the given nick is protected by someone.
--
-- @param   string   nick: The nick that should be checked.
-- @return  boolean  true/false
-- ]]
function isNickProtected(nick)
	local data = getProtectedNickData(nick)
	if not data then
		return false
	end
	return true
end

--[[
-- getProtectedNicksByAccountName
--
-- Returns a table with protected nicks associated with the given account name.
--
-- @param   string   accountName: The name of the account, e.g. "Adnan"
-- @return  table	protectedNicks: A table of protected nicks (could also contain no elements at all)
-- ]]
function getProtectedNicksByAccountName(accountName)
	local protectedNicks = executeSQLQuery("SELECT *, ((JULIANDAY('now') - JULIANDAY(lastUsed))) AS lastUsedDaysPassed FROM nickProtection WHERE accountName = ?",accountName)
	return protectedNicks
end

--[[
-- isPlayerAllowedToUseNick
--
-- Checks if the player is allowed to use the given nick,
-- so if it is protected at all and if the player is the one
-- who protected it.
--
-- @param   player   player: The player who claims ownership of the nick
-- @param   string   nick: The nick who should be checked
-- @return  boolean  true/false
-- ]]
function isPlayerAllowedToUseNick(player,nick)
	local data = getProtectedNickData(nick)
	if data == false then
		return true
	end

	-- if player is logged in to the required account, return
	local playerAccountName = getAccountName(getPlayerAccount(player))
	if data.accountName ~= nil and data.accountName == playerAccountName then
		-- consider nick used, when the rightful owner tried to take it
		updateLastUsed(nick)
		return true
	end

	return false

end




--------------------
-- ### Player Events
--------------------

--[[
-- playerJoined
--
-- Simply calls checkNick() as soon as a player joins.
-- ]]
function playerJoined()
	checkNick(source)
end
addEventHandler("onPlayerJoin",root,playerJoined)

--[[
-- playerLeft
--
-- Clears up when a player leaves the server. For now it only kills
-- the timer (if necessary).
-- ]]
function playerLeft()
	killTimerForPlayer(source)
end
addEventHandler("onPlayerQuit",root,playerLeft)

--[[
-- playerChangedNick
--
-- Checks on change of nick if the player is allowed to use the new nick.
-- If so, nickChangeSpamProtection is also called if enabled.
--
-- Event Handler for onPlayerChangeNick.
--
-- @param   string   oldNick: The nick previously used
-- @param   string   newNick: The nick the player wants to change to
-- @return
-- ]]
function playerChangedNick(oldNick,newNick)
	hexlessNick = removeHex(newNick)
	if isPlayerAllowedToUseNick(source,hexlessNick) then
		killTimerForPlayer(source)
		-- check for nick spam if enabled
		if toboolean(get("enableNickChangeSpamProtection")) then
			nickChangeSpamProtection(source)
		end
	else
		cancelEvent()
		outputMessage("You are not allowed to use this nick. Please login if it's yours.",source,0)
	end
end
addEventHandler("onPlayerChangeNick",root,playerChangedNick)

--[[
-- playerLoggedIn
--
-- Checks if the login actually authorizes the player to use the current nick
-- (if it is protected) and if not, warns him about it.
--
-- Event handler for onPlayerLogin.
--
-- @param   account   prevAccount: Previously used account
-- @param   account   currentAccount: The account the player just logged in to.
-- @param   boolean   autoLogin: Whether auto login was used.
-- @return
-- ]]
function playerLoggedIn(prevAccount,currentAccount,autoLogin)
	if not isNickProtected(removeHex(getPlayerName(source))) then
		return
	end
	if isPlayerAllowedToUseNick(source,removeHex(getPlayerName(source))) then
		outputMessage("You are now allowed to use this protected nick.",source,1)
		killTimerForPlayer(source)
		return
	end
	if isTimer(timers[source]) then
		outputMessage("Warning: You may have logged into the wrong account for this nick! You are still not allowed to use it!",source,0)
	end
end

addEventHandler("onPlayerLogin",root,playerLoggedIn)





---------------
-- ### Commands
---------------

--[[
-- protectNick
--
-- Called by /protect to protect the given nick if possible.
--
-- @param   player   player: The player who called the command
-- @return
-- ]]
function protectNick(player)
	local account = getPlayerAccount(player)
	if isGuestAccount(account) then
		outputMessage("protect: You must login to use this command.",player,0)
		return
	end

	nick = removeHex(getPlayerName(player))

	if isNickProtected(nick) then
		outputMessage("protect: Nick '"..nick.."' is already protected.",player,0)
		return
	end

	local accountName = getAccountName(account)
	local alreadyProtectedNicks = getProtectedNicksByAccountName(accountName)

	local maxNumberOfProtectedNicks = tonumber(get("protectedNicksPerAccount"))
	local maxNumberOfProtectedNicksExtended = tonumber(get("protectedNicksPerAccountExtended"))

	if hasObjectPermissionTo(player,"resource.nickProtection.extended",false) then
		if #alreadyProtectedNicks >= maxNumberOfProtectedNicksExtended then
			outputMessage("You are not allowed to protect any more nicks (max. "..maxNumberOfProtectedNicksExtended..").",player,0)
			return
		end
	elseif (#alreadyProtectedNicks >= maxNumberOfProtectedNicks) then
		outputMessage("You are not allowed to protect any more nicks (max. "..maxNumberOfProtectedNicks..").",player,0)
		return
	end

	if accountName then
		executeSQLQuery("INSERT INTO nickProtection (protectedNick,accountName) VALUES (?,?)",nick,accountName)
		outputMessage("Your nick '"..nick.."' is now protected.",player,1)
		updateLastUsed(nick)
	end
end

addCommandHandler("protect",protectNick)

--[[
-- unprotectNick
--
-- Called by /unprotect to unprotect a nick if possible.
--
-- @param   player   player: The player who called the command
-- @param   string   command: The name of the command
-- @param   string   nick: The nick the player wants to unprotect (optional), e.g. "DasBaby"
-- @return
-- ]]
function unprotectNick(player,command,nick)
	local account = getPlayerAccount(player)
	if isGuestAccount(account) then
		outputMessage("unprotect: You must login to use this command.",player,0)
		return
	end

	if nick == nil then
		nick = removeHex(getPlayerName(player))
	end

	if not isPlayerAllowedToUseNick(player,nick) then
		outputMessage("You can't 'unprotect' the nick '"..nick.."' you don't have access to. Please login if it is yours.",player,0)
		return
	end

	if not isNickProtected(nick) then
		outputMessage("The nick '"..nick.."' is not protected and can therefore not be unprotected.",player,0)
		return
	end

	executeSQLQuery("DELETE FROM nickProtection WHERE protectedNick = ?",nick)
	outputMessage("Nick '"..nick.."' is no longer protected.",player,1)
end

addCommandHandler("unprotect",unprotectNick)

--[[
-- outputProtectedNicks
--
-- Outputs a list of protected nicks associated with the player's account to the player.
-- Called by /protected.
--
-- @param   player   player: The player who called the command.
-- @return
-- ]]
function outputProtectedNicks(player)
	local account = getPlayerAccount(player)
	if isGuestAccount(account) then
		outputMessage("protected: You must login to use this command.",player,0)
		return
	end

	local nicks = getProtectedNicksByAccountName(getAccountName(account))
	local nicksString = ""
	for k,v in ipairs(nicks) do
		nicksString = nicksString.." "..v.protectedNick.." ("..round(v.lastUsedDaysPassed)..")"
	end

	local expireMode = tonumber(get("protectedNicksExpireMode"))
	local expireTime = tonumber(get("protectedNicksExpireAfterDays"))

	local expireTimeString = "unused never expire"
	if expireMode == 2 or not hasObjectPermissionTo(player,"resource.nickProtection.extended",false) then
		expireTimeString = "unused expire after "..expireTime.."days"
	end
	if nicksString == "" then
		outputMessage("You have no protected nicks.",player,1)
	else
		outputMessage("Your protected nicks ("..expireTimeString.."):"..nicksString,player,1)
	end
end

addCommandHandler("protected",outputProtectedNicks)

---------------
-- ### Initiate
---------------

--[[
-- Creates the sqlite table on the start of the resource.
-- ]]
function initializeDatabase()
	executeSQLCreateTable("nickProtection","protectedNick TEXT, accountName TEXT, lastUsed TEXT")
end
addEventHandler("onResourceStart",resourceRoot,initializeDatabase)




---------------------
-- ### Help functions
---------------------

--[[
-- toboolean
--
-- Simple help function that turns boolean strings into boolean values.
--
-- @param   string   string: The boolean value that should be converted, e.g. "true"
-- @return  boolean  true or false
-- ]]
function toboolean(string)
	if string == "true" then return true end
	return false
end

--[[
-- killTimerForPlayer
--
-- Help function which kills the timer for a player if needed.
--
-- @param   player   player: The player for which the timer should be killed
-- @return
-- ]]
function killTimerForPlayer(player)
	local timer = timers[player]
	if isTimer(timer) then
		killTimer(timer)
	end
end

--[[
-- warnPlayer
--
-- Shows a warning to the player (as text display).
--
-- @param   player   player: The player that should see the text
-- @param   string   text: The text of the warning
-- @return
-- ]]
function warnPlayer(player,text)
	local display = textCreateDisplay()
	local text = textCreateTextItem(text,0.5,0.2,nil,nil,nil,nil,nil,1.2,"center")
	textDisplayAddText(display,text)
	textDisplayAddObserver(display,player)
	setTimer(textDestroyDisplay,5000,1,display)
	setTimer(textDestroyTextItem,5000,1,text)
end

--[[
-- outputMessage
--
-- Outputs a message and changes to color according to the
-- type of the message. It also splits up the message and
-- sends the rest in a second message, if the string is longer
-- than 128 characters.
--
-- @param   string   message: The string you want to output
-- @param   element  to: To whom you want to output the message (e.g. player)
-- @param   number   typeOfMessage: 0 - error message, 1 - normal response, everything else - standard outputChatBox color
-- ]]
function outputMessage(message,to,typeOfMessage)
	secondMessage = ""
	if string.len(message) > 128 then
		secondMessage = ".."..string.sub(message,127)
		message = string.sub(message,1,126)..".."
	end
	if typeOfMessage == 0 then
		outputChatBox(message,to,205,92,92)
	elseif typeOfMessage == 1 then
		outputChatBox(message,to,50,205,50)
	else
		outputChatBox(message,to)
	end
	if string.len(secondMessage) > 0 then
		outputMessage(secondMessage,to,typeOfMessage)
	end
end

--[[
-- round
--
-- Rounds the given number to the number of decimals given. This function
-- is used to output nice number, so it returns a string.
--
-- @param   number   number: The number you which to round.
-- @param   number   decimals: The number of decimals the number should have afterwards.
-- @return  string   Returns the rounded number as a string.
-- ]]
function round(number,decimals)
	if decimals == nil then
		decimals = 0
	end
	local factor = 10^decimals
	local rounded = math.floor(number * factor + 0.5) / factor
	local pos = string.find(rounded,".",1,true)
	if pos == nil then
		return rounded
	else
		return string.sub(rounded,1,pos + decimals)
	end
end





-----------------------------------
-- ### Nick change flood protection
-----------------------------------


local count = {}
local last = {}

function nickChangeSpamProtection(player)
	local waitForSeconds = tonumber(get("nickChangeSpamProtectionWaitTime"))

	-- reset if waiting time has passed
	if last[player] ~= nil and last[player] < (getTickCount() - waitForSeconds * 1000) then
		count[player] = 0
	end

	-- increase count
	if count[player] == nil then
		count[player] = 1
	else
		count[player] = count[player] + 1
	end

	-- if count is too high, cancel changing of nick
	if count[player] > tonumber(get("maxNickChanges")) then
		cancelEvent()
		outputChatBox("Please wait some time before changing your nick again.",player,255,100,100)
	else
		last[player] = getTickCount()
	end

end

function removeHex (s)
	local g, c = string.gsub, 0
	repeat
		s, c = g(s, '#%x%x%x%x%x%x', '')
	until c == 0
	return s
end
