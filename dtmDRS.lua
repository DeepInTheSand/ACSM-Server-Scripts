ac.debug("!version", "dtmDRS v1.2")

--[[
  Server config example (paste into CSP Extra Options):

  [DTM_DRS]
  MAX_PER_SESSION=20     ; Total DRS activations allowed per session  (0 = unlimited)
  MAX_PER_LAP=2          ; DRS activations allowed per lap            (0 = unlimited)
  ACTIVATION_GAP=1.0     ; Gap in seconds to car ahead required to activate DRS
  ACTIVE_PQR=0;0;1       ; Enable in Practice, Qualifying, Race (1=yes, 0=no)
]]

local sim = ac.getSim()
local car = ac.getCar(0)

-- Config defaults (overwritten on welcome)
local maxPerSession = 20
local maxPerLap     = 2
local activationGap = 1.0
local activePQR     = { 0, 0, 1 }

-- Runtime state
local scriptReady        = false
local active             = false
local sessionActivations = 0
local lapActivations     = 0
local gapToAhead         = 999.0
local drsOn              = false  -- our internal DRS state

local hudPos       = ac.storage { pos = vec2(20, 200) }
local flagDragging = false
local flagStartPos = vec2(0, 0)

local drsButton = ac.ControlButton("DRS")

-- ── helpers ──────────────────────────────────────────────────────────────────

local function checkActive()
    local s = ac.getSession(sim.currentSessionIndex).type
    if s == ac.SessionType.Practice then return activePQR[1] == 1
    elseif s == ac.SessionType.Qualify  then return activePQR[2] == 1
    elseif s == ac.SessionType.Race     then return activePQR[3] == 1
    end
    return false
end

local function updateGap()
    gapToAhead = 999.0
    for i = 0, sim.carsCount - 1 do
        local entry = ac.getCar.leaderboard(i)
        if entry and entry.index == 0 then
            if i > 0 then
                local ahead = ac.getCar.leaderboard(i - 1)
                if ahead then
                    gapToAhead = math.abs(ac.getGapBetweenCars(0, ahead.index))
                end
            end
            break
        end
    end
end

local function canActivate()
    return gapToAhead <= activationGap
        and (maxPerLap == 0     or lapActivations     < maxPerLap)
        and (maxPerSession == 0 or sessionActivations < maxPerSession)
end

local function deniedReason()
    if gapToAhead > activationGap then
        return string.format("Gap %.2fs | need < %.1fs to car ahead", gapToAhead, activationGap)
    elseif maxPerLap > 0 and lapActivations >= maxPerLap then
        return string.format("Lap limit reached (%d / %d uses)", lapActivations, maxPerLap)
    end
    return string.format("Session limit reached (%d / %d uses)", sessionActivations, maxPerSession)
end

-- ── DRS button ───────────────────────────────────────────────────────────────

drsButton:onPressed(function()
    if not scriptReady or not active then return end
    if canActivate() then
        drsOn              = true
        lapActivations     = lapActivations     + 1
        sessionActivations = sessionActivations + 1
    else
        ac.setMessage("DRS Unavailable", deniedReason(), nil, 3)
    end
end)

drsButton:onReleased(function()
    drsOn = false
end)

-- ── lifecycle ─────────────────────────────────────────────────────────────────

ac.onOnlineWelcome(function(message, config)
    maxPerSession = config:get("DTM_DRS", "MAX_PER_SESSION", 20)
    maxPerLap     = config:get("DTM_DRS", "MAX_PER_LAP",     2)
    activationGap = config:get("DTM_DRS", "ACTIVATION_GAP",  1.0)
    activePQR[1]  = config:get("DTM_DRS", "ACTIVE_PQR", 0, 1)
    activePQR[2]  = config:get("DTM_DRS", "ACTIVE_PQR", 0, 2)
    activePQR[3]  = config:get("DTM_DRS", "ACTIVE_PQR", 1, 3)
    active      = checkActive()
    scriptReady = true
end)

ac.onSessionStart(function()
    sessionActivations = 0
    lapActivations     = 0
    drsOn              = false
    active = checkActive()
end)

ac.onLapCompleted(0, function()
    lapActivations = 0
    drsOn          = false
end)

-- ── update ────────────────────────────────────────────────────────────────────

function script.update(dt)
    if not scriptReady or not active then return end
    updateGap()
end

function script.frameBegin(dt)
    if not scriptReady or not active then return end
    ac.setDRS(drsOn)  -- enforce our authorised DRS state every frame
end

-- ── UI ───────────────────────────────────────────────────────────────────────

function script.drawUI()
    if not scriptReady or not active then return end

    local W, H = 215, 100

    -- Clamp stored position to keep window on-screen
    hudPos.pos = vec2(
        math.clamp(hudPos.pos.x, 0, sim.windowWidth  - W),
        math.clamp(hudPos.pos.y, 0, sim.windowHeight - H)
    )

    local allowed = canActivate()

    local statusColor, statusText
    if drsOn then
        statusColor = rgbm(0.1, 0.9, 0.1, 1)
        statusText  = "DRS  ACTIVE"
    elseif allowed then
        statusColor = rgbm(1.0, 0.75, 0.0, 1)
        statusText  = "DRS  AVAILABLE"
    else
        statusColor = rgbm(0.55, 0.55, 0.55, 1)
        statusText  = "DRS  CLOSED"
    end

    local lapStr = maxPerLap > 0
        and string.format("%d / %d", lapActivations, maxPerLap)
        or  "unlimited"
    local sesStr = maxPerSession > 0
        and string.format("%d / %d", sessionActivations, maxPerSession)
        or  "unlimited"
    local gapStr = gapToAhead > 99
        and "-- s"
        or  string.format("%.2f s", gapToAhead)

    ui.transparentWindow("DTM_DRS_HUD", hudPos.pos, vec2(W, H), true, true, function()
        ui.drawRectFilled(vec2(0, 0), ui.windowSize(), rgbm(0, 0, 0, 0.65), 5)

        ui.setCursor(vec2(8, 6))
        ui.pushFont(ui.Font.Title)
        ui.pushStyleColor(ui.StyleColor.Text, statusColor)
        ui.text(statusText)
        ui.popStyleColor()
        ui.popFont()

        ui.setCursor(vec2(8, 30))
        ui.pushFont(ui.Font.Small)
        ui.text(string.format("Gap:     %s  (< %.1f s)", gapStr, activationGap))
        ui.text(string.format("Lap:     %s", lapStr))
        ui.text(string.format("Session: %s", sesStr))
        ui.popFont()

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
