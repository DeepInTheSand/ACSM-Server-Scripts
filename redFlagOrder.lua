-- redFlagOrder.lua v2.0
-- Admin button broadcasts red flag order via ac.OnlineEvent (same pattern as startLights).
-- All clients receive it and display it as a drawUI overlay. No chat flood issues.
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

-- Display state (populated when OnlineEvent is received).
local orderLines = nil
local displayTimer = 0

-- Broadcast order to all clients; each client renders it locally.
local broadcastOrder = ac.OnlineEvent({
    key = ac.StructItem.key("Red Flag Order"),
    data = ac.StructItem.string(2048)
}, function(sender, msg)
    orderLines = {}
    for line in msg.data:gmatch("[^\n]+") do
        table.insert(orderLines, line)
    end
    displayTimer = 60
end, ac.SharedNamespace.ServerScript)

ac.onOnlineWelcome(function(message, config)
    if config:get("REDFLAGORDER", "ADMIN_ONLY", 1) == 1 then
        adminFlag = ui.OnlineExtraFlags.Admin
    else
        adminFlag = ui.OnlineExtraFlags.None
    end

    ui.registerOnlineExtra(ui.Icons.Flag, "Red Flag Order", function() return true end, nil,
        function(okClicked)
            local entries = {}

            for _, car in ac.iterateCars.serverSlots() do
                if not car.isActive then goto continue end

                local id = car.sessionID
                local sector = car.currentSector
                local lap = car.lapCount
                local t = (crossingTime[id] and crossingTime[id][sector]) or math.huge
                local pitLabel = car.isInPitlane and " (PIT)" or ""

                table.insert(entries, {
                    score = lap * 1000 + sector,
                    time = t,
                    spline = car.splinePosition,
                    lap = lap,
                    sector = sector,
                    name = tostring(car:driverName()) .. pitLabel
                })

                ::continue::
            end

            table.sort(entries, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                if a.time ~= b.time then return a.time < b.time end
                return a.spline > b.spline
            end)

            local lines = {"=== RED FLAG ORDER  " .. #entries .. " cars ==="}
            for pos, e in ipairs(entries) do
                table.insert(lines, "P" .. pos .. "  " .. e.name ..
                    "  Lap " .. (e.lap + 1) .. " S" .. (e.sector + 1))
            end
            table.insert(lines, "(click button again to close)")

            local packed = table.concat(lines, "\n")
            broadcastOrder({data = packed})

            ac.setMessage("Red Flag Order", #entries .. " cars. Order shown to all drivers.")
            ac.log("Red Flag Order broadcast: " .. #entries .. " cars.")
        end, adminFlag)
end)

ac.debug("!version", "redFlagOrder v2.0")

local updateTimer = 0

function script.update(dt)
    if orderLines then
        displayTimer = displayTimer - dt
        if displayTimer <= 0 then
            orderLines = nil
        end
    end

    updateTimer = updateTimer - dt
    if updateTimer > 0 then return end
    updateTimer = 1.0

    for _, car in ac.iterateCars.serverSlots() do
        if not car.isActive then goto continue end

        local id = car.sessionID
        if crossingTime[id] == nil then initCar(id) end

        local sector = car.currentSector
        local lap = car.lapCount

        if trackLap[id] == -1 then
            trackLap[id] = lap
            trackSector[id] = sector
            if sector == 0 then
                crossingTime[id][0] = sim.currentSessionTime
            end
            goto continue
        end

        if lap ~= trackLap[id] then
            crossingTime[id] = {}
            crossingTime[id][0] = sim.currentSessionTime
            trackLap[id] = lap
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
    local w = 400
    local h = #orderLines * lineH + 40

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

    if ui.button("Close") then
        orderLines = nil
    end

    ui.endTransparentWindow()
end
