-- usage: lua smoke.lua <body.lua>   ('rmap help' responds; uninstall cleans)
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
local S = dofile(dir .. "/mudlet_stub.lua")
S.install()
S.load(arg[1])
S.fire("sysLoadEvent")
assert(S.alias("rmap help"), "rm alias not registered")
local text = table.concat(S.out)
assert(text:find("retromud", 1, true) and text:find("rmap help", 1, true),
    "no help text: " .. text)
io.write(text)
S.out = {}
S.alias("rmap bogus")
assert(table.concat(S.out):find("unknown command", 1, true))
-- help: command names coloured, tag only on the header line
assert(text:find("<cyan>rmap where ", 1, true), "help commands not coloured")
assert(select(2, text:gsub("%[rmap%]", "")) == 1, "help repeats the tag")
-- output format: coloured tag by level, new line only after prompt text
assert(not S.alias("rm somefile"), "rm alias still swallows rm <file>")
S.out = {}
rmap.out("hello", "ok")
assert(table.concat(S.out) == "<green>[rmap]<reset> hello\n", table.concat(S.out))
S.out = {}
rmap.out("nope", "skip")
assert(table.concat(S.out):find("^<yellow>%[rmap%]"), "skip colour")
S.out = {}
rmap.out("bad", "err")
assert(table.concat(S.out):find("^<red>%[rmap%]"), "err colour")
S.out = {}
rmap.out("  body", "plain")
assert(table.concat(S.out) == "  body\n", "plain has no tag")
S.out = {}
rmap.out("a <b>")
assert(table.concat(S.out):find("a <<b>", 1, true), "cecho tags escaped")
S.lastLine = "Hp: 1/1 >"            -- cursor is on the prompt's line
S.out = {}
rmap.out("x", "ok")
assert(S.out[1] == "\n", "no new line after prompt text")
S.lastLine = nil
-- script re-run while started: handlers come back without sysLoadEvent
S.load(arg[1])
assert(S.alias("rmap help") and #S.handlers > 0, "re-run left mapper dead")
S.fire("sysUninstallPackage", "retromud")
assert(#S.aliases == 0 and #S.handlers == 0, "uninstall left objects")
print("smoke ok")
