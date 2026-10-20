-- Lane F2 research probe (one instance): world text materials the cooked game has (name tags).
return function(T)
    local log = T.log
    local function try(tag, fn)
        local ok, err = pcall(fn)
        if not ok then log("PT|info probe %s err %s", tag, tostring(err)) end
        return true
    end
    local function registry()
        local reg = StaticFindObject("/Script/AssetRegistry.Default__AssetRegistryHelpers"):GetAssetRegistry()
        local out = {}
        reg:GetAssetsByPath(FName("/Game"), out, true, false)
        local n = 0
        for i = 1, #out do
            local a = out[i]:get()
            local nm, c = a.AssetName:ToString(), a.AssetClass:ToString()
            local l = nm:lower()
            if c:find("Material") and (l:find("text") or l:find("font") or l:find("label") or l:find("billboard")) then
                n = n + 1; log("PT|info probe mat %s.%s class=%s", a.PackageName:ToString(), nm, c)
            end
        end
        local eng = {}
        reg:GetAssetsByPath(FName("/Engine/EngineMaterials"), eng, true, false)
        for i = 1, #eng do local a = eng[i]:get(); log("PT|info probe engmat %s class=%s", a.AssetName:ToString(), a.AssetClass:ToString()) end
        log("PT|info probe mats=%d engine=%d", n, #eng)
    end
    local function comps()
        for _, c in ipairs(FindAllOf("TextRenderComponent") or {}) do
            if c:IsValid() then log("PT|info probe textcomp %s owner=%s mat=%s text='%s'", T.name(c), T.cls(c:GetOwner()), T.name(c:GetMaterial(0)), c.Text:ToString()) end
        end
        for _, c in ipairs(FindAllOf("WidgetComponent") or {}) do
            if c:IsValid() then log("PT|info probe widgetcomp %s owner=%s", T.name(c), T.cls(c:GetOwner())) end
        end
    end
    return {
        T.onMap("RB_MainMenu", 90),
        { check = "probe_registry", timeout = 5, cond = function() try("registry", registry); return true end },
        { run = function() T.console("open " .. T.GARAGE .. "?listen") end },
        T.onMap("RB_Garage", 120),
        { wait = 8 },
        { check = "probe_comps", timeout = 5, cond = function() try("comps", comps); return true end },
    }
end
