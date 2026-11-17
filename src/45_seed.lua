-- 45_seed: first-login map seeding.
-- Contract: on the first room block of a session, if the profile's map has
-- no rooms (a new character), find the guild seed whose start-room
-- fingerprint equals the block's, load it, turn mapping on and put the
-- player on that room. No match: start a fresh map from this room. A map
-- with rooms is never touched: loadJsonMap replaces the whole map.
-- Seeds ship in the package as seeds/<name>.json; build.py generates
-- rmap.seedIndex (start fingerprint -> seed name) from the rooms marked
-- userData start = "1". Runs after 40_tracker so the tracker has already
-- resolved the block (a spontaneous login block leaves T.pos nil). Creation and
-- first-login rooms never reach it: see settings.ignoreRooms.

rmap.seed = { checked = false }
local S = rmap.seed

function S.path(name)
    return getMudletHomeDir() .. "/" .. rmap.name .. "/seeds/" .. name .. ".json"
end

function S.onRoom(_, b)
    if S.checked then return end
    S.checked = true                 -- once per session, whatever happens
    if next(getRooms() or {}) then return end
    local name = rmap.seedIndex and rmap.seedIndex[b.fingerprint]
    if name then
        if loadJsonMap(S.path(name)) then
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
