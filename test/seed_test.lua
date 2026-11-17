-- usage: lua seed_test.lua <body.lua>
-- Guild maps (45_seed): every seed is merged into the player's map as its own area;
-- a new character's first room block puts them on their room; an existing map is
-- only added to, never replaced.
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
local S = dofile(dir .. "/mudlet_stub.lua")
local PROMPT = "Hp: 1/1  Sp: 1/1  Ep: 1/1"

-- a block as the game prints it on login (no command was sent)
local function block(name, exit)
    rmap.onLine(name)
    rmap.onLine("  A place.")
    rmap.onLine("The only obvious exit is " .. exit .. ".")
    rmap.onLine(PROMPT)
end

local function blockEx(name, exitsLine)
    rmap.onLine(name)
    rmap.onLine("  A place.")
    rmap.onLine(exitsLine)
    rmap.onLine(PROMPT)
end

-- prefill: rooms (id -> name) and map user data the player already has
local function boot(prefill, userdata)
    S.reset()
    S.install()
    S.load(arg[1], true)
    for id, name in pairs(prefill or {}) do
        S.map.rooms[id] = { name = name, x = 0, y = 0, z = 0, exits = {},
            stubs = {}, special = {}, ud = {} }
    end
    for k, v in pairs(userdata or {}) do S.map.userdata[k] = v end
    S.fire("sysLoadEvent")
end

local function startOf(guild)
    for fp, name in pairs(rmap.seedIndex) do
        if name == guild then return rmap.build.find(fp) end
    end
end

local function zoomCalls()
    local n, last = 0, nil
    for _, c in ipairs(S.calls) do
        if c.name == "setMapZoom" then n = n + 1; last = c end
    end
    return n, last
end

boot()                      -- loads the package, so rmap.seedData exists
local TOTAL = 0
for _, d in pairs(rmap.seedData or {}) do TOTAL = TOTAL + #d.rooms end
local GUILDS = 0
for _ in pairs(rmap.seedData) do GUILDS = GUILDS + 1 end
assert(GUILDS == 19 and TOTAL > 300, "seed data missing: " .. GUILDS .. " guilds, " .. TOTAL .. " rooms")

-- 1. a new character: the package start merges every guild map; the first block
-- (their guild's start room) puts them there, turns mapping on and zooms in
boot()
assert(S.roomCount() == TOTAL, "not every guild map was merged: " .. S.roomCount())
local areas = 0
for name in pairs(S.map.areas) do if name ~= "Default Area" then areas = areas + 1 end end
assert(areas == GUILDS, "one area per guild expected: " .. areas)
block("Biomancer Library", "south")
local bio = startOf("biomancer")
assert(bio and rmap.track.pos == bio, "not placed on the start room: " .. tostring(rmap.track.pos))
assert(rmap.mapping and rmap.track.state() == "SYNCED")
assert(S.roomCount() == TOTAL, "the first block added rooms")
local n, z = zoomCalls()
assert(n == 1 and z.args[1] == rmap.settings.seedZoom and z.args[2] == S.map.areas.Biomancer,
    "zoom not set once for the guild's area")
assert(S.map.rooms[bio].area == S.map.areas.Biomancer)

-- 1b. the guild service symbols: Biomancer is marked, a guild not yet checked is not
local marked, other = 0, 0
for _, r in pairs(S.map.rooms) do
    if r.char then
        if r.area == S.map.areas.Biomancer then marked = marked + 1 else other = other + 1 end
    end
end
assert(S.map.rooms[bio].char == "S" and marked > 10, "Biomancer was not marked: " .. marked)
assert(other == 0, "an unchecked guild was marked")

-- 1c. merging again (a restart) adds nothing
S.fire("sysLoadEvent")
assert(S.roomCount() == TOTAL, "merged twice: " .. S.roomCount())

-- 2. once per session: a later block is not a first login
block("Biomancer Library", "south")
assert(select(1, zoomCalls()) == 1, "welcomed twice")

-- 2b. any guild's start room works, not just the first one (the Merchant's has an `adv-guild` exit)
boot()
blockEx("Training room.", "Obvious exits are: adv-guild, and south.")
assert(rmap.track.pos == startOf("merchant"), "Merchant start room not found")
assert(S.map.rooms[rmap.track.pos].area == S.map.areas.Merchant)

-- 3. a first room that is in no seed: the maps are all there, and a room is
-- started here for the player
boot()
block("A muddy lane", "east")
assert(rmap.mapping and rmap.track.pos, "no fresh room")
assert(S.roomCount() == TOTAL + 1 and S.map.rooms[rmap.track.pos].name == "A muddy lane")

-- 4. a returning player: nothing of theirs is replaced, the guild areas are
-- added beside it, and mapping resumes without a zoom change
boot({ [7] = "Somewhere I mapped" })
assert(S.map.rooms[7].name == "Somewhere I mapped" and S.roomCount() == TOTAL + 1,
    "an existing room was replaced or lost")
block("Biomancer Library", "south")
assert(rmap.mapping, "mapping did not resume for a returning player")
assert(select(1, zoomCalls()) == 0, "a returning player was zoomed")

-- 4b. ...unless they stopped it: that choice is remembered across sessions
boot({ [7] = "Somewhere I mapped" }, { ["rmap.mapping"] = "off" })
block("Biomancer Library", "south")
assert(not rmap.mapping, "mapping resumed after the player stopped it")

-- 4c. rmap stop / rmap start write the choice; it is read back next session
boot({ [7] = "Somewhere I mapped" })
assert(S.alias("rmap stop") and S.map.userdata["rmap.mapping"] == "off", "stop not remembered")
assert(S.alias("rmap start") and S.map.userdata["rmap.mapping"] == "on", "start not remembered")
S.alias("rmap stop")
local choice = S.map.userdata["rmap.mapping"]     -- the next session finds it in the map
boot({ [7] = "Somewhere I mapped" }, { ["rmap.mapping"] = choice })
block("Biomancer Library", "south")
assert(not rmap.mapping, "a remembered stop was ignored by the next session")

-- 4d. a map that already has an area of a guild's name (an older seeded map, or
-- one drawn by hand) is not given a second one
S.reset()
S.install()
S.load(arg[1], true)
S.map.areas.Biomancer = 1
S.map.nextArea = 2
S.fire("sysLoadEvent")
local count = 0
for _, r in pairs(S.map.rooms) do if r.area == 1 then count = count + 1 end end
assert(count == 0, "the player's own Biomancer area was merged into")
assert(S.roomCount() == TOTAL - #rmap.seedData.biomancer.rooms, "wrong number of rooms merged")

-- 5. character creation prints room blocks first: ignored, and they must not
-- use up the one try; the guild room that follows still welcomes
boot()
blockEx("Character Creation", "Obvious exits are: enter, prev, and shrines.")
blockEx("Race Selection Room", "Obvious exits are: next, and prev.")
blockEx("Guild Selection Room", "The only obvious exit is next.")
assert(S.roomCount() == TOTAL, "creation room was mapped")
assert(not rmap.mapping and not rmap.seed.checked, "creation rooms used up the try")
block("Biomancer Library", "south")
assert(rmap.mapping and rmap.track.pos == startOf("biomancer"))

-- 6. an unknown first room after creation still starts a room
boot()
blockEx("Guild Selection Room", "The only obvious exit is next.")
block("A muddy lane", "east")
assert(S.roomCount() == TOTAL + 1 and rmap.mapping, "no room after creation")

-- 7. a room entered from a seeded room joins its area, not the setting's
boot()
block("Biomancer Library", "south")
local guildArea = S.map.areas.Biomancer
send("south")
blockEx("Biomancer Entrance", "Obvious exits are: north, east, and up.")
local entrance = rmap.track.pos
assert(entrance and entrance ~= startOf("biomancer") and S.map.rooms[entrance].name == "Biomancer Entrance",
    "walking along a seeded link did not follow it")
assert(S.roomCount() == TOTAL, "a known room was created again")
-- the entrance has an unexplored exit east
send("east")
blockEx("Bazz Street", "Obvious exits are: east, and west.")
local street = rmap.track.pos
assert(street and S.map.rooms[street].area == guildArea,
    "new room went to area " .. tostring(street and S.map.rooms[street].area))
assert(not S.map.areas.RetroMUD, "the default area was created anyway")

-- 8. rmap area <name> pins the area: new rooms go there from then on
assert(S.alias("rmap area Elsewhere"))
send("east")
blockEx("Another Street", "Obvious exits are: east, and west.")
local more = rmap.track.pos
assert(more and S.map.rooms[more].area == S.map.areas.Elsewhere,
    "pinned area ignored: " .. tostring(S.map.rooms[more] and S.map.rooms[more].area))

-- 9. a new room must not land on a room already in the guild's area: free
-- cells are looked up in the area the room joins, not the default area
boot()
block("Biomancer Library", "south")
ga = S.map.areas.Biomancer
send("south")
blockEx("Biomancer Entrance", "Obvious exits are: north, east, and up.")
local ex, ey, ez = S.map.rooms[rmap.track.pos].x, S.map.rooms[rmap.track.pos].y, S.map.rooms[rmap.track.pos].z
S.map.rooms[900] = { name = "Stray", area = ga, x = ex + 1, y = ey, z = ez, exits = {},
    stubs = {}, special = {}, ud = { fp = "Stray|none" } }
send("east")
blockEx("Bazz Street", "Obvious exits are: east, and west.")
local placed = S.map.rooms[rmap.track.pos]
assert(placed and not (placed.x == ex + 1 and placed.y == ey and placed.z == ez),
    "new room was put on top of an existing room in its area")

-- 10. the real first login: `enter` typed in creation, then the guild room,
-- the guide's chatter and the disclaimers room, all before one prompt. The
-- player lands on the guild's start room, and the disclaimers room is not
-- mapped or linked as an `enter` exit.
boot()
send("enter")
for _, l in ipairs({
    "Biomancer Library", "  A place.", "The only obvious exit is south.",
    "Wysoom guide gasps 'Hello master! To learn more about me, ask me about world",
    "      guide.  To learn more about how to play this game, ask me about getting",
    "      started.'", "You must read a few disclaimers once in the",
    "entire life of your character on Retromud.", "Welcome to RetroMUD",
    "  This fairly large room, is very clean and sterile looking.",
    "A very stern receptionist sits behind a large imposing desk.",
    " It is fairly well lit here.", "Obvious exits are: enter, and skip.", PROMPT }) do
    rmap.onLine(l)
end
local start = startOf("biomancer")
assert(S.roomCount() == TOTAL, "disclaimers room was mapped: " .. S.roomCount() .. " rooms")
assert(rmap.track.pos == start, "player moved off the start room: " .. tostring(rmap.track.pos))
assert(next(getSpecialExitsSwap(start)) == nil, "a bogus special exit was recorded")

-- 11. a wrong turn in an ignored room loses the position; the redisplayed
-- guild room after registration puts it back
boot()
block("Biomancer Library", "south")
assert(rmap.track.pos == start)
rmap.track.pos = nil                              -- e.g. a rejected move expired
block("Biomancer Library", "south")               -- the game prints the guild room again
assert(rmap.track.pos == start and rmap.track.state() == "SYNCED", "lost position not healed")

-- 12. commands typed before the first room (creation, description, enter) must
-- not claim a later block: a quick first move follows the seeded link
boot()
send("desc set"); send("."); send("enter")
block("Biomancer Library", "south")
assert(rmap.track.pos == start)
assert(#rmap.track.q == 0, "stale expectations survived the first room: " .. #rmap.track.q)
send("south")
blockEx("Biomancer Entrance", "Obvious exits are: north, east, and up.")
assert(next(S.map.rooms[start].special) == nil, "a stale expectation created a special exit")
assert(rmap.track.pos and rmap.track.pos ~= start, "the first move was not followed")

-- 13. a named exit in a seed (Biomancer "college") becomes a special exit
boot()
local found = false
for id, r in pairs(S.map.rooms) do
    if r.name == "Initiation Room" then found = next(r.special) == "college" end
end
assert(found, "the `college` exit was not merged as a special exit")

print("seed_test ok")
