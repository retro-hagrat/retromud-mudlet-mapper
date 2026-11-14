-- usage: lua tracker_test.lua <body.lua> <captures-dir>
-- Phase 2: replayed capture graphs + synthetic scenarios for 40_tracker
-- and 50_builder (mapper-protocol fixtures 1,2,4,5,6 + Phase 2 fixtures).
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
local body, caps = arg[1], arg[2]
local S = dofile(dir .. "/mudlet_stub.lua")
package.loaded.mudlet_stub = S
local replay = dofile(dir .. "/replay.lua")

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
local function quiet(f)
    local p = print
    print = function() end
    local ok, e = pcall(f)
    print = p
    assert(ok, e)
end

-- ===== replayed captures =====
quiet(function()
    replay(body, caps .. "/2026-11-13_walk_with_combat.md",
        caps .. "/2026-11-13_walk_with_combat.md.expect")
end)
-- 12 distinct rooms; the failed 's' and every look/get/wield add none;
-- both "The pathway" rooms differ by exits so they stay separate.
assert(S.roomCount() == 12, "walk rooms " .. S.roomCount())
local lk = one("Between Xavien and Platinum on Kelvin")
local kp, kpr = one("Kelvin and Platinum")
assert(S.map.rooms[lk].exits.east == kp and kpr.y == S.map.rooms[lk].y)
assert(S.map.rooms[lk].exits.south == nil, "failed s linked")
local gate, gr = one("The Gate to the Tsoda Pools")
local hill = one("Up the hill")
assert(gr.special.gate == hill, "gate special exit")
local orange = one("Orange Tsoda Pool")
assert(rmap.track.pos == orange and rmap.track.state() == "SYNCED")
assert(#rmap.track.q == 0, "queue not drained: " .. #rmap.track.q)
-- Mudlet exit numbering (confirmed live: sw drew as se when it was 7)
local N = rmap.settings.dirs
assert(N.north.num == 1 and N.northeast.num == 2 and N.northwest.num == 3
    and N.east.num == 4 and N.west.num == 5 and N.south.num == 6
    and N.southeast.num == 7 and N.southwest.num == 8
    and N.up.num == 9 and N.down.num == 10, "exit numbers")
-- the map pane follows the player: last centerview is the current room
local lastCenter
for _, c in ipairs(S.calls) do
    if c.name == "centerview" then lastCenter = c.args[1] end
end
assert(lastCenter == orange, "centerview " .. tostring(lastCenter))

quiet(function()
    replay(body, caps .. "/2026-11-01_hagrat_lab_sauronan.log",
        caps .. "/2026-11-01_hagrat_lab_sauronan.log.expect")
end)
-- lab, Sun Gate, arena path, zoo: peer and revisits create nothing.
assert(S.roomCount() == 4, "log rooms " .. S.roomCount())
local lab, labr = one("Hagrat's laboratory")
local sg, sgr = one("Sauronan City - Sun Gate")
local arena, arr = one("A path leading to the arena.")
local zoo, zr = one("Entrance to the zoo")
assert(labr.special.sungate == sg and sgr.special.arena == arena
    and sgr.special.zoo == zoo)
assert(arr.special.away == sg and zr.special.away == sg, "away links")
assert(rmap.track.pos == sg)

quiet(function()
    replay(body, caps .. "/2026-111-3_width_80.md",
        caps .. "/2026-111-3_width_80.md.expect")
end)
assert(S.roomCount() == 1, "width80 rooms " .. S.roomCount())

-- ===== synthetic scenarios =====
local PROMPT = "Hp: 1/1  Sp: 1/1  Ep: 1/1"
local function fresh()
    S.reset()
    S.install()
    S.load(body)
    S.fire("sysLoadEvent")
end
local function send(c) S.raiseEvent("sysDataSendRequest", c) end
local function exitsLine(ex)
    if #ex == 1 then return "The only obvious exit is " .. ex[1] .. "." end
    local head = table.concat(ex, ", ", 1, #ex - 1)
    return "Obvious exits are: " .. head .. ", and " .. ex[#ex] .. "."
end
local function show(name, ex, weather)
    rmap.onLine(name)
    rmap.onLine("  A place.")
    rmap.onLine(weather or " The sky is overcast.")
    rmap.onLine(exitsLine(ex))
    rmap.onLine(PROMPT)
end
local function go(cmd, name, ex) send(cmd); show(name, ex) end
local function start(name, ex)    -- first block is spontaneous: adopt it
    local got
    local id = registerAnonymousEventHandler("rmap.onRoom",
        function(_, r) got = r end)
    show(name, ex)
    killAnonymousEventHandler(id)
    rmap.track.adopt(got)
end

-- fixture 1: look after a move verifies, creates nothing
fresh(); start("A", { "east" })
go("e", "B", { "east", "west" })
assert(S.roomCount() == 2 and rmap.track.pos == (one("B")))
go("look", "B", { "east", "west" }); go("l", "B", { "east", "west" })
assert(S.roomCount() == 2 and rmap.track.pos == (one("B")), "look created")

-- repeated look mid-combat is a no-op; so does a different weather line
send("look")
rmap.onLine(" *** NEW ROUND ***"); rmap.onLine("--- HP:1/1  SP:1/1  EP:1/1")
show("B", { "east", "west" }, " Rain falls in sheets here.")
send("look")
show("B", { "east", "west" }, " The clouds part for a moment.")
assert(S.roomCount() == 2 and rmap.track.pos == (one("B")), "weather")
assert(S.map.rooms[one("B")].ud.fp == "B|east,west")

-- fixture 2: failed move cancels the expectation, no room, queue clean
send("s"); rmap.onLine("You can't go that way!")
assert(#rmap.track.q == 0, "fail line must cancel at once")
rmap.onLine(PROMPT)
assert(#rmap.track.q == 0 and S.roomCount() == 2, "fail not cancelled")
go("e", "C", { "west" })
assert(S.roomCount() == 3 and rmap.track.pos == (one("C")), "e after fail")

-- fixture 4: coordinate loop and non-Euclidean fingerprint revisit
fresh(); start("A", { "east", "south" })
go("e", "B", { "south", "west" })
go("s", "C", { "north", "west" })
go("w", "D", { "east", "north" })
go("n", "A", { "east", "south" })           -- coordinates say A is here
assert(S.roomCount() == 4 and rmap.track.pos == (one("A")), "loop")
fresh(); start("A", { "east" })
go("e", "B", { "south", "west" })
go("e", "C", { "west", "east" })
go("e", "D", { "west", "north" })
go("n", "B", { "south", "west" })           -- no room at D+north: link to B
assert(S.roomCount() == 4 and rmap.track.pos == (one("B")), "non-euclidean")
assert(S.map.rooms[one("D")].exits.north == one("B"))

-- fixture 5: spontaneous block -> UNSYNCED, creates nothing; look heals
show("Z", { "north" })
assert(rmap.track.state() == "UNSYNCED" and S.roomCount() == 4, "spont")
go("look", "A", { "east" })
assert(rmap.track.pos == (one("A")) and S.roomCount() == 4, "heal")
show("Q", { "north" })
assert(rmap.track.state() == "UNSYNCED")
go("e", "R", { "west" })                   -- unsynced + no match: no create
assert(S.roomCount() == 4 and rmap.track.state() == "UNSYNCED", "no guess")

-- fixture 6: peer preview identifies a neighbour, position unchanged
fresh(); start("A", { "east" })
go("e", "B", { "east", "west" })
go("peer east", "C", { "west" })
assert(S.roomCount() == 2 and rmap.track.pos == (one("B")), "peer")

-- gate then back via leave: one room pair
fresh(); start("Gate", { "gate", "west" })
go("gate", "Hill", { "leave", "up" })
assert(S.roomCount() == 2)
local g, h = one("Gate"), one("Hill")
assert(S.map.rooms[g].special.gate == h and rmap.track.pos == h)
go("leave", "Gate", { "gate", "west" })
assert(S.roomCount() == 2 and rmap.track.pos == g, "leave duplicated")
assert(S.map.rooms[h].special.leave == g)
assert(S.map.rooms[h].stubs.up, "cardinal exit not stubbed")

-- direction names/abbreviations, multi-line sends, empty sends
fresh(); start("A", { "northeast" })
go("NE", "B", { "southwest" })
assert(S.map.rooms[one("A")].exits.northeast == one("B"))
assert(S.map.rooms[one("B")].exits.southwest == one("A"), "back link")
send("   "); send("")
assert(#rmap.track.q == 0)
send("up\nn\n\nlook")
assert(#rmap.track.q == 3 and rmap.track.q[1].dir == "up"
    and rmap.track.q[2].dir == "north" and rmap.track.q[3].kind == "VERIFY")

-- a command with only ack output closes its expectation
fresh(); start("A", { "east" })
send("wield sword"); rmap.onLine("You wield the sword."); rmap.onLine(PROMPT)
assert(#rmap.track.q == 0 and rmap.track.state() == "SYNCED")
-- combat noise alone does not close it
send("look"); rmap.onLine(" *** NEW ROUND ***"); rmap.onLine(PROMPT)
assert(#rmap.track.q == 1)
show("A", { "east" })
assert(#rmap.track.q == 0 and rmap.track.state() == "SYNCED")

-- expectation timeout: a stale ADVANCE cannot claim a later block
fresh(); start("A", { "east" })
local now = 1000
rmap.now = function() return now end
send("e")
now = now + rmap.settings.expectTimeout + 1
show("B", { "west" })
assert(S.roomCount() == 1 and rmap.track.state() == "UNSYNCED", "timeout")

-- chatter + prompt before the move response must not drop the ADVANCE
fresh(); start("A", { "east" })
send("e")
rmap.onLine("Brown tooth leaves to the northeast."); rmap.onLine(PROMPT)
assert(#rmap.track.q == 1, "chatter closed ADVANCE")
show("B", { "east", "west" })
assert(S.roomCount() == 2 and rmap.track.pos == (one("B")), "chatter")

-- corridor of identical rooms: no fold back onto an earlier room
fresh(); start("R", { "east", "west" })
go("e", "R", { "east", "west" }); go("e", "R", { "east", "west" })
assert(S.roomCount() == 3, "corridor " .. S.roomCount())

-- block disagrees with a known neighbour: UNSYNCED, nothing linked/created
fresh(); start("A", { "east" })
go("e", "B", { "east", "west" })
go("w", "X", { "east" })
assert(rmap.track.state() == "UNSYNCED" and S.roomCount() == 2, "advance mismatch")
fresh(); start("Gate", { "gate" })
go("gate", "Hill", { "leave" })
rmap.track.pos = (one("Gate"))
go("gate", "Other", { "leave" })
assert(rmap.track.state() == "UNSYNCED" and S.roomCount() == 2, "special mismatch")

-- grid does not fit the MUD: an unrelated room already on the expected
-- cell is not the destination; the new room takes the nearest free cell
-- and is still linked by exit
fresh(); start("A", { "east" })
local ax = S.map.rooms[one("A")]
local rogue = createRoomID(); addRoom(rogue); setRoomArea(rogue, ax.area)
setRoomName(rogue, "Rogue"); setRoomCoordinates(rogue, ax.x + 1, ax.y, ax.z)
setRoomUserData(rogue, "fp", "Rogue|west")
go("e", "B", { "west" })
local bid, br = one("B")
assert(S.roomCount() == 3 and ax.exits.east == bid, "occupied cell link")
assert(not (br.x == ax.x + 1 and br.y == ax.y and br.z == ax.z),
    "B placed on the occupied cell")
assert(rmap.track.pos == bid and rmap.track.state() == "SYNCED", "still synced")

-- a nudged room must not steal the cell another listed exit of its
-- source will want (north), or the next real north room is nudged too
fresh(); start("A", { "east", "north" })
local a2 = S.map.rooms[one("A")]
local rg = createRoomID(); addRoom(rg); setRoomArea(rg, a2.area)
setRoomName(rg, "Rogue"); setRoomCoordinates(rg, a2.x + 1, a2.y, a2.z)
setRoomUserData(rg, "fp", "Rogue|west")
-- south is taken too, so the reserved north cell is the closest free one
local rs = createRoomID(); addRoom(rs); setRoomArea(rs, a2.area)
setRoomName(rs, "Rogue S"); setRoomCoordinates(rs, a2.x, a2.y - 1, a2.z)
setRoomUserData(rs, "fp", "Rogue S|north")
go("e", "B", { "west" })
for id, r in pairs(S.map.rooms) do
    assert(not (id ~= one("A") and r.x == a2.x and r.y == a2.y + 1 and r.z == a2.z),
        "nudged room took the reserved north cell: " .. r.name)
end
go("w", "A", { "east", "north" })
go("n", "N", { "south" })
local nr = S.map.rooms[one("N")]
assert(nr.x == a2.x and nr.y == a2.y + 1, "north room not on its own cell")

-- a freeform vertical verb (climb) is drawn one layer up, and the
-- room's down exit lines up with the room it came from
fresh(); start("Oak", { "climb", "west" })
go("climb", "Climbing", { "down", "up" })
local oakId, oakR = one("Oak")
local clId, clR = one("Climbing")
assert(clR.z == oakR.z + 1 and clR.x == oakR.x and clR.y == oakR.y, "climb z")
go("down", "Oak", { "climb", "west" })
assert(S.roomCount() == 2 and S.map.rooms[clId].exits.down == oakId
    and rmap.track.pos == oakId, "climb round trip")

-- two rooms with one fingerprint: look never guesses
fresh(); start("A", { "east" })
local twin = createRoomID(); addRoom(twin); setRoomArea(twin, S.map.rooms[one("A")].area)
setRoomUserData(twin, "fp", "A|east")
rmap.track.pos = nil
go("look", "A", { "east" })
assert(rmap.track.pos == nil, "guessed between twins")

-- failed move must not let the prompt close the next queued command
fresh(); start("A", { "east" })
send("s"); send("wield sword")
rmap.onLine("You can't go that way!"); rmap.onLine(PROMPT)
assert(#rmap.track.q == 1 and rmap.track.q[1].cmd == "wield sword", "fail handled")

-- up creates a room one level higher; look leaves special exits alone
fresh(); start("A", { "up" })
go("u", "U", { "down" })
assert(S.map.rooms[one("U")].z == S.map.rooms[one("A")].z + 1, "z")
go("look", "U", { "down" })
assert(next(S.map.rooms[one("U")].special) == nil and #S.calls > 0
    and next(S.map.rooms[one("A")].special) == nil, "look added special")
print("tracker_test ok")
