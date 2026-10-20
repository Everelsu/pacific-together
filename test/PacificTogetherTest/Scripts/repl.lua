-- Live console for agents (tools/repl.ps1): run Lua in a running test game without relaunching it.
-- The client drops ue4ss/pt_repl/in.lua (first line "-- id=<id>"); we run it on the game thread and append
-- "=== id=<id> ok|err" + the result + "=== end id=<id>" to ue4ss/pt_repl/out.txt. Test copies only.
local DIR = "ue4ss/pt_repl/"

local function show(v, depth)
    depth = depth or 0
    if type(v) == "userdata" then
        local ok, s = pcall(function()
            if v.IsValid then return v:IsValid() and v:GetFullName() or "<invalid>" end
            if v.ToString then return v:ToString() end
            if v.get then return show(v:get(), depth) end
        end)
        return ok and s ~= nil and tostring(s) or tostring(v)
    end
    if type(v) == "table" and depth < 2 then
        local parts = {}
        for k, x in pairs(v) do
            if #parts >= 50 then parts[#parts + 1] = "..."; break end
            parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    end
    return tostring(v)
end

return function(T)
    T.show = show
    -- the repl scenario holds the session until tools/repl.ps1 -Stop drops this file
    function T.replStopped()
        local f = io.open(DIR .. "stop", "rb")
        if not f then return false end
        f:close(); os.remove(DIR .. "stop")
        return true
    end

    local function run(code)
        local lines = {}
        local env = setmetatable({ T = T, show = show, out = function(...)
            local t = {}
            for i = 1, select("#", ...) do t[i] = show((select(i, ...))) end
            lines[#lines + 1] = table.concat(t, "\t")
        end }, { __index = function(_, k) if T[k] ~= nil then return T[k] end return _G[k] end })
        -- expression first ("FindFirstOf('X')"), then a statement block
        local fn = load("return " .. code, "=repl", "t", env) or load(code, "=repl", "t", env)
        if not fn then
            local _, err = load(code, "=repl", "t", env)
            return false, tostring(err)
        end
        local res = table.pack(pcall(fn))
        if not res[1] then return false, tostring(res[2]) end
        for i = 2, res.n do lines[#lines + 1] = show(res[i]) end
        return true, table.concat(lines, "\n")
    end

    LoopInGameThreadWithDelay(250, function()
        local f = io.open(DIR .. "in.lua", "rb")
        if not f then return end
        local code = f:read("a")
        f:close(); os.remove(DIR .. "in.lua")
        local id = code:match("^%-%- id=(%S+)") or "?"
        local ok, result = run(code)
        local o = io.open(DIR .. "out.txt", "ab")
        if o then
            o:write(string.format("=== id=%s %s\n%s\n=== end id=%s\n", id, ok and "ok" or "err", result, id))
            o:close()
        end
        T.log("PT|repl id=%s %s", id, ok and "ok" or "err")
    end)
end
