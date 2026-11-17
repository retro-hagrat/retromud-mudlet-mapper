-- 10_rm: namespace, version, lifecycle, event wiring.
-- Contract (docs/design.md): one global namespace `rmap`, nothing else leaks.
-- Load/install (sysLoadEvent, sysInstall) runs rmap.start(), which runs the
-- init functions other modules appended to rmap.inits (they build their
-- temp triggers/aliases/UI). sysUninstallPackage runs rmap.stop(), which
-- kills every registered handler/trigger/alias id. Every id a module
-- creates must be tracked here via rmap.on / rmap.alias so teardown is total.

-- Re-running the script (Mudlet re-executes it on save): tear down first.
local wasStarted = rmap and rmap.started
if rmap and rmap.stop then rmap.stop() end
rmap = {}
rmap.restart = wasStarted
rmap.name = "retromud"
rmap.version = "0.0.22"
rmap.inits = {}
rmap.started = false
rmap.mapping = false
rmap.ids = { handler = {}, trigger = {}, alias = {} }

-- One tagged line per message: "[rmap] text". level colours the tag:
-- "ok" green, "skip" yellow, "err" red, nil cyan, "plain" no tag, and
-- "markup" no tag with the caller's own cecho colours (help body).
-- Output can land on the prompt's line, so start a new line first
-- when the last line already has text.
-- getLines(from, to) excludes `to` (checked live), hence last + 1
local COLOR = { ok = "green", skip = "yellow", err = "red" }
function rmap.out(text, level)
    local last = getLastLineNumber("main")
    local cur = getLines(last, last + 1)[1]
    if cur and cur ~= "" then echo("\n") end
    if level ~= "markup" then text = text:gsub("<", "<<") end
    if level == "plain" or level == "markup" then
        cecho(text .. "\n")
    else
        cecho("<" .. (COLOR[level] or "cyan") .. ">[rmap]<reset> "
            .. text .. "\n")
    end
end

function rmap.on(event, fn)
    local id = registerAnonymousEventHandler(event, fn)
    rmap.ids.handler[#rmap.ids.handler + 1] = id
    return id
end

function rmap.alias(pattern, fn)
    -- unverified: tempAlias accepts a Lua function as its code argument
    local id = tempAlias(pattern, fn)
    rmap.ids.alias[#rmap.ids.alias + 1] = id
    return id
end

function rmap.start()
    if rmap.started then return end
    rmap.started = true
    for i = 1, #rmap.inits do rmap.inits[i]() end
end

function rmap.stop()
    for i = 1, #rmap.ids.handler do
        killAnonymousEventHandler(rmap.ids.handler[i])
    end
    for i = 1, #rmap.ids.trigger do killTrigger(rmap.ids.trigger[i]) end
    for i = 1, #rmap.ids.alias do killAlias(rmap.ids.alias[i]) end
    rmap.job = nil
    if rmap.ids.timer then killTimer(rmap.ids.timer) end
    -- the one documented global exception (see 60_speedwalk): put back the
    -- profile's own, but only if the global is still ours
    if doSpeedWalk == rmap.speedwalk then doSpeedWalk = rmap.prevSpeedWalk end
    rmap.prevSpeedWalk = nil
    rmap.ids = { handler = {}, trigger = {}, alias = {} }
    rmap.started = false
end

rmap.on("sysLoadEvent", function() rmap.start() end)
-- unverified: sysInstall is raised with (event, packageName) after an
-- .mpackage install, and after this script body has already run
rmap.on("sysInstall", function(_, pkg)
    if pkg == rmap.name then rmap.start() end
end)
rmap.on("sysUninstallPackage", function(_, pkg)
    if pkg == rmap.name then rmap.stop() end
end)

-- 20_settings: defaults + merge/load/save of user overrides.
-- Contract (docs/design.md): defaults in code, user overrides merged from
-- a table.save'd file in the profile dir; per-character prompt/exits
-- patterns; persisted UI geometry. No behavior. Phase 0 holds defaults
-- only; persistence arrives with the first setting that needs it.

rmap.settings = {
    -- Fallback prompt pattern (Lua pattern), used when the connection
    -- sends no GA and by offline replay. Not end-anchored. See
    -- docs/output-format.md "Prompt patterns".
    -- Allows an "EQ Tick: " style prefix and a negative Sp.
    promptPattern = "^[%w ]*:? *Hp:%s*%d+/%d+%s+Sp:%s*%-?%d+/%d+%s+Ep:%s*%d+/%d+",
    -- The short tick prompt (nothing after Ep). It can land between a
    -- command and its output (swimming: "You are in deep water...", short
    -- prompt, then the room block), so once a full prompt has been seen a
    -- segment ending at it is "soft" and closes no command.
    shortPrompt = "^Hp:%s*%d+/%d+%s+Sp:%s*%-?%d+/%d+%s+Ep:%s*%d+/%d+%s*$",

    -- Exits grammar (docs/output-format.md "Exits grammar"). The solo
    -- pattern is lazy so the trailing period is not captured.
    exitsMulti = "^Obvious exits are:%s+(.*)",
    exitsNone = "^There are no obvious exits%.?%s*$",
    exitsSolo = "^The only obvious exit is%s+(%S-)%.?%s*$",

    -- Noise lines skipped when looking for the room title.
    ignore = {
        "^You are flying%.$",
        "^.- starts using ",
        "^ %*%*%* NEW ROUND %*%*%*",
        "^%-%-%- HP:",
        "^You hit ", "^You do not hit ", "^You attack ",
        " fails to hit you%.$", " hits you ",
        "is DEAD, R%.I%.P%.$", "^You can act again%.$",
        "^The clouds begin to break apart",
    },

    -- Lines buffered with no prompt before reporting "no usable prompt".
    maxBlockLines = 500,

    -- Seconds before an unresolved expectation is dropped (a silent or
    -- failed command must never stall the queue).
    expectTimeout = 10,

    -- Command classification (docs/mapper-protocol.md). First word of
    -- the sent command; extend during calibration.
    verifyVerbs = { look = true, l = true, glance = true },
    previewVerbs = { peer = true, scry = true },

    -- Lines that cancel the head expectation (a move that did not move).
    moveFail = { "^You can't go that way!" },

    -- Fingerprint search radius (Chebyshev) for non-Euclidean links.
    maxSearchDistance = 5,
    -- Freeform verbs that are vertical in meaning: layers to climb (layout
    -- only; the link is by room id either way).
    freeformDz = { climb = 1 },
    areaName = "RetroMUD",

    -- Map zoom set when a guild seed loads (lower is closer). The default of 20 is too far out to
    -- read the room symbols; 8 shows about a dozen rooms in the map pane. Returning players keep theirs.
    seedZoom = 8,

    -- Room blocks the game prints around character creation and the first
    -- login. They are not part of the world: capture never raises them, so
    -- neither the tracker nor the seeder sees them. By fingerprint.
    ignoreRooms = {
        ["Character Creation|enter,prev,shrines"] = true,
        ["Race Selection Room|next,prev"] = true,
        ["Guild Selection Room|next"] = true,
        ["Welcome to RetroMUD|enter,skip"] = true,       -- one-time disclaimers room
        -- the creation shrines (stat boosts) off Character Creation: a hub and
        -- fourteen identical rooms
        ["A room full of shrines|agi,allstats,cha,con,dex,hermmax,int,maxsize,minsize,out,per,skillmax,spirmax,str,wis"] = true,
        ["A small shrine|out"] = true,
    },

    -- Cardinal directions: abbreviation, Mudlet direction number
    -- (setExit/setExitStub), coordinate delta, opposite. in/out are not
    -- here: they have no delta, so they are freeform (special) exits.
    dirs = {
        north     = { abbr = "n",  num = 1,  dx = 0,  dy = 1,  dz = 0,  opp = "south" },
        northeast = { abbr = "ne", num = 2,  dx = 1,  dy = 1,  dz = 0,  opp = "southwest" },
        northwest = { abbr = "nw", num = 3,  dx = -1, dy = 1,  dz = 0,  opp = "southeast" },
        east      = { abbr = "e",  num = 4,  dx = 1,  dy = 0,  dz = 0,  opp = "west" },
        west      = { abbr = "w",  num = 5,  dx = -1, dy = 0,  dz = 0,  opp = "east" },
        southeast = { abbr = "se", num = 7,  dx = 1,  dy = -1, dz = 0,  opp = "northwest" },
        southwest = { abbr = "sw", num = 8,  dx = -1, dy = -1, dz = 0,  opp = "northeast" },
        south     = { abbr = "s",  num = 6,  dx = 0,  dy = -1, dz = 0,  opp = "north" },
        up        = { abbr = "u",  num = 9,  dx = 0,  dy = 0,  dz = 1,  opp = "down" },
        down      = { abbr = "d",  num = 10, dx = 0,  dy = 0,  dz = -1, opp = "up" },
    },
}

-- 30_capture: line buffer -> room-block detection -> rmap.onRoom event.
-- Contract (docs/design.md, docs/output-format.md): rmap.onLine(line) is
-- called once per received line (a trigger live, the replay harness
-- offline). Segments end at a prompt: isPrompt() (GA/EOR) live, else
-- rmap.settings.promptPattern. Each exits line in a segment raises
-- raiseEvent("rmap.onRoom", {name=, exits={...}, lines={...},
-- fingerprint=}), then rmap.onSegment(n); a move-fail line raises
-- rmap.onMoveFail. Knows nothing about the map.

rmap.cap = { buf = {}, warned = false }

local function isNoise(line)
    if line:find("^%s*$") then return true end
    for i = 1, #rmap.settings.ignore do
        if line:find(rmap.settings.ignore[i]) then return true end
    end
    return false
end

-- Exits starting at buf[i]: returns exits list, index of last line.
local function parseExits(buf, i)
    local s = rmap.settings
    if buf[i]:find(s.exitsNone) then return {}, i end
    local solo = buf[i]:match(s.exitsSolo)
    if solo then return { solo:lower() }, i end
    local rest = buf[i]:match(s.exitsMulti)
    if not rest then return nil end
    local j = i
    while not rest:find("%.%s*$") do
        j = j + 1
        if not buf[j] then return nil end
        if not isNoise(buf[j]) then rest = rest .. " " .. buf[j] end
    end
    local exits = {}
    -- names never contain spaces (underscores), so "a and b" splits too
    for name in rest:gsub("%.%s*$", ""):gmatch("[^,%s]+") do
        if name ~= "and" then exits[#exits + 1] = name:lower() end
    end
    return exits, j
end

local function fingerprint(name, exits)
    local sorted = {}
    for i = 1, #exits do sorted[i] = exits[i] end
    table.sort(sorted)
    return name .. "|" .. table.concat(sorted, ",")
end

-- A plausible title: not a continuation (lowercase start) and not a
-- list header ("There are several special commands here:").
local function titleLike(line)
    return not line:find("^%l") and not line:find(":%s*$")
        and not line:find("^[^%w\"'(]")
end

-- Nearest non-noise, non-indented line above d, or nil.
local function titleAbove(buf, lo, d)
    local t = d - 1
    while t >= lo and (isNoise(buf[t]) or buf[t]:find("^%s")) do t = t - 1 end
    if t >= lo then return t end
end

-- Walk back from each exits line to a description start: a line indented
-- 2 spaces, else 3+ (builders vary: 2, 4, 10; deeper indents inside a
-- description are boxes and lists, so exactly 2 wins) whose non-noise, non-indented
-- predecessor looks like a title. A later paragraph's first line has a
-- sentence fragment above it, so nearer candidates with such a
-- predecessor are skipped. Description-less rooms (title, then the
-- single-space light line) fall back to that light line.
local function findTitle(buf, lo, i)
    for _, pat in ipairs({ "^  %S", "^  $", "^   +%S", "^   +$", "^ %S" }) do
        for d = i - 1, lo, -1 do
            if buf[d]:find(pat) then
                local t = titleAbove(buf, lo, d)
                if t and titleLike(buf[t]) then return t end
            end
        end
    end
end

-- Last resort for areas whose descriptions are not indented at all: the
-- earliest line before the exits line that reads as a title (short, not
-- indented, no sentence punctuation at the end) and is directly followed
-- by text. Chatter ends in punctuation ("...tower.'", "...alarm!").
local function bareTitle(buf, lo, i)
    for t = lo, i - 2 do
        local l = buf[t]
        if not isNoise(l) and not l:find("^%s") and #l <= 60
            and not l:find("[%.!?'\"%]%)]%s*$") and titleLike(l)
            and not isNoise(buf[t + 1]) then
            return t
        end
    end
end

-- Returns the index after the last exits line handled.
local function scan(buf)
    local lo, i = 1, 1
    while i <= #buf do
        local exits, last = parseExits(buf, i)
        if exits then
            local t = findTitle(buf, lo, i) or bareTitle(buf, lo, i)
            if t then
                local lines = {}
                for k = t, last do lines[#lines + 1] = buf[k] end
                local name = buf[t]:match("^(.-)%s*$")
                local fp = fingerprint(name, exits)
                if not rmap.settings.ignoreRooms[fp] then
                    raiseEvent("rmap.onRoom", {
                        name = name, exits = exits, lines = lines,
                        fingerprint = fp,
                    })
                end
            end
            lo, i = last + 1, last + 1
        else
            i = i + 1
        end
    end
    return lo
end

-- Raises rmap.onRoom per room, then rmap.onSegment(n, soft) with the count of
-- non-noise lines, so the tracker can close commands that print no room.
-- keepTail: on a forced flush keep the unscanned tail so a room whose
-- title is already buffered is not split from its exits line.
-- soft: the segment ended at a short tick prompt, so it may be only the
-- first half of a command's reply (see settings.shortPrompt).
local function flush(keepTail, soft)
    local buf = rmap.cap.buf
    rmap.cap.buf = {}
    local lo = scan(buf)
    if keepTail then
        for k = math.max(lo, #buf - 40), #buf do
            rmap.cap.buf[#rmap.cap.buf + 1] = buf[k]
        end
    end
    local n = 0
    for i = 1, #buf do
        if not isNoise(buf[i]) then n = n + 1 end
    end
    raiseEvent("rmap.onSegment", n, soft)
end

function rmap.onLine(line)
    local c = rmap.cap
    if isPrompt() or line:find(rmap.settings.promptPattern) then
        c.warned = false
        local soft = false
        if line:find(rmap.settings.shortPrompt) then
            soft = c.tall                    -- a tick prompt, not a reply
        else
            c.tall = true
        end
        flush(false, soft)
        return
    end
    -- a reconnect banner (login art) is never part of a room
    if line:find("^%% Connected to") then c.buf = {} end
    for i = 1, #rmap.settings.moveFail do
        if line:find(rmap.settings.moveFail[i]) then
            raiseEvent("rmap.onMoveFail")
            break
        end
    end
    c.buf[#c.buf + 1] = line
    if #c.buf > rmap.settings.maxBlockLines then
        if not c.warned then
            c.warned = true
            rmap.out("no usable prompt (no GA, and the prompt "
                .. "pattern never matched in " .. #c.buf .. " lines); "
                .. "set rmap.settings.promptPattern", "err")
        end
        flush(true)
    end
end

rmap.inits[#rmap.inits + 1] = function()
    -- unverified: tempRegexTrigger("^", fn) fires for every line, and
    -- the global `line` holds the current line inside fn
    local id = tempRegexTrigger("^", function() rmap.onLine(line) end)
    rmap.ids.trigger[#rmap.ids.trigger + 1] = id
end

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
        -- a step we never saw land leaves us unsure where we are; a late
        -- reply must not be linked from the old room (it re-syncs by
        -- unique fingerprint instead). Only directions: an unrecognised
        -- verb that printed nothing ("get gold") is not a lost move.
        if e.kind == "ADVANCE" then T.pos = nil end
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
            -- the player moved on mid-job: later steps/previews would come
            -- from another room, so the job stops here (its callbacks
            -- see rmap.job == nil and drop out)
            if not T.hook and rmap.job then
                rmap.out(rmap.job .. ": stopped, you sent a command", "skip")
                rmap.job = nil
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
    -- no expectation took the callback (not connected, no event): end the
    -- job now, or it would wait forever and block every later job
    local lost = T.hook
    T.hook = nil
    if lost then return lost(nil, "not sent") end
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
    elseif e.kind == "MAYBE_MOVE" and rmap.build.known(cur, e.cmd, b) then
        T.pos = rmap.build.known(cur, e.cmd, b)      -- into a look-alike room
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
    if not e then                                    -- SPONTANEOUS
        -- The game printing the room we are already in (after registration,
        -- say) is not movement. Any other room means we may have been moved
        -- (drag, summon, or a lost position healing): sync only to the one
        -- known room with this fingerprint, never guess, never create. Twin
        -- rooms share a fingerprint, so a forced move between twins goes
        -- unnoticed. (pcall: the position may name a room deleted since.)
        local same = T.pos and select(2, pcall(rmap.build.fp, T.pos)) == b.fingerprint
        if not same then
            T.pos = rmap.build.find(b.fingerprint)
            T.focus()
        end
        return
    end
    resolve(e, b)
    T.focus()
    done(e, b)
end

-- A failed move cancels the head expectation; nothing was created on send.
function T.onMoveFail()
    expire()
    T.handled = true
    local e = table.remove(T.q, 1)
    if e and e.kind == "ADVANCE" and T.pos and rmap.mapping then
        rmap.build.reject(T.pos, e.dir)
    end
    done(e, nil, "fail")
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

-- 45_seed: first-login map seeding.
-- Contract: on the first room block of a session, if the profile's map has
-- no rooms (a new character), find the guild seed whose start-room
-- fingerprint equals the block's, load it, turn mapping on and put the
-- player on that room. No match: start a fresh map from this room. A map
-- with rooms is never touched (loadJsonMap replaces the whole map); mapping
-- just resumes, unless the player ran `rmap stop`.
-- Seeds ship in the package as seeds/<name>.json; build.py generates
-- rmap.seedIndex (start fingerprint -> seed name) from the rooms marked
-- userData start = "1". Runs after 40_tracker so the tracker has already
-- resolved the block (a spontaneous login block leaves T.pos nil). Creation and
-- first-login rooms never reach it: see settings.ignoreRooms.

rmap.seed = { checked = false }
local S = rmap.seed

-- The player's explicit `rmap start` / `rmap stop` is kept in the map's user
-- data, so it survives sessions and goes with the map. Unset means "on".
S.PREF = "rmap.mapping"
function S.remember(choice) setMapUserData(S.PREF, choice) end
function S.wantsMapping() return getMapUserData(S.PREF) ~= "off" end

function S.path(name)
    return getMudletHomeDir() .. "/" .. rmap.name .. "/seeds/" .. name .. ".json"
end

function S.onRoom(_, b)
    if S.checked then return end
    S.checked = true                 -- once per session, whatever happens
    -- Whatever is still queued comes from commands typed before this room
    -- (creation, login, registration): none can relate to the map. Left in,
    -- a stale entry would claim the next room block.
    rmap.track.q = {}
    if next(getRooms() or {}) then
        -- a returning player: the map is theirs, never replaced; mapping
        -- resumes unless they stopped it
        if S.wantsMapping() then
            rmap.mapping = true
            rmap.out("mapping is on (rmap stop turns it off)", "ok")
        end
        return
    end
    local name = rmap.seedIndex and rmap.seedIndex[b.fingerprint]
    if name then
        if loadJsonMap(S.path(name)) then
            rmap.icons.apply(name)
            if setMapZoom then pcall(setMapZoom, rmap.settings.seedZoom) end
            rmap.mapping = true
            rmap.track.pos = rmap.build.find(b.fingerprint)
            rmap.track.focus()
            -- unverified: openMapWidget() exists in Mudlet 4.17+
            if openMapWidget then pcall(openMapWidget) end
            rmap.out("loaded the " .. name .. " map; mapping is on", "ok")
            return
        end
        rmap.out("could not load the " .. name .. " map", "err")
    end
    rmap.mapping = true
    rmap.track.adopt(b)
    rmap.out("new map started here; mapping is on", "ok")
end

rmap.inits[#rmap.inits + 1] = function()
    S.checked = false
    rmap.on("rmap.onRoom", S.onRoom)
end

-- 46_icons: ASCII symbols on guild-service rooms of a seeded map.
-- Contract: after a seed loads, rooms whose title names a service get a one-character
-- symbol (and colour) so a new player can find joining, advancing, training and so on.
-- Only seeds listed in I.seeds are marked: each one is checked by hand first, since the
-- rules go by title words. A symbol already on a room is kept; the start room is `S`.
-- ASCII only, and nothing religious: the shrines use `*`.

rmap.icons = {}
local I = rmap.icons

I.seeds = { biomancer = true }

-- first match wins; plain, case-insensitive substrings of the room title
I.rules = {
    { "joining", "J" }, { "initiation", "J" }, { "admissions", "J" },
    { "advancement", "A" }, { "training", "T" }, { "check room", "C" },
    { "supplies", "$" }, { "wares", "$" },
    { "lecture", "L" }, { "main hall of the library", "L" },
    { "entrance", "E" },
}

I.colors = {
    S = { 80, 255, 80 }, E = { 255, 200, 60 }, ["$"] = { 255, 220, 120 },
    L = { 200, 160, 255 },
    J = { 120, 200, 255 }, A = { 120, 200, 255 }, T = { 120, 200, 255 }, C = { 120, 200, 255 },
}

function I.symbolFor(title)
    local t = title:lower()
    for _, r in ipairs(I.rules) do
        if t:find(r[1], 1, true) then return r[2] end
    end
end

function I.apply(seedName)
    if not I.seeds[seedName] then return 0 end
    local n = 0
    for id, title in pairs(getRooms() or {}) do
        local ch = getRoomUserData(id, "start") == "1" and "S" or I.symbolFor(title)
        local have = getRoomChar and getRoomChar(id)
        if ch and (have == nil or have == "") then
            setRoomChar(id, ch)
            local c = I.colors[ch]
            if c then setRoomCharColor(id, c[1], c[2], c[3]) end
            n = n + 1
        end
    end
    return n
end

-- 50_builder: the ONLY module that writes the map graph.
-- Contract (docs/design.md, docs/mapper-protocol.md): fingerprint
-- matching, coordinate-first dedupe, room/area/exit creation, stub
-- semantics, special exits. Each decision function returns the room id
-- the player is now in, or nil when the map disagrees with the block
-- (the tracker then goes UNSYNCED; nothing is guessed or created).
-- Fingerprints persist as room user data "fp".

rmap.build = {}
local B = rmap.build
-- Auto-created rooms, newest last: { id, from, dir | cmd } (for undo).
B.created = {}

local function areaId()
    local name = rmap.settings.areaName
    -- unverified: getAreaTable() returns {name = id}; addAreaName returns the id
    return getAreaTable()[name] or addAreaName(name)
end

-- The area a room entered from `from` joins: its origin's, so walking out of
-- a seeded guild map stays in that guild's area. `rmap area <name>` pins the
-- setting instead; a room with no origin (adopt) uses the setting too.
local function areaFor(from)
    if not rmap.settings.areaPinned and from then
        local a = getRoomArea(from)
        if a then return a end
    end
    return areaId()
end

function B.fp(id)
    -- unverified: getRoomUserData returns "" when the key is unset
    return getRoomUserData(id, "fp")
end

-- area: defaults to the one new rooms go into; pass a room's own area
-- when the cell is relative to that room (coordinates are per area).
local function roomAt(x, y, z, area)
    -- unverified: getRoomsByPosition(area, x, y, z) returns a table of ids
    for _, id in pairs(getRoomsByPosition(area or areaId(), x, y, z)) do
        return id
    end
end

-- Every room with this fingerprint, in any area: `rmap area` changes
-- where new rooms go, not which known rooms the player can be in.
local function candidates(fp)
    local out = {}
    -- unverified: searchRoomUserData(key, value) returns the matching room ids
    for _, id in pairs(searchRoomUserData("fp", fp)) do out[#out + 1] = id end
    return out
end
B.candidates = candidates

-- The one room with this fingerprint, or nil if none or ambiguous.
function B.find(fp)
    local c = candidates(fp)
    if #c == 1 then return c[1] end
end

local function link(from, to, dir)
    local n = rmap.settings.dirs[dir].num
    -- unverified: setExit takes the direction number 1-12
    setExit(from, to, n)
    -- unverified: setExit leaves a stub in place, so clear it
    setExitStub(from, n, false)
end

local function create(b, x, y, z, peer, from)
    local id = createRoomID()
    addRoom(id)
    setRoomArea(id, areaFor(from))
    setRoomName(id, b.name)
    setRoomCoordinates(id, x, y, z)
    setRoomUserData(id, "fp", b.fingerprint)
    setRoomUserData(id, "source", peer and "peer" or "walk")
    return id
end

-- Walking into a peer stub confirms it.
local function confirm(id)
    if getRoomUserData(id, "source") == "peer" then
        setRoomUserData(id, "source", "walk")
    end
end

-- Listed cardinal exits not linked yet become stubs. Freeform exits
-- (gate, leave) have no stub form; they link when first walked.
local function stub(id, b)
    -- unverified: getRoomExits returns {directionName = roomId}
    local linked = getRoomExits(id)
    for _, ex in ipairs(b.exits) do
        local d = rmap.settings.dirs[ex]
        if d and not linked[ex] then setExitStub(id, d.num, true) end
    end
end

-- Existing room one step in dir: a real link first (second result true),
-- else whatever sits on the expected cell (a guess; see B.advance).
local function neighbor(from, dir)
    local to = getRoomExits(from)[dir]
    if to then return to, true end
    local d = rmap.settings.dirs[dir]
    local x, y, z = getRoomCoordinates(from)
    return roomAt(x + d.dx, y + d.dy, z + d.dz, getRoomArea(from)), false
end

-- The grid is only a layout: the MUD's exits need not fit on it. The
-- cell (x, y, z) if free, else the nearest free cell on that level that
-- is not in `reserved` ("x,y,z" keys), ties broken by distance to the
-- source cell (sx, sy) so the room stays close to where it came from. Cells
-- are checked in `area`, the area the new room will join.
local function freeCell(x, y, z, reserved, sx, sy, area)
    reserved = reserved or {}
    for r = 0, math.huge do
        local bx, by, bd
        for i = -r, r do
            for j = -r, r do
                local cx, cy = x + i, y + j
                if math.max(math.abs(i), math.abs(j)) == r
                    and not roomAt(cx, cy, z, area)
                    and not reserved[cx .. "," .. cy .. "," .. z] then
                    local d = sx and (cx - sx) * (cx - sx)
                        + (cy - sy) * (cy - sy) or 0
                    if not bd or d < bd then bx, by, bd = cx, cy, d end
                end
            end
        end
        if bd then return bx, by, z end
    end
end

-- Cells that `from`'s other listed cardinal exits will want, so a nudged
-- room does not steal them (a nudge must not force the next nudge).
local function reservedFor(from, dir)
    local out = {}
    local x, y, z = getRoomCoordinates(from)
    for ex in (B.fp(from):match("^.*|(.*)$") or ""):gmatch("[^,]+") do
        local d = rmap.settings.dirs[ex]
        if d and ex ~= dir then
            out[(x + d.dx) .. "," .. (y + d.dy) .. "," .. (z + d.dz)] = true
        end
    end
    return out
end

-- Set of rooms `from` already leads to. The exit walked now is a
-- different one, so a look-alike behind it is a different room (two
-- exits to one look-alike become a duplicate, easy to merge by hand,
-- rather than a false merge that breaks paths).
local function leadsTo(from)
    local taken = {}
    for _, id in pairs(getRoomExits(from)) do taken[id] = true end
    for _, id in pairs(getSpecialExitsSwap(from)) do taken[id] = true end
    return taken
end

-- Non-Euclidean link (decision step 2): the single nearby room with this
-- fingerprint whose way back toward us is not already linked elsewhere.
local function near(from, fp, opp)
    local x, y, z = getRoomCoordinates(from)
    local taken = leadsTo(from)
    local hit
    for _, id in ipairs(candidates(fp)) do
        local a, b, c = getRoomCoordinates(id)
        local back = getRoomExits(id)[opp]
        -- the room already linked behind us is never "ahead" (a
        -- corridor of identical rooms would fold back on itself)
        if id ~= from and getRoomArea(id) == getRoomArea(from)
            and (not back or back == from)
            and not taken[id]
            and math.max(math.abs(a - x), math.abs(b - y),
                math.abs(c - z)) <= rmap.settings.maxSearchDistance then
            if hit then return nil end               -- ambiguous
            hit = id
        end
    end
    return hit
end

-- The way back to a new room is linked on the strength of its exits line
-- alone. The game need not honour it (a swimming current only runs one
-- way), so such links are listed in user data "bl" on the room they leave
-- until a real step along them is seen.
local function inferred(id, dir)
    return (" " .. getRoomUserData(id, "bl") .. " "):find(" " .. dir .. " ", 1, true)
end

local function setInferred(id, dir, on)
    local list = {}
    for d in getRoomUserData(id, "bl"):gmatch("%S+") do
        if d ~= dir then list[#list + 1] = d end
    end
    if on then list[#list + 1] = dir end
    setRoomUserData(id, "bl", table.concat(list, " "))
end

-- The move along `dir` from `from` was refused: if that link was only
-- inferred from an exits line, remove it and turn it back into a stub.
function B.reject(from, dir)
    local d = rmap.settings.dirs[dir]
    if not (d and inferred(from, dir) and getRoomExits(from)[dir]) then return end
    setExit(from, -1, d.num)
    setExitStub(from, d.num, true)
    setInferred(from, dir, false)
end

-- peer: a `peer` preview from `from` (rmap scan): new rooms are stubs and
-- the way back is left as a soft exit stub, never a real link.
function B.advance(from, dir, b, peer)
    local d = rmap.settings.dirs[dir]
    local to, linked = neighbor(from, dir)
    -- An unlinked room on the expected cell is only a coordinate guess;
    -- a different room there means the map does not fit the grid, so
    -- ignore it (links, not cells, are the truth).
    if to and not linked and B.fp(to) ~= b.fingerprint then to = nil end
    -- an inferred way back that led somewhere else was wrong: drop it
    if to and linked and B.fp(to) ~= b.fingerprint and not peer
        and inferred(from, dir) then
        setExit(from, -1, d.num)
        setExitStub(from, d.num, true)
        to = nil
    end
    -- a preview must not fold two look-alike neighbours into one room:
    -- only a real link (or the cell guess above) may reuse a room
    to = to or (not peer and near(from, b.fingerprint, d.opp)) or nil
    if to then
        if B.fp(to) ~= b.fingerprint then return nil end
        link(from, to, dir)
        if not peer then
            confirm(to)
            setInferred(from, dir, false)
        end
        return to
    end
    local x, y, z = getRoomCoordinates(from)
    x, y, z = freeCell(x + d.dx, y + d.dy, z + d.dz,
        reservedFor(from, dir), x, y, areaFor(from))
    to = create(b, x, y, z, peer, from)
    B.created[#B.created + 1] = { id = to, from = from, dir = dir }
    link(from, to, dir)
    if not peer then setInferred(from, dir, false) end
    for _, ex in ipairs(b.exits) do
        if ex == d.opp and not peer then
            link(to, from, d.opp)
            setInferred(to, d.opp, true)
        end
    end
    stub(to, b)
    return to
end

-- Freeform command (gate, leave, sungate...) that landed in a different
-- room: a special exit to a known or new room.
function B.special(from, cmd, b, peer)
    -- unverified: getSpecialExitsSwap(id) returns {command = roomId}
    local to = getSpecialExitsSwap(from)[cmd]
    -- a walked move may land in a known room; a preview never merges by
    -- fingerprint alone (look-alike rooms are different rooms)
    if not to and not peer then
        to = B.find(b.fingerprint)
        if to and leadsTo(from)[to] then to = nil end
    end
    -- a peered neighbour that looks like this room is another room, not a loop
    if to == from then to = nil end
    if to then
        if B.fp(to) ~= b.fingerprint then return nil end
        if not peer then confirm(to) end
    else
        local x, y, z = getRoomCoordinates(from)
        -- nearest free cell beside the room, off its cardinal exits' cells
        x, y, z = freeCell(x, y, z + (rmap.settings.freeformDz[cmd] or 0),
            reservedFor(from), x, y, areaFor(from))
        to = create(b, x, y, z, peer, from)
        B.created[#B.created + 1] = { id = to, from = from, cmd = cmd }
        stub(to, b)
    end
    addSpecialExit(from, to, cmd)
    return to
end

-- The room a known special exit of `from` leads to when `b` is its block,
-- else nil (twin rooms: same fingerprint, different room).
function B.known(from, cmd, b)
    local to = getSpecialExitsSwap(from)[cmd]
    if to and to ~= from and B.fp(to) == b.fingerprint then return to end
end

-- Read-only B.advance/B.special for when mapping is off: a known link
-- (cardinal or special) or a unique fingerprint match, nothing written.
function B.follow(from, key, b)
    local to = getRoomExits(from)[key] or getSpecialExitsSwap(from)[key]
    if to and B.fp(to) == b.fingerprint then return to end
    return B.find(b.fingerprint)
end

-- Orphan room for an explicit sync (`rmap where`); reuses a unique match.
function B.adopt(b)
    local to = B.find(b.fingerprint)
    if to then return to end
    local x = 0
    while roomAt(x, 0, 0) do x = x + 1 end
    to = create(b, x, 0, 0)
    B.created[#B.created + 1] = { id = to }
    stub(to, b)
    return to
end

-- Remove exactly the newest auto-created room and the link that led to
-- it; the exit it came through goes back to a stub. Returns its record.
function B.undo()
    local e = table.remove(B.created)
    if not e then return nil end
    if e.dir then
        local n = rmap.settings.dirs[e.dir].num
        -- unverified: setExit(from, -1, dir) removes the exit
        setExit(e.from, -1, n)
        setExitStub(e.from, n, true)
    elseif e.cmd then
        -- unverified: removeSpecialExit(id, command) exists
        removeSpecialExit(e.from, e.cmd)
    end
    e.name = getRoomName(e.id)
    -- unverified: deleteRoom also drops exits other rooms hold into it
    deleteRoom(e.id)
    return e
end

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

-- 70_ui: Geyser container, Geyser.Mapper pane, status label, buttons.
-- Contract (docs/design.md): geometry persisted via settings; `rmap ui off`
-- kill-switch; pure consumer of tracker/builder state.
-- Phase 0: empty; implemented in Phase 5.

-- 80_commands: all aliases (`rmap <command>`).
-- Contract (docs/design.md): rmap start/stop/goto/path/where/scan/undo/fix/
-- save/load/prompt(Phase 6)/exits/fail/debug/ui/reload/help. Pure
-- consumer of the other modules.
-- Phase 3: where, scan, undo (start/stop only toggle rmap.mapping, which
-- lets `rmap where` create an orphan room when nothing matches).

rmap.commands = {}

function rmap.commands.help()
    rmap.out("retromud " .. rmap.version .. " - RetroMUD auto-mapper")
    for _, c in ipairs({
        { "rmap help", "show this text" },
        { "rmap start|stop", "mapping on/off (where may create a room)" },
        { "rmap where", "re-sync position from the room you are in" },
        { "rmap scan", "peer every exit of this room and map the stubs" },
        { "rmap undo", "remove the last auto-created room" },
        { "rmap area [name]", "show, or pin, the area new rooms go into (default: their origin room's)" },
    }) do
        rmap.out(string.format("  <cyan>%-16s<reset>%s", c[1], c[2]), "markup")
    end
end

local T, B = rmap.track, rmap.build

-- the choice is remembered across sessions (see 45_seed)
function rmap.commands.start()
    rmap.mapping = true
    rmap.seed.remember("on")
    rmap.out("mapping on", "ok")
end
function rmap.commands.stop()
    rmap.mapping = false
    rmap.seed.remember("off")
    rmap.out("mapping off", "ok")
end

-- Every where/scan run gets a fresh id; its callbacks drop out once the
-- job was cancelled or replaced, so a late reply never revives it.
local function startJob(name)
    rmap.job = name
    rmap.jobId = (rmap.jobId or 0) + 1
    return rmap.jobId
end
local function live(id) return rmap.job ~= nil and rmap.jobId == id end

local function finish(msg, cb, ok)
    rmap.job = nil
    T.focus()
    if msg then rmap.out(msg, ok and "ok" or "skip") end
    if cb then cb(ok) end
end

-- Neighbour of room `id` through exit `ex` (linked or special), or nil.
local function beyond(id, ex)
    return getRoomExits(id)[ex] or getSpecialExitsSwap(id)[ex]
end

-- Peer each exit of `b` and drop candidate rooms whose known neighbour
-- through that exit has another fingerprint. Calls done(room or nil).
local function narrow(c, b, i, id, done)
    if #c <= 1 then return done(c[1]) end
    local ex = b.exits[i]
    if not ex then return done(nil) end
    T.exec("peer " .. ex, function(pb)
        if not live(id) then return end                  -- cancelled
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
        narrow(c, b, i + 1, id, done)
    end)
end

-- rmap where: look; unique fingerprint -> synced; several -> disambiguate
-- by peering; none -> report (or adopt when mapping). cb(ok) when done.
local function where(cb)
    local id = rmap.jobId
    T.exec("look", function(b)
        if not live(id) then return end                  -- cancelled
        if not b then return finish("where: no room seen", cb, false) end
        local c = B.candidates(b.fingerprint)
        if #c == 1 then
            T.pos = c[1]
            return finish("where: synced", cb, true)
        end
        if #c == 0 then
            if not rmap.mapping then
                return finish("where: no match in the map", cb, false)
            end
            T.adopt(b)
            return finish("where: created a new room", cb, true)
        end
        narrow(c, b, 1, id, function(room)
            if not room then
                return finish("where: could not narrow to one room", cb, false)
            end
            T.pos = room
            finish("where: synced", cb, true)
        end)
    end)
end

function rmap.commands.where()
    if not rmap.canRun() then return end
    startJob("where")
    where()
end

-- rmap scan: peer every exit that is not already linked to a real room.
function rmap.commands.scan()
    if not rmap.canRun() then return end
    if not rmap.mapping then
        return rmap.out("scan writes rooms: type 'rmap start' first", "skip")
    end
    local id = startJob("scan")
    local function scan()
        T.exec("look", function(b)
            if not live(id) then return end              -- cancelled
            local cur = T.pos
            if not b or not cur or B.fp(cur) ~= b.fingerprint then
                return finish("scan: position lost", nil)
            end
            -- cardinals first: freeform rooms take the nearest free cell
            -- and must not squat on a cardinal neighbour's cell
            local order = {}
            for _, want in ipairs({ true, false }) do
                for _, ex in ipairs(b.exits) do
                    if (rmap.settings.dirs[ex] ~= nil) == want then
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
                    if not live(id) then return end          -- cancelled
                    if not rmap.mapping or T.pos ~= cur then
                        return finish("scan: stopped", nil)
                    end
                    if pb then
                        local n = #B.created
                        if rmap.settings.dirs[ex] then
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
        -- where() already ended the shared job; only a newer job voids this
        if rmap.jobId ~= id then return end
        if not ok then return finish("scan: could not sync", nil) end
        rmap.job = "scan"
        scan()
    end)
end

-- Area names are session-only (not persisted); set it before mapping.
function rmap.commands.area(name)
    if name and name ~= "" then
        rmap.settings.areaName = name
        rmap.settings.areaPinned = true     -- new rooms go here, not to their origin's area
    end
    rmap.out("area: " .. rmap.settings.areaName, "ok")
end

function rmap.commands.undo()
    -- a running job holds room ids that undo would delete under it
    if rmap.job then return rmap.out("busy with " .. rmap.job, "skip") end
    local e = B.undo()
    if not e then return rmap.out("undo: nothing to undo", "skip") end
    if T.pos == e.id then T.pos = nil end
    rmap.out("undo: removed '" .. e.name .. "' (room " .. e.id .. ")", "ok")
end

function rmap.command(arg)
    local cmd, rest = arg:match("^%s*(%S*)%s*(.-)%s*$")
    if cmd == "" then cmd = "help" end
    local fn = rmap.commands[cmd]
    if fn then
        fn(rest)
    else
        rmap.out("unknown command '" .. cmd .. "'. Try 'rmap help'.", "err")
    end
end

rmap.inits[#rmap.inits + 1] = function()
    -- unverified: an unmatched optional group leaves matches[2] nil or ""
    rmap.alias("^rmap( .*)?$", function() rmap.command(matches[2] or "") end)
end

-- Last module: a script re-run (save in the editor) does not raise
-- sysLoadEvent again, so resume if the previous instance was running.
if rmap.restart then rmap.restart = nil rmap.start() end

-- generated by build.py from seeds/*.json
rmap.seedIndex = {
    ["A forest spring ~ Druid training room|adv,east,north,south,southeast,tree"] = "druid",
    ["Abjurer Quarters|west"] = "abjurer",
    ["Alchemist Joining Room|guild,north"] = "alchemist",
    ["Apprentices' Chambers|north"] = "mage",
    ["Assassin Training room|east,northeast"] = "assassin",
    ["Biomancer Library|south"] = "biomancer",
    ["Chamber of Necromantic Studies|advguild,north"] = "necromancer",
    ["Chapel of Arcane Study|west"] = "cultist",
    ["Fighter training room|adv,west"] = "fighter",
    ["Jomsviking Training Area|adv"] = "jomsviking",
    ["Monk Training Area|adv,east,north,northeast,northwest,south,southeast,southwest,west"] = "monk",
    ["Psionicist training room|down"] = "psionicist",
    ["Ranger Training Hall|adv-guild,west"] = "ranger",
    ["Sentinel Practice Room|adv,south"] = "sentinel",
    ["Sikkarian Temple|adv,east,north,south,west"] = "paladin",
    ["Stage|north,suthnas"] = "bard",
    ["Templar Training Hall|adv,east"] = "templar",
    ["Training Cavern|guild,north,south"] = "fallen",
    ["Training room.|adv-guild,south"] = "merchant",
}
