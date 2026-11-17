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
