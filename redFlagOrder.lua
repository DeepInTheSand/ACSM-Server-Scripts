-- redFlagOrder.lua
-- Admin button to display race order at the last timing line each driver crossed.
-- Used for red flag procedures. Supports variable sector counts.
--
-- Optional server config ([REDFLAGORDER] section):
--   ADMIN_ONLY = 1   (1 = admin only, 0 = all players; default 1)

local sim = ac.getSim()
local adminFlag = ui.OnlineExtraFlags.Admin

-- Per-car sector crossing data, keyed by car.sessionID (stable online index).
-- crossingTime[sessionID][sectorIdx] = sim.currentSessionTime when that sector line was crossed this lap.
local crossingTime = {}
local trackSector = {}  -- last known car.currentSector per sessionID
local trackLap = {}     -- last known car.lapCount per sessionID

local function initCar(id)
    crossingTime[id] = {}
    trackSector[id] = -1  -- -1 = not yet observed this session
    trackLap[id] = -1
end

for id = 0, 199 do initCar(id) end

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
                    score = lap * 1000 + sector,  -- higher = further ahead in race
                    time = t,                      -- lower = reached this line first = was ahead
                    spline = car.splinePosition,   -- fallback tiebreaker
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

            messageQueue = {}
            table.insert(messageQueue, "=== RED FLAG ORDER (" .. #entries .. " cars) ===")
            for pos, e in ipairs(entries) do
                table.insert(messageQueue, "P" .. pos .. " | " .. e.name ..
                    " | Lap " .. (e.lap + 1) .. " S" .. (e.sector + 1))
            end
            table.insert(messageQueue, "=== END OF ORDER ===")

            ac.setMessage("Red Flag Order", "Order posted to chat.")
            ac.log("Red Flag Order: " .. #entries .. " cars.")
        end, adminFlag)
end)

ac.debug("!version", "redFlagOrder v1.3")

local updateTimer = 0
local messageQueue = {}
local messageTimer = 0

function script.update(dt)
    -- Drain message queue at ~1 message per 0.5s to avoid AC chat flood filter.
    if #messageQueue > 0 then
        messageTimer = messageTimer - dt
        if messageTimer <= 0 then
            ac.sendChatMessage(table.remove(messageQueue, 1))
            messageTimer = 0.5
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
            -- First observation: record without inventing a false crossing time.
            trackLap[id] = lap
            trackSector[id] = sector
            if sector == 0 then
                crossingTime[id][0] = sim.currentSessionTime
            end
            goto continue
        end

        if lap ~= trackLap[id] then
            -- Crossed S/F line — new lap
            crossingTime[id] = {}
            crossingTime[id][0] = sim.currentSessionTime
            trackLap[id] = lap
            trackSector[id] = 0
        elseif sector > trackSector[id] then
            -- Crossed one or more sector timing lines within the lap
            for s = trackSector[id] + 1, sector do
                crossingTime[id][s] = sim.currentSessionTime
            end
            trackSector[id] = sector
        end

        ::continue::
    end
end
