
---------------------------------------------------------------------------
--
-- Settings
--
--
--
---------------------------------------------------------------------------

-- Get option updates from the server
g_GameOptions = {
	alphavalue = 100,
	hideatstart = false,
	validatetime = false,
	validatespawn = false
}

addEvent ( "race_ghost.updateOptions", true )
addEventHandler('race_ghost.updateOptions', resourceRoot,
	function( gameOptions )
		if type(gameOptions) == "table" then
			g_GameOptions = gameOptions
		end
		if playback then
			playback:onUpdateOptions()
		end
	end
)
