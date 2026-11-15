-- 10_rm: namespace, version, lifecycle, event wiring.
-- Contract (docs/design.md): one global namespace `rmap`, nothing else leaks.
-- Load/install (sysLoadEvent, sysInstall) runs rmap.start(), which runs the
-- init functions other modules appended to rmap.inits (they build their
-- temp triggers/aliases/UI). sysUninstallPackage runs rmap.stop(), which
-- kills every registered handler/trigger/alias id. Every id a module
-- creates must be tracked here via rmap.on / rmap.alias so teardown is total.

-- Re-running the script (Mudlet re-executes it on save): tear down first.
local wasStarted = rmap and rmap.started
if rmap and rmap.stop then rmap.stop() end
rmap = {}
rmap.restart = wasStarted
rmap.name = "retromud"
rmap.version = "0.0.12"
rmap.inits = {}
rmap.started = false
rmap.mapping = false
rmap.ids = { handler = {}, trigger = {}, alias = {} }

-- One tagged line per message: "[rmap] text". level colours the tag:
-- "ok" green, "skip" yellow, "err" red, nil cyan, "plain" no tag, and
-- "markup" no tag with the caller's own cecho colours (help body).
-- Output can land on the prompt's line, so start a new line first
-- when the last line already has text.
-- getLines(from, to) excludes `to` (checked live), hence last + 1
local COLOR = { ok = "green", skip = "yellow", err = "red" }
function rmap.out(text, level)
    local last = getLastLineNumber("main")
    local cur = getLines(last, last + 1)[1]
    if cur and cur ~= "" then echo("\n") end
    if level ~= "markup" then text = text:gsub("<", "<<") end
    if level == "plain" or level == "markup" then
        cecho(text .. "\n")
    else
        cecho("<" .. (COLOR[level] or "cyan") .. ">[rmap]<reset> "
            .. text .. "\n")
    end
end

function rmap.on(event, fn)
    local id = registerAnonymousEventHandler(event, fn)
    rmap.ids.handler[#rmap.ids.handler + 1] = id
    return id
end

function rmap.alias(pattern, fn)
    -- unverified: tempAlias accepts a Lua function as its code argument
    local id = tempAlias(pattern, fn)
    rmap.ids.alias[#rmap.ids.alias + 1] = id
    return id
end

function rmap.start()
    if rmap.started then return end
    rmap.started = true
    for i = 1, #rmap.inits do rmap.inits[i]() end
end

function rmap.stop()
    for i = 1, #rmap.ids.handler do
        killAnonymousEventHandler(rmap.ids.handler[i])
    end
    for i = 1, #rmap.ids.trigger do killTrigger(rmap.ids.trigger[i]) end
    for i = 1, #rmap.ids.alias do killAlias(rmap.ids.alias[i]) end
    rmap.job = nil
    if rmap.ids.timer then killTimer(rmap.ids.timer) end
    -- the one documented global exception (see 60_speedwalk)
    if doSpeedWalk == rmap.speedwalk then doSpeedWalk = nil end
    rmap.ids = { handler = {}, trigger = {}, alias = {} }
    rmap.started = false
end

rmap.on("sysLoadEvent", function() rmap.start() end)
-- unverified: sysInstall is raised with (event, packageName) after an
-- .mpackage install, and after this script body has already run
rmap.on("sysInstall", function(_, pkg)
    if pkg == rmap.name then rmap.start() end
end)
rmap.on("sysUninstallPackage", function(_, pkg)
    if pkg == rmap.name then rmap.stop() end
end)
