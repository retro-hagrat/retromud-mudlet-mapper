-- 20_settings: defaults + merge/load/save of user overrides.
-- Contract (docs/design.md): defaults in code, user overrides merged from
-- a table.save'd file in the profile dir; per-character prompt/exits
-- patterns; persisted UI geometry. No behavior. Phase 0 holds defaults
-- only; persistence arrives with the first setting that needs it.

rmap.settings = {
    -- Fallback prompt pattern (Lua pattern), used when the connection
    -- sends no GA and by offline replay. Not end-anchored. See
    -- docs/output-format.md "Prompt patterns".
    -- Allows an "EQ Tick: " style prefix and a negative Sp.
    promptPattern = "^[%w ]*:? *Hp:%s*%d+/%d+%s+Sp:%s*%-?%d+/%d+%s+Ep:%s*%d+/%d+",
    -- The short tick prompt (nothing after Ep). It can land between a
    -- command and its output (swimming: "You are in deep water...", short
    -- prompt, then the room block), so once a full prompt has been seen a
    -- segment ending at it is "soft" and closes no command.
    shortPrompt = "^Hp:%s*%d+/%d+%s+Sp:%s*%-?%d+/%d+%s+Ep:%s*%d+/%d+%s*$",

    -- Exits grammar (docs/output-format.md "Exits grammar"). The solo
    -- pattern is lazy so the trailing period is not captured.
    exitsMulti = "^Obvious exits are:%s+(.*)",
    exitsNone = "^There are no obvious exits%.?%s*$",
    exitsSolo = "^The only obvious exit is%s+(%S-)%.?%s*$",

    -- Noise lines skipped when looking for the room title.
    ignore = {
        "^You are flying%.$",
        "^.- starts using ",
        "^ %*%*%* NEW ROUND %*%*%*",
        "^%-%-%- HP:",
        "^You hit ", "^You do not hit ", "^You attack ",
        " fails to hit you%.$", " hits you ",
        "is DEAD, R%.I%.P%.$", "^You can act again%.$",
        "^The clouds begin to break apart",
    },

    -- Lines buffered with no prompt before reporting "no usable prompt".
    maxBlockLines = 500,

    -- Seconds before an unresolved expectation is dropped (a silent or
    -- failed command must never stall the queue).
    expectTimeout = 10,

    -- Command classification (docs/mapper-protocol.md). First word of
    -- the sent command; extend during calibration.
    verifyVerbs = { look = true, l = true, glance = true },
    previewVerbs = { peer = true, scry = true },
    -- Teleports that work from any room: they re-sync by fingerprint, never
    -- become a special exit (a "wizhome" link on every room walked from).
    teleportVerbs = { ["goto"] = true, wizhome = true, home = true },

    -- Lines that cancel the head expectation (a move that did not move).
    moveFail = { "^You can't go that way!" },

    -- Fingerprint search radius (Chebyshev) for non-Euclidean links.
    maxSearchDistance = 5,
    -- Freeform verbs that are vertical in meaning: layers to climb (layout
    -- only; the link is by room id either way).
    freeformDz = { climb = 1 },
    areaName = "RetroMUD",

    -- Map zoom set when a guild seed loads (lower is closer). The default of 20 is too far out to
    -- read the room symbols; 8 shows about a dozen rooms in the map pane. Returning players keep theirs.
    seedZoom = 8,

    -- Room blocks the game prints around character creation and the first
    -- login. They are not part of the world: capture never raises them, so
    -- neither the tracker nor the seeder sees them. By fingerprint.
    ignoreRooms = {
        ["Character Creation|enter,prev,shrines"] = true,
        ["Race Selection Room|next,prev"] = true,
        ["Guild Selection Room|next"] = true,
        ["Welcome to RetroMUD|enter,skip"] = true,       -- one-time disclaimers room
        -- the creation shrines (stat boosts) off Character Creation: a hub and
        -- fourteen identical rooms
        ["A room full of shrines|agi,allstats,cha,con,dex,hermmax,int,maxsize,minsize,out,per,skillmax,spirmax,str,wis"] = true,
        ["A small shrine|out"] = true,
    },

    -- Cardinal directions: abbreviation, Mudlet direction number
    -- (setExit/setExitStub), coordinate delta, opposite. in/out are not
    -- here: they have no delta, so they are freeform (special) exits.
    dirs = {
        north     = { abbr = "n",  num = 1,  dx = 0,  dy = 1,  dz = 0,  opp = "south" },
        northeast = { abbr = "ne", num = 2,  dx = 1,  dy = 1,  dz = 0,  opp = "southwest" },
        northwest = { abbr = "nw", num = 3,  dx = -1, dy = 1,  dz = 0,  opp = "southeast" },
        east      = { abbr = "e",  num = 4,  dx = 1,  dy = 0,  dz = 0,  opp = "west" },
        west      = { abbr = "w",  num = 5,  dx = -1, dy = 0,  dz = 0,  opp = "east" },
        southeast = { abbr = "se", num = 7,  dx = 1,  dy = -1, dz = 0,  opp = "northwest" },
        southwest = { abbr = "sw", num = 8,  dx = -1, dy = -1, dz = 0,  opp = "northeast" },
        south     = { abbr = "s",  num = 6,  dx = 0,  dy = -1, dz = 0,  opp = "north" },
        up        = { abbr = "u",  num = 9,  dx = 0,  dy = 0,  dz = 1,  opp = "down" },
        down      = { abbr = "d",  num = 10, dx = 0,  dy = 0,  dz = -1, opp = "up" },
    },
}
