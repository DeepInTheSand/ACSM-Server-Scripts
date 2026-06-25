-- redFlagOrder.lua v2.1
-- Broadcasts one OnlineEvent per car (seq=position). Each event is ~112 bytes,
-- well within the 175-byte struct limit. Clients reassemble and render as drawUI overlay.
--
-- Optional server config ([REDFLAGORDER] section):
--   ADMIN_ONLY = 1   (1 = admin only, 0 = all players; default 1)

local sim = ac.getSim()
local adminFlag = ui.OnlineExtraFlags.Admin

-- Sector crossing data, keyed by car.sessionID.
local crossingTime = {}
local trackSector = {}
local trackLap = {}

local function initCar(id)
    crossingTime[id] = {}
    trackSector[id] = -1
    trackLap[id] = -1
end
for id = 0, 199 do initCar(id) end

-- Display state
local orderLines = nil
local displayTimer = 0

-- Assembly buffer (populated as per-car events arrive)
local pending = nil
local pendingTotal = 0
local pendingCount = 0

-- One event per car. Struct size: 8(key)+1+1+1+1+100 = 112 bytes < 175-byte limit.
local rfOrder = ac.OnlineEvent({
    key    = ac.StructItem.key("Red Flag Order"),
    seq    = ac.StructItem.uint8(),   -- position (1-based)
    total  = ac.StructItem.uint8(),   -- total cars in order
    lap    = ac.StructItem.uint8(),   -- car.lapCount
    sector = ac.StructItem.uint8(),   -- car.currentSector
    name   = ac.StructItem.string(100)
}, function(sender, msg)
    if msg.seq == 1 then
        pending = {}
        pendingTotal = msg.total
        pendingCount = 0
    end

    if pending == nil then return end

    pendingCount = pendingCount + 1
    pending[msg.seq] = "P" .. msg.seq .. "  " .. tostring(msg.name) ..
        "  Lap " .. (msg.lap + 1) .. " S" .. (msg.sector + 1)

    if pendingCount >= pendingTotal then
        orderLines = {"=== RED FLAG ORDER  " .. pendingTotal .. " cars ==="}
        for i = 1, pendingTotal do
            table.insert(orderLines, pending[i] or ("P" .. i .. "  ???"))
        end
        table.insert(orderLines, "(press button again to close)")
        displayTimer = 60
        pending = nil
    end
end, ac.SharedNamespace.ServerScript)

ac.onOnlineWelcome(function(message, config)
    if config:get("REDFLAGORDER", "ADMIN_ONLY", 1) == 1 then
        adminFlag = ui.OnlineExtraFlags.Admin
    else
        adminFlag = ui.OnlineExtraFlags.None
    end

    ui.registerOnlineExtra(ui.Icons.Flag, "Red Flag Order", function() return true end, nil,
        function(okClicked)
            -- Toggle: press again to close.
            if orderLines then
                orderLines = nil
                return
            end

            local entries = {}

            for _, car in ac.iterateCars.serverSlots() do
                if not car.isActive then goto continue end

                local id = car.sessionID
                local sector = car.currentSector
                local lap = car.lapCount
                local t = (crossingTime[id] and crossingTime[id][sector]) or math.huge
                local pitLabel = car.isInPitlane and " (PIT)" or ""

                table.insert(entries, {
                    score  = lap * 1000 + sector,
                    time   = t,
                    spline = car.splinePosition,
                    lap    = lap,
                    sector = sector,
                    name   = tostring(car:driverName()) .. pitLabel
                })

                ::continue::
            end

            if #entries == 0 then
                ac.setMessage("Red Flag Order", "No active cars found.")
                return
            end

            table.sort(entries, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                if a.time  ~= b.time  then return a.time  < b.time  end
                return a.spline > b.spline
            end)

            for pos, e in ipairs(entries) do
                rfOrder({
                    seq    = pos,
                    total  = #entries,
                    lap    = e.lap,
                    sector = e.sector,
                    name   = e.name
                })
            end

            ac.setMessage("Red Flag Order", #entries .. " cars. Order sent to all drivers.")
            ac.log("Red Flag Order: " .. #entries .. " cars broadcast.")
        end, adminFlag)
end)

ac.debug("!version", "redFlagOrder v2.1")

local updateTimer = 0

function script.update(dt)
    if orderLines then
        displayTimer = displayTimer - dt
        if displayTimer <= 0 then orderLines = nil end
    end

    updateTimer = updateTimer - dt
    if updateTimer > 0 then return end
    updateTimer = 1.0

    for _, car in ac.iterateCars.serverSlots() do
        if not car.isActive then goto continue end

        local id = car.sessionID
        if crossingTime[id] == nil then initCar(id) end

        local sector = car.currentSector
        local lap    = car.lapCount

        if trackLap[id] == -1 then
            trackLap[id]   = lap
            trackSector[id] = sector
            if sector == 0 then
                crossingTime[id][0] = sim.currentSessionTime
            end
            goto continue
        end

        if lap ~= trackLap[id] then
            crossingTime[id] = {}
            crossingTime[id][0] = sim.currentSessionTime
            trackLap[id]   = lap
            trackSector[id] = 0
        elseif sector > trackSector[id] then
            for s = trackSector[id] + 1, sector do
                crossingTime[id][s] = sim.currentSessionTime
            end
            trackSector[id] = sector
        end

        ::continue::
    end
end

function script.drawUI()
    if not orderLines then return end

    local lineH = 18
    local w = 420
    local h = #orderLines * lineH + 44

    ui.beginTransparentWindow("rfOrder", vec2(20, 80), vec2(w, h), true)
    ui.pushDWriteFont("Consolas")

    for i, line in ipairs(orderLines) do
        if i == 1 then
            ui.pushStyleColor(ui.StyleColor.Text, rgbm(1, 0.25, 0.25, 1))
            ui.text(line)
            ui.popStyleColor()
        else
            ui.text(line)
        end
    end

    ui.popDWriteFont()

    if ui.button("Close") then orderLines = nil end

    ui.endTransparentWindow()
end
