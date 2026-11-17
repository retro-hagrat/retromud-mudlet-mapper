-- Fake Mudlet globals for headless tests. Returns the stub table S;
-- S.install() puts the fake globals into _G. Everything the module calls
-- is recorded: S.sent (send), S.out (echo/cecho), S.calls (mapper API).
-- Limitation: S.alias(line) understands only aliases of the form
-- "^word( .*)?$"-style (literal word prefix); it does not run PCRE.
local S = { sent = {}, out = {}, calls = {}, handlers = {},
            aliases = {}, triggers = {}, timers = {}, nextId = 0, prompt = false,
            onSend = nil }

local function newId()
    S.nextId = S.nextId + 1
    return S.nextId
end

local function remove(list, id)
    for i = 1, #list do
        if list[i].id == id then
            table.remove(list, i)
            return true
        end
    end
    return false
end

-- Recorded only (no behaviour).
local MAPPER_API = {
    "connectExitStub", "setMapZoom", "centerview",
    "saveMap", "loadMap", "saveJsonMap", "loadJsonMap",
    "gotoRoom", "lockRoom", "createMapper",
}

-- Mudlet direction number -> exit name (unverified: 1-12 numbering).
local DIRNAME = { "north", "northeast", "northwest", "east", "west",
    "south", "southeast", "southwest", "up", "down", "in", "out" }

-- In-memory map. All function names are the real Mudlet mapper API; the
-- argument/return shapes are from memory and each is unverified.
-- room = { name, area, x, y, z, exits = {dir = id}, stubs = {dir = true},
--          special = {cmd = id}, ud = {} }
function S.reset()
    S.sent, S.out, S.calls, S.handlers = {}, {}, {}, {}
    S.aliases, S.triggers, S.nextId, S.prompt = {}, {}, 0, false
    S.timers = {}
    S.onSend = nil
    S.map = { rooms = {}, areas = {}, nextArea = 1, userdata = {} }
    _G.rmap, _G.doSpeedWalk = nil, nil
end
S.map = { rooms = {}, areas = {}, nextArea = 1, userdata = {} }

local function rec(name, ...)
    S.calls[#S.calls + 1] = { name = name, args = { ... } }
end

local function installMap(g)
    local function room(id) return S.map.rooms[id] end
    g.createRoomID = function()
        local n = 1
        while room(n) do n = n + 1 end
        return n
    end
    g.addRoom = function(id)
        rec("addRoom", id)
        S.map.rooms[id] = { name = "", x = 0, y = 0, z = 0, exits = {},
            stubs = {}, special = {}, ud = {} }
        return true
    end
    g.setRoomName = function(id, v) rec("setRoomName", id, v); room(id).name = v end
    g.getRoomName = function(id) return room(id).name end
    g.setRoomChar = function(id, ch) room(id).char = ch end
    g.getRoomChar = function(id) return room(id).char or "" end
    g.setRoomCharColor = function(id, r, gr, b) room(id).charColor = { r, gr, b } end
    g.getRooms = function()
        local out = {}
        for id, r in pairs(S.map.rooms) do out[id] = r.name end
        return out
    end
    g.getMudletHomeDir = function() return "/profile" end
    g.setMapUserData = function(k, v) S.map.userdata[k] = v return true end
    g.getMapUserData = function(k) return S.map.userdata[k] end
    g.setRoomArea = function(id, a) rec("setRoomArea", id, a); room(id).area = a end
    g.getRoomArea = function(id) return room(id).area end
    g.setRoomCoordinates = function(id, x, y, z)
        rec("setRoomCoordinates", id, x, y, z)
        local r = room(id)
        r.x, r.y, r.z = x, y, z
    end
    g.getRoomCoordinates = function(id)
        local r = room(id)
        return r.x, r.y, r.z
    end
    g.getRoomsByPosition = function(a, x, y, z)
        local out = {}
        for id, r in pairs(S.map.rooms) do
            if r.area == a and r.x == x and r.y == y and r.z == z then
                out[#out + 1] = id
            end
        end
        return out
    end
    g.setExit = function(from, to, n)
        rec("setExit", from, to, n)
        room(from).exits[DIRNAME[n]] = to ~= -1 and to or nil
        return true
    end
    g.removeSpecialExit = function(id, cmd)
        rec("removeSpecialExit", id, cmd)
        room(id).special[cmd] = nil
    end
    g.deleteRoom = function(id)
        rec("deleteRoom", id)
        S.map.rooms[id] = nil
        -- unverified: Mudlet also drops exits other rooms hold into it
        for _, r in pairs(S.map.rooms) do
            for k, v in pairs(r.exits) do if v == id then r.exits[k] = nil end end
            for k, v in pairs(r.special) do if v == id then r.special[k] = nil end end
        end
        return true
    end
    g.getRoomExits = function(id)
        local out = {}
        for k, v in pairs(room(id).exits) do out[k] = v end
        return out
    end
    g.setExitStub = function(id, n, on)
        rec("setExitStub", id, n, on)
        room(id).stubs[DIRNAME[n]] = on or nil
    end
    g.addSpecialExit = function(from, to, cmd)
        rec("addSpecialExit", from, to, cmd)
        room(from).special[cmd] = to
    end
    g.getSpecialExitsSwap = function(id)
        local out = {}
        for k, v in pairs(room(id).special) do out[k] = v end
        return out
    end
    g.setRoomUserData = function(id, k, v)
        rec("setRoomUserData", id, k, v)
        room(id).ud[k] = v
        return true
    end
    g.getRoomUserData = function(id, k) return room(id).ud[k] or "" end
    g.searchRoomUserData = function(k, v)
        local out = {}
        for id, r in pairs(S.map.rooms) do
            if r.ud[k] == v then out[#out + 1] = id end
        end
        return out
    end
    g.addAreaName = function(name)
        rec("addAreaName", name)
        local id = S.map.nextArea
        S.map.nextArea = id + 1
        S.map.areas[name] = id
        return id
    end
    g.getAreaTable = function()
        local out = {}
        for k, v in pairs(S.map.areas) do out[k] = v end
        return out
    end
end

function S.roomCount()
    local n = 0
    for _ in pairs(S.map.rooms) do n = n + 1 end
    return n
end

function S.raiseEvent(name, ...)
    local snapshot = {}
    for i = 1, #S.handlers do snapshot[i] = S.handlers[i] end
    for i = 1, #snapshot do
        local h = snapshot[i]
        if h.name == name then h.fn(name, ...) end
    end
end

function S.install()
    local g = _G
    g.matches = {}
    g.send = function(cmd)
        S.sent[#S.sent + 1] = cmd
        if S.onSend then S.onSend(cmd) end
        S.raiseEvent("sysDataSendRequest", cmd)
    end
    g.echo = function(s) S.out[#S.out + 1] = s end
    g.cecho = g.echo
    g.getLastLineNumber = function() return 1 end
    g.getLines = function() return { S.lastLine or "" } end
    g.raiseEvent = S.raiseEvent
    g.registerAnonymousEventHandler = function(name, fn)
        local id = newId()
        S.handlers[#S.handlers + 1] = { id = id, name = name, fn = fn }
        return id
    end
    g.killAnonymousEventHandler = function(id)
        return remove(S.handlers, id)
    end
    g.tempRegexTrigger = function(pat, fn)
        local id = newId()
        S.triggers[#S.triggers + 1] = { id = id, pat = pat, fn = fn }
        return id
    end
    g.killTrigger = function(id) return remove(S.triggers, id) end
    g.tempAlias = function(pat, fn)
        local id = newId()
        S.aliases[#S.aliases + 1] = { id = id, pat = pat, fn = fn }
        return id
    end
    g.killAlias = function(id) return remove(S.aliases, id) end
    g.tempTimer = function(secs, fn)
        local id = newId()
        S.timers[#S.timers + 1] = { id = id, secs = secs, fn = fn }
        return id
    end
    g.killTimer = function(id) return remove(S.timers, id) end
    g.isPrompt = function() return S.prompt end
    installMap(g)
    for _, name in ipairs(MAPPER_API) do
        g[name] = function(...)
            S.calls[#S.calls + 1] = { name = name, args = { ... } }
        end
    end
end

-- Simulate typing `line` at the command line (aliases only).
function S.alias(line)
    for _, a in ipairs(S.aliases) do
        local word = a.pat:match("^%^(%a+)")
        if line == word or line:sub(1, #word + 1) == word .. " " then
            local rest = line:sub(#word + 1)
            _G.matches = { line, rest ~= "" and rest or nil }
            a.fn()
            return true
        end
    end
    return false
end

function S.fire(name, ...) S.raiseEvent(name, ...) end

-- Load the stitched body file into _G; errors propagate.
function S.load(path)
    local chunk, err = loadfile(path)
    if not chunk then error("load failed: " .. tostring(err), 0) end
    chunk()
end

return S
