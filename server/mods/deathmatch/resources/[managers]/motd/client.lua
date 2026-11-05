-- ### Variables

-- # Please don't edit unless you know what you do

motdText = "Loading motd failed."
motdVersion = 0
motdLastChanged = ""
rulesText = "Loading rules failed."
rulesVersion = 0
rulesLastChanged = ""
currentTab = "rules" -- Track which tab is currently selected in the admin editor
waitForMessage = false
local screenWidth, screenHeight = guiGetScreenSize()



-------------------------
-- Edit Gui (for Admins)
-------------------------

editgui = {}

--[[
-- createEditGui
--
-- Creates the edit Gui if it isn't already created.
-- ]]
function createEditGui()
	if editgui.window ~= nil then
		return
	end

	editgui.window = guiCreateWindow(screenWidth/2 - width/2, screenHeight/2 - height/2,width,height,"Edit Motd/Rules", false )

	-- New: Tab Panel
	editgui.tabPanel = guiCreateTabPanel(14,30,width - 14*2,height - 100,false,editgui.window)

	-- New: MOTD Tab
	editgui.motdTab = guiCreateTab("Changelog (MOTD)",editgui.tabPanel)
    -- FIX: Memo size is now calculated based on the tab size, minus a small buffer for internal tab padding
	local editTabW, editTabH = guiGetSize(editgui.motdTab, false)
	editgui.motdMemo = guiCreateMemo(0, 0, editTabW, editTabH, "Loading...", false, editgui.motdTab)

	-- New: Rules Tab
	editgui.rulesTab = guiCreateTab("Rules",editgui.tabPanel)
    -- FIX: Memo size is now calculated based on the tab size, minus a small buffer for internal tab padding
	local editTabW, editTabH = guiGetSize(editgui.rulesTab, false)
	editgui.rulesMemo = guiCreateMemo(0, 0, editTabW, editTabH, "Loading...", false, editgui.rulesTab)

	-- Update tab change handler
	addEventHandler("onClientGUITabSwitched", editgui.tabPanel, onEditTabSwitched)

	editgui.closeButton = guiCreateButton(width - 120,height - 30, 100,20,"Close",false,editgui.window)
	addEventHandler("onClientGUIClick",editgui.closeButton,closeEditGui,false)

	editgui.saveButton = guiCreateButton(20,height - 30,100,20,"Save",false,editgui.window)
	addEventHandler("onClientGUIClick",editgui.saveButton,saveEditGui,false)

	editgui.dontIncreaseVersion = guiCreateCheckBox(130,height - 30,140,20,"Don't increase version",false,false,editgui.window)

	guiSetVisible(editgui.window,false)
end

-- New: Function to track which tab is active for saving
function onEditTabSwitched()
	local selectedTab = guiGetSelectedTab(editgui.tabPanel)
	if selectedTab == editgui.motdTab then
		currentTab = "motd"
	elseif selectedTab == editgui.rulesTab then
		currentTab = "rules"
	end
	updateEditGuiTexts()
end

-- New: Function to update the memo text and window title
function updateEditGuiTexts()
	if editgui.window == nil then return end

	guiSetText(editgui.motdMemo, motdText)
	guiSetText(editgui.rulesMemo, rulesText)

	-- Update window title with current version/timestamp
	local version, lastChanged
	if currentTab == "motd" then
		version = motdVersion
		lastChanged = motdLastChanged
	elseif currentTab == "rules" then
		version = rulesVersion
		lastChanged = rulesLastChanged
	end

	if version and lastChanged then
		guiSetText(editgui.window, "Edit Motd/Rules (Version "..version..", "..lastChanged..")")
	end
end

--[[
-- openEditGui
--
-- Opens the edit gui and requests the current data from the server.
-- ]]
function openEditGui()
	createEditGui()
	guiSetVisible(editgui.window,true)
	showCursor(true)

	-- Ensure the correct tab is selected and text is loaded
	guiSetSelectedTab(editgui.tabPanel, editgui.motdTab)
	currentTab = "motd"
	updateEditGuiTexts()

	sendMessageToServer("get")
end
--[[
-- closeEditGui
--
-- Hides the edit gui.
-- ]]
function closeEditGui()
	guiSetVisible(editgui.window,false)
	showCursor(false)
end

--[[
-- saveEditGui
--
-- Sends the current text, the value of the increase version checkbox, and the tab name
-- to the server.
--]]
function saveEditGui()
	local tabName = currentTab
	local text
	if tabName == "motd" then
		text = guiGetText(editgui.motdMemo)
	elseif tabName == "rules" then
		text = guiGetText(editgui.rulesMemo)
	end

	local dontIncreaseVersion = guiCheckBoxGetSelected(editgui.dontIncreaseVersion)
	-- Send tabName, text, and dontIncreaseVersion
	sendMessageToServer("save",{tabName, text, dontIncreaseVersion})
end



--------------
-- Normal Gui
--------------

gui = {}

--[[
-- createGui
--
-- Creates the motd gui if it isn't already created.
-- ]]
function createGui()
	if gui.window ~= nil then
		return
	end

	-- Determine GUI dimensions and scale
	local w, h, scale = width, height, 1
	if (screenWidth > 1280) or (screenHeight > 820) then
		w, h, scale = width * 1.5, height * 1.5, 1.5
	end

	gui.window = guiCreateWindow ( screenWidth/2 - w/2, screenHeight/2 - h/2, w, h, "Message of the Day", false )

	local imageHeightScaled = 0
	-- Use imageWidth and imageHeight from settings.lua (0 in your case, disabling the image)
	if image ~= "" and image ~= nil and imageWidth > 0 and imageHeight > 0 then
		gui.image = guiCreateStaticImage( w/2 - (imageWidth*scale)/2, 30, imageWidth * scale, imageHeight * scale, image, false, gui.window )
		imageHeightScaled = imageHeight * scale + 10
	end

	-- Define heights for bottom controls
	local checkboxHeight = 20 * scale
	local closeButtonHeight = 40 * scale
	local paddingBelowClose = 5 * scale -- Space between close button and checkbox/label
	local paddingToBottom = margin * scale -- Standard margin at bottom
	local paddingContentToButton = 10 * scale -- Padding between tab content and Close button

	-- 1. Close Button Y position: Calculated to place the bottom row above the window bottom
	local closeButtonY = h - (checkboxHeight + paddingToBottom) - paddingBelowClose - closeButtonHeight

	-- 2. Tab Panel Y position: Starts at 30 (below window title) + imageHeightScaled
	local tabPanelY = 30 + imageHeightScaled

	-- 3. Tab Panel Height: Calculated space between its start Y and the Close Button's Y, MINUS content padding.
	--    We remove the extra buffer to avoid unnecessary subtraction. The memo size inside the tab will handle the rest.
	local tabPanelHeight = closeButtonY - tabPanelY - paddingContentToButton

	-- Tab Panel
	gui.tabPanel = guiCreateTabPanel(margin, tabPanelY, w - 2*margin, tabPanelHeight, false, gui.window)

	-- Rules Tab (Default)
	gui.rulesTab = guiCreateTab("Rules", gui.tabPanel)
	-- **FIX:** Memo size MUST be calculated relative to the tab's internal usable area (W and H) to prevent cut-off.
	local tabW, tabH = guiGetSize(gui.rulesTab, false)
	gui.rulesMemo = guiCreateMemo(0, 0, tabW, tabH, rulesText, false, gui.rulesTab)
	guiMemoSetReadOnly(gui.rulesMemo, true)

	-- Changelog Tab
	gui.motdTab = guiCreateTab("Changelog (MOTD)", gui.tabPanel)
	-- **FIX:** Memo size MUST be calculated relative to the tab's internal usable area (W and H) to prevent cut-off.
	local tabW, tabH = guiGetSize(gui.motdTab, false)
	gui.motdMemo = guiCreateMemo(0, 0, tabW, tabH, motdText, false, gui.motdTab)
	guiMemoSetReadOnly(gui.motdMemo, true)

	-- Tab switch handler
	addEventHandler("onClientGUITabSwitched", gui.tabPanel, onGuiTabSwitched)

	-- Close Button
	gui.closeButton = guiCreateButton(margin, closeButtonY, w - 2*margin, closeButtonHeight, "Close", false, gui.window)
	addEventHandler("onClientGUIClick",gui.closeButton,closeGui,false)

	-- Checkbox and label positioning
	local checkboxY = closeButtonY + closeButtonHeight + paddingBelowClose
	local labelY = checkboxY + 4 * scale

	local checked = getSettings()
	gui.checkbox = guiCreateCheckBox(margin + 6*scale, checkboxY, 240 * scale, checkboxHeight,"Don't show again until text changes",checked,false,gui.window)
	addEventHandler("onClientGUIClick",gui.checkbox,toggleCheckbox,false)

	gui.label = guiCreateLabel(w - 160*scale, labelY, 200 * scale, checkboxHeight,"Last changed",false,gui.window)

	-- Initial label update (will default to the Rules tab's timestamp)
	updateGuiLabel()

	guiSetVisible(gui.window,false)
end

-- New: Function to update the label based on the active tab
function updateGuiLabel()
	if gui.window == nil then return end

	local selectedTab = guiGetSelectedTab(gui.tabPanel)
	local labelText = "Last changed "

	if selectedTab == gui.rulesTab then
		labelText = labelText .. rulesLastChanged:sub(1,10) .. " (Rules V." .. rulesVersion .. ")"
	elseif selectedTab == gui.motdTab then
		labelText = labelText .. motdLastChanged:sub(1,10) .. " (MOTD V." .. motdVersion .. ")"
	end

	guiSetText(gui.label, labelText)
end

-- New: Handler for when the user switches tabs in the main window
function onGuiTabSwitched()
	updateGuiLabel()
end


--[[
-- openGui
--
-- Opens the motd GUI on request or on join. If on join,
-- it checks if the motd should be shown.
--
-- @param   boolean   onJoin: Whether the function has been called on join.
-- ]]
function openGui(onJoin)

	-- get the current message and version first, but only if it hasn't already been requested
	if not waitForMessage then
		sendMessageToServer("get")
	end

	-- if message not yet received, stop
	-- Check if both versions are loaded now
	if motdVersion == 0 or rulesVersion == 0 then
		waitForMessage = true
		return
	end
	waitForMessage = false

	-- then check if motd should be shown on join
	if onJoin == true then
		local dontOpen, lastViewedMOTD, lastViewedRules = getSettings()

		-- Only open if the user checked "don't show again" AND both versions haven't changed
		if dontOpen and lastViewedMOTD == motdVersion and lastViewedRules == rulesVersion then
			return
		end
	end

	-- create gui if necessary and show
	createGui()
	guiSetVisible(gui.window,true)
	showCursor(true)

	-- motd is shown, so update last viewed with both versions
	updateLastViewedMotdVersion(motdVersion, rulesVersion)

	-- Set default tab to Rules for first view
	guiSetSelectedTab(gui.tabPanel, gui.rulesTab)
	updateGuiLabel()
end
addCommandHandler("motd",openGui)


-- FIX: Added /editmotd command handler
addCommandHandler("editmotd",function() sendMessageToServer("edit") end)


--[[
-- closeGui
--
-- Hides the Gui.
-- ]]
function closeGui()
	guiSetVisible(gui.window,false)
	showCursor(false)
end


--[[
-- toggleCheckbox
--
-- Gets the state of the checkbox and saves it.
-- ]]
function toggleCheckbox()
	local checked = guiCheckBoxGetSelected(source)
	changeSetting(checked)
end



-----------------------------------------------------
-- Settings (read and write "dont show again" stuff)
-----------------------------------------------------

local serverNode = {tag="server",create=true,attribute={ip=serverIp,port=serverPort}}

--[[
-- getSettings
--
-- Gets the current settings from the local XML file
--
-- @return   mixed: The settings
-- ]]
function getSettings()
	settings:open()
	local dontShowMotdAgain = settings:getAttribute(serverNode,"dontShowMotdAgain")
	-- Now retrieve two version numbers
	local lastViewedMOTD = tonumber(settings:getAttribute(serverNode,"lastViewedMotdVersion")) or 0
	local lastViewedRules = tonumber(settings:getAttribute(serverNode,"lastViewedRulesVersion")) or 0
	settings:unload()
	if dontShowMotdAgain == "true" then
		return true, lastViewedMOTD, lastViewedRules -- Returns status and both versions
	end
	return false, 0, 0
end

--[[
-- changeSettings
--
-- Sets whether the motd should be shown again in the local XML file.
--
-- @param   boolean   dontShowMotdAgain: Whether the motd should be shown again.
-- ]]
function changeSetting(dontShowMotdAgain)
	settings:setAttribute(serverNode,"dontShowMotdAgain",dontShowMotdAgain)
end

--[[
-- updateLastViewedMotdVersion
--
-- Sets the given motd and rules versions as the last viewed.
--
-- @param   number   motdVer: The MOTD version
-- @param   number   rulesVer: The Rules version
-- ]]
function updateLastViewedMotdVersion(motdVer, rulesVer)
	settings:setAttribute(serverNode,"lastViewedMotdVersion",motdVer)
	settings:setAttribute(serverNode,"lastViewedRulesVersion",rulesVer) -- New: Track rules version
end

-- ## on start of resource

--[[
-- initiate
--
-- Initiate the XML File and try to open the gui (this is on join).
-- ]]
function initiate()
	settings = Xml:new("settings.xml","settings") -- Moved XML object creation here
	openGui(true)
end
addEventHandler("onClientResourceStart",resourceRoot,initiate)



-------------------------------
-- Client/Server Communication
-------------------------------

--[[
-- sendMessageToServer
--
-- Sends the given message with some data to the server.
--
-- @param   string   message: The 'type' of the message
-- @param   mixed    parameter: Any data (e.g. a table)
-- ]]
function sendMessageToServer(message,parameter)
	triggerServerEvent("onMotdClientMessage",root,message,parameter)
end

--[[
-- serverMessage
--
-- Handles message sent from the server.
--
-- @param   string   message: The 'type' of the message
-- @param   mixed    parameter: The data
-- ]]
function serverMessage(message,parameter)
	if message == "get" then
		-- Parameter is now a table of two tables: {motdTable, rulesTable}
		local motdData = parameter[1] -- {text, version, lastChanged}
		local rulesData = parameter[2] -- {text, version, lastChanged}

		-- Update MOTD variables
		motdText = motdData[1]
		motdVersion = motdData[2]
		motdLastChanged = motdData[3]

		-- Update Rules variables
		rulesText = rulesData[1]
		rulesVersion = rulesData[2]
		rulesLastChanged = rulesData[3]

		-- Update main GUI if it exists
		if gui.window ~= nil then
			guiSetText(gui.motdMemo, motdText)
			guiSetText(gui.rulesMemo, rulesText)
			updateGuiLabel() -- Update label for current tab
		end

		if waitForMessage then
			openGui(true)
		end

		-- Update edit GUI if it exists
		if editgui.window ~= nil then
			updateEditGuiTexts()
		end
	end
	if message == "edit" then
		openEditGui()
	end
end
addEvent("onClientMotdServerMessage",true)
addEventHandler("onClientMotdServerMessage",root,serverMessage)
