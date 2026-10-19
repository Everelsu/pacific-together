-- Test bot for tools/run-test.ps1. Never shipped. Inert unless PT_SCENARIO is set.
local UEHelpers = require("UEHelpers")

local TAG = "[PacificTogetherTest] "
local ROLE = os.getenv("PT_ROLE") or "host"
local SCENARIO = os.getenv("PT_SCENARIO")
local HOST = os.getenv("PT_HOST") or "127.0.0.1:7777"
local MUTATE = os.getenv("PT_MUTATE") or ""
local GARAGE = "/Game/Maps/RunProto/RB_Garage"

local function log(fmt, ...) print(TAG .. string.format(fmt, ...) .. "\n") end

if not SCENARIO then return end

local function world() return UEHelpers.GetWorld() end

local function map()
    local w = world()
    return w:IsValid() and UEHelpers.GetGameplayStatics():GetCurrentLevelName(w, true):ToString() or "none"
end

local function netMode()
    local ksl, w = UEHelpers.GetKismetSystemLibrary(), world()
    if not w:IsValid() then return "none" end
    if ksl:IsStandalone(w) then return "standalone" end
    return ksl:IsServer(w) and "listen" or "client"
end

-- Only controllers of the current world: the previous map's controllers linger until garbage collection.
local function pcs()
    local w, n = world(), 0
    if not w:IsValid() then return 0 end
    local wn = w:GetFullName()
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if pc:IsValid() and pc:GetWorld():IsValid() and pc:GetWorld():GetFullName() == wn then n = n + 1 end
    end
    return n
end

local function state() return string.format("net=%s map=%s pcs=%d", netMode(), map(), pcs()) end

local function console(cmd)
    log("PT|console %s", cmd)
    UEHelpers.GetKismetSystemLibrary():ExecuteConsoleCommand(world(), cmd, UEHelpers.GetPlayerController())
end

-- Step kinds: {check=id, timeout=s, cond=fn, tick=fn(t)} | {wait=s} | {run=fn}
local function onMap(name, timeout) return { check = "map_" .. name, timeout = timeout, cond = function() return map() == name end } end

local FOREST = "/Game/Maps/Wilderness/Forest/Wilderness_Forest_01"
local function name(o) return (o and o:IsValid()) and o:GetFullName() or "none" end
local function cls(o) return (o and o:IsValid()) and o:GetClass():GetFName():ToString() or "none" end
local function first(c) for _, o in ipairs(FindAllOf(c) or {}) do if o:IsValid() then return o end end end
local function saveMgr() return first("BP_SaveGameManager_C") end
-- "/Game/Maps/X/Map" of the current world
local function mapPath() return world():GetFullName():match("^%S+ ([^%.]+)") end
-- NetDriver of the current world: listening = has a driver and no server connection
local function driver()
    local d = world().NetDriver
    if not d:IsValid() then return "driver=none" end
    return string.format("driver=%s server=%s clients=%d", d:GetFName():ToString(), tostring(d.ServerConnection:IsValid()), #d.ClientConnections)
end
local function listening()
    local d = world().NetDriver
    return d:IsValid() and not d.ServerConnection:IsValid()
end
local function quitToMenu()
    log("PT|info QuitToMenu")
    StaticFindObject("/Script/PenDriverPro.Default__BaseSaveGameManager"):QuitToMenu(world())
end


-- "connected" = net=client and the server's map (the pending connect already reports net=client in the menu)
local function join(id, mapName, timeout, retry)
    local nextTry = 0
    return { check = id, timeout = timeout, cond = function() return netMode() == "client" and map() == mapName end,
             tick = function(t)
                 if MUTATE == "skipconnect" or t < nextTry or map() ~= "RB_MainMenu" or netMode() == "client" then return end
                 nextTry = retry and t + retry or math.huge
                 console("open " .. HOST)
             end }
end

-- X3: aggregate every actor of the current world by class, Role, bReplicates, loaded-from-map and owner class
local RF_WasLoaded = 0x00080000
local function survey(tag)
    local wn, agg, n, bad = world():GetFullName(), {}, 0, 0
    for _, a in ipairs(FindAllOf("Actor") or {}) do
        local ok, key = pcall(function()
            if not a:IsValid() or a:GetWorld():GetFullName() ~= wn then return nil end
            return string.format("class=%s role=%s rep=%d loaded=%d owner=%s", cls(a), tostring(a.Role),
                a.bReplicates and 1 or 0, a:HasAnyFlags(RF_WasLoaded) and 1 or 0, cls(a.Owner))
        end)
        if not ok then bad = bad + 1 elseif key then agg[key] = (agg[key] or 0) + 1; n = n + 1 end
    end
    local keys = {}
    for k in pairs(agg) do keys[#keys + 1] = k end
    table.sort(keys)
    for _, k in ipairs(keys) do log("PT|actors side=%s tag=%s %s n=%d", ROLE, tag, k, agg[k]) end
    log("PT|info survey %s: %d actors, %d keys, %d errors, map=%s", tag, n, #keys, bad, map())
end

-- X1: log every UEngine::LoadMap. The FURL arrives as a Lua userdata; probe what it exposes.
local lm = { pre = 0, post = 0, preAt = 0, furl = nil }
local function probeURL(url)
    local r = { "type=" .. type(url) }
    local ok, s = pcall(tostring, url); r[#r + 1] = "tostring=" .. (ok and s or "err")
    for _, k in ipairs({ "Map", "Host", "Port", "Op", "Portal", "Protocol" }) do
        local okk, v = pcall(function() return url[k] end)
        r[#r + 1] = k .. "=" .. (okk and tostring(v) or "err(" .. tostring(v):sub(1, 60) .. ")")
    end
    local okg, g = pcall(function() return url:get() end)
    r[#r + 1] = "get=" .. (okg and tostring(g) or "err(" .. tostring(g):sub(1, 60) .. ")")
    local okc, c = pcall(function() return url() end)
    r[#r + 1] = "call=" .. (okc and tostring(c) or "err(" .. tostring(c):sub(1, 60) .. ")")
    return table.concat(r, " ")
end
local function onLoadMap(phase, engine, worldp, url, pending, err)
    local ok, msg = pcall(function()
        local w, p = worldp:get(), pending:get()
        local extra = ""
        if phase == "post" then
            local ksl = UEHelpers.GetKismetSystemLibrary()
            extra = string.format(" standalone=%s server=%s %s took=%ds", tostring(ksl:IsStandalone(w)), tostring(ksl:IsServer(w)),
                (function() local okd, d = pcall(driver); return okd and d or "driver=err" end)(), os.time() - lm.preAt)
        else
            lm.preAt = os.time()
        end
        if not lm.furl then lm.furl = probeURL(url); log("PT|info furl %s", lm.furl) end
        return string.format("engine=%s world=%s pending=%s pendingDriver=%s error='%s'%s", name(engine:get()), name(w), name(p),
            p:IsValid() and name(p.NetDriver) or "none", tostring(err), extra)
    end)
    lm[phase] = lm[phase] + 1
    log("PT|loadmap %s n=%d %s", phase, lm[phase], ok and msg or ("err " .. tostring(msg)))
end
RegisterLoadMapPreHook(function(...) onLoadMap("pre", ...) end)
RegisterLoadMapPostHook(function(...) onLoadMap("post", ...) end)

-- X11: timeouts of the IpNetDriver CDO and of every live driver
local function timeouts()
    local r = {}
    for _, d in ipairs(FindAllOf("NetDriver") or {}) do
        if d:IsValid() then r[#r + 1] = string.format("%s{init=%.0f conn=%.0f noTimeouts=%s}", d:GetFName():ToString(), d.InitialConnectTimeout, d.ConnectionTimeout, tostring(d.bNoTimeouts)) end
    end
    local cdo = StaticFindObject("/Script/OnlineSubsystemUtils.Default__IpNetDriver")
    return string.format("cdo{init=%.0f conn=%.0f} live=%s", cdo.InitialConnectTimeout, cdo.ConnectionTimeout, table.concat(r, ","))
end

-- X10: the runner snapshots this side's Saved\SaveGames and Saved\Config on every PT|snap line
local function snap(tag) log("PT|snap side=%s tag=%s", ROLE, tag) end
local blocking = MUTATE ~= "noblock"
local saveHooks = false
local function hookSaves()
    if saveHooks then return end
    saveHooks = true
    local function try(fn, pre, post)
        local ok, err = pcall(RegisterHook, fn, pre, post)
        log("PT|info hook %s ok=%s %s", fn, tostring(ok), ok and "" or tostring(err))
    end
    -- native UFunctions: pre-hooks cannot cancel; the slot param is redirected instead
    try("/Script/PenDriverPro.BaseSaveGameManager:SaveGame", function(self, slot, level, kind)
        log("PT|save SaveGame slot=%s level='%s' type=%s block=%s", tostring(slot:get()), tostring(level:get()), tostring(kind:get()), tostring(blocking))
        if blocking then slot:set(-1) end
    end, function(self, ...) log("PT|save SaveGame done") end)
    for _, f in ipairs({ "SaveCheckpoint", "MakeBookmark", "WriteUserSettings", "WriteGameplaySettingsToSlot", "Rinse", "SetCurrentSlot", "DeleteGame" }) do
        try("/Script/PenDriverPro.BaseSaveGameManager:" .. f, function() log("PT|save %s", f) end)
    end
    for _, f in ipairs({ "SaveGameToSlot", "AsyncSaveGameToSlot" }) do
        local owner = f == "SaveGameToSlot" and "/Script/Engine.GameplayStatics:" or "/Script/Engine.AsyncActionHandleSaveGame:"
        try(owner .. f, function() log("PT|save %s", f) end)
    end
    -- Blueprint gates (BP hooks run after the body, so out params can still be overwritten)
    local dir, mgr = first("BP_AutoSaveDirector_C"), saveMgr()
    if dir then
        local path = dir:GetClass():GetFullName():match("^%S+ (.+)$")
        try(path .. ":CanAutoSave", function(self, enabled)
            log("PT|save CanAutoSave was=%s block=%s", tostring(enabled:get()), tostring(blocking))
            if blocking then enabled:set(false) end
        end)
        try(path .. ":TriggerAutosave", function() log("PT|save TriggerAutosave") end)
    else
        log("PT|info no BP_AutoSaveDirector_C")
    end
    if mgr then
        local path = mgr:GetClass():GetFullName():match("^%S+ (.+)$")
        try(path .. ":CanUserSaveGame", function(self, can)
            log("PT|save CanUserSaveGame was=%s block=%s", tostring(can:get()), tostring(blocking))
            if blocking then can:set(false) end
        end)
    end
end
local function mgrState()
    local m = saveMgr()
    return m and string.format("slot=%s mode=%s", tostring(m:GetCurrentSlot()), tostring(m:GetActivePlayMode())) or "no manager"
end

local function dumpers(at)
    local steps = {}
    for _, f in ipairs({ "GenerateUHTCompatibleHeaders", "GenerateLuaTypes", "DumpUSMAP", "GenerateSDK" }) do
        table.insert(steps, { check = at .. "_" .. f, timeout = 0, cond = function()
            assert(type(_G[f]) == "function", f .. " not in this UE4SS build")
            local t0 = os.time()
            _G[f]()
            log("PT|info %s took %ds", f, os.time() - t0)
            return true
        end })
    end
    return steps
end

local scenarios = {
    boot = function() return { onMap("RB_MainMenu", 90) } end,

    listen = function()
        if ROLE == "host" then
            return {
                onMap("RB_MainMenu", 90),
                { wait = 5 },
                { run = function() console("open " .. GARAGE .. "?listen") end },
                { check = "host_listen_garage", timeout = 120, cond = function() return netMode() == "listen" and map() == "RB_Garage" end },
                { check = "host_two_pcs", timeout = 180, cond = function() return pcs() == 2 end },
            }
        end
        -- the host may still be loading, and a pending connect gives up after 20 s, so retry
        return { onMap("RB_MainMenu", 90), join("client_connected_garage", "RB_Garage", 210, 30) }
    end,

    -- X1 + X3 garage: the game's own travel (UserNewGame, QuitToMenu) with a client connected
    travel = function()
        local t0, newMap = 0, nil
        if ROLE == "host" then
            return {
                onMap("RB_MainMenu", 90),
                { wait = 5 },
                { run = function() console("open " .. GARAGE .. "?listen") end },
                { check = "host_listen_garage", timeout = 120, cond = function() return netMode() == "listen" and map() == "RB_Garage" end },
                { check = "host_two_pcs", timeout = 180, cond = function() return pcs() == 2 end },
                { wait = 20 },
                { run = function() survey("garage") end },
                { run = function()
                    lm.mark, t0 = lm.post, os.time()
                    log("PT|info UserNewGame(5, STORY) -> %s", tostring(saveMgr():UserNewGame(5, 1)))
                end },
                { check = "host_native_travel", timeout = 240, cond = function()
                    return lm.post > lm.mark and not ({ RB_Garage = 1, RB_MainMenu = 1, none = 1 })[map()]
                end },
                { run = function() newMap = mapPath(); log("PT|info native travel to %s in %ds, loadmaps pre=%d post=%d", newMap, os.time() - t0, lm.pre, lm.post) end },
                { wait = 5 },
                { check = "host_listen_after_native_travel", timeout = 5, cond = function() return netMode() == "listen" and listening() end },
                { run = function()
                    log("PT|info after native travel: %s %s", state(), driver())
                    if netMode() ~= "listen" and MUTATE ~= "norehost" then t0 = os.time(); console("servertravel " .. newMap .. "?listen") end
                end },
                { check = "host_listen_after_rehost", timeout = 240, cond = function() return netMode() == "listen" and listening() and map() ~= "none" end },
                { run = function() log("PT|info rehost took %ds: %s %s", os.time() - t0, state(), driver()) end },
                { check = "host_two_pcs_after_rehost", timeout = 300, cond = function() return pcs() == 2 end },
                { wait = 15 },
                { run = function() log("PT|info before quit: %s %s", state(), driver()); t0 = os.time(); quitToMenu() end },
                { check = "host_menu_after_quit", timeout = 180, cond = function() return map() == "RB_MainMenu" end },
                { run = function() log("PT|info quit took %ds", os.time() - t0) end },
                { wait = 15 },
            }
        end
        local left
        return {
            onMap("RB_MainMenu", 90),
            join("client_connected_garage", "RB_Garage", 210, 30),
            { wait = 20 },
            { run = function() survey("garage") end },
            { check = "client_left_garage", timeout = 300, cond = function() return map() ~= "RB_Garage" and map() ~= "none" end },
            { run = function() left = os.time(); log("PT|info client left the garage: %s", state()) end },
            { check = "client_at_menu_after_host_travel", timeout = 60, cond = function() return map() == "RB_MainMenu" end },
            { check = "client_rejoined_new_map", timeout = 400, cond = function()
                return netMode() == "client" and not ({ RB_Garage = 1, RB_MainMenu = 1, none = 1 })[map()]
            end, tick = (function()
                local nextTry = 0
                return function(t)
                    if t < nextTry or map() ~= "RB_MainMenu" or netMode() == "client" then return end
                    nextTry = t + 30
                    console("open " .. HOST)
                end
            end)() },
            { run = function() log("PT|info rejoined %ds after leaving: %s", os.time() - left, state()) end },
            { check = "client_menu_after_host_quit", timeout = 400, cond = function() return map() == "RB_MainMenu" end },
            { run = function() log("PT|info after host quit: %s", state()) end },
        }
    end,

    -- X11 + X3 zone: the client connects before the host starts a long zone load and must not time out
    zonejoin = function()
        if ROLE == "host" then
            return {
                onMap("RB_MainMenu", 90),
                { run = function() log("PT|info timeouts %s", timeouts()) end },
                { wait = 25 },
                { run = function() console("open " .. FOREST .. "?listen") end },
                { check = "host_listen_zone", timeout = 180, cond = function() return netMode() == "listen" and map() == "Wilderness_Forest_01" end },
                { check = "host_two_pcs", timeout = 120, cond = function() return pcs() == 2 end },
                { wait = 20 },
                { run = function() survey("zone") end },
                { wait = 30 },
            }
        end
        local opened = 0
        local live = MUTATE == "live"
        return {
            onMap("RB_MainMenu", 90),
            { run = function() log("PT|info timeouts %s", timeouts()); opened = os.time(); console("open " .. HOST) end },
            -- one open only: a timeout must show as a failure, not be hidden by a retry
            { check = "client_connected_zone", timeout = 150, cond = function() return netMode() == "client" and map() == "Wilderness_Forest_01" end,
              tick = function(t)
                  if live then
                      for _, d in ipairs(FindAllOf("NetDriver") or {}) do
                          if d:IsValid() and d.InitialConnectTimeout < 120 then d.InitialConnectTimeout = 120 end
                      end
                  end
                  if t % 2 == 0 then log("PT|info t=%d %s %s", t, state(), timeouts()) end
              end },
            { run = function() log("PT|info connected %ds after open", os.time() - opened) end },
            { wait = 20 },
            { run = function() survey("zone") end },
        }
    end,

    -- X10: a guest who played their own save (slot 6) joins, follows a map change; do the guest's saves change?
    guestsave = function()
        if ROLE == "host" then
            return {
                onMap("RB_MainMenu", 90),
                { wait = 5 },
                { run = function() console("open " .. GARAGE .. "?listen") end },
                { check = "host_listen_garage", timeout = 120, cond = function() return netMode() == "listen" and map() == "RB_Garage" end },
                { check = "host_two_pcs", timeout = 400, cond = function() return pcs() == 2 end },
                { wait = 40 },
                { run = function() console("servertravel " .. GARAGE .. "?listen") end },
                { wait = 10 },
                { check = "host_two_pcs_after_travel", timeout = 240, cond = function() return netMode() == "listen" and pcs() == 2 end },
                { wait = 120 },
            }
        end
        local worldName
        return {
            onMap("RB_MainMenu", 90),
            { wait = 5 },
            { run = function() log("PT|info own game: UserNewGame(6, STORY) -> %s", tostring(saveMgr():UserNewGame(6, 1))) end },
            { check = "client_own_game", timeout = 240, cond = function() return not ({ RB_MainMenu = 1, none = 1 })[map()] end },
            { wait = 20 },
            { run = function() log("PT|info own game %s %s", map(), mgrState()); quitToMenu() end },
            { check = "client_back_in_menu", timeout = 180, cond = function() return map() == "RB_MainMenu" end },
            { wait = 5 },
            { run = function() log("PT|info menu %s", mgrState()); hookSaves(); snap("menu") end },
            join("client_connected_garage", "RB_Garage", 300, 30),
            { run = function() worldName = world():GetFullName() end },
            { wait = 30 },
            { run = function() log("PT|info joined %s", mgrState()); snap("joined") end },
            { check = "client_followed_travel", timeout = 240, cond = function()
                return netMode() == "client" and map() == "RB_Garage" and world():GetFullName() ~= worldName and lm.post >= 2
            end },
            { wait = 30 },
            { run = function() log("PT|info travelled %s", mgrState()); snap("travelled") end },
            -- the game's own autosave path, then a direct save call
            { run = function()
                local d = first("BP_AutoSaveDirector_C")
                log("PT|info autosave director %s", name(d))
                d:FlagAutosave(); d:CheckFlagAndTrigger()
            end },
            { wait = 15 },
            { run = function() snap("autosave") end },
            { run = function() log("PT|info SaveGame -> %s", tostring(saveMgr():SaveGame(saveMgr():GetCurrentSlot(), "", 2))) end },
            { wait = 15 },
            { run = function() snap("savegame") end },
        }
    end,

    dump = function()
        local steps = { onMap("RB_MainMenu", 90), { wait = 5 } }
        for _, s in ipairs(dumpers("menu")) do table.insert(steps, s) end
        table.insert(steps, { run = function() console("open " .. GARAGE) end })
        table.insert(steps, onMap("RB_Garage", 120))
        table.insert(steps, { wait = 10 })
        for _, s in ipairs(dumpers("garage")) do table.insert(steps, s) end
        return steps
    end,
}

local function check(name, pass, detail)
    log("PT|check side=%s name=%s result=%s detail=%s", ROLE, name, pass and "PASS" or "FAIL", detail)
end

local make = scenarios[SCENARIO]
if not make then
    log("PT|error unknown scenario %s", SCENARIO)
    return
end
local steps = make()
local planned = 0
for _, s in ipairs(steps) do if s.check then planned = planned + 1 end end
log("PT|plan side=%s checks=%d scenario=%s mutate=%s", ROLE, planned, SCENARIO, MUTATE)

local i, started, loop = 1, os.time(), nil
loop = LoopInGameThreadWithDelay(1000, function()
    local s, t = steps[i], os.time() - started
    local finished = true
    if s.run then
        local ok, err = pcall(s.run)
        if not ok then log("PT|error step %d: %s", i, tostring(err)) end
    elseif s.wait then
        finished = t >= s.wait
    else
        -- errors during map loads are transient, so they count as "not yet" until the timeout
        local ok, r = pcall(s.cond)
        local pass = ok and r == true
        if pass or t >= s.timeout then
            local okd, d = pcall(state)
            check(s.check, pass, (ok and "" or "error=" .. tostring(r) .. " ") .. (okd and d or "") .. " t=" .. t)
        else
            finished = false
            if s.tick then
                local okt, err = pcall(s.tick, t)
                if not okt then log("PT|error step %d tick: %s", i, tostring(err)) end
            end
        end
    end
    if not finished then return end
    i, started = i + 1, os.time()
    if i > #steps then
        log("PT|done side=%s", ROLE)
        CancelDelayedAction(loop)
    end
end)
