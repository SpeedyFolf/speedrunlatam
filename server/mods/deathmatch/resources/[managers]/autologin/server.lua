-- This encryption key will never be used as it is forcefully read from a file
encryption_key = "test_key_please_ignore"

TYPE = {
	ALREADY_LOGGED_IN = 1,
	NO_USER_OR_PASS = 2,
	NO_KNOWN_ACCOUNT = 3,
	NO_PASSWORD_PROVIDED = 4,
	INVALID_CREDENTIALS = 5,
}

function loadEncryptionKey()
	if not fileExists("encryption_key.txt") then
		-- Create an empty file
		local file = fileCreate("encryption_key.txt")
		fileClose(file)

		outputDebugString('[Autologin] No "encryption_key.txt" file found in the autologin folder. Empty one is being created. Stopping resource.')
		cancelEvent(true, 'No "encryption_key.txt" file found in the autologin folder.')
		return
	end

	local file = fileOpen("encryption_key.txt")
	if not file then
		outputDebugString('[Autologin] Error opening "encryption_key.txt" file. Stopping.')
		cancelEvent(true, 'Error opening "encryption_key.txt" file.')
		return
	end

	encryption_key = fileRead(file, fileGetSize(file)) or ""
	fileClose(file)

	local isEmpty = encryption_key == ""
	if isEmpty then
		outputDebugString('[Autologin] "encryption_key.txt" is empty. Stopping.')
		cancelEvent(true, '"encryption_key.txt" is empty.')
		return
	end
end
addEventHandler("onResourceStart", resourceRoot, loadEncryptionKey)

function loginPlayer(player, username, password)
	local isLoggedIn = not isGuestAccount(getPlayerAccount(player))
	if isLoggedIn then
		return TYPE.ALREADY_LOGGED_IN
	end

	if not username then
		return TYPE.NO_USER_OR_PASS
	end

	local account = getAccount(username)
	if not account then
		return TYPE.NO_KNOWN_ACCOUNT
	end

	if password == nil then
		return TYPE.NO_PASSWORD_PROVIDED
	end

	if logIn(player, account, password) then
		return true
	else
		return TYPE.INVALID_CREDENTIALS
	end
end

function logoutPlayer()
	local player = client
	local account = getPlayerAccount(player)

	if isGuestAccount(account) then
		return
	end

	local username = getAccountName(account)

	logOut(player)
	outputChatBox(
		"* #FFFFFFAuto-login is now #FF6464DISABLED#FFFFFF for account '#6666FF" .. username .. "#FFFFFF'!",
		player,
		255,
		100,
		100,
		true
	)
end
addEvent("autologin:logout", true)
addEventHandler("autologin:logout", root, logoutPlayer)

function command_autologin(player, _, username, password)
	local typedUsername = username ~= nil
	if not password then
		password = username
		username = getPlayerName(player)
	end

	local result = loginPlayer(player, username, password)
	if result == TYPE.ALREADY_LOGGED_IN then
		triggerClientEvent(player, "autologin:clear", player, typedUsername)
		return
	elseif result == TYPE.NO_USER_OR_PASS then
		outputChatBox("* #FFFFFFUsage: #6666FF/autologin [username] [password]", player, 255, 100, 100, true)
		return
	elseif result == TYPE.NO_KNOWN_ACCOUNT then
		outputChatBox(
			"* #FFFFFFNo known account with the username '#6666FF" .. username .. "#FFFFFF'!",
			player,
			255,
			100,
			100,
			true
		)
		return
	elseif result == TYPE.NO_PASSWORD_PROVIDED then
		outputChatBox(
			"* #FFFFFFUsage: #6666FF/autologin <username> <password>",
			player,
			255,
			100,
			100,
			true
		)
		return
	elseif result == TYPE.INVALID_CREDENTIALS then
		outputChatBox(
			"* #FFFFFFInvalid credentials for account '#6666FF" .. username .. "#FFFFFF'!",
			player,
			255,
			100,
			100,
			true
		)
		return
	end

	encodeString("tea", password, { key = encryption_key }, function(encodedPassword)
		triggerClientEvent(player, "autologin:save", player, username, encodedPassword)
	end)

	outputChatBox(
		"* #FFFFFFAuto-login is now #329932ENABLED#FFFFFF for account '#6666FF" .. username .. "#FFFFFF'!",
		player,
		255,
		100,
		100,
		true
	)
end
addCommandHandler("autologin", command_autologin)

function autoLoginPlayer(username, password)
	local decodedPassword = decodeString("tea", password, { key = encryption_key })
	local result = loginPlayer(client, username, decodedPassword)

	if result == true then
		outputChatBox("* #FFFFFFLogged into account '#6666FF" .. username .. "#FFFFFF'!", client, 255, 100, 100, true)
	elseif result ~= TYPE.ALREADY_LOGGED_IN then
		outputChatBox(
			"* #FFFFFFAuto-login failed for account '#6666FF" .. tostring(username) .. "#FFFFFF'. Please run #6666FF/autologin <username> <password>#FFFFFF again.",
			client,
			255,
			100,
			100,
			true
		)
	end
end
addEvent("autologin:login", true)
addEventHandler("autologin:login", root, autoLoginPlayer)
