-- Tabla de resultados al terminar la ronda (sr:results).
-- La Task 5 agrega la votacion; por ahora la tabla se oculta sola o al empezar otra ronda.
SR = SR or {}

local SHOW_MS = 12000
local FONT_TITLE = "pricedown"
local FONT_BIG = "bankgothic"
local FONT_SMALL = "default-bold"

local rows, title, record = nil, "", nil
local showAt, hideAt = 0, 0
local shownYet = false

addEvent("sr:results", true)

function SR.hideResults()
    rows, record = nil, nil
    SR.resultsVisible = false
end

addEventHandler("sr:results", resourceRoot, function(rankedRows, missionTitle, recordRow)
    if type(rankedRows) ~= "table" then return end
    rows = rankedRows
    title = tostring(missionTitle or "")
    record = type(recordRow) == "table" and recordRow or nil
    -- Si hay un GXT de falla / cumplida a medias, la tabla espera a que cumpla su tiempo.
    showAt = getTickCount() + (SR.missionTextRemainingMs and SR.missionTextRemainingMs() or 0)
    shownYet = false
    SR.resultsVisible = true
    if SR.endRound then SR.endRound() end
end)

local function clean(name)
    return (tostring(name):gsub("#%x%x%x%x%x%x", ""))
end

addEventHandler("onClientRender", root, function()
    if not rows then return end
    local now = getTickCount()
    if now < showAt then return end
    if not shownYet then
        shownYet = true
        hideAt = now + SHOW_MS
    end
    if now > hideAt then
        SR.hideResults()
        return
    end
    local sw, sh = guiGetScreenSize()
    local ui, drawText = SR.ui, SR.drawText

    local rowH = ui(34)
    local w = ui(760)
    local shown = math.min(#rows, 12)
    local h = ui(110) + rowH * (shown + 1) + (record and rowH or 0)
    local x = (sw - w) / 2
    local y = math.max(ui(20), (sh - h) / 2)

    dxDrawRectangle(x, y, w, h, tocolor(0, 0, 0, 175))
    drawText("RESULTADOS", x, y + ui(8), x + w, y + ui(48), tocolor(255, 220, 60, 255), ui(1.5), FONT_TITLE)
    drawText(title, x, y + ui(48), x + w, y + ui(80), tocolor(255, 255, 255, 255), ui(1.1), FONT_SMALL)

    local colPos, colName, colTime, colFails = x + ui(20), x + ui(90), x + w - ui(250), x + w - ui(20)
    local ry = y + ui(90)
    local head = tocolor(190, 190, 190, 255)
    drawText("Pos", colPos, ry, colPos + ui(60), ry + rowH, head, ui(1), FONT_SMALL, "left")
    drawText("Jugador", colName, ry, colName + ui(300), ry + rowH, head, ui(1), FONT_SMALL, "left")
    drawText("Tiempo", colTime, ry, colTime + ui(130), ry + rowH, head, ui(1), FONT_SMALL, "left")
    drawText("Fallos", colFails - ui(80), ry, colFails, ry + rowH, head, ui(1), FONT_SMALL, "right")
    ry = ry + rowH

    for i = 1, shown do
        local r = rows[i]
        local finished = r.position ~= nil
        local color = finished and tocolor(255, 255, 255, 255) or tocolor(170, 170, 170, 255)
        drawText(finished and (r.position .. "º") or "-", colPos, ry, colPos + ui(60), ry + rowH, color, ui(1.1), FONT_SMALL, "left")
        drawText(clean(r.name), colName, ry, colName + ui(300), ry + rowH, color, ui(1.1), FONT_SMALL, "left")
        drawText(tostring(r.timeText), colTime, ry, colTime + ui(130), ry + rowH, color, ui(1.1), FONT_SMALL, "left")
        drawText(tostring(r.failures or 0), colFails - ui(80), ry, colFails, ry + rowH, color, ui(1.1), FONT_SMALL, "right")
        ry = ry + rowH
    end

    if record then
        drawText(("Récord: %s  %s"):format(clean(record.name or "?"), tostring(record.timeText or "")),
            x, ry, x + w, ry + rowH, tocolor(255, 220, 60, 255), ui(1.1), FONT_SMALL)
    end
end)
