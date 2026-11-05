local win, grid, combo, paint, buttons, preview, tabPanel, modelTab, globalTab, globalWheelCombo, globalFields, globalChecks
local selected, data, compatible = nil, nil, {}
local modelByIndex = {}
local mapBlocked = false
local globalData = {
	colors = {255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
	wheel = 0,
	useColors = false,
	useWheels = false
}

local wheelByIndex = {}
local wheelNames = {
	[1073] = 'Shadow',
	[1074] = 'Mega',
	[1075] = 'Rimshine',
	[1076] = 'Wires',
	[1077] = 'Classic',
	[1078] = 'Twist',
	[1079] = 'Cutter',
	[1080] = 'Switch',
	[1081] = 'Grove',
	[1082] = 'Import',
	[1083] = 'Dollar',
	[1084] = 'Trance',
	[1085] = 'Atomic',
	[1096] = 'Ahab',
	[1097] = 'Virtual',
	[1098] = 'Access'
}

local upgradeNames = {
	[1000] = 'Pro Spoiler',
	[1001] = 'Win Spoiler',
	[1002] = 'Drag Spoiler',
	[1003] = 'Alpha Spoiler',
	[1014] = 'Champ Scoop',
	[1015] = 'Race Scoop',
	[1016] = 'Worx Scoop',
	[1017] = 'Right Sideskirt',
	[1018] = 'Upswept Exhaust',
	[1019] = 'Twin Exhaust',
	[1020] = 'Large Exhaust',
	[1021] = 'Medium Exhaust',
	[1022] = 'Small Exhaust',
	[1023] = 'Fury Spoiler',
	[1024] = 'Square Fog Lights',
	[1034] = 'Alien Exhaust',
	[1037] = 'Alien Exhaust',
	[1046] = 'Alien Spoiler',
	[1049] = 'Alien Spoiler',
	[1050] = 'X-Flow Spoiler',
	[1058] = 'Alien Spoiler',
	[1060] = 'X-Flow Spoiler',
	[1067] = 'Alien Roof',
	[1071] = 'Alien Spoiler',
	[1072] = 'X-Flow Spoiler',
	[1086] = 'Stereo',
	[1087] = 'Hydraulics',
	[1090] = 'Alien Rear Bumper',
	[1091] = 'X-Flow Rear Bumper',
	[1100] = 'Chrome Grill',
	[1101] = 'Chrome Flames',
	[1102] = 'Chrome Strip',
	[1103] = 'Covertible Roof',
	[1104] = 'Chrome Exhaust',
	[1105] = 'Slamin Exhaust',
	[1138] = 'Alien Spoiler',
	[1139] = 'X-Flow Spoiler',
	[1140] = 'X-Flow Spoiler',
	[1141] = 'Alien Spoiler',
	[1160] = 'X-Flow Front Bumper',
	[1161] = 'Alien Front Bumper',
	[1162] = 'X-Flow Rear Bumper',
	[1163] = 'Alien Rear Bumper',
}

local function upgradeLabel(id, slot)
	return wheelNames[id] or upgradeNames[id] or ((slots and slots[slot]) or 'Tuning') .. ' (' .. id .. ')'
end

local function syncCursor()
	if isElement(win) and guiGetVisible(win) and not mapBlocked then
		if not isCursorShowing() then
			showCursor(true)
		end
		guiBringToFront(win)
	end
end

-- Other resources may hide the cursor on the same F2 keypress.
-- Restore it on the following frame while our menu is open.
addEventHandler('onClientRender', root, function()
	if isElement(win) and guiGetVisible(win) and not mapBlocked and not isCursorShowing() then
		showCursor(true)
	end
end)

addEvent('vc:mapBlocked', true)
addEventHandler('vc:mapBlocked', resourceRoot, function(blocked)
	mapBlocked = blocked == true
	if mapBlocked and isElement(win) then
		guiSetVisible(win, false)
		showCursor(false)
	end
end)

local slots = {
	[0] = 'Spoiler',
	[1] = 'Hood',
	[2] = 'Roof',
	[3] = 'Sideskirt',
	[4] = 'Lights',
	[5] = 'Front bumper',
	[6] = 'Rear bumper',
	[7] = 'Wheels',
	[8] = 'Nitro',
	[9] = 'Hydraulics',
	[10] = 'Front bumper',
	[11] = 'Rear bumper',
	[12] = 'Vent right',
	[13] = 'Vent left',
	[14] = 'Front bullbar',
	[15] = 'Rear bullbar',
	[16] = 'Bullbar'
}

-- Actual MTA slot indices: nitro 8, hydraulics 9; excluded server-side.
local excluded = {
	[8] = true,
	[9] = true
}

local function notify(s)
	outputChatBox('[Customizer] ' .. s, 120, 220, 160)
end

local function updatePreview()
	if isElement(preview) then
		destroyElement(preview)
	end
	if not selected then
		return
	end
	local x, y, z = getElementPosition(localPlayer)
	preview = createVehicle(selected, x, y, z - 100)
	if not preview then
		return
	end
	setElementAlpha(preview, 0)
	compatible = {}
	for slot = 0, 16 do
		if not excluded[slot] then
			compatible[slot] = getVehicleCompatibleUpgrades(preview, slot) or {}
		end
	end

	destroyElement(preview)
	preview = nil
end

local function rebuild()
	guiGridListClear(grid)
	if not data then
		return
	end
	for slot = 0, 16 do
		if not excluded[slot] and compatible[slot] and #compatible[slot] > 0 then
			local r = guiGridListAddRow(grid)
			guiGridListSetItemText(grid, r, 1, (slots[slot] or ('Slot ' .. slot)) .. ' - None', false, false)
			guiGridListSetItemData(grid, r, 1, {
				slot = slot,
				id = 0
			})

			for _, id in ipairs(compatible[slot]) do
				if id ~= 1025 then
					r = guiGridListAddRow(grid)
					guiGridListSetItemText(grid, r, 1, '   ' .. upgradeLabel(id, slot), false, false)
					guiGridListSetItemData(grid, r, 1, {
						slot = slot,
						id = id
					})
				end
			end
		end
	end
end

local function pickModel()
	local item = guiComboBoxGetSelected(combo)
	if not item or item < 0 then
		return
	end
	selected = modelByIndex[item]
	updatePreview()
	if selected then
		data = nil
		guiGridListClear(grid)
		triggerServerEvent('vc:request', resourceRoot, selected)
	end
end

local function open()
	if mapBlocked then
		outputChatBox('[Customizer] Tuning is disabled on this map.', 255, 120, 120)
		return
	end

	if isElement(win) then
		local visible = not guiGetVisible(win)
		guiSetVisible(win, visible)
		showCursor(visible)
		if visible then
			setTimer(syncCursor, 100, 1)
		end
		return
	end

	local sw, sh = guiGetScreenSize()
	win = guiCreateWindow((sw - 690) / 2, (sh - 590) / 2, 690, 590, 'Vehicle Customizer - F2', false)
	guiWindowSetSizable(win, false)
	tabPanel = guiCreateTabPanel(10, 25, 670, 510, false, win)
	modelTab = guiCreateTab('Vehicle tuning', tabPanel)
	globalTab = guiCreateTab('Global colors & wheels', tabPanel)
	guiCreateLabel(20, 20, 200, 20, 'Vehicle model', false, modelTab)
	combo = guiCreateComboBox(20, 50, 320, 350, 'Choose vehicle', false, modelTab)
	local models = {}
	for model = 400, 611 do
		local name = getVehicleNameFromModel(model)
		if name and name ~= '' then
			models[#models + 1] = {
				id = model,
				name = name
			}
		end
	end

	table.sort(models, function(a, b)
		local an, bn = a.name:lower(), b.name:lower()
		if an == bn then
			return a.id < b.id
		end
		return an < bn
	end)

	for _, vehicle in ipairs(models) do
		local i = guiComboBoxAddItem(combo, vehicle.name)
		modelByIndex[i] = vehicle.id
	end

	guiCreateLabel(365, 20, 280, 20, 'Compatible upgrades (select to toggle)', false, modelTab)
	grid = guiCreateGridList(365, 50, 300, 365, false, modelTab)
	guiGridListAddColumn(grid, 'Tuning part', 0.88)
	buttons = {}
	for i = 1, 12 do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local x = 20 + col * 110
		local y = 105 + row * 60
		guiCreateLabel(x, y, 100, 18, ('Color %d - %s'):format(math.floor((i - 1) / 3) + 1, ({'R', 'G', 'B'})[col + 1]), false, modelTab)
		buttons[i] = guiCreateEdit(x, y + 20, 90, 27, '255', false, modelTab)
	end

	guiCreateLabel(20, 345, 200, 20, 'Paintjob', false, modelTab)
	paint = guiCreateComboBox(20, 365, 200, 90, 'Paintjob', false, modelTab)
	for i = 0, 3 do
		guiComboBoxAddItem(paint, i == 3 and 'None' or ('Paintjob ' .. i))
	end

	guiComboBoxSetSelected(paint, 3)
	local save = guiCreateButton(365, 438, 300, 43, 'Save tuning for this vehicle', false, modelTab)
	local close = guiCreateButton(20, 547, 645, 30, 'Close', false, win)
	guiCreateLabel(20, 20, 610, 24, 'These settings apply to every vehicle on every non-blacklisted map.', false, globalTab)
	globalChecks = {}
	globalChecks.colors = guiCreateCheckBox(20, 55, 300, 25, 'Use global colors on all cars', false, false, globalTab)
	globalChecks.wheels = guiCreateCheckBox(355, 55, 280, 25, 'Use global wheels on all cars', false, false, globalTab)
	globalFields = {}
	for i = 1, 12 do
		local col = (i - 1) % 3
		local row = math.floor((i - 1) / 3)
		local x = 20 + col * 110
		local y = 105 + row * 60
		guiCreateLabel(x, y, 100, 18, ('Color %d - %s'):format(math.floor((i - 1) / 3) + 1, ({'R', 'G', 'B'})[col + 1]), false, globalTab)
		globalFields[i] = guiCreateEdit(x, y + 20, 90, 27, '255', false, globalTab)
	end

	guiCreateLabel(360, 100, 260, 20, 'Global wheel design', false, globalTab)
	globalWheelCombo = guiCreateComboBox(360, 125, 270, 300, 'Default / unchanged', false, globalTab)
	wheelByIndex[guiComboBoxAddItem(globalWheelCombo, 'Default / unchanged')] = 0
	local wheelIds = {}
	for id in pairs(wheelNames) do
		wheelIds[#wheelIds + 1] = id
	end

	table.sort(wheelIds)
	for _, id in ipairs(wheelIds) do
		wheelByIndex[guiComboBoxAddItem(globalWheelCombo, wheelNames[id])] = id
	end

	guiComboBoxSetSelected(globalWheelCombo, 0)
	local globalSave = guiCreateButton(360, 420, 270, 42, 'Save global settings', false, globalTab)
	addEventHandler('onClientGUIClick', globalSave, function()
		local colors = {}
		for i = 1, 12 do
			colors[i] = math.max(0, math.min(255, math.floor(tonumber(guiGetText(globalFields[i])) or 255)))
		end

		local wheel = wheelByIndex[guiComboBoxGetSelected(globalWheelCombo)] or 0
		triggerServerEvent('vc:saveGlobal', resourceRoot, {
			colors = colors,
			wheel = wheel,
			useColors = guiCheckBoxGetSelected(globalChecks.colors),
			useWheels = guiCheckBoxGetSelected(globalChecks.wheels)
		})
	end, false)

	triggerServerEvent('vc:requestGlobal', resourceRoot)
	addEventHandler('onClientGUIComboBoxAccepted', combo, pickModel, false)
	-- Choose a useful initial model without relying on unsupported combo item-data APIs.
	local initial = getPedOccupiedVehicle(localPlayer)
	local targetModel = initial and getElementModel(initial) or 400
	for idx, model in pairs(modelByIndex) do
		if model == targetModel then
			guiComboBoxSetSelected(combo, idx)
			break
		end
	end

	pickModel()
	addEventHandler('onClientGUIClick', grid, function()
		if not data then
			return
		end
		local r = guiGridListGetSelectedItem(grid)
		if r < 0 then
			return
		end
		local part = guiGridListGetItemData(grid, r, 1)
		if type(part) ~= 'table' then
			return
		end
		local upgrades = {}
		for _, id in ipairs(data.upgrades or {}) do
			local oldslot = nil
			for slot, ids in pairs(compatible) do
				for _, v in ipairs(ids) do
					if v == id then
						oldslot = slot
						break
					end
				end

				if oldslot then
					break
				end
			end

			if oldslot ~= part.slot then
				table.insert(upgrades, id)
			end
		end

		if part.id ~= 0 then
			table.insert(upgrades, part.id)
		end
		data.upgrades = upgrades
		notify('Selected part #' .. part.id .. ' for slot ' .. part.slot .. '. Save to apply.')
	end, false)

	addEventHandler('onClientGUIClick', save, function()
		if not selected or not data then
			return
		end
		data.colors = {}
		for i = 1, 12 do
			data.colors[i] = math.max(0, math.min(255, math.floor(tonumber(guiGetText(buttons[i])) or 255)))
		end

		data.paintjob = guiComboBoxGetSelected(paint)
		if data.paintjob < 0 then
			data.paintjob = 3
		end
		triggerServerEvent('vc:save', resourceRoot, selected, data)
	end, false)

	addEventHandler('onClientGUIClick', close, function()
		guiSetVisible(win, false)
		showCursor(false)
	end, false)

	showCursor(true)
	setTimer(syncCursor, 100, 1)
end

bindKey('F2', 'down', open)
addEvent('vc:loaded', true)
addEventHandler('vc:loaded', resourceRoot, function(model, saved)
	if model ~= selected or not isElement(win) then
		return
	end
	data = saved or {
		colors = {255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255, 255},
		upgrades = {},
		paintjob = 3
	}

	for i = 1, 12 do
		guiSetText(buttons[i], tostring((data.colors or {})[i] or 255))
	end

	guiComboBoxSetSelected(paint, data.paintjob or 3)
	rebuild()
end)

addEvent('vc:saved', true)
addEventHandler('vc:saved', resourceRoot, function(model) notify('Saved tuning for ' .. getVehicleNameFromModel(model) .. '.') end)
addEvent('vc:globalLoaded', true)
addEventHandler('vc:globalLoaded', resourceRoot, function(saved)
	if type(saved) ~= 'table' then
		return
	end
	globalData = saved
	if not isElement(globalTab) then
		return
	end
	guiCheckBoxSetSelected(globalChecks.colors, saved.useColors == true)
	guiCheckBoxSetSelected(globalChecks.wheels, saved.useWheels == true)
	for i = 1, 12 do
		guiSetText(globalFields[i], tostring((saved.colors or {})[i] or 255))
	end

	for idx, id in pairs(wheelByIndex) do
		if id == (saved.wheel or 0) then
			guiComboBoxSetSelected(globalWheelCombo, idx)
			break
		end
	end
end)

addEvent('vc:globalSaved', true)
addEventHandler('vc:globalSaved', resourceRoot, function()
	notify('Global colors and wheels saved.')
end)
