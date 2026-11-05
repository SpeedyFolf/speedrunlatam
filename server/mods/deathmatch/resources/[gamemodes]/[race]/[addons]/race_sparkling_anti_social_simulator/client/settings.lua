Settings = {
	hideType = HIDE_TYPES.DISABLED,
	altGhostMode = false,
	enableWhenSpectating = false,

	gui = {},
}

Settings.load = function()
	if not fileExists("@settings.json") then
		return -- Do nothing if the file doesn't exist
	end

	local file = fileOpen("@settings.json", true)
	if file then
		local data = fileRead(file, fileGetSize(file))
		fileClose(file)

		local jsonData = fromJSON(data)
		if jsonData then
			Settings.setHideType(jsonData.hideType or Settings.hideType)
			Settings.setAltGhostMode(jsonData.altGhostMode or Settings.altGhostMode)
			Settings.setEnabledWhenSpectating(jsonData.enableWhenSpectating or Settings.enableWhenSpectating)
		end
	end
end

Settings.save = function()
	local jsonData = toJSON({
		hideType = Settings.hideType,
		altGhostMode = Settings.altGhostMode,
		enableWhenSpectating = Settings.enableWhenSpectating,
	}, false, "spaces")

	local file = fileCreate("@settings.json")
	if file then
		fileWrite(file, jsonData)
		fileClose(file)
	end
end

Settings.setHideType = function(hideType, postChatMessage)
	Settings.hideType = hideType
	guiComboBoxSetSelected(Settings.gui.comboHideType, hideType)
	Settings.save()

	if postChatMessage == true then
		local typeString = "disabled"
		if hideType == HIDE_TYPES.DISABLED then
			typeString = "visible #FFFFFF(Type: #66BB66Disabled#FFFFFF)"
		elseif hideType == HIDE_TYPES.FADE then
			typeString = "faded by distance #FFFFFF(Type: #66BB66Fade#FFFFFF)"
		elseif hideType == HIDE_TYPES.FADE_HIDE then
			typeString = "hidden by distance #FFFFFF(Type: #66BB66Fade+#FFFFFF)"
		elseif hideType == HIDE_TYPES.HIDE then
			typeString = "hidden #FFFFFF(Type: #66BB66Hide#FFFFFF)"
		end

		outputChatBox("SASS: Setting other players #7777FF" .. typeString .. "#FFFFFF.", 255, 255, 255, true)
	end
end

Settings.getHideType = function()
	return Settings.hideType
end

Settings.setAltGhostMode = function(enabled, postChatMessage)
	enabled = enabled == true

	Settings.altGhostMode = enabled
	guiCheckBoxSetSelected(Settings.gui.checkAltGhostMode, enabled)
	Settings.save()

	if postChatMessage == true then
		local typeString = "#66BB66enabled"
		if not enabled then
			typeString = "#FF3333disabled"
		end

		outputChatBox("SASS: Alternative Ghost Mode " .. typeString .. "#FFFFFF.", 255, 255, 255, true)
	end
end

Settings.isAltGhostModeEnabled = function()
	return Settings.altGhostMode
end

Settings.setEnabledWhenSpectating = function(enabled, postChatMessage)
	enabled = enabled == true

	Settings.enableWhenSpectating = enabled
	guiCheckBoxSetSelected(Settings.gui.checkEnableSpectating, enabled)
	Settings.save()

	if postChatMessage == true then
		local typeString = "#66BB66enabled"
		if not enabled then
			typeString = "#FF3333disabled"
		end

		outputChatBox("SASS: Modifications during spectating " .. typeString .. "#FFFFFF.", 255, 255, 255, true)
	end
end

Settings.isEnabledWhenSpectating = function()
	return Settings.enableWhenSpectating
end

Settings.createGUI = function()
	local screenX, screenY = guiGetScreenSize()

	Settings.gui.window = guiCreateWindow(screenX / 2 - 128, screenY / 2 - (216 / 2), 256, 216, "SASS Settings")
	guiSetVisible(Settings.gui.window, false) -- Hide the GUI by default
	guiWindowSetSizable(Settings.gui.window, false) -- Disable scaling on the GUI

	guiCreateLabel(0.36, 0.15, 0.8, 0.3, "SASS Type", true, Settings.gui.window)

	Settings.gui.comboHideType = guiCreateComboBox(0.1, 0.25, 0.8, 0.45, "Hide Type", true, Settings.gui.window)
	guiComboBoxAddItem(Settings.gui.comboHideType, "0 - Disabled")
	guiComboBoxAddItem(Settings.gui.comboHideType, "1 - Fade")
	guiComboBoxAddItem(Settings.gui.comboHideType, "2 - Fade+")
	guiComboBoxAddItem(Settings.gui.comboHideType, "3 - Hide")
	guiComboBoxSetSelected(Settings.gui.comboHideType, Settings.hideType)

	addEventHandler("onClientGUIComboBoxAccepted", Settings.gui.comboHideType, function()
		Settings.setHideType(guiComboBoxGetSelected(Settings.gui.comboHideType), true)
	end, false)

	Settings.gui.checkAltGhostMode =
		guiCreateCheckBox(0.1, 0.45, 0.8, 0.1, "Alt. Ghost Mode", Settings.altGhostMode, true, Settings.gui.window)
	addEventHandler("onClientGUIClick", Settings.gui.checkAltGhostMode, function()
		Settings.setAltGhostMode(guiCheckBoxGetSelected(Settings.gui.checkAltGhostMode), true)
	end, false)

	Settings.gui.checkEnableSpectating = guiCreateCheckBox(
		0.1,
		0.55,
		0.8,
		0.1,
		"Enable When Spectating",
		Settings.enableWhenSpectating,
		true,
		Settings.gui.window
	)
	addEventHandler("onClientGUIClick", Settings.gui.checkEnableSpectating, function()
		Settings.setEnabledWhenSpectating(guiCheckBoxGetSelected(Settings.gui.checkEnableSpectating), true)
	end, false)

	local closeButton = guiCreateButton(0.3, 0.8, 0.4, 0.15, "Close", true, Settings.gui.window)
	addEventHandler("onClientGUIClick", closeButton, function()
		Settings.toggleUI()
	end, false)
end

Settings.toggleUI = function()
	if Settings.gui.window then
		local isVisible = guiGetVisible(Settings.gui.window)
		guiSetVisible(Settings.gui.window, not isVisible)
		showCursor(not isVisible)
	end
end

Settings.onHideCommand = function(_, hideType)
	if not hideType then
		Settings.toggleUI()
		return
	end

	hideType = tonumber(hideType) or 0

	Settings.setHideType(hideType, true)
end
addCommandHandler("hide", Settings.onHideCommand)
addCommandHandler("sass", Settings.onHideCommand)

local function onClientResourceStart()
	Settings.createGUI()
	Settings.load()
end
addEventHandler("onClientResourceStart", resourceRoot, onClientResourceStart)
