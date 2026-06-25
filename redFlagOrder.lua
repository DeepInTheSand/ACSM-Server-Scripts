-- redFlagOrder.lua
-- Admin button to display race order at the last timing line each driver crossed.
-- Used for red flag procedures. Supports variable sector counts.

local sim = ac.getSim()
local adminFlag = ui.OnlineExtraFlags.Admin

-- Per-car sector crossing data
-- crossingTime[carIdx][sectorIdx] = sim.currentSessionTime when car entered that sector this lap
local crossingTime = {}
local trackSector = {}  -- last known currentSectorIndex per car
local trackLap = {}     -- last known lapCount per car

local function initCar(i)
    crossingTime[i] = {}
    trackSector[i] = -1  -- -1 = not yet seen
    trackLap[i] = -1
end

for i = 0, 199 do initCar(i) end

ac.onOnlineWelcome(function(message, config)
    if config:get("REDFLAGORDER", "ADMIN_ONLY", 1) == 1 then
        adminFlag = ui.OnlineExtraFlags.Admin
    else
        adminFlag = ui.OnlineExtraFlags.None
    end

    ui.registerOnlineExtra(ui.Icons.Flag, "Red Flag Order", function() return true end, nil,
        function(okClicked)
            local entries = {}

            for i = 0, sim.carsCount - 1 do
                local car = ac.getCar(i)
                if car == nil or not car.isConnected then goto continue end

                local sectorIdx = car.currentSectorIndex
                local lapCount = car.lapCount
                local t = (crossingTime[i] and crossingTime[i][sectorIdx]) or math.huge
                local pitLabel = car.isInPitlane and " (PIT)" or ""

                table.insert(entries, {
                    -- Higher score = further ahead in race
                    score = lapCount * 1000 + sectorIdx,
                    -- Lower crossing session time = reached this timing line first = was ahead
                    time = t,
                    -- Fallback: spline position at moment button was pressed
                    spline = car.splinePosition,
                    lap = lapCount,
                    sector = sectorIdx,
                    name = car:driverName() .. pitLabel
                })

                ::continue::
            end

            -- Sort: score desc → crossing time asc → spline position desc
            table.sort(entries, function(a, b)
                if a.score ~= b.score then return a.score > b.score end
                if a.time ~= b.time then return a.time < b.time end
                return a.spline > b.spline
            end)

            ac.sendChatMessage("=== RED FLAG ORDER ===")
            for pos, e in ipairs(entries) do
                ac.sendChatMessage(string.format("P%d | %s | Lap %d S%d",
                    pos, e.name, e.lap + 1, e.sector + 1))
            end
            ac.sendChatMessage("=== END OF ORDER ===")

            ac.setMessage("Red Flag Order", "Order posted to chat.")
            ac.log("Red Flag Order generated for " .. #entries .. " cars.")
        end, adminFlag)
end)

ac.debug("!version", "redFlagOrder v1.0")

function script.update(dt)
    for i = 0, sim.carsCount - 1 do
        local car = ac.getCar(i)
        if car == nil or not car.isConnected then goto continue end
        if crossingTime[i] == nil then initCar(i) end

        local sector = car.currentSectorIndex
        local lap = car.lapCount

        if trackLap[i] == -1 then
            -- First time seeing this car this session: snapshot current state without
            -- recording a false sector crossing (we don't know when they crossed earlier lines).
            trackLap[i] = lap
            trackSector[i] = sector
            -- Only record a crossing time if they just started a lap (sector 0).
            -- For cars mid-lap, crossingTime stays empty; spline is used as fallback.
            if sector == 0 then
                crossingTime[i][0] = sim.currentSessionTime
            end
            goto continue
        end

        if lap ~= trackLap[i] then
            -- Crossed start/finish line into a new lap
            crossingTime[i] = {}
            crossingTime[i][0] = sim.currentSessionTime
            trackLap[i] = lap
            trackSector[i] = 0
        elseif sector ~= trackSector[i] then
            -- Crossed a sector timing line within the current lap
            crossingTime[i][sector] = sim.currentSessionTime
            trackSector[i] = sector
        end

        ::continue::
    end
end
