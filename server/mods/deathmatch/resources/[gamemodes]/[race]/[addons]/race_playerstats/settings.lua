
getPlayerKey = getPlayerName
getPlayerFromKey = getPlayerFromName

--
-- SETTINGS
--

function toboolean(value)
	return tostring(value) == "true"
end


Settings = {}
SettingKeys = {
	["debugMessages"] = {
		dataType = toboolean,
		defaultValue = false
	},
	["welcomeMessage"] = {
		dataType = tostring,
		defaultValue = nil
	},
	["messageColor"] = {
		dataType = tostring,
		defaultValue = "#FFFFFF"
	},
	["messageHeaderColor"] = {
		dataType = tostring,
		defaultValue = "#FFFFFF"
	},
	["countMidraceJoinAsRacestart"] = {
		dataType = toboolean,
		defaultValue = true
	},
	["countPostFinishDeath"] = {
		dataType = toboolean,
		defaultValue = true
	},
	["vehicleWreckHealthLimit"] = {
		dataType = tonumber,
		defaultValue = 250
	},
	["statsExportUrl"] = {
		dataType = tostring,
		defaultValue = nil
	},
	["serverKey"] = {
		dataType = tostring,
		defaultValue = nil
	},
	["statsGracePeriod"] = {
		dataType = tonumber,
		defaultValue = 30
	},
	["playerKeyType"] = {
		dataType = tostring,
		defaultValue = "AccountName"
	}
}


local function cacheResourceSettings()
	for key,setting in pairs(SettingKeys) do
		local value = get(key)
		if value == nil then
			value = setting.defaultValue
		else
			value = (setting.dataType or tostring)(value)
		end
		Settings[key] = value
	end
	if Settings["playerKeyType"] == "AccountName" then
		getPlayerKey = function(player)
			local account = nil
			if isElement(player) then
				local elementType = getElementType(player)
				if elementType == "player" then
					account = getPlayerAccount(player)
				elseif elementType == "account" then
					account = player
				end
			end
			if account and not isGuestAccount(account) then
				return getAccountName(account)
			end
			return nil
		end
		getPlayerFromKey = function(name)
			local account = getAccount(name)
			if account and not isGuestAccount(account) then
				return getAccountPlayer(account)
			end
			return nil
		end
	else
		getPlayerKey = getPlayerName
		getPlayerFromKey = getPlayerFromName
	end
end


addEventHandler("onResourceStart", resourceRoot, cacheResourceSettings)


addEvent("onSettingChange")
addEventHandler("onSettingChange", resourceRoot, cacheResourceSettings)

