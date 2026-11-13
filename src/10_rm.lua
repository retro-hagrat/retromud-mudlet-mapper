-- 10_rm: namespace, version, lifecycle, event wiring.
-- Contract (docs/design.md): one global namespace `rm`, nothing else leaks.
-- Load/install (sysLoadEvent, sysInstall) runs rm.start(), which runs the
-- init functions other modules appended to rm.inits (they build their
-- temp triggers/aliases/UI). sysUninstallPackage runs rm.stop(), which
-- kills every registered handler/trigger/alias id. Every id a module
-- creates must be tracked here via rm.on / rm.alias so teardown is total.

-- Re-running the script (Mudlet re-executes it on save): tear down first.
local wasStarted = rm and rm.started
if rm and rm.stop then rm.stop() end
rm = {}
rm.restart = wasStarted
rm.name = "retromud"
rm.version = "0.0.1"
rm.inits = {}
rm.started = false
rm.mapping = false
rm.ids = { handler = {}, trigger = {}, alias = {} }

-- One tagged line per message: "[rmap] text". level colours the tag:
-- "ok" green, "skip" yellow, "err" red, nil cyan, "plain" no tag, and
-- "markup" no tag with the caller's own cecho colours (help body).
-- Output can land on the prompt's line, so start a new line first
-- when the last line already has text.
-- getLines(from, to) excludes `to` (checked live), hence last + 1
local COLOR = { ok = "green", skip = "yellow", err = "red" }
function rm.out(text, level)
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

function rm.on(event, fn)
    local id = registerAnonymousEventHandler(event, fn)
    rm.ids.handler[#rm.ids.handler + 1] = id
    return id
end

function rm.alias(pattern, fn)
    -- unverified: tempAlias accepts a Lua function as its code argument
    local id = tempAlias(pattern, fn)
    rm.ids.alias[#rm.ids.alias + 1] = id
    return id
end

function rm.start()
    if rm.started then return end
    rm.started = true
    for i = 1, #rm.inits do rm.inits[i]() end
end

function rm.stop()
    for i = 1, #rm.ids.handler do
        killAnonymousEventHandler(rm.ids.handler[i])
    end
    for i = 1, #rm.ids.trigger do killTrigger(rm.ids.trigger[i]) end
    for i = 1, #rm.ids.alias do killAlias(rm.ids.alias[i]) end
    rm.job = nil
    if rm.ids.timer then killTimer(rm.ids.timer) end
    -- the one documented global exception (see 60_speedwalk)
    if doSpeedWalk == rm.speedwalk then doSpeedWalk = nil end
    rm.ids = { handler = {}, trigger = {}, alias = {} }
    rm.started = false
end

rm.on("sysLoadEvent", function() rm.start() end)
-- unverified: sysInstall is raised with (event, packageName) after an
-- .mpackage install, and after this script body has already run
rm.on("sysInstall", function(_, pkg)
    if pkg == rm.name then rm.start() end
end)
rm.on("sysUninstallPackage", function(_, pkg)
    if pkg == rm.name then rm.stop() end
end)
