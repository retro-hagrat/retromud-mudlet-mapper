-- 70_ui: the map pane (container "rmap.map") and the public API for the GUI.
-- Contract (retromud-mudlet-gui doc/design.md): the mapper owns the pane and
-- raises rmap.onUiReady(name); the GUI moves it. Methods return plain values,
-- or nil and a reason; they run the same code as the matching `rmap` alias.

local T = rmap.track
local NAME = "rmap.map"

local function build()
    if not (Adjustable and Adjustable.Container and Geyser and Geyser.Mapper) then return end
    local ok, box = pcall(function()
        local old = Geyser.windowList and Geyser.windowList[NAME]
        if old then return old end                 -- script re-run: reuse, never duplicate
        local c = Adjustable.Container:new({ name = NAME, titleText = "Map",
            x = "60%", y = "0", width = "40%", height = "50%" })
        Geyser.Mapper:new({ name = "rmap.mapper", x = 0, y = 0,
            width = "100%", height = "100%" }, c)
        return c
    end)
    if ok and box then
        rmap.pane = box
        raiseEvent("rmap.onUiReady", NAME)
    end
end

rmap.api = {
    version = 1,
    state = function() return T.state() end,
    position = function() return T.where() end,
    isMapping = function() return rmap.mapping end,
    busy = function() return rmap.job end,
    container = function() return rmap.pane and NAME or nil end,
    start = function() rmap.commands.start() return true end,
    stop = function() rmap.commands.stop() return true end,
    where = function()
        if not rmap.canRun() then return nil, "busy" end
        rmap.commands.where() return true
    end,
    scan = function()
        if not rmap.mapping then return nil, "mapping is off" end
        if not rmap.canRun() then return nil, "busy" end
        rmap.commands.scan() return true
    end,
    undo = function()
        if rmap.commands.undo() then return true end
        return nil, "nothing to undo, or busy"
    end,
}

rmap.inits[#rmap.inits + 1] = build
