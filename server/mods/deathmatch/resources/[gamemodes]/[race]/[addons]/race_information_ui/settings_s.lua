g_Options = {}

function cacheGameOptions()
	g_Options = {}
	g_Options.colorbottomleft = getString("race_information_ui.colorbottomleft", "#FFC864")
	g_Options.mapfolder = getString("race_information_ui.mapfolder", "folder")
end

addEventHandler("onResourceStart", resourceRoot,
	function()
		cacheGameOptions()
	end
)

-- --------------------------------------------------------------------------------------------------
-- Boiler plate code the size of Siberia just to get the client to also know the resource settings...
-- --------------------------------------------------------------------------------------------------

function settingsRequested(p)
	triggerClientEvent(p, "onSettingsReceive", resourceRoot, g_Options)
end

addEvent("onSettingsRequested")
addEventHandler("onSettingsRequested", resourceRoot,
	function()
		settingsRequested(source)
	end
)

-- Called from the admin panel when a setting is changed there
addEvent("onSettingChange")
addEventHandler("onSettingChange", resourceRoot,
	function(name, oldvalue, value, player)
		cacheGameOptions()
		triggerClientEvent(root, "onSettingsReceive", resourceRoot, g_Options)
	end
)

addEvent("onClientWantSettings", true)
addEventHandler("onClientWantSettings", root,
	function()
		settingsRequested(source)
	end
)
