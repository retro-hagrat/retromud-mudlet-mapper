-- 80_commands: all aliases (`rm <command>`).
-- Contract (docs/design.md): rmap start/stop/goto/path/where/scan/undo/fix/
-- save/load/prompt(Phase 6)/exits/fail/debug/ui/reload/help. Pure
-- consumer of the other modules.
-- Phase 3: where, scan, undo (start/stop only toggle rm.mapping, which
-- lets `rmap where` create an orphan room when nothing matches).

rm.commands = {}

function rm.commands.help()
    rm.out("retromud " .. rm.version .. " - RetroMUD auto-mapper")
    for _, c in ipairs({
        { "rmap help", "show this text" },
        { "rmap start|stop", "mapping on/off (where may create a room)" },
        { "rmap where", "re-sync position from the room you are in" },
        { "rmap scan", "peer every exit of this room and map the stubs" },
        { "rmap undo", "remove the last auto-created room" },
    }) do
        rm.out(string.format("  <cyan>%-16s<reset>%s", c[1], c[2]), "markup")
    end
end

local T, B = rm.track, rm.build

function rm.commands.start() rm.mapping = true rm.out("mapping on", "ok") end
function rm.commands.stop() rm.mapping = false rm.out("mapping off", "ok") end

local function finish(msg, cb, ok)
    rm.job = nil
    T.focus()
    if msg then rm.out(msg, ok and "ok" or "skip") end
    if cb then cb(ok) end
end

-- Neighbour of room `id` through exit `ex` (linked or special), or nil.
local function beyond(id, ex)
    return getRoomExits(id)[ex] or getSpecialExitsSwap(id)[ex]
end

-- Peer each exit of `b` and drop candidate rooms whose known neighbour
-- through that exit has another fingerprint. Calls done(room or nil).
local function narrow(c, b, i, done)
    if #c == 1 then return done(c[1]) end
    local ex = b.exits[i]
    if not ex then return done(nil) end
    T.exec("peer " .. ex, function(pb)
        if pb then
            local keep = {}
            for _, id in ipairs(c) do
                local n = beyond(id, ex)
                if not n or B.fp(n) == pb.fingerprint then
                    keep[#keep + 1] = id
                end
            end
            c = keep
        end
        narrow(c, b, i + 1, done)
    end)
end

-- rmap where: look; unique fingerprint -> synced; several -> disambiguate
-- by peering; none -> report (or adopt when mapping). cb(ok) when done.
local function where(cb)
    T.exec("look", function(b)
        if not b then return finish("where: no room seen", cb, false) end
        local c = B.candidates(b.fingerprint)
        if #c == 1 then
            T.pos = c[1]
            return finish("where: synced", cb, true)
        end
        if #c == 0 then
            if not rm.mapping then
                return finish("where: no match in the map", cb, false)
            end
            T.adopt(b)
            return finish("where: created a new room", cb, true)
        end
        narrow(c, b, 1, function(id)
            if not id then
                return finish("where: could not narrow to one room", cb, false)
            end
            T.pos = id
            finish("where: synced", cb, true)
        end)
    end)
end

function rm.commands.where()
    if not rm.canRun() then return end
    rm.job = "where"
    where()
end

-- rmap scan: peer every exit that is not already linked to a real room.
function rm.commands.scan()
    if not rm.canRun() then return end
    rm.job = "scan"
    local function scan()
        T.exec("look", function(b)
            local cur = T.pos
            if not b or not cur or B.fp(cur) ~= b.fingerprint then
                return finish("scan: position lost", nil)
            end
            -- cardinals first: freeform rooms take the nearest free cell
            -- and must not squat on a cardinal neighbour's cell
            local order = {}
            for _, want in ipairs({ true, false }) do
                for _, ex in ipairs(b.exits) do
                    if (rm.settings.dirs[ex] ~= nil) == want then
                        order[#order + 1] = ex
                    end
                end
            end
            local made, i = 0, 0
            local function nextExit()
                i = i + 1
                local ex = order[i]
                if not ex then
                    return finish("scan: done, " .. made .. " new", nil, true)
                end
                local to = beyond(cur, ex)
                if to and getRoomUserData(to, "source") ~= "peer" then
                    return nextExit()
                end
                T.exec("peer " .. ex, function(pb)
                    if pb then
                        local n = #B.created
                        if rm.settings.dirs[ex] then
                            B.advance(cur, ex, pb, true)
                        else
                            B.special(cur, ex, pb, true)
                        end
                        made = made + #B.created - n
                    end
                    nextExit()
                end)
            end
            nextExit()
        end)
    end
    if T.state() ~= "UNSYNCED" then return scan() end
    where(function(ok)
        if not ok then return finish("scan: could not sync", nil) end
        rm.job = "scan"
        scan()
    end)
end

function rm.commands.undo()
    local e = B.undo()
    if not e then return rm.out("undo: nothing to undo", "skip") end
    if T.pos == e.id then T.pos = nil end
    rm.out("undo: removed '" .. e.name .. "' (room " .. e.id .. ")", "ok")
end

function rm.command(arg)
    local cmd = arg:match("^%s*(%S*)")
    if cmd == "" then cmd = "help" end
    local fn = rm.commands[cmd]
    if fn then
        fn()
    else
        rm.out("unknown command '" .. cmd .. "'. Try 'rmap help'.", "err")
    end
end

rm.inits[#rm.inits + 1] = function()
    -- unverified: an unmatched optional group leaves matches[2] nil or ""
    rm.alias("^rmap( .*)?$", function() rm.command(matches[2] or "") end)
end

-- Last module: a script re-run (save in the editor) does not raise
-- sysLoadEvent again, so resume if the previous instance was running.
if rm.restart then rm.restart = nil rm.start() end
