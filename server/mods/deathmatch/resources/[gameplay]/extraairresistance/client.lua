addEventHandler( "onClientResourceStart", resourceRoot,
function()
	setWorldSpecialPropertyEnabled("extraairresistance", false)
end )

addEventHandler( "onClientResourceStop", resourceRoot,
function()
	setWorldSpecialPropertyEnabled("extraairresistance", true)
end )

addEvent ( "onClientMapStarting", true )
addEventHandler("onClientMapStarting", root,
function()
	setWorldSpecialPropertyEnabled("extraairresistance", false)
end )
