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
        S.map.areas.RetroMUD = 1
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

-- 4. existing map: untouched, mapping stays off
loaded = boot({ [7] = "Somewhere I mapped" })
block("Biomancer Library", "south")
assert(not loaded(), "replaced an existing map")
assert(not rmap.mapping and S.roomCount() == 1, "touched an existing map")

print("seed_test ok")
