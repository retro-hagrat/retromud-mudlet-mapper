-- 40_tracker: expectation queue and sync state.
-- Contract (docs/design.md, docs/mapper-protocol.md): sysDataSendRequest
-- pushes one classified expectation (VERIFY / PREVIEW / ADVANCE /
-- MAYBE_MOVE) per sent command; sync state is SYNCED / UNSYNCED /
-- PENDING; each rmap.onRoom block resolves the queue head. Decides
-- advance/verify/preview. Never writes the graph (rmap.build does).
-- Rules 3 and 4 of the protocol hold by construction: T.send below is
-- the only function that pushes onto the queue; no module calls
-- sendSocket or pushes directly.

rmap.track = { q = {}, pos = nil, handled = false, following = false }
local T = rmap.track

-- name or abbreviation -> full direction name
local dirAlias = {}
for name, d in pairs(rmap.settings.dirs) do
    dirAlias[name] = name
    dirAlias[d.abbr] = name
end

function rmap.now() return os.time() end

local function classify(cmd)
    local word = cmd:match("^(%S+)")
    if rmap.settings.verifyVerbs[word] then return "VERIFY" end
    if rmap.settings.previewVerbs[word] then return "PREVIEW" end
    if dirAlias[cmd] then return "ADVANCE", dirAlias[cmd] end
    return "MAYBE_MOVE"
end

-- An expectation can carry cb(block_or_nil, why): called when it
-- resolves (block), is cancelled (nil, "fail"), closed with no room
-- (nil) or expires (nil, "timeout"). Used by speedwalk/scan/where.
local function done(e, b, why)
    if e and e.cb then e.cb(b, why) end
end

local function expire()
    local cutoff = rmap.now() - rmap.settings.expectTimeout
    local dead = {}
    while T.q[1] and T.q[1].t < cutoff do
        local e = table.remove(T.q, 1)
        dead[#dead + 1] = e
        -- a move we never saw land leaves us unsure where we are; a late
        -- reply must not be linked from the old room (it re-syncs by
        -- unique fingerprint instead)
        if e.kind == "ADVANCE" or e.kind == "MAYBE_MOVE" then T.pos = nil end
    end
    for i = 1, #dead do done(dead[i], nil, "timeout") end
end

-- SYNCED / PENDING / UNSYNCED (PENDING = synced with a command in flight)
function T.state()
    if not T.pos then return "UNSYNCED" end
    if #T.q > 0 then return "PENDING" end
    return "SYNCED"
end

-- Rule 1 and 2: skip empty commands, one expectation per embedded line.
function T.send(_, cmd)
    for raw in (tostring(cmd) .. "\n"):gmatch("(.-)\r?\n") do
        local part = raw:lower():match("^%s*(.-)%s*$")
        if part ~= "" then
            -- the player moved on mid-scan: later previews would come
            -- from another room, so the scan stops here (its callbacks
            -- see rmap.job ~= "scan" and drop out)
            if not T.hook and rmap.job == "scan" then
                rmap.job = nil
                rmap.out("scan: stopped, you sent a command", "skip")
            end
            expire()
            local kind, dir = classify(part)
            T.q[#T.q + 1] = { kind = kind, cmd = part, dir = dir,
                t = rmap.now(), cb = T.hook }
            T.hook = nil
            -- unverified: `follow` syntax; "follow self"/"unfollow" end it
            local verb, arg = part:match("^(%S+)%s*(%S*)")
            if verb == "follow" then
                T.following = arg ~= "" and arg ~= "self"
            elseif verb == "unfollow" then
                T.following = false
            end
        end
    end
end

-- Internal sends (speedwalk, scan, where) go through send() so that
-- T.send above still pushes the expectation; cb rides on it.
function T.exec(cmd, cb)
    T.hook = cb
    -- unverified: sysDataSendRequest handlers run synchronously in send()
    send(cmd)
    T.hook = nil
    -- a silent game must not stall a job: expire() runs from this timer
    if rmap.ids.timer then killTimer(rmap.ids.timer) end
    -- unverified: tempTimer(seconds, fn) returns a timer id for killTimer
    rmap.ids.timer = tempTimer(rmap.settings.expectTimeout + 1, expire)
end

local function resolve(e, b)
    if e.kind == "PREVIEW" then return end
    local cur = T.pos
    -- mapping off: follow what is already mapped, never write the graph
    local move = rmap.mapping and rmap.build or { advance = rmap.build.follow,
        special = rmap.build.follow }
    if not cur then
        -- never guess: only a unique fingerprint match re-syncs
        T.pos = rmap.build.find(b.fingerprint)
    elseif e.kind == "ADVANCE" then
        T.pos = move.advance(cur, e.dir, b)
    elseif rmap.build.fp(cur) == b.fingerprint then    -- VERIFY / no move
        return
    elseif e.kind == "VERIFY" then
        T.pos = rmap.build.find(b.fingerprint)
    else
        T.pos = move.special(cur, e.cmd, b)
    end
end

-- Keep the Mudlet map pane on the player's room (it follows the area).
-- unverified: centerview(id) switches the pane to that room's area.
function T.focus()
    if T.pos then centerview(T.pos) end
end

function T.onRoom(_, b)
    expire()
    T.handled = true
    local e = table.remove(T.q, 1)
    if not e then T.pos = nil return end             -- SPONTANEOUS
    resolve(e, b)
    T.focus()
    done(e, b)
end

-- A failed move cancels the head expectation; nothing was created on send.
function T.onMoveFail()
    expire()
    T.handled = true
    done(table.remove(T.q, 1), nil, "fail")
end

-- A prompt closed a segment with n real lines. If no room block and no
-- fail message already resolved the head, the head command is done.
-- An ADVANCE head is the exception: its ack is the room block or the
-- fail line, so unrelated chatter before it must not close it (timeout
-- covers a move that prints neither). A soft segment (ended by a short
-- tick prompt) closes nothing: swimming prints "You are in deep water..."
-- and a short prompt before the room block.
function T.onSegment(_, n, soft)
    expire()
    local e, head = nil, T.q[1]
    if not T.handled and not soft and n > 0 and head
        and head.kind ~= "ADVANCE" then
        e = table.remove(T.q, 1)
    end
    T.handled = false
    done(e, nil)
end

-- Explicit orphan creation / re-sync entry point (used by `rmap where`).
function T.adopt(b) T.pos = rmap.build.adopt(b) T.focus() end

rmap.inits[#rmap.inits + 1] = function()
    rmap.on("sysDataSendRequest", T.send)
    rmap.on("rmap.onRoom", T.onRoom)
    rmap.on("rmap.onMoveFail", T.onMoveFail)
    rmap.on("rmap.onSegment", T.onSegment)
end
