addEventHandler("onClientResourceStart", resourceRoot,
	function()
		triggerServerEvent("onClientWantSettings", localPlayer)
		triggerServerEvent("onClientWantMapData", localPlayer)
	end
)
