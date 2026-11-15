-- usage: lua replay.lua <body.lua> <capture> [<capture>.expect]
-- Feeds the capture line by line to rmap.onLine. Block ends come from the
-- settings prompt pattern (captures contain no GA bytes), surfaced to the
-- module through isPrompt(). Prints ROOM|title|exits per rmap.onRoom event.
-- With an .expect file, each SEND|cmd in it is raised as
-- sysDataSendRequest where the capture shows the command: after the
-- prompt line for a prompt echo (`... >cmd`), before the line for a
-- command typed alone on its own line. Also usable as a module:
-- dofile("replay.lua")(body, capture, expect) returns the stub S.
local dir = arg and arg[0]:match("^(.*)/[^/]*$") or "."
local S = package.loaded.mudlet_stub or dofile(dir .. "/mudlet_stub.lua")

local function run(body, capture, expect)
    S.reset()
    S.install()
    S.load(body)
    S.fire("sysLoadEvent")
    rmap.mapping = true
    local sends, nextSend = {}, 1
    for l in io.lines(expect or "/dev/null") do
        local c = l:match("^SEND|(.*)$")
        if c then sends[#sends + 1] = c end
    end
    local function send(cmd)
        assert(sends[nextSend] == cmd, "SEND order: expected "
            .. tostring(sends[nextSend]) .. " got " .. cmd)
        nextSend = nextSend + 1
        S.raiseEvent("sysDataSendRequest", cmd)
    end
    registerAnonymousEventHandler("rmap.onRoom", function(_, room)
        print("ROOM|" .. room.name .. "|" .. table.concat(room.exits, ","))
        -- The first block in a capture has no command before it: that is
        -- the explicit `rmap where` orphan creation.
        if S.roomCount() == 0 and not rmap.track.pos then
            rmap.track.adopt(room)
        end
    end)
    for raw in io.lines(capture) do
        local line = raw:gsub("\r$", "")
        S.prompt = line:find(rmap.settings.promptPattern) ~= nil
        if not S.prompt and line == sends[nextSend] then send(line) end
        rmap.onLine(line)
        local echo = S.prompt and line:match(">%s*(%S.-)%s*$")
        if echo then send(echo) end
    end
    -- A capture can end mid-block with no prompt line; close it as the
    -- next prompt would.
    S.prompt = true
    rmap.onLine("")
    assert(nextSend == #sends + 1, "unsent SEND lines from " .. (expect or ""))
    return S
end

if arg and arg[0]:find("replay%.lua$") then
    run(arg[1], arg[2], arg[3])
end
return run
