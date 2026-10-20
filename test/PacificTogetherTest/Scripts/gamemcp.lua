-- Helpers for the game MCP (tools/gamemcp/server.py). They run through the live console (repl.lua), so they are in scope there
-- as plain names. Test copies only, never shipped.
-- long object names keep their class and their tail (the part that tells instances apart)
local function clip(s, n)
    s = tostring(s)
    if #s <= n then return s end
    local cls = s:match("^(%w+) /")
    return cls and (cls .. " ..." .. s:sub(-60)) or (s:sub(1, n) .. "...")
end

return function(T)
    -- "Class /Path.Obj:Sub" (a GetFullName), a bare path, or a class name (first live instance)
    function T.mcp_obj(s)
        local path = s:match("^%S+ (/.*)$") or s
        local o
        if path:find("/", 1, true) then o = StaticFindObject(path) end
        if not (o and o:IsValid()) then o = FindFirstOf(s) end
        if not (o and o:IsValid()) then o = FindObject("Class", s) end
        assert(o and o:IsValid(), "no object or class found for '" .. s .. "'")
        return o
    end

    -- live objects of a class in the current world (CDOs and other worlds' leftovers dropped unless anyWorld)
    function T.mcp_find(class, limit, anyWorld)
        local res, total = {}, 0
        for _, o in ipairs(FindAllOf(class) or {}) do
            if o:IsValid() then
                local n = o:GetFullName()
                if not n:find("Default__", 1, true) and (anyWorld or select(2, pcall(T.inWorld, o)) == true) then
                    total = total + 1
                    if total <= limit then res[#res + 1] = n end
                end
            end
        end
        res[#res + 1] = string.format("-- %d match(es)%s", total, total > limit and (", first " .. limit .. " shown") or "")
        return table.concat(res, "\n")
    end

    -- properties (with the object's current values) and functions (with parameters) of an object, own class first then parents
    function T.mcp_describe(target)
        local o = T.mcp_obj(target)
        local isClass = pcall(function() return o:GetSuperStruct():IsValid() end) and o:GetFullName():match("^%w*Class ")
        local cls = isClass and o or o:GetClass()
        local lines = { (isClass and "class " or "object ") .. o:GetFullName() }
        local c, depth = cls, 0
        while c and c:IsValid() and depth < 12 do
            lines[#lines + 1] = "== " .. c:GetFName():ToString()
            c:ForEachProperty(function(p)
                local name = p:GetFName():ToString()
                local ty = select(2, pcall(function() return p:GetClass():GetFName():ToString() end))
                local v = ""
                if not isClass then
                    local ok, val = pcall(function() return o[name] end)
                    v = " = " .. clip(ok and T.show(val) or "<unreadable>", 100)
                end
                lines[#lines + 1] = string.format("  prop %s : %s%s", name, ty, v)
            end)
            c:ForEachFunction(function(f)
                local ps = {}
                f:ForEachProperty(function(p)
                    local pn = p:GetFName():ToString()
                    ps[#ps + 1] = pn .. ":" .. tostring(select(2, pcall(function() return p:GetClass():GetFName():ToString():gsub("Property$", "") end)))
                end)
                lines[#lines + 1] = string.format("  fn %s(%s)", f:GetFName():ToString(), table.concat(ps, ", "))
            end)
            c = c:GetSuperStruct(); depth = depth + 1
        end
        return table.concat(lines, "\n")
    end

    -- call obj:fn(...); returns every result (out params of a UFunction come back as extra results in UE4SS Lua)
    function T.mcp_call(target, fn, ...)
        local o = T.mcp_obj(target)
        local f = o[fn]
        assert(f ~= nil, "no member '" .. fn .. "' on " .. o:GetFullName())
        local res = table.pack(f(o, ...))
        local parts = {}
        for i = 1, res.n do parts[i] = T.show(res[i]) end
        return #parts == 0 and "(no return value)" or table.concat(parts, "\n")
    end
end
