-- Custom polls by Ali Digitali
-- anyone reading this has permission to coppy parts of this script


GUIEditor = {
	button = {},
	window = {},
	label = {},
	edit = {}
}
addEventHandler("onClientResourceStart", resourceRoot,
	function()
		-- main window
		GUIEditor.window[1] = guiCreateWindow(334, 198, 698, 387, "Make a Poll GUI", false)
		guiWindowSetSizable(GUIEditor.window[1], false)
		guiSetAlpha(GUIEditor.window[1], 0.90)


		-- buttons
		GUIEditor.button[1] = guiCreateButton(24, 33, 84, 33, "Start Poll", false, GUIEditor.window[1])
		guiSetProperty(GUIEditor.button[1], "NormalTextColour", "FFAAAAAA")

		GUIEditor.button[2] = guiCreateButton(133, 33, 84, 33, "Clear All", false, GUIEditor.window[1])
		guiSetProperty(GUIEditor.button[2], "NormalTextColour", "FFAAAAAA")

		GUIEditor.button[3] = guiCreateButton(589, 33, 84, 33, "Close", false, GUIEditor.window[1])
		guiSetProperty(GUIEditor.button[3], "NormalTextColour", "FFAAAAAA")

		-- error message
		GUIEditor.label[11] = guiCreateLabel(235, 39, 338, 22, "", false, GUIEditor.window[1])
		guiSetFont(GUIEditor.label[11], "default-bold-small")
		guiLabelSetColor(GUIEditor.label[11], 254, 0, 0)

		-- question Box
		questionBox = guiCreateEdit(87, 76, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.label[10] = guiCreateLabel(24, 76, 87, 21, "Question:", false, GUIEditor.window[1])

		-- answer boxes
		GUIEditor.edit[1] = guiCreateEdit(87, 109, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.edit[2] = guiCreateEdit(87, 137, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.edit[3] = guiCreateEdit(87, 168, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.edit[4] = guiCreateEdit(87, 196, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.edit[5] = guiCreateEdit(87, 224, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.edit[6] = guiCreateEdit(87, 252, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.edit[7] = guiCreateEdit(87, 280, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.edit[8] = guiCreateEdit(87, 308, 435, 21, "", false, GUIEditor.window[1])
		GUIEditor.edit[9] = guiCreateEdit(87, 336, 435, 21, "", false, GUIEditor.window[1])

		-- labels for answer boxes
		GUIEditor.label[1] = guiCreateLabel(62, 112, 25, 18, "1.", false, GUIEditor.window[1])
		GUIEditor.label[2] = guiCreateLabel(62, 140, 25, 18, "2.", false, GUIEditor.window[1])
		GUIEditor.label[3] = guiCreateLabel(62, 168, 25, 18, "3.", false, GUIEditor.window[1])
		GUIEditor.label[4] = guiCreateLabel(62, 196, 25, 18, "4.", false, GUIEditor.window[1])
		GUIEditor.label[5] = guiCreateLabel(62, 224, 25, 18, "5.", false, GUIEditor.window[1])
		GUIEditor.label[6] = guiCreateLabel(62, 252, 25, 18, "6.", false, GUIEditor.window[1])
		GUIEditor.label[7] = guiCreateLabel(62, 280, 25, 18, "7.", false, GUIEditor.window[1])
		GUIEditor.label[8] = guiCreateLabel(62, 308, 25, 18, "8.", false, GUIEditor.window[1])
		GUIEditor.label[9] = guiCreateLabel(62, 336, 25, 18, "9.", false, GUIEditor.window[1])

		-- duration
		GUIEditor.label[12] = guiCreateLabel(528, 78, 112, 21, "Poll Duration:", false, GUIEditor.window[1])
		GUIEditor.edit[11] = guiCreateEdit(613, 79, 44, 18, "15", false, GUIEditor.window[1])
		guiEditSetMaxLength(GUIEditor.edit[11], 3)

		-- hide the window
		guiSetVisible(GUIEditor.window[1], false)

		-- add handlers for the buttons
		addEventHandler("onClientGUIClick", GUIEditor.button[1], sendPoll, false)
		addEventHandler("onClientGUIClick", GUIEditor.button[2], resetInput, false)
		addEventHandler("onClientGUIClick", GUIEditor.button[3], closeWindow, false)
	end
)

function sendPoll ()
	-- clear error message if there is one
	guiSetProperty(GUIEditor.label[11], "Text","" )

	-- get the question and put the answers in a table
	local question = guiGetText(questionBox)
	if (question == "") then question = " " end

	local options = {}
	for i=1,9 do
		local optionText = guiGetText(GUIEditor.edit[i])
		if (optionText ~= "") then
			table.insert(options,{optionText})
		end
	end

	if (#options < 2) then
		guiSetProperty(GUIEditor.label[11], "Text","Error: You need at least two answers" )
		return
	end

	local duration = tonumber(guiGetText(GUIEditor.edit[11]))
	if not duration then
		duration = 15
		guiSetProperty(GUIEditor.label[11], "Text","Warning: used default value of 15 for duration" )
	end
	-- send the poll to the server
	triggerServerEvent("voteStart", root,question,options,duration)
end

-- function to reset all the input fields
function resetInput()
	guiSetProperty(GUIEditor.label[11], "Text","" )
	guiSetProperty(questionBox,"Text","" )
	for i=1,9 do
		if GUIEditor.edit[i] then
			guiSetProperty(GUIEditor.edit[i], "Text","" )
		end
	end
end

-- function to change the error label, triggerable from serverside
function updateErrorBoxHandler(didPollStart,errorCode)
	if didPollStart then
		closeWindow()
	elseif errorCode == 10 then
		guiSetProperty(GUIEditor.label[11],"Text","Error: another poll is currently running")
	end
end
addEvent("updateErrorBox",true)
addEventHandler("updateErrorBox",root,updateErrorBoxHandler)

-- close the gui window
function closeWindow()
	guiSetVisible(GUIEditor.window[1], false)
	showCursor(false)
	guiSetInputEnabled(false)
end

-- open the gui window, triggered from serverside after rights check
function showPollGuiHandler()
	guiSetVisible(GUIEditor.window[1], true)
	showCursor(true)
	guiSetInputEnabled(true)
end
addEvent("showPollGui",true)
addEventHandler("showPollGui",root,showPollGuiHandler)

-- check the rights of the player using /poll
function checkRights ()
	triggerServerEvent ("checkRight", localPlayer)
end
addCommandHandler ("poll", checkRights )
