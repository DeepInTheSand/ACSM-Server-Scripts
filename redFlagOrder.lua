-- redFlagOrder.lua
-- Admin button to display race order at the last timing line each driver crossed.
-- Used for red flag procedures. Supports variable sector counts.
--
-- Server config ([REDFLAGORDER] section):
--   SECTOR_SPLITS = 0.333|0.667   (spline positions of sector boundary lines; default = even thirds)
--   ADMIN_ONLY    = 1             (1 = admin only, 0 = all players)

local sim = ac.getSim()
local adminFlag = ui.OnlineExtraFlags.Admin

-- Sector boundary spline positions (sorted ascending). Default: 3 sectors split evenly.
local sectorSplits = {1/3, 2/3}

-- Returns 0-based sector index from a spline position
local function sectorAt(spline)
    for i = #sectorSplits, 1, -1 do
        if spline >= sectorSplits[i] then return i end
    end
    return 0
end

-- Per-car tracking
-- crossingTime[carIdx][sectorIdx] = sim.currentSessionTime when that sector line was first crossed this lap
local crossingTime = {}
local trackSector = {}
local trackLap = {}

local function initCar(i)
    crossingTime[i] = {}
    trackSector[i] = -1  -- -1 = not yet observed
    trackLap[i] = -1
end

for i = 0, 199 do initCar(i) end

ac.onOnlineWelcome(function(message, config)
    if config:get("REDFLAGORDER", "ADMIN_ONLY", 1) == 1 then
        adminFlag = ui.OnlineExtraFlags.Admin
    else
        adminFlag = ui.OnlineExtraFlags.None
    end

    -- Read sector split spline positions: SECTOR_SPLITS=0.333|0.667 for 3 sectors, etc.
    local splits = {}
    for idx = 1, 10 do
        local v = config:get("REDFLAGORDER", "SECTOR_SPLITS", -1, idx)
        if v < 0 then break end
        table.insert(splits, v)
    end
    if #splits > 0 then
        table.sort(splits)
        sectorSplits = splits
    end

    ui.registerOnlineExtra(ui.Icons.Flag, "Red Flag Order", function() return true end, nil,
        function(okClicked)
            local entries = {}

            for i = 0, sim.carsCount - 1 do
                local car = ac.getCar(i)
                if car == nil or not car.isConnected then goto continue end

                local spline = car.splinePosition
                local lapCount = car.lapCount
                local sector = sectorAt(spline)
                local t = (crossingTime[i] and crossingTime[i][sector]) or math.huge
                local pitLabel = car.isInPitlane and " (PIT)" or ""

                table.insert(entries, {
                    score = lapCount * 1000 + sector,  -- higher = further ahead
                    time = t,       -- lower = crossed this line first = was ahead
                    spline = spline, -- fallback tiebreaker within same (lap, sector)
                    lap = lapCount,
                    sector = sector,
                    name = car:driverName() .. pitLabel
                })

                ::continue::
            end

            -- score desc → crossing session time asc → spline position desc
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
            ac.log("Red Flag Order: " .. #entries .. " cars, " .. (#sectorSplits + 1) .. " sectors")
        end, adminFlag)
end)

ac.debug("!version", "redFlagOrder v1.1")

local updateTimer = 0

function script.update(dt)
    updateTimer = updateTimer - dt
    if updateTimer > 0 then return end
    updateTimer = 1.0  -- poll once per second

    for i = 0, sim.carsCount - 1 do
        local car = ac.getCar(i)
        if car == nil or not car.isConnected then goto continue end
        if crossingTime[i] == nil then initCar(i) end

        local spline = car.splinePosition
        local sector = sectorAt(spline)
        local lap = car.lapCount

        if trackLap[i] == -1 then
            -- First observation: record state without inventing a crossing time.
            -- If they happen to be at sector 0 (just crossed S/F), record it.
            trackLap[i] = lap
            trackSector[i] = sector
            if sector == 0 then
                crossingTime[i][0] = sim.currentSessionTime
            end
            goto continue
        end

        if lap ~= trackLap[i] then
            -- Crossed S/F line into a new lap
            crossingTime[i] = {}
            crossingTime[i][0] = sim.currentSessionTime
            trackLap[i] = lap
            trackSector[i] = 0
        elseif sector > trackSector[i] then
            -- Crossed one or more sector timing lines (record all in case of gap)
            for s = trackSector[i] + 1, sector do
                crossingTime[i][s] = sim.currentSessionTime
            end
            trackSector[i] = sector
        end

        ::continue::
    end
end
