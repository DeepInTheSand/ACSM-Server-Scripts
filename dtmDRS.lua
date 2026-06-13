ac.debug("!version", "dtmDRS v1.6")

--[[
  Server config example (paste into CSP Extra Options):

  [DTM_DRS]
  MAX_PER_SESSION=20     ; Total DRS activations allowed per session  (0 = unlimited, practice ignores this)
  MAX_PER_LAP=2          ; DRS activations allowed per lap            (0 = unlimited)
  ACTIVATION_GAP=1.0     ; Gap in seconds to car ahead required to activate DRS (practice ignores this)
  ACTIVE_PQR=1;0;1       ; Enable in Practice, Qualifying, Race (1=yes, 0=no)
]]

local sim = ac.getSim()
local car = ac.getCar(0)

-- Config defaults (overwritten on welcome)
local maxPerSession = 20
local maxPerLap     = 2
local activationGap = 1.0
local activePQR     = { 1, 0, 1 }

-- Runtime state
local scriptReady        = false
local active             = false
local sessionActivations = 0
local lapActivations     = 0
local gapToAhead         = 999.0
local drsOn              = false

local hudPos       = ac.storage { pos = vec2(20, 200) }
local flagDragging = false
local flagStartPos = vec2(0, 0)

local drsButton = ac.ControlButton("DRS")

-- ── helpers ──────────────────────────────────────────────────────────────────

local function sessionTypeNow()
    return ac.getSession(ac.getSim().currentSessionIndex).type
end

local function isPracticeNow()
    return sessionTypeNow() == ac.SessionType.Practice
end

local function activateForSession(sType)
    if sType == ac.SessionType.Practice then
        active = activePQR[1] == 1
    elseif sType == ac.SessionType.Qualify then
        active = activePQR[2] == 1
    elseif sType == ac.SessionType.Race then
        active = activePQR[3] == 1
    else
        active = true  -- unknown session: don't silently disable
    end
end

-- Gap via spline positions (avoids ac.getGapBetweenCars which internally uses
-- lapCount — always 0 for other cars online, breaking results after lap 1).
-- Formula mirrors CMRT leaderboard: splineDiff * trackLengthM / speed.
local function updateGap()
    gapToAhead = 999.0
    local myPos = car.racePosition
    if myPos <= 1 then return end  -- P1 has nobody ahead

    for i = 1, sim.carsCount - 1 do
        local other = ac.getCar(i)
        if other ~= nil and other.racePosition == myPos - 1 then
            local delta = other.splinePosition - car.splinePosition
            if delta < 0 then delta = delta + 1.0 end  -- car ahead just crossed the line
            local speed = math.max(car.speedMs, 14.0)  -- floor at 65 km/h avoids huge gaps when slow
            gapToAhead = delta * sim.trackLengthM / speed
            break
        end
    end
end

local function canActivate()
    local practice  = isPracticeNow()
    local gapOk     = practice or gapToAhead <= activationGap
    local sessionOk = practice or (maxPerSession == 0 or sessionActivations < maxPerSession)
    local lapOk     = maxPerLap == 0 or lapActivations < maxPerLap
    return gapOk and lapOk and sessionOk
end

local function deniedReason()
    local practice = isPracticeNow()
    if not practice and gapToAhead > activationGap then
        return string.format("Gap %.2fs | need < %.1fs to car ahead", gapToAhead, activationGap)
    elseif maxPerLap > 0 and lapActivations >= maxPerLap then
        return string.format("Lap limit reached (%d / %d uses)", lapActivations, maxPerLap)
    end
    return string.format("Session limit reached (%d / %d uses)", sessionActivations, maxPerSession)
end

-- ── DRS button (toggle) ───────────────────────────────────────────────────────

drsButton:onPressed(function()
    if not scriptReady or not active then return end
    if drsOn then
        drsOn = false
    elseif canActivate() then
        drsOn              = true
        lapActivations     = lapActivations     + 1
        sessionActivations = sessionActivations + 1
    else
        ac.setMessage("DRS Unavailable", deniedReason(), nil, 3)
    end
end)

-- ── lifecycle ─────────────────────────────────────────────────────────────────

ac.onOnlineWelcome(function(message, config)
    maxPerSession = config:get("DTM_DRS", "MAX_PER_SESSION", 20)
    maxPerLap     = config:get("DTM_DRS", "MAX_PER_LAP",     2)
    activationGap = config:get("DTM_DRS", "ACTIVATION_GAP",  1.0)
    activePQR[1]  = config:get("DTM_DRS", "ACTIVE_PQR", 1, 1)
    activePQR[2]  = config:get("DTM_DRS", "ACTIVE_PQR", 0, 2)
    activePQR[3]  = config:get("DTM_DRS", "ACTIVE_PQR", 1, 3)
    activateForSession(sessionTypeNow())
    scriptReady = true
end)

ac.onSessionStart(function(sessionIndex, restarted)
    sessionActivations = 0
    lapActivations     = 0
    drsOn              = false
    activateForSession(ac.getSession(sessionIndex).type)
end)

ac.onLapCompleted(0, function()
    lapActivations = 0
    -- drsOn is intentionally NOT reset — carry-over activation is allowed
end)

-- ── update ────────────────────────────────────────────────────────────────────

function script.update(dt)
    if not scriptReady or not active then return end
    updateGap()
    if drsOn and car.brake > 0 then
        drsOn = false
    end
end

function script.frameBegin(dt)
    if not scriptReady or not active then return end
    ac.setDRS(drsOn)
end

-- ── UI ───────────────────────────────────────────────────────────────────────

function script.drawUI()
    if not scriptReady or not active then return end

    local practice = isPracticeNow()
    local W = 220
    local H = practice and 64 or 98

    hudPos.pos = vec2(
        math.clamp(hudPos.pos.x, 0, sim.windowWidth  - W),
        math.clamp(hudPos.pos.y, 0, sim.windowHeight - H)
    )

    local accentCol, labelText
    if drsOn then
        accentCol = rgbm(0.08, 0.88, 0.08, 1)
        labelText = "DRS  ACTIVE"
    elseif canActivate() then
        accentCol = rgbm(1.0, 0.68, 0.0, 1)
        labelText = "DRS  AVAILABLE"
    else
        accentCol = rgbm(0.42, 0.42, 0.42, 1)
        labelText = "DRS  CLOSED"
    end

    local dimText = rgbm(0.60, 0.60, 0.60, 1)
    local dimPip  = rgbm(0.20, 0.20, 0.20, 1)

    ui.transparentWindow("DTM_DRS_HUD", hudPos.pos, vec2(W, H), true, true, function()
        ui.drawRectFilled(vec2(0, 0), vec2(W, H), rgbm(0, 0, 0, 0.76))
        ui.drawRectFilled(vec2(0, 0), vec2(4, H), accentCol)

        ui.setCursor(vec2(12, 6))
        ui.pushFont(ui.Font.Title)
        ui.pushStyleColor(ui.StyleColor.Text, accentCol)
        ui.text(labelText)
        ui.popStyleColor()
        ui.popFont()

        ui.drawRectFilled(vec2(12, 28), vec2(W - 8, 29), rgbm(1, 1, 1, 0.10))

        -- Lap pips + count
        local pipR    = 4
        local pipStep = 14
        local pipX    = 14
        local pipY    = 46
        local textX   = pipX

        if maxPerLap > 0 and maxPerLap <= 8 then
            for p = 1, maxPerLap do
                local c = p <= lapActivations and dimPip or accentCol
                ui.drawCircleFilled(vec2(pipX + (p - 1) * pipStep, pipY), pipR, c, 12)
            end
            textX = pipX + (maxPerLap - 1) * pipStep + pipR + 10
        end

        ui.setCursor(vec2(textX, 39))
        ui.pushStyleColor(ui.StyleColor.Text, dimText)
        if maxPerLap == 0 then
            ui.text("Lap  —")
        else
            ui.text(string.format("%d / %d  lap", lapActivations, maxPerLap))
        end
        ui.popStyleColor()

        if not practice then
            ui.drawRectFilled(vec2(12, 60), vec2(W - 8, 61), rgbm(1, 1, 1, 0.10))

            local gapStr = gapToAhead > 99
                and "--"
                or  string.format("%.2f s", gapToAhead)
            local sesStr = maxPerSession == 0
                and "--"
                or  string.format("%d left", maxPerSession - sessionActivations)

            ui.pushStyleColor(ui.StyleColor.Text, dimText)
            ui.setCursor(vec2(14, 65))
            ui.text(string.format("Gap      %s  < %.1f s", gapStr, activationGap))
            ui.setCursor(vec2(14, 81))
            ui.text(string.format("Session  %s", sesStr))
            ui.popStyleColor()
        end

        if ui.windowHovered(ui.HoveredFlags.RectOnly) then
            if ui.isMouseDragging(ui.MouseButton.Left) and not flagDragging then
                flagStartPos = ui.windowPos()
                flagDragging = true
            end
        end
        if flagDragging and ui.mouseDragDelta(ui.MouseButton.Left) ~= vec2(0, 0) then
            hudPos.pos = flagStartPos + ui.mouseDragDelta()
        else
            flagDragging = false
        end
    end)
end
