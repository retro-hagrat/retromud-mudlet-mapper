-- 30_capture: line buffer -> room-block detection -> rm.onRoom event.
-- Contract (docs/design.md, docs/output-format.md): rm.onLine(line) is
-- called once per received line (a trigger live, the replay harness
-- offline). Segments end at a prompt: isPrompt() (GA/EOR) live, else
-- rm.settings.promptPattern. Each exits line in a segment raises
-- raiseEvent("rm.onRoom", {name=, exits={...}, lines={...},
-- fingerprint=}), then rm.onSegment(n); a move-fail line raises
-- rm.onMoveFail. Knows nothing about the map.

rm.cap = { buf = {}, warned = false }

local function isNoise(line)
    if line:find("^%s*$") then return true end
    for i = 1, #rm.settings.ignore do
        if line:find(rm.settings.ignore[i]) then return true end
    end
    return false
end

-- Exits starting at buf[i]: returns exits list, index of last line.
local function parseExits(buf, i)
    local s = rm.settings
    if buf[i]:find(s.exitsNone) then return {}, i end
    local solo = buf[i]:match(s.exitsSolo)
    if solo then return { solo:lower() }, i end
    local rest = buf[i]:match(s.exitsMulti)
    if not rest then return nil end
    local j = i
    while not rest:find("%.%s*$") do
        j = j + 1
        if not buf[j] then return nil end
        if not isNoise(buf[j]) then rest = rest .. " " .. buf[j] end
    end
    local exits = {}
    for part in rest:gsub("%.%s*$", ""):gmatch("[^,]+") do
        local name = part:match("^%s*(.-)%s*$"):gsub("^and%s+", ""):lower()
        if name ~= "" then exits[#exits + 1] = name end
    end
    return exits, j
end

local function fingerprint(name, exits)
    local sorted = {}
    for i = 1, #exits do sorted[i] = exits[i] end
    table.sort(sorted)
    return name .. "|" .. table.concat(sorted, ",")
end

-- A plausible title: not a continuation (lowercase start) and not a
-- list header ("There are several special commands here:").
local function titleLike(line)
    return not line:find("^%l") and not line:find(":%s*$")
        and not line:find("^[^%w\"'(]")
end

-- Nearest non-noise, non-indented line above d, or nil.
local function titleAbove(buf, lo, d)
    local t = d - 1
    while t >= lo and (isNoise(buf[t]) or buf[t]:find("^%s")) do t = t - 1 end
    if t >= lo then return t end
end

-- Walk back from each exits line to a description start: a line indented
-- 2 spaces, else 3+ (builders vary: 2, 4, 10; deeper indents inside a
-- description are boxes and lists, so exactly 2 wins) whose non-noise, non-indented
-- predecessor looks like a title. A later paragraph's first line has a
-- sentence fragment above it, so nearer candidates with such a
-- predecessor are skipped. Description-less rooms (title, then the
-- single-space light line) fall back to that light line.
local function findTitle(buf, lo, i)
    for _, pat in ipairs({ "^  %S", "^  $", "^   +%S", "^   +$", "^ %S" }) do
        for d = i - 1, lo, -1 do
            if buf[d]:find(pat) then
                local t = titleAbove(buf, lo, d)
                if t and titleLike(buf[t]) then return t end
            end
        end
    end
end

-- Returns the index after the last exits line handled.
local function scan(buf)
    local lo, i = 1, 1
    while i <= #buf do
        local exits, last = parseExits(buf, i)
        if exits then
            local t = findTitle(buf, lo, i)
            if t then
                local lines = {}
                for k = t, last do lines[#lines + 1] = buf[k] end
                local name = buf[t]:match("^(.-)%s*$")
                raiseEvent("rm.onRoom", {
                    name = name, exits = exits, lines = lines,
                    fingerprint = fingerprint(name, exits),
                })
            end
            lo, i = last + 1, last + 1
        else
            i = i + 1
        end
    end
    return lo
end

-- Raises rm.onRoom per room, then rm.onSegment(n) with the count of
-- non-noise lines, so the tracker can close commands that print no room.
-- keepTail: on a forced flush keep the unscanned tail so a room whose
-- title is already buffered is not split from its exits line.
local function flush(keepTail)
    local buf = rm.cap.buf
    rm.cap.buf = {}
    local lo = scan(buf)
    if keepTail then
        for k = math.max(lo, #buf - 40), #buf do
            rm.cap.buf[#rm.cap.buf + 1] = buf[k]
        end
    end
    local n = 0
    for i = 1, #buf do
        if not isNoise(buf[i]) then n = n + 1 end
    end
    raiseEvent("rm.onSegment", n)
end

function rm.onLine(line)
    local c = rm.cap
    if isPrompt() or line:find(rm.settings.promptPattern) then
        c.warned = false
        flush()
        return
    end
    -- a reconnect banner (login art) is never part of a room
    if line:find("^%% Connected to") then c.buf = {} end
    for i = 1, #rm.settings.moveFail do
        if line:find(rm.settings.moveFail[i]) then
            raiseEvent("rm.onMoveFail")
            break
        end
    end
    c.buf[#c.buf + 1] = line
    if #c.buf > rm.settings.maxBlockLines then
        if not c.warned then
            c.warned = true
            rm.out("no usable prompt (no GA, and the prompt "
                .. "pattern never matched in " .. #c.buf .. " lines); "
                .. "set rm.settings.promptPattern", "err")
        end
        flush(true)
    end
end

rm.inits[#rm.inits + 1] = function()
    -- unverified: tempRegexTrigger("^", fn) fires for every line, and
    -- the global `line` holds the current line inside fn
    local id = tempRegexTrigger("^", function() rm.onLine(line) end)
    rm.ids.trigger[#rm.ids.trigger + 1] = id
end
