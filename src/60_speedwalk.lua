-- 60_speedwalk: doSpeedWalk() contract and stepping engine.
-- Contract (docs/design.md): reads speedWalkDir/speedWalkPath; confirmed
-- per step (send, then wait for a resolved block); aborts on move-fail.
-- Mudlet calls the global doSpeedWalk() after a path is computed
-- (gotoRoom, map clicks): speedWalkDir is the list of commands,
-- speedWalkPath the list of room ids each step should land in. It is
-- the one global outside `rmap` (set at start, cleared by rmap.stop).
-- A job is one command sequence at a time, tracked in rmap.job.

local T = rmap.track

-- Shared guard for every job that sends commands (speedwalk, scan, where).
function rmap.canRun()
    if T.following then
        rmap.out("refused while following someone", "skip")
    elseif rmap.job then
        rmap.out("busy with " .. rmap.job, "skip")
    else
        return true
    end
end

function rmap.speedwalk()
    if not rmap.canRun() then return end
    local dirs, path = speedWalkDir, speedWalkPath
    -- unverified: speedWalkDir/speedWalkPath are tables set by Mudlet
    -- (path entries may be strings), and speedWalkPath[i] is the room
    -- reached after step i (the start room is not listed)
    if type(dirs) ~= "table" or #dirs == 0 then return end
    rmap.job = "speedwalk"
    rmap.jobId = (rmap.jobId or 0) + 1
    local id = rmap.jobId
    -- a late callback of a cancelled walk must not step or clear a newer job
    local function live() return rmap.job == "speedwalk" and rmap.jobId == id end
    local i = 0
    local function step()
        if not live() then return end
        i = i + 1
        if i > #dirs then
            rmap.job = nil
            rmap.out("speedwalk: arrived", "ok")
            return
        end
        T.exec(dirs[i], function(b, why)
            if not live() then return end
            local want = path and tonumber(path[i])
            if b and T.pos and (not want or T.pos == want) then
                return step()
            end
            rmap.job = nil
            rmap.out("speedwalk stopped at step " .. i .. " ("
                .. dirs[i] .. "): " .. (why or "unexpected room"), "skip")
        end)
    end
    step()
end

rmap.inits[#rmap.inits + 1] = function()
    -- remember the profile's own doSpeedWalk (if any); rmap.stop restores it
    if doSpeedWalk ~= rmap.speedwalk then rmap.prevSpeedWalk = doSpeedWalk end
    doSpeedWalk = rmap.speedwalk
end
