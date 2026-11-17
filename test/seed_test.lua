-- usage: lua seed_test.lua <body.lua>
-- First-login seeding (45_seed): a new character's first room block loads
-- the matching guild seed; an existing map is never replaced.
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

local function boot(rooms)
    S.reset()
    S.install()
    S.load(arg[1])
    S.fire("sysLoadEvent")
    for id, name in pairs(rooms or {}) do
        S.map.rooms[id] = { name = name, x = 0, y = 0, z = 0, exits = {},
            stubs = {}, special = {}, ud = {} }
    end
    local loaded
    -- stands in for Mudlet's loadJsonMap: the seed's start room is room 1
    loadJsonMap = function(path)
        loaded = path
        S.map.areas.Biomancer = 1
        S.map.nextArea = 2          -- the next area (the default one) must differ
        S.map.rooms[1] = { name = "Biomancer Library", area = 1, x = 0, y = 0,
            z = 0, exits = {}, stubs = {}, special = {},
            ud = { fp = "Biomancer Library|south", start = "1" } }
        return true
    end
    return function() return loaded end
end

-- 1. new character in a guild start room: seed loaded, mapping on, synced
local loaded = boot()
assert(rmap.seedIndex["Biomancer Library|south"] == "biomancer", "no index")
block("Biomancer Library", "south")
assert(loaded() == "/profile/retromud/seeds/biomancer.json", tostring(loaded()))
assert(rmap.mapping, "mapping not turned on")
assert(rmap.track.pos == 1, "not placed on the start room: " .. tostring(rmap.track.pos))
assert(rmap.track.state() == "SYNCED")
assert(S.roomCount() == 1, "seeded map was added to")

-- 2. only once per session: a later block must not reload
S.map.rooms = {}
block("Biomancer Library", "south")
assert(S.roomCount() == 0, "seeded twice")

-- 3. empty map, room in no seed: start a fresh map here, nothing loaded
loaded = boot()
block("A muddy lane", "east")
assert(not loaded(), "loaded a seed for an unknown room")
assert(rmap.mapping and S.roomCount() == 1 and rmap.track.pos, "no fresh map")

-- 4. existing map (a returning player): never replaced, and mapping resumes
loaded = boot({ [7] = "Somewhere I mapped" })
block("Biomancer Library", "south")
assert(not loaded(), "replaced an existing map")
assert(S.roomCount() == 1, "touched an existing map")
assert(rmap.mapping, "mapping did not resume for a returning player")

-- 4b. ...unless they stopped it: that choice is remembered across sessions
loaded = boot({ [7] = "Somewhere I mapped" })
S.map.userdata["rmap.mapping"] = "off"
block("Biomancer Library", "south")
assert(not loaded() and S.roomCount() == 1 and not rmap.mapping,
    "mapping resumed after the player stopped it")

-- 4c. rmap stop / rmap start write the choice; it is read back next session
loaded = boot({ [7] = "Somewhere I mapped" })
assert(S.alias("rmap stop") and S.map.userdata["rmap.mapping"] == "off", "stop not remembered")
assert(S.alias("rmap start") and S.map.userdata["rmap.mapping"] == "on", "start not remembered")
S.alias("rmap stop")
local choice = S.map.userdata["rmap.mapping"]     -- the next session finds it in the map
boot({ [7] = "Somewhere I mapped" })
S.map.userdata["rmap.mapping"] = choice
block("Biomancer Library", "south")
assert(not rmap.mapping, "a remembered stop was ignored by the next session")

-- 5. character creation prints room blocks first: ignored, and they must not
-- use up the one try; the guild room that follows still seeds
loaded = boot()
blockEx("Character Creation", "Obvious exits are: enter, prev, and shrines.")
blockEx("Race Selection Room", "Obvious exits are: next, and prev.")
blockEx("Guild Selection Room", "The only obvious exit is next.")
assert(not loaded() and S.roomCount() == 0, "creation room was mapped or seeded")
assert(not rmap.mapping and not rmap.seed.checked, "creation rooms used up the try")
block("Biomancer Library", "south")
assert(loaded() == "/profile/retromud/seeds/biomancer.json", "no seed after creation")
assert(rmap.mapping and rmap.track.pos == 1)

-- 6. an unknown first room after creation still starts a fresh map
loaded = boot()
blockEx("Guild Selection Room", "The only obvious exit is next.")
block("A muddy lane", "east")
assert(not loaded() and S.roomCount() == 1 and rmap.mapping, "no fresh map after creation")

-- 7. a room entered from a seeded room joins its area, not the setting's
loaded = boot()
block("Biomancer Library", "south")
local guildArea = S.map.areas.Biomancer
assert(guildArea and S.map.rooms[1].area == guildArea)
send("south")
blockEx("Biomancer Entrance", "Obvious exits are: north, and east.")
local entrance = rmap.track.pos
assert(entrance and entrance ~= 1, "walk out of the seed did not create a room")
assert(S.map.rooms[entrance].area == guildArea,
    "new room went to area " .. tostring(S.map.rooms[entrance].area))
assert(not S.map.areas.RetroMUD, "the default area was created anyway")

-- 8. rmap area <name> pins the area: new rooms go there from then on
assert(S.alias("rmap area Elsewhere"))
send("east")
blockEx("Bazz Street", "Obvious exits are: east, and west.")
local street = rmap.track.pos
assert(street and S.map.rooms[street].area == S.map.areas.Elsewhere,
    "pinned area ignored: " .. tostring(S.map.rooms[street] and S.map.rooms[street].area))

-- 9. a new room must not land on a room already in the guild's area: free
-- cells are looked up in the area the room joins, not the default area
loaded = boot()
block("Biomancer Library", "south")
local ga = S.map.areas.Biomancer
S.map.rooms[50] = { name = "Stray", area = ga, x = 0, y = -1, z = 0, exits = {},
    stubs = {}, special = {}, ud = { fp = "Stray|none" } }
send("south")
blockEx("Biomancer Entrance", "Obvious exits are: north, and east.")
local placed = S.map.rooms[rmap.track.pos]
assert(placed and not (placed.x == 0 and placed.y == -1 and placed.z == 0),
    "new room was put on top of an existing room in its area")

-- 10. the real first login: `enter` typed in creation, then the guild room,
-- the guide's chatter and the disclaimers room, all before one prompt. The
-- seed loads, the player stays on the guild's start room, and the disclaimers
-- room is not mapped or linked as an `enter` exit.
loaded = boot()
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
assert(loaded() == "/profile/retromud/seeds/biomancer.json", "seed not loaded")
assert(S.roomCount() == 1, "disclaimers room was mapped: " .. S.roomCount() .. " rooms")
assert(rmap.track.pos == 1, "player moved off the start room: " .. tostring(rmap.track.pos))
assert(next(getSpecialExitsSwap(1)) == nil, "a bogus special exit was recorded")

print("seed_test ok")
