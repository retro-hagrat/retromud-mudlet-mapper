-- 45_seed: put every guild map into the player's map, and welcome a new player.
-- Contract: build.py embeds each seeds/<guild>.json as rmap.seedData. Whenever the
-- package starts, and again at the first room block of a session, every seed the
-- map has not yet had is merged in as its own area (named for the guild). Merging adds
-- rooms with fresh ids and never touches or replaces a room the player already has
-- (loadJsonMap replaces the whole map, so it is not used). Which seeds were merged is
-- kept in the map's user data, so a deleted area is not brought back.
-- A new character is told apart by an empty map at the first merge: that sets
-- "rmap.welcome" to pending, and the first room block then puts the player on their
-- room (a guild start room is in the map), turns mapping on, opens the map pane and
-- zooms in. Everyone else just resumes mapping, unless they ran `rmap stop`.
-- Runs after 40_tracker so the tracker has already resolved the block (a spontaneous
-- login block leaves T.pos nil). Creation and first-login rooms never reach it:
-- see settings.ignoreRooms.

rmap.seed = { checked = false }
local S = rmap.seed

-- The player's explicit `rmap start` / `rmap stop` is kept in the map's user
-- data, so it survives sessions and goes with the map. Unset means "on".
S.PREF = "rmap.mapping"
function S.remember(choice) setMapUserData(S.PREF, choice) end
function S.wantsMapping() return getMapUserData(S.PREF) ~= "off" end

S.MERGED, S.WELCOME = "rmap.merged", "rmap.welcome"

-- Mudlet direction numbers (the same as settings.dirs)
local DIRNUM = { north = 1, northeast = 2, northwest = 3, east = 4, west = 5, south = 6,
    southeast = 7, southwest = 8, up = 9, down = 10, ["in"] = 11, out = 12 }

local function names(csv)
    local t = {}
    for n in (csv or ""):gmatch("[^,]+") do t[n] = true end
    return t
end

-- One seed as a new area. Returns the number of rooms added.
function S.mergeSeed(name, d)
    if getAreaTable()[d.area] then return 0 end   -- the player already has an area of that name
    local area = addAreaName(d.area)
    if not area then return 0 end
    local ids, made = {}, {}
    for _, r in ipairs(d.rooms) do
        local id = createRoomID()
        addRoom(id)
        setRoomArea(id, area)
        setRoomName(id, r[2])
        setRoomCoordinates(id, r[3], r[4], r[5])
        for k, v in pairs(r[8]) do setRoomUserData(id, k, v) end
        ids[r[1]], made[#made + 1] = id, id
    end
    for _, r in ipairs(d.rooms) do
        local from = ids[r[1]]
        for dir, to in pairs(r[6]) do
            if ids[to] then
                if DIRNUM[dir] then setExit(from, ids[to], DIRNUM[dir])
                else addSpecialExit(from, ids[to], dir) end    -- a named exit, e.g. "college"
            end
        end
        for _, dir in ipairs(r[7]) do setExitStub(from, DIRNUM[dir], true) end
    end
    rmap.icons.apply(name, made)
    return #made
end

-- Merge every seed the map has not had. A new character's map is empty: mark it.
function S.mergeAll()
    local done = names(getMapUserData(S.MERGED))
    local todo = {}
    for name in pairs(rmap.seedData or {}) do
        if not done[name] then todo[#todo + 1] = name end
    end
    if #todo == 0 then return 0 end
    table.sort(todo)
    local fresh = next(getRooms() or {}) == nil and next(done) == nil
    local n = 0
    for _, name in ipairs(todo) do
        n = n + S.mergeSeed(name, rmap.seedData[name])
        done[name] = true
    end
    local list = {}
    for name in pairs(done) do list[#list + 1] = name end
    table.sort(list)
    setMapUserData(S.MERGED, table.concat(list, ","))
    if fresh then setMapUserData(S.WELCOME, "pending") end
    if updateMap then updateMap() end
    return n
end

function S.onRoom(_, b)
    if S.checked then return end
    S.checked = true                 -- once per session, whatever happens
    -- Whatever is still queued comes from commands typed before this room
    -- (creation, login, registration): none can relate to the map. Left in,
    -- a stale entry would claim the next room block.
    rmap.track.q = {}
    S.mergeAll()                     -- no-op unless the map was not ready at start-up
    local welcome = getMapUserData(S.WELCOME) == "pending"
    if welcome then setMapUserData(S.WELCOME, "done") end
    if not welcome and not S.wantsMapping() then return end
    rmap.mapping = true
    if not welcome then
        rmap.out("mapping is on (rmap stop turns it off)", "ok")
        return
    end
    local id = rmap.build.find(b.fingerprint)
    if not id then
        rmap.track.adopt(b)
        rmap.out("new map started here; mapping is on", "ok")
        return
    end
    rmap.track.pos = id
    rmap.track.focus()
    -- zoom is stored per area: without the area it lands on whichever one was showing
    if setMapZoom then pcall(setMapZoom, rmap.settings.seedZoom, getRoomArea(id)) end
    -- unverified: openMapWidget() exists in Mudlet 4.17+
    if openMapWidget then pcall(openMapWidget) end
    rmap.out("the guild maps are loaded; mapping is on", "ok")
end

rmap.inits[#rmap.inits + 1] = function()
    S.checked = false
    rmap.on("rmap.onRoom", S.onRoom)
    S.mergeAll()
end
