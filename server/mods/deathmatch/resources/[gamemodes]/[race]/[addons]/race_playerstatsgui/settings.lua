--
-- SETTINGS
--

function toboolean(value)
	return tostring(value) == 'true'
end



Settings = {}
SettingKeys = {
	["showStatsOnMapFinish"] = {
		dataType = toboolean,
		defaultValue = false
	}
}

function cacheResourceSettings()
	for key,setting in pairs(SettingKeys) do
		local value = (setting.dataType or tostring)(get(key))
		if value == nil then
			value = setting.defaultValue
		end
		Settings[key] = value
	end
end


addEventHandler("onResourceStart", resourceRoot,
	function()
		cacheResourceSettings()
	end
)


addEvent("onSettingChange")
addEventHandler("onSettingChange", resourceRoot,
	function()
		cacheResourceSettings()
	end
)
