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
    -- the room it was entered from: a freeform way out of it (out, leave)
    -- leads back there (see B.special)
    if from then setRoomUserData(id, "via", tostring(from)) end
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
-- is not in `reserved` ("x,y,z" keys). The room slides outward along the
-- exit's ray first (a NE exit never draws as east); failing that, of the
-- nearest free cells the one whose bearing from the source cell (sx, sy)
-- is closest to the exit's, then the closest to the source. Cells are
-- checked in `area`, the area the new room will join.
local function freeCell(x, y, z, reserved, sx, sy, area)
    reserved = reserved or {}
    -- first slide the room outward along the exit's own ray, which keeps
    -- its compass bearing exact; only then search the grid around it
    local ux, uy = x - (sx or x), y - (sy or y)
    if ux ~= 0 or uy ~= 0 then
        for k = 0, 3 do
            local cx, cy = x + k * ux, y + k * uy
            if not roomAt(cx, cy, z, area) and not reserved[cx .. "," .. cy .. "," .. z] then
                return cx, cy, z
            end
        end
    end
    for r = 0, math.huge do
        local bx, by, bd
        for i = -r, r do
            for j = -r, r do
                local cx, cy = x + i, y + j
                if math.max(math.abs(i), math.abs(j)) == r
                    and not roomAt(cx, cy, z, area)
                    and not reserved[cx .. "," .. cy .. "," .. z] then
                    local d = 0
                    if sx then
                        local vx, vy, ux, uy = cx - sx, cy - sy, x - sx, y - sy
                        local len = math.sqrt(vx * vx + vy * vy) * math.sqrt(ux * ux + uy * uy)
                        -- bearing off by 1-cos in 1e-6 steps; none for up/down/freeform (u = 0)
                        local off = len > 0 and math.floor((1 - (vx * ux + vy * uy) / len) * 1e6 + 0.5) or 0
                        d = off * 1e4 + vx * vx + vy * vy
                    end
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
local function near(from, fp, opp, dir)
    local x, y, z = getRoomCoordinates(from)
    local d = rmap.settings.dirs[dir]
    local ex, ey, ez = x + d.dx, y + d.dy, z + d.dz     -- the cell the exit points at
    local taken = leadsTo(from)
    local hit
    local all = candidates(fp)
    -- a fingerprint on many rooms (a forest, a marsh) proves nothing: a
    -- duplicate is easy to merge by hand, a false merge breaks paths
    if #all > 1 then return nil end
    for _, id in ipairs(all) do
        local a, b, c = getRoomCoordinates(id)
        local back = getRoomExits(id)[opp]
        -- the room already linked behind us is never "ahead" (a
        -- corridor of identical rooms would fold back on itself)
        if id ~= from and getRoomArea(id) == getRoomArea(from)
            and (not back or back == from)
            and not taken[id]
            -- a look-alike right beside the free expected cell is a
            -- neighbour in the layout, not a fold back onto itself
            and not (c == ez and math.max(math.abs(a - ex), math.abs(b - ey)) <= 1)
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
    -- ...and a look-alike whose way back already leads to another room is
    -- that room's neighbour, not ours (a forest of identical rooms)
    if to and not linked then
        local back = getRoomExits(to)[d.opp]
        if back and back ~= from then to = nil end
    end
    -- an inferred way back that led somewhere else was wrong: drop it
    if to and linked and B.fp(to) ~= b.fingerprint and not peer
        and inferred(from, dir) then
        setExit(from, -1, d.num)
        setExitStub(from, d.num, true)
        to = nil
    end
    -- a preview must not fold two look-alike neighbours into one room:
    -- only a real link (or the cell guess above) may reuse a room
    to = to or (not peer and near(from, b.fingerprint, d.opp, dir)) or nil
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
        -- a freeform way out of a room entered by a freeform exit, onto a
        -- room that looks like the one we came in from, leads back there
        if not to then
            local ok, v = pcall(function() return tonumber(getRoomUserData(from, "via")) end)
            if ok and v and select(1, pcall(B.fp, v)) and B.fp(v) == b.fingerprint
                and v ~= from and not leadsTo(from)[v] then
                to = v
            end
        end
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
    -- a place not linked to anything mapped gets its own area (named after
    -- its first room), so unrelated places never share one grid and grow
    -- into each other; a pinned `rmap area` still wins
    if not rmap.settings.areaPinned then
        local name, n = b.name, 1
        while getAreaTable()[name] do n = n + 1; name = b.name .. " (" .. n .. ")" end
        setRoomArea(to, addAreaName(name))
        setRoomCoordinates(to, 0, 0, 0)
    end
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
