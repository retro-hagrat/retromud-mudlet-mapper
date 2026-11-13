-- 40_tracker: expectation queue and sync state.
-- Contract (docs/design.md, docs/mapper-protocol.md): sysDataSendRequest
-- pushes one classified expectation (VERIFY / PREVIEW / ADVANCE /
-- MAYBE_MOVE) per sent command; sync state is SYNCED / UNSYNCED /
-- PENDING; each rm.onRoom block resolves the queue head. Decides
-- advance/verify/preview. Never writes the graph (rm.build does).
-- Rules 3 and 4 of the protocol hold by construction: T.send below is
-- the only function that pushes onto the queue; no module calls
-- sendSocket or pushes directly.

rm.track = { q = {}, pos = nil, handled = false, following = false }
local T = rm.track

-- name or abbreviation -> full direction name
local dirAlias = {}
for name, d in pairs(rm.settings.dirs) do
    dirAlias[name] = name
    dirAlias[d.abbr] = name
end

function rm.now() return os.time() end

local function classify(cmd)
    local word = cmd:match("^(%S+)")
    if rm.settings.verifyVerbs[word] then return "VERIFY" end
    if rm.settings.previewVerbs[word] then return "PREVIEW" end
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
    local cutoff = rm.now() - rm.settings.expectTimeout
    local dead = {}
    while T.q[1] and T.q[1].t < cutoff do
        dead[#dead + 1] = table.remove(T.q, 1)
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
            expire()
            local kind, dir = classify(part)
            T.q[#T.q + 1] = { kind = kind, cmd = part, dir = dir,
                t = rm.now(), cb = T.hook }
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
    if rm.ids.timer then killTimer(rm.ids.timer) end
    -- unverified: tempTimer(seconds, fn) returns a timer id for killTimer
    rm.ids.timer = tempTimer(rm.settings.expectTimeout + 1, expire)
end

local function resolve(e, b)
    if e.kind == "PREVIEW" then return end
    local cur = T.pos
    if not cur then
        -- never guess: only a unique fingerprint match re-syncs
        T.pos = rm.build.find(b.fingerprint)
    elseif e.kind == "ADVANCE" then
        T.pos = rm.build.advance(cur, e.dir, b)
    elseif rm.build.fp(cur) == b.fingerprint then    -- VERIFY / no move
        return
    elseif e.kind == "VERIFY" then
        T.pos = rm.build.find(b.fingerprint)
    else
        T.pos = rm.build.special(cur, e.cmd, b)
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
-- covers a move that prints neither).
function T.onSegment(_, n)
    expire()
    local e, head = nil, T.q[1]
    if not T.handled and n > 0 and head and head.kind ~= "ADVANCE" then
        e = table.remove(T.q, 1)
    end
    T.handled = false
    done(e, nil)
end

-- Explicit orphan creation / re-sync entry point (used by `rmap where`).
function T.adopt(b) T.pos = rm.build.adopt(b) T.focus() end

rm.inits[#rm.inits + 1] = function()
    rm.on("sysDataSendRequest", T.send)
    rm.on("rm.onRoom", T.onRoom)
    rm.on("rm.onMoveFail", T.onMoveFail)
    rm.on("rm.onSegment", T.onSegment)
end
