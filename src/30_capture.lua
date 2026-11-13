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

-- Walk back from each exits line to the description start (first
-- exactly-two-space-indented line, which may be just the two spaces;
-- deeper indents are list continuations); the title is the non-noise
-- line above it.
local function scan(buf)
    local lo, i = 1, 1
    while i <= #buf do
        local exits, last = parseExits(buf, i)
        if exits then
            local d = i - 1
            while d >= lo and not (buf[d]:find("^  %S") or buf[d] == "  ") do
                d = d - 1
            end
            if d < lo then
                -- shortcut: builders may indent the first line 3+ spaces;
                -- nearest such line wins, so a deeper-indented mid-description
                -- line can be mistaken for the start. Upgrade if seen.
                d = i - 1
                while d >= lo and not buf[d]:find("^   +%S") do d = d - 1 end
            end
            local t = d - 1
            -- an indented line above the 2-space line is the description's
            -- real first line (e.g. a 4-space "You have arrived..."), not a title
            while t >= lo and (isNoise(buf[t]) or buf[t]:find("^%s+%S")) do
                t = t - 1
            end
            if d >= lo and t >= lo then
                local lines = {}
                for k = t, last do lines[#lines + 1] = buf[k] end
                raiseEvent("rm.onRoom", {
                    name = buf[t], exits = exits, lines = lines,
                    fingerprint = fingerprint(buf[t], exits),
                })
            end
            lo, i = last + 1, last + 1
        else
            i = i + 1
        end
    end
end

-- Raises rm.onRoom per room, then rm.onSegment(n) with the count of
-- non-noise lines, so the tracker can close commands that print no room.
local function flush()
    local buf = rm.cap.buf
    rm.cap.buf = {}
    scan(buf)
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
        flush()
    end
end

rm.inits[#rm.inits + 1] = function()
    -- unverified: tempRegexTrigger("^", fn) fires for every line, and
    -- the global `line` holds the current line inside fn
    local id = tempRegexTrigger("^", function() rm.onLine(line) end)
    rm.ids.trigger[#rm.ids.trigger + 1] = id
end
