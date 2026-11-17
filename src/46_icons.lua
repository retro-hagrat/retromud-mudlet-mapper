-- 46_icons: ASCII symbols on guild-service rooms of a seeded map.
-- Contract: after a seed loads, rooms whose title names a service get a one-character
-- symbol (and colour) so a new player can find joining, advancing, training and so on.
-- Only seeds listed in I.seeds are marked: each one is checked by hand first, since the
-- rules go by title words. The start room is `S`.
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

-- Mark the rooms `ids` of the seed just merged.
function I.apply(seedName, ids)
    if not I.seeds[seedName] then return 0 end
    local n = 0
    for _, id in ipairs(ids) do
        local ch = getRoomUserData(id, "start") == "1" and "S" or I.symbolFor(getRoomName(id))
        if ch then
            setRoomChar(id, ch)
            local c = I.colors[ch]
            if c then setRoomCharColor(id, c[1], c[2], c[3]) end
            n = n + 1
        end
    end
    return n
end
