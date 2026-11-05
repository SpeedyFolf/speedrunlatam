function onClientResourceStart()
	loadData()
end
addEventHandler("onClientResourceStart", resourceRoot, onClientResourceStart)

function getLoginData()
	if not fileExists("@credentials") then
		return false
	end

	local file = fileOpen("@credentials")
	if not file then
		return false
	end

	local size = fileGetSize(file)
	local raw_data = fileRead(file, size)
	fileClose(file)

	local data = fromJSON(raw_data)
	if not data or type(data) ~= "table" or not data.username or not data.password then
		return false
	end

	return data
end

function loadData()
	local data = getLoginData()
	if not data then
		return
	end

	triggerServerEvent("autologin:login", localPlayer, data.username, data.password)
end

function saveData(username, password)
	if fileExists("@credentials") then
		fileDelete("@credentials")
	end

	local file = fileCreate("@credentials")
	if not file then
		return
	end

	local save_string = toJSON({ username = username, password = password })
	fileWrite(file, save_string)
	fileClose(file)
end
addEvent("autologin:save", true)
addEventHandler("autologin:save", root, saveData)

function clearAutoLogin(triedWithUsernameOrPassword)
	if fileExists("@credentials") then
		fileDelete("@credentials")
		triggerServerEvent("autologin:logout", localPlayer)
	else
		if triedWithUsernameOrPassword then
			outputChatBox(
				"* #FFFFFFYou are already logged in. Please logout and use the command again.",
				255,
				100,
				100,
				true
			)
		else
			outputChatBox(
				"* #FFFFFFAuto-login not active, please log out and use the #6666FF/autologin #FFFFFFcommand.",
				255,
				100,
				100,
				true
			)
		end
	end
end
addEvent("autologin:clear", true)
addEventHandler("autologin:clear", root, clearAutoLogin)
