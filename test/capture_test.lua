-- usage: lua capture_test.lua <body.lua>   (unit checks for 30_capture)
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
local S = dofile(dir .. "/mudlet_stub.lua")
S.install()
S.load(arg[1])
S.fire("sysLoadEvent")
local rooms
registerAnonymousEventHandler("rmap.onRoom", function(_, r)
    rooms[#rooms + 1] = r
end)
-- Feed lines with isPrompt() false: only the settings pattern ends a segment.
local function feed(lines)
    rooms = {}
    for _, l in ipairs(lines) do rmap.onLine(l) end
end
local ROOM = { "Orange Tsoda Pool", "  An orange pool.", "smell of oranges.",
    " It is dark and shadowy here.",
    "Obvious exits are: northeast, and west.", "A pretty girl" }

-- 1. every default-pattern prompt shape ends a segment
for _, p in ipairs({
    "Hp:3127/3127 Sp:988/988 Ep:2070/2120 Exp:1384189 >look",
    "Hp: 296/296 Sp: 102/102 Ep: 74/74 Gold: 0 Exp: 48 >",
    "Hp: 296/296  Sp: 102/102  Ep: 74/74",
}) do
    local t = {}
    for i, l in ipairs(ROOM) do t[i] = l end
    rmap.cap.tall = nil
    feed(t)
    assert(#rooms == 0, "room emitted before prompt")
    rmap.onLine(p)
    assert(#rooms == 1 and rooms[1].name == "Orange Tsoda Pool", p)
end
-- once a full prompt was seen, a segment ended by a short tick prompt is
-- soft (swimming: message, short prompt, then the room block)
local soft
registerAnonymousEventHandler("rmap.onSegment", function(_, n, sf) soft = sf end)
rmap.cap.tall = true
feed({ "You are in deep water and start swimming.",
    "Hp: 296/296  Sp: 102/102  Ep: 72/74" })
assert(soft == true, "short prompt after a full one must be soft")
rmap.onLine("Hp: 296/296 Sp: 102/102 Ep: 74/74 Gold: 0 Exp: 48 >")
assert(not soft, "full prompt is not soft")
rmap.cap.tall = nil
-- combat round line (uppercase) is not a prompt
feed({ "--- HP:296/296  SP:102/102  EP:74/74" })
assert(#rmap.cap.buf == 1)
rmap.onLine("Hp: 1/1  Sp: 1/1  Ep: 1/1")

-- 2. combat lines before and inside the block do not hide the title
feed({ " *** NEW ROUND ***", "--- HP:296/296  SP:102/102  EP:74/74",
    "You hit Tummyache once. (5)", "look", "Orange Tsoda Pool",
    " *** NEW ROUND ***", "--- HP:291/296  SP:102/102  EP:74/74",
    "Tummyache fails to hit you.",
    "  An orange pool.", "smell of oranges.",
    "Obvious exits are: northeast, and west.", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "Orange Tsoda Pool", "combat title")
assert(table.concat(rooms[1].exits, ",") == "northeast,west")
assert(rooms[1].fingerprint == "Orange Tsoda Pool|northeast,west")

-- 3. look <target> (no exits line) yields nothing
feed({ "You look at girl", "A pretty girl looks very ill.",
    "  indented flavour", "She is human.", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 0, "target look made a room")

-- 4. no prompt at all: reported once, block still closes
S.out = {}
local many = { "Some Room", "  desc", "Obvious exits are: north.", "x" }
for i = 1, rmap.settings.maxBlockLines + 10 do many[#many + 1] = "line" end
feed(many)
assert(#rooms == 1 and rooms[1].name == "Some Room", "flush on overflow")
local out = table.concat(S.out)
assert(out:find("no usable prompt", 1, true), "no report")
assert(select(2, out:gsub("no usable prompt", "")) == 1, "reported repeatedly")

-- 5. fingerprint is exit-order independent; noise inside wrapped exits
feed({ "Title", "  d", "Obvious exits are: west, and east.", "x", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(rooms[1].fingerprint == "Title|east,west", rooms[1].fingerprint)
feed({ "Title", "  d", "Obvious exits are: north,", " *** NEW ROUND ***",
    "and south.", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(rooms[1].fingerprint == "Title|north,south", rooms[1].fingerprint)
-- description whose first line is only the two-space indent (seen live:
-- "Path leading to the playground")
feed({ "Path leading", "  ", "Along the path there are shrubs.",
    " The sun shines.", "Obvious exits are: north, and south.", "a nurse",
    "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "Path leading", "blank desc line")
-- first description line indented 4 spaces, no 2-space line at all
feed({ "You are flying.", "Jade Street", "    You arrived at the north end.",
    "This area is plain.", " The sun shines.",
    "Obvious exits are: north, and south.", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "Jade Street", "4-space desc")
-- 4-space line above the 2-space line is description, not the title
feed({ "North Path", "    You arrived.", "  More text.", " The sun shines.",
    "Obvious exits are: north.", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "North Path", "4+2 desc")
-- multi-paragraph description: a fragment above the 2nd paragraph is not a title
feed({ "You are flying.", "A dense fog", "  You float in mist.",
    "you are not alone here.", "  This is the realm.", " It is dark.",
    "Obvious exits are: east, and west.", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "A dense fog", "2nd paragraph")
-- 10-space first line, 8-space second paragraph, trailing-space title
feed({ "Light Room ", "          First line.", "into every corner.  ",
    "        Second para.", " It is lit.", "Obvious exits are: up.",
    "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "Light Room", "10-space")
-- description-less room (title, light sentence, exits) and no-exits room
feed({ "Over the Rift", " The sky is black.", "Obvious exits are: up.",
    "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "Over the Rift", "no desc")
feed({ "An endless descent", "  Falling.", " It is dim.",
    "There are no obvious exits.", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and #rooms[1].exits == 0, "no exits")
-- prefixed prompt and negative Sp end a block
feed({ "Title", "  d", "Obvious exits are: up.", "EQ Tick: Hp: 1/1  Sp: -5/9  Ep: 1/1" })
assert(#rooms == 1, "EQ Tick prompt")
-- description with no indentation at all (Alchemist pub, live capture):
-- chatter and the flying line above the title must not hide it
feed({ "The golem looks at you and warns, 'Look out for the golems in the tower.'",
    "You are flying.", "The Soggy Scientist",
    "This building seems a fairly popular place to be between lectures. The",
    "bartender is a quiet, efficent type, and the tables are full of happy",
    "clean and the clientele are mostly students.",
    "Look at the sign for commands you can use here.", "",
    "The only obvious exit is west.", "Alchemy Student", "Arten, the bartender",
    "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "The Soggy Scientist", "unindented desc: " .. tostring(rooms[1] and rooms[1].name))
assert(rooms[1].fingerprint == "The Soggy Scientist|west")
-- ...and sentence text before an exits line is not a room
feed({ "You see nothing special.", "The only obvious exit is west.",
    "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 0, "bare sentence became a room")
-- creation and first-login rooms are never raised; a real room in the same
-- segment still is (live capture: guild room, guide chatter, disclaimers room)
feed({ "Orange Tsoda Pool", "  An orange pool.", "Obvious exits are: northeast, and west.",
    "Wysoom guide gasps 'Hello master! To learn more about me, ask me about world",
    "      guide.  To learn more about how to play this game, ask me about getting",
    "      started.'", "You must read a few disclaimers once in the",
    "entire life of your character on Retromud.", "Welcome to RetroMUD",
    "  This fairly large room, is very clean and sterile looking.",
    "Official documents and pamphlets lie all over the place.", " It is fairly well lit here.",
    "Obvious exits are: enter, and skip.", "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
assert(#rooms == 1 and rooms[1].name == "Orange Tsoda Pool", "ignored room was raised: " .. #rooms)
for _, blk in ipairs({
    { "Character Creation", "Obvious exits are: enter, prev, and shrines." },
    { "Race Selection Room", "Obvious exits are: next, and prev." },
    { "Guild Selection Room", "The only obvious exit is next." },
    { "A room full of shrines", "Obvious exits are: agi, allstats, cha, con, dex, hermmax, int, maxsize, minsize, out, per, skillmax, spirmax, str, and wis." },
    { "A small shrine", "The only obvious exit is out." } }) do
    feed({ blk[1], "  A room.", blk[2], "Hp: 1/1  Sp: 1/1  Ep: 1/1" })
    assert(#rooms == 0, blk[1] .. " was raised")
end
print("capture_test ok")
