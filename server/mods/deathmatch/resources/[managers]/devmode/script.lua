iprint("Developer Mode resource activated. Use /devmode to enable devmode if it hasn't already.")
setDevelopmentMode(true)
showCol(true)

addCommandHandler("devmode",
    function()
		iprint("Dev mode set to ", not getDevelopmentMode())
		showCol(not isShowCollisionsEnabled())
        setDevelopmentMode(not getDevelopmentMode())
		showCol(not isShowCollisionsEnabled())
    end
)
