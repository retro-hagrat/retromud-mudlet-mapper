-- usage: lua jobs_test.lua <body.lua> <captures-dir>
-- Phases 3 and 4: rmap scan / where / undo and the speedwalk engine, run
-- against a tiny scripted game that answers look / peer / moves.
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
local body, caps = arg[1], arg[2]
local S = dofile(dir .. "/mudlet_stub.lua")

local PROMPT = "Hp: 1/1  Sp: 1/1  Ep: 1/1"
local world, cur, answered

local function exitsLine(ex)
    if #ex == 1 then return "The only obvious exit is " .. ex[1] .. "." end
    local head = table.concat(ex, ", ", 1, #ex - 1)
    return "Obvious exits are: " .. head .. ", and " .. ex[#ex] .. "."
end
local function exitsOf(key)
    local ex = {}
    for e in pairs(world[key].nb) do ex[#ex + 1] = e end
    table.sort(ex)
    return ex
end
local function show(key)
    rmap.onLine(world[key].name)
    rmap.onLine("  A place.")
    rmap.onLine(exitsLine(exitsOf(key)))
    rmap.onLine(PROMPT)
end
local function full(c)
    for name, d in pairs(rmap.settings.dirs) do
        if c == d.abbr then return name end
    end
    return c
end
-- The game answers every sent command (after send() has returned).
local function respond(cmd)
    local what = cmd:match("^peer (.+)$")
    if cmd == "look" then
        show(cur)
    elseif what then
        if world[cur].nb[what] then show(world[cur].nb[what])
        else rmap.onLine("You peer nowhere.") rmap.onLine(PROMPT) end
    elseif world.silent then
        return
    else
        local to = world[cur].nb[full(cmd)]
        if to and world.block ~= cmd then
            cur = to
            show(cur)
        else
            rmap.onLine("You can't go that way!")
            rmap.onLine(PROMPT)
        end
    end
end
local function pump()
    while answered < #S.sent do
        answered = answered + 1
        respond(S.sent[answered])
    end
end
local function fresh(w, start)
    S.reset()
    S.install()
    S.load(body)
    S.fire("sysLoadEvent")
    rmap.mapping = true
    world, cur, answered = w, start, 0
end
local function walk(cmd) send(cmd) pump() end
local function adopt()           -- first block: explicit orphan creation
    local got
    local id = registerAnonymousEventHandler("rmap.onRoom",
        function(_, r) got = r end)
    show(cur)
    killAnonymousEventHandler(id)
    rmap.track.adopt(got)
end
local function run(line) assert(S.alias(line), line) pump() end
local function said() return table.concat(S.out) end
local function byName(name)
    local out = {}
    for id, r in pairs(S.map.rooms) do
        if r.name == name then out[#out + 1] = id end
    end
    return out
end
local function one(name)
    local t = byName(name)
    assert(#t == 1, name .. ": " .. #t .. " rooms")
    return t[1], S.map.rooms[t[1]]
end
local function snap(v)
    if type(v) ~= "table" then return tostring(v) end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local out = {}
    for _, k in ipairs(keys) do out[#out + 1] = tostring(k) .. "=" .. snap(v[k]) end
    return "{" .. table.concat(out, ",") .. "}"
end
local function room(name, nb) return { name = name, nb = nb } end

-- ===== scan: fixture 3, stubs, soft back-links =====
local sunExits = { "arena", "east", "gate", "northeast", "northwest",
    "south", "southeast", "southwest", "tavern", "up", "west", "zoo" }
local w = { sg = room("Sauronan City - Sun Gate", {}) }
local back = { east = "west", northeast = "southwest", northwest = "southeast",
    south = "north", southeast = "northwest", southwest = "northeast",
    up = "down", west = "east", arena = "away", gate = "leave",
    tavern = "out", zoo = "away" }
for _, e in ipairs(sunExits) do
    w[e] = room("Room " .. e, { [back[e]] = "sg" })
    w.sg.nb[e] = e
end
fresh(w, "sg"); adopt()
run("rmap scan")
assert(S.roomCount() == 13, "scan rooms " .. S.roomCount() .. said() .. table.concat(S.sent, ";"))
local sg, sgr = one("Sauronan City - Sun Gate")
local ex, exr = one("Room east")
assert(sgr.exits.east == ex and exr.ud.source == "peer", "forward link")
assert(exr.x == sgr.x + 1 and exr.y == sgr.y, "cardinal delta")
assert(exr.stubs.west and exr.exits.west == nil, "soft back-link")
local ne, ner = one("Room northeast")
assert(ner.x == sgr.x + 1 and ner.y == sgr.y + 1 and ner.stubs.southwest)
local gate = one("Room gate")
assert(sgr.special.gate == gate and sgr.special.zoo == (one("Room zoo")))
assert(S.map.rooms[gate].exits.leave == nil, "freeform has no back-link")
assert(rmap.job == nil and said():find("scan: done, 12 new", 1, true), said())
local before = snap(S.map.rooms)
local nsent = #S.sent
run("rmap scan")
assert(snap(S.map.rooms) == before, "second scan changed the map")
assert(said():find("scan: done, 0 new", 1, true))
assert(#S.sent > nsent and S.sent[#S.sent] == "peer zoo")
-- walking into a stub confirms it and hardens the back link
walk("e")
assert(S.map.rooms[ex].ud.source == "walk" and rmap.track.pos == ex, tostring(S.map.rooms[ex].ud.source) .. tostring(rmap.track.pos) .. "/" .. ex .. said())
assert(S.map.rooms[ex].exits.west == nil, "soft until walked")
walk("w")
assert(S.map.rooms[ex].exits.west == sg and S.roomCount() == 13)
assert(rmap.track.pos == sg and not S.map.rooms[ex].stubs.west)

-- scan over the real Sun Gate peer data (zoo -> away)
local lines, grab = {}, false
for raw in io.lines(caps .. "/2026-11-01_hagrat_lab_sauronan.log") do
    local l = raw:gsub("\r$", "")
    if l:find(">peer away", 1, true) then grab = true
    elseif grab and l:find("^Sauronan City") then grab = 2
    end
    if grab == 2 then
        lines[#lines + 1] = l
        if l:find("and zoo%.$") then break end
    end
end
assert(#lines == 10, "captured " .. #lines)
fresh({ zoo = room("Entrance to the zoo", { away = "sg" }) }, "zoo")
adopt()
local real = respond
respond = function(cmd)
    if cmd == "peer away" then
        for _, l in ipairs(lines) do rmap.onLine(l) end
        rmap.onLine(PROMPT)
    else real(cmd) end
end
run("rmap scan")
local sg2, s2 = one("Sauronan City - Sun Gate")
local z, zr = one("Entrance to the zoo")
assert(zr.special.away == sg2 and s2.ud.source == "peer")
assert(s2.ud.fp == "Sauronan City - Sun Gate|" .. table.concat(sunExits, ","))
assert(s2.stubs.east and s2.stubs.southwest and s2.stubs.up, "stubs")
assert(S.roomCount() == 2 and rmap.track.pos == z)
respond = real

-- ===== where =====
-- unique match
local line = { a = room("A", { east = "b" }), b = room("B", { east = "c", west = "a" }),
    c = room("C", { west = "b" }) }
fresh(line, "a"); adopt(); walk("e"); walk("e")
rmap.track.pos = nil
run("rmap where")
assert(rmap.track.pos == (one("C")) and S.roomCount() == 3 and rmap.job == nil)
-- ambiguous fingerprints, resolved by peering
local pipe = {
    s = room("S", { east = "p1" }),
    p1 = room("Pipe", { east = "q", west = "s" }),
    q = room("Quay", { east = "p2", west = "p1" }),
    p2 = room("Pipe", { east = "r", west = "q" }),
    r = room("Rock", { west = "p2" }) }
fresh(pipe, "s"); adopt(); walk("e"); walk("e"); walk("e"); walk("e")
assert(S.roomCount() == 5, "pipe rooms " .. S.roomCount())
local pipes = byName("Pipe")
assert(#pipes == 2)
rmap.track.pos = nil
cur = "p2"
run("rmap where")
local p2id
for _, id in ipairs(pipes) do
    if S.map.rooms[id].x == 3 then p2id = id end
end
assert(rmap.track.pos == p2id, "disambiguated")
-- no match: honest report, nothing created; mapping on adopts
fresh({ n = room("Nowhere", { north = "n" }) }, "n")
rmap.mapping = false
run("rmap where")
assert(S.roomCount() == 0 and rmap.track.pos == nil and rmap.job == nil)
assert(said():find("no match", 1, true))
run("rmap start"); run("rmap where")
assert(S.roomCount() == 1 and rmap.track.state() == "SYNCED")

-- the player moves while a scan's peer reply is pending: the scan stops
-- and never attaches previews from the new room to the old one
fresh({ a = room("A", { east = "b", north = "c" }), b = room("B", { west = "a", north = "d" }),
    c = room("C", { south = "a" }), d = room("D", { south = "b" }),
    }, "a")
world.a.nb.east = "b" world.a.nb.north = "c" world.b.nb.north = "d"
adopt()
assert(S.alias("rmap scan"))
answered = 1; respond(S.sent[1])                  -- look answered, peer sent
send("e"); pump()
local peers = 0
for _, c in ipairs(S.sent) do if c:find("^peer") then peers = peers + 1 end end
assert(peers == 1 and rmap.job == nil, "scan went on after the player moved")
assert(said():find("scan: stopped", 1, true), said())
local a2, b2 = one("A"), one("B")
assert(S.map.rooms[b2].exits.north == nil and S.map.rooms[a2].exits.north == nil,
    "preview from the new room attached to the old one")

-- ===== undo =====
local gw = { a = room("A", { east = "b" }), b = room("B", { east = "c", west = "a" }),
    c = room("C", { west = "b", gate = "h" }), h = room("Hill", { leave = "c" }) }
fresh(gw, "a"); adopt(); walk("e"); walk("e"); walk("gate")
assert(S.roomCount() == 4)
local c = one("C")
run("rmap undo")                                  -- Hill + gate
assert(S.roomCount() == 3 and #byName("Hill") == 0)
assert(S.map.rooms[c].special.gate == nil and rmap.track.pos == nil)
run("rmap undo")                                  -- C + B's east link
local b, br = one("B")
assert(S.roomCount() == 2 and #byName("C") == 0)
assert(br.exits.east == nil and br.stubs.east, "exit restored as stub")
run("rmap undo"); run("rmap undo")                  -- B, then A (the orphan)
assert(S.roomCount() == 0)
run("rmap undo")
assert(said():find("nothing to undo", 1, true))
-- a walk creates exactly one room, undo removes exactly that one
fresh(gw, "a"); adopt(); walk("e")
local snapA = snap(S.map.rooms)
walk("e"); run("rmap undo")
local ra = one("A")
assert(S.roomCount() == 2 and #byName("C") == 0)

-- ===== speedwalk =====
local long = {}
for i = 1, 5 do
    local nb = {}
    if i > 1 then nb.west = "r" .. (i - 1) end
    if i < 5 then nb.east = "r" .. (i + 1) end
    long["r" .. i] = room("Hall " .. i, nb)
end
local function corridor()
    long.block, long.silent = nil, nil
    fresh(long, "r1"); adopt()
    for _ = 1, 4 do walk("e") end
    for _ = 1, 4 do walk("w") end
    assert(rmap.track.pos == (one("Hall 1")) and #S.sent == 8)
end
local function ids(n) -- room ids of Hall 2..n+1 as strings, like Mudlet
    local out = {}
    for i = 2, n + 1 do out[#out + 1] = tostring((one("Hall " .. i))) end
    return out
end
corridor()
speedWalkDir, speedWalkPath = { "e", "e", "e", "e" }, ids(4)
assert(doSpeedWalk == rmap.speedwalk, "doSpeedWalk not installed")
doSpeedWalk(); pump()
assert(rmap.track.pos == (one("Hall 5")) and rmap.job == nil, "walked")
assert(#S.sent == 12 and S.roomCount() == 5 and #rmap.track.q == 0)
assert(said():find("arrived", 1, true))
-- injected move-fail at step 3: halts, position intact
corridor()
speedWalkDir, speedWalkPath = { "e", "e", "e", "e" }, ids(4)
world.block = "e"
local mark = #S.sent
doSpeedWalk(); pump()                      -- step 1 is blocked outright
assert(rmap.track.pos == (one("Hall 1")) and #S.sent == mark + 1 and rmap.job == nil)
world.block = nil
corridor()
speedWalkDir, speedWalkPath = { "e", "e", "e", "e" }, ids(4)
local steps = 0
local realRespond = respond
respond = function(cmd)
    if cmd == "e" then
        steps = steps + 1
        if steps == 3 then world.block = "e" end
    end
    realRespond(cmd)
end
doSpeedWalk(); pump()
assert(steps == 3, "steps " .. steps)
assert(rmap.track.pos == (one("Hall 3")) and rmap.job == nil, "position intact")
assert(#rmap.track.q == 0 and said():find("stopped at step 3", 1, true), said())
respond = realRespond
-- no speedWalkPath at all: a blocked step still aborts
corridor()
speedWalkDir, speedWalkPath = { "e", "e" }, nil
world.block = "e"
mark = #S.sent
doSpeedWalk(); pump()
assert(#S.sent == mark + 1 and rmap.job == nil, "pathless walk continued")
world.block = nil
-- wrong room reached (path says otherwise): abort
corridor()
speedWalkDir, speedWalkPath = { "e", "e" }, { tostring((one("Hall 2"))), "999" }
doSpeedWalk(); pump()
assert(said():find("stopped at step 2", 1, true), "mismatch should stop at step 2")
-- silent game: the timer expires the step and aborts
corridor()
local now = 1000
rmap.now = function() return now end
world.silent = true
speedWalkDir, speedWalkPath = { "e" }, ids(1)
doSpeedWalk(); pump()
assert(rmap.job == "speedwalk" and #S.timers == 1)
now = now + rmap.settings.expectTimeout + 1
S.timers[1].fn()
assert(rmap.job == nil and said():find("timeout", 1, true))

-- ===== follow / busy refusals =====
corridor()
send("follow bob"); pump()
speedWalkDir, speedWalkPath = { "e" }, ids(1)
local n = #S.sent
doSpeedWalk(); run("rmap scan")
assert(#S.sent == n and rmap.job == nil and said():find("following", 1, true))
send("follow self"); pump()
assert(rmap.track.following == false)
rmap.job = "scan"; doSpeedWalk()
assert(said():find("busy", 1, true))
rmap.job = nil
-- uninstall removes the global and the timer
S.fire("sysUninstallPackage", "retromud")
assert(doSpeedWalk == nil and #S.timers == 0)
print("jobs_test ok")
