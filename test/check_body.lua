-- usage: lua check_body.lua <body.lua>
-- Loads the body (syntax check), runs it plus the load event against the
-- stub, and fails if any global other than `rm` was added or changed.
local dir = arg[0]:match("^(.*)/[^/]*$") or "."
local S = dofile(dir .. "/mudlet_stub.lua")
S.install()
local before = {}
for k, v in pairs(_G) do before[k] = v end
local ok, err = pcall(function()
    S.load(arg[1])
    S.fire("sysLoadEvent")
end)
if not ok then print("ERROR " .. tostring(err)) os.exit(1) end
local bad, seen = {}, {}
for _, t in ipairs({ _G, before }) do
    for k in pairs(t) do
        -- doSpeedWalk is a Mudlet-mandated global (60_speedwalk)
        if k ~= "rm" and k ~= "doSpeedWalk" and not seen[k] and before[k] ~= _G[k] then
            seen[k] = true
            bad[#bad + 1] = tostring(k)
        end
    end
end
table.sort(bad)
if #bad > 0 then
    print("LEAK " .. table.concat(bad, ", "))
    os.exit(1)
end
print("ok")
