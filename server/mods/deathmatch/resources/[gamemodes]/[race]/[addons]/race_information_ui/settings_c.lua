g_Options = {}

addEvent("onSettingsReceive", true)
addEventHandler("onSettingsReceive", resourceRoot,
	function(options)
		g_Options = options
		triggerEvent("onResourceSettingsReady", resourceRoot)
	end
)
