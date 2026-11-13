-- 60_speedwalk: doSpeedWalk() contract and stepping engine.
-- Contract (docs/design.md): reads speedWalkDir/speedWalkPath; confirmed
-- per step (send, then wait for a resolved block); aborts on move-fail.
-- Mudlet calls the global doSpeedWalk() after a path is computed
-- (gotoRoom, map clicks): speedWalkDir is the list of commands,
-- speedWalkPath the list of room ids each step should land in. It is
-- the one global outside `rm` (set at start, cleared by rm.stop).
-- A job is one command sequence at a time, tracked in rm.job.

local T = rm.track

-- Shared guard for every job that sends commands (speedwalk, scan, where).
function rm.canRun()
    if T.following then
        rm.out("refused while following someone", "skip")
    elseif rm.job then
        rm.out("busy with " .. rm.job, "skip")
    else
        return true
    end
end

function rm.speedwalk()
    if not rm.canRun() then return end
    local dirs, path = speedWalkDir, speedWalkPath
    -- unverified: speedWalkDir/speedWalkPath are tables set by Mudlet
    -- (path entries may be strings), and speedWalkPath[i] is the room
    -- reached after step i (the start room is not listed)
    if type(dirs) ~= "table" or #dirs == 0 then return end
    rm.job = "speedwalk"
    local i = 0
    local function step()
        i = i + 1
        if i > #dirs then
            rm.job = nil
            rm.out("speedwalk: arrived", "ok")
            return
        end
        T.exec(dirs[i], function(b, why)
            local want = path and tonumber(path[i])
            if b and T.pos and (not want or T.pos == want) then
                return step()
            end
            rm.job = nil
            rm.out("speedwalk stopped at step " .. i .. " ("
                .. dirs[i] .. "): " .. (why or "unexpected room"), "skip")
        end)
    end
    step()
end

rm.inits[#rm.inits + 1] = function()
    doSpeedWalk = rm.speedwalk
end
