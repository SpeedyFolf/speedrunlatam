addEventHandler("onClientResourceStart", resourceRoot, function()
	setWorldSpecialPropertyEnabled("randomfoliage", false)
end )

addEventHandler("onClientResourceStop", resourceRoot, function()
	setWorldSpecialPropertyEnabled("randomfoliage", true)
end )

addEvent("onClientMapStarting", true)
addEventHandler("onClientMapStarting", root, function()
	setWorldSpecialPropertyEnabled("randomfoliage", false)
end )
