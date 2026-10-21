-- M2 session core. Host: listens on every gameplay map (S1, D14), checks each guest's hello (S4), gives the guest a
-- character next to its own (P1) and removes it before any map change. Guest: joins by direct IP (S3) and rejoins
-- after the host's map changes (S5, S6). Both: the other player's body is drawn visible (X13).
-- With no guest connected and no join address, nothing here changes the game.
local UEHelpers = require("UEHelpers")
local common = require("common")
local log = common.log

local MENU = "RB_MainMenu"
local HELLO_WAIT_MS = 20000
-- X11: a connect to a host that is still loading must wait instead of dying at 20 s
local CONNECT_TIMEOUT = 120
local CHAR_CLASS = "/Game/Characters/Player/PDP_MainCharacter.PDP_MainCharacter_C"

-- direct IP (M2): env var PT_JOIN=<ip:port>, else the first line of join.txt next to the mod's Scripts folder
local function joinAddress()
    local env = os.getenv("PT_JOIN")
    if env and env ~= "" then return env end
    local dir = (debug.getinfo(1, "S").source:match("^@(.*[\\/])Scripts[\\/]") or "")
    local f = io.open(dir .. "join.txt", "r")
    if not f then return nil end
    local line = (f:read("l") or ""):match("^%s*(%S+)")
    f:close()
    return line
end
local JOIN = joinAddress()
-- guest: a session is wanted until the player quits to the menu or the host refuses us
local guestActive = JOIN ~= nil

local function world() return UEHelpers.GetWorld() end
-- destroyed actors stay findable (and IsValid) until garbage collection; calling into them can crash the game
local function valid(o) return o ~= nil and o:IsValid() and not o:HasAnyInternalFlags(EInternalObjectFlags.PendingKill) end
local function fullName(o) return valid(o) and o:GetFullName() or "none" end
local function same(a, b) return valid(a) and valid(b) and a:GetFullName() == b:GetFullName() end
local function mapOf(w) return valid(w) and UEHelpers.GetGameplayStatics():GetCurrentLevelName(w, true):ToString() or "none" end
local function inWorld(o, w) return valid(o) and valid(o:GetWorld()) and same(o:GetWorld(), w) end
local function console(cmd)
    UEHelpers.GetKismetSystemLibrary():ExecuteConsoleCommand(world(), cmd, UEHelpers.GetPlayerController())
end
local function listening(w)
    if not valid(w) then return false end
    local d = w.NetDriver
    return valid(d) and not d.ServerConnection:IsValid()
end
local function localPC(w)
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if inWorld(pc, w) and pc:IsLocalController() then return pc end
    end
end
local function charManager()
    for _, m in ipairs(FindAllOf("BP_MainCharacterManager_C") or {}) do if valid(m) then return m end end
end

local function gameVersion()
    return StaticFindObject("/Script/EngineSettings.Default__GeneralProjectSettings").ProjectVersion:ToString()
end
local function gameBuild() return PTNative_GameBuild and PTNative_GameBuild() or 0 end
-- S4 hello, guest -> host over the stock reliable ServerChangeName RPC; the host puts the login name back afterwards.
-- Never rewrite the hooked RPC's string parameter: that corrupted the host's heap (docs/spikes/M2-session.md).
local function hello()
    return string.format("PT|hello mod=%s protocol=%d game=%s build=%d", common.MOD_VERSION, common.PROTOCOL_VERSION,
        gameVersion(), gameBuild())
end
local function parseHello(s)
    if not s:find("^PT|hello ") then return nil end
    local h = {}
    for k, v in s:gmatch("(%w+)=(%S*)") do h[k] = v end
    return h
end

-- X13: every character is drawn with an invisible material (first-person game), its mesh's own materials too. Give
-- the other player's body a cooked cloth material, falling back to the engine grid; never touch our own.
local BODY = { "/Game/Env/Generic/Props/Cloth/MI_GenManMade_Cloth_01.MI_GenManMade_Cloth_01",
               "/Engine/EngineMaterials/WorldGridMaterial.WorldGridMaterial" }
local changed = {} -- character full name -> original materials
local function visibleMaterial()
    for _, path in ipairs(BODY) do
        local m = StaticFindObject(path)
        if not valid(m) then m = LoadAsset(path) end
        if valid(m) then return m end
    end
end
local function setBody(c, visible)
    local mesh, key = c.Mesh, c:GetFullName()
    if not valid(mesh) or (visible and changed[key]) or (not visible and not changed[key]) then return end
    if visible then
        local orig = {}
        for i = 0, mesh:GetNumMaterials() - 1 do
            orig[i] = mesh:GetMaterial(i)
            mesh:SetMaterial(i, visibleMaterial())
        end
        changed[key] = orig
    else
        for i, m in pairs(changed[key]) do mesh:SetMaterial(i, m) end
        changed[key] = nil
    end
    log("PT|session body %s visible=%s material=%s", key, tostring(visible), fullName(mesh:GetMaterial(0)))
end
-- Every PDP_MainCharacter binds these to the process's single-player managers (BP_MainCharacterManager CommandEnterCar /
-- CommandExitCar, storm and feedback managers), so the local player's enter-car also ran on the other player's character:
-- it attached itself to the car, replicated to the guest and dropped them through the map (playtest 2026-10-20).
-- Only events: a muted call returns zeros, so a pipeline step with a return value (FOVZoomPipelineStep: max(Input - zoom, 25))
-- would clamp the local player's FOV to 25 (playtest 2 "weird FOV"). The other player's zoom is 0 on our side, so it may run.
-- ReceiveHit: only fall damage (to the process's one player health), so the other player's landing must not hurt us (health.lua).
local LOCAL_ONLY = "CommandEnterCar|Exit Car|PlayerEnteredStorm|PlayerExitStorm|LongInventoryInteract|On player Burst feedback|On Player Ambient Feedback|ReceiveHit"
local function isolate(c, remote)
    if not PTNative_Mute then return end
    if remote then PTNative_Mute(c:GetAddress(), LOCAL_ONLY) else PTNative_Unmute(c:GetAddress()) end
end
local function refreshBodies()
    local w = world()
    local pc, cm = localPC(w), charManager()
    if not pc then return end
    -- ours: the pawn, or the manager's character while we sit in the car
    local own = cm and cm.CharacterActor
    for _, c in ipairs(FindAllOf("BaseCharacter") or {}) do
        if inWorld(c, w) then
            local remote = not same(c, pc.Pawn) and not same(c, own)
            isolate(c, remote)
            setBody(c, remote)
        end
    end
end

-- host --------------------------------------------------------------------------------------------------------------

local greeted = {} -- remote PC full name -> true once its hello was accepted

local function refuse(pc, reason)
    log("PT|session refused %s: %s", fullName(pc), reason)
    local text = FText("Pacific Together: " .. reason)
    pc:ClientWasKicked(text)
    pc:ClientReturnToMainMenuWithTextReason(text)
end

-- returns false while there is nothing to spawn next to yet and last is not set
local function spawnFor(pc, last)
    local w = pc:GetWorld()
    local me, cm = localPC(w), charManager()
    local own = cm and cm.CharacterActor
    local base = me and me.Pawn
    if not valid(base) then base = own end
    local cls = valid(own) and own:GetClass() or StaticFindObject(CHAR_CLASS)
    if not valid(base) or not valid(cls) then
        if not last then return false end
        log("PT|error session no host pawn or character class to spawn next to (%s)", fullName(base))
        return true
    end
    -- next to whatever the host controls (character or car); the spawn moves it out of collisions
    local l, r = base:K2_GetActorLocation(), base:GetActorRightVector()
    local yaw = base:K2_GetActorRotation().Yaw
    local xf = { Rotation = { X = 0, Y = 0, Z = math.sin(math.rad(yaw) / 2), W = math.cos(math.rad(yaw) / 2) },
                 Translation = { X = l.X + r.X * 150, Y = l.Y + r.Y * 150, Z = l.Z + 50 }, Scale3D = { X = 1, Y = 1, Z = 1 } }
    local gs = UEHelpers.GetGameplayStatics()
    local c = gs:FinishSpawningActor(gs:BeginDeferredActorSpawnFromClass(w, cls, xf, 2, nil), xf)
    if not valid(c) then
        log("PT|error session spawn failed for %s", fullName(pc))
        return true
    end
    pc:Possess(c)
    -- the game's single-player manager follows the newest character; it must keep the host's
    if cm and valid(own) and not same(cm.CharacterActor, own) then cm.CharacterActor = own end
    log("PT|session spawned %s for %s possessed=%s manager=%s", fullName(c), fullName(pc), tostring(same(pc.Pawn, c)), fullName(cm and cm.CharacterActor))
    refreshBodies()
    return true
end

local function onHello(pc, s)
    local h = parseHello(s:get():ToString())
    if not h then return end
    local key = pc:GetFullName()
    if greeted[key] then return end
    -- the login name, before the engine applies the hello as the new name
    local name = valid(pc.PlayerState) and pc.PlayerState:GetPlayerName():ToString() or "Guest"
    local mine = { mod = common.MOD_VERSION, protocol = tostring(common.PROTOCOL_VERSION), game = gameVersion(), build = tostring(gameBuild()) }
    log("PT|session hello from %s mod=%s protocol=%s game=%s build=%s", key, tostring(h.mod), tostring(h.protocol), tostring(h.game), tostring(h.build))
    for _, k in ipairs({ "mod", "protocol", "game", "build" }) do
        if h[k] ~= mine[k] then
            refuse(pc, string.format("%s mismatch: host has %s, you have %s. Both players need the same game build and mod version.", k, mine[k], tostring(h[k])))
            return
        end
    end
    greeted[key] = true
    -- outside the RPC's hook, so the spawn's own hooks and Blueprint events do not run nested in it. A guest that
    -- connects while the host still loads a zone logs in before the host's own character exists: look again each second.
    local function try(n)
        ExecuteInGameThreadWithDelay(n == 0 and 100 or 1000, function()
            local ok, err = pcall(function()
                if not valid(pc) or not greeted[key] then return end
                if n == 0 then UEHelpers.GetGameModeBase():ChangeName(pc, name, false) end
                if not spawnFor(pc, n >= 60) then try(n + 1) end
            end)
            if not ok then log("PT|error session spawn %s", tostring(err)) end
        end)
    end
    try(0)
end

local function onLogin(pc)
    if pc:IsLocalController() then return end
    local key = pc:GetFullName()
    log("PT|session login %s", key)
    ExecuteInGameThreadWithDelay(HELLO_WAIT_MS, function()
        if valid(pc) and not greeted[key] and listening(pc:GetWorld()) then
            refuse(pc, "no handshake received. Install the same Pacific Together version as the host.")
        end
    end)
end

-- the reference saw the host crash tearing down a world that still had the guest's character in it
local function removeRemoteCharacters(w)
    local n = 0
    for _, pc in ipairs(FindAllOf("PlayerController") or {}) do
        if inWorld(pc, w) and not pc:IsLocalController() and valid(pc.Pawn) then
            local p = pc.Pawn
            pc:UnPossess()
            p:K2_DestroyActor()
            n = n + 1
        end
    end
    greeted = {}
    if n > 0 then log("PT|session cleanup removed=%d map=%s", n, mapOf(w)) end
end

-- guest -------------------------------------------------------------------------------------------------------------

local attempt, lastJoin = 0, -100
local function join()
    -- the boot menu load and the start-up both ask; one open at a time
    if not guestActive or mapOf(world()) ~= MENU or os.time() - lastJoin < 5 then return end
    attempt, lastJoin = attempt + 1, os.time()
    local mine = attempt
    StaticFindObject("/Script/OnlineSubsystemUtils.Default__IpNetDriver").ResolutionConnectionTimeout = CONNECT_TIMEOUT
    log("PT|session join %s attempt=%d", JOIN, mine)
    console("open " .. JOIN)
    -- a connect that fails without a map load leaves us in the menu: try again once it has surely timed out
    ExecuteInGameThreadWithDelay((CONNECT_TIMEOUT + 10) * 1000, function() if mine == attempt then join() end end)
end

-- hooks -------------------------------------------------------------------------------------------------------------

local function hook(fn, pre)
    local ok, err = pcall(RegisterHook, fn, function(...)
        local okc, e = pcall(pre, ...)
        if not okc then log("PT|error session %s %s", fn, tostring(e)) end
    end)
    if not ok then log("PT|error session hook %s %s", fn, tostring(err)) end
end

local hooked = false
local function hookAll()
    if hooked then return end
    hooked = true
    -- PostLogin's native event for every joining player (K2_PostLogin never fires: no Blueprint implements it)
    hook("/Script/Engine.GameModeBase:HandleStartingNewPlayer", function(gm, pc) onLogin(pc:get()) end)
    hook("/Script/Engine.PlayerController:ServerChangeName", function(self, s)
        local pc = self:get()
        if pc:HasAuthority() and not pc:IsLocalController() then onHello(pc, s) end
    end)
    -- the server set up our controller: say hello
    hook("/Script/Engine.PlayerController:ClientSetHUD", function(self)
        local pc = self:get()
        if JOIN and guestActive and common.netMode() == "client" and pc:IsLocalController() then
            pc:ServerChangeName(hello())
            log("PT|session hello sent")
        end
    end)
    hook("/Script/Engine.PlayerController:ClientWasKicked", function(self, reason)
        if not self:get():IsLocalController() then return end
        guestActive = false
        if PTNative_SetRejoin then PTNative_SetRejoin("") end
        log("PT|session refused by host: %s", reason:get():ToString())
    end)
    hook("/Script/Engine.PlayerController:ClientRestart", function(self, pawn)
        local pc, cm = self:get(), charManager()
        if not pc:IsLocalController() or common.netMode() ~= "client" then return end
        -- the guest's own managers follow its own character
        if cm and valid(pawn:get()) and not same(cm.CharacterActor, pawn:get()) then cm.CharacterActor = pawn:get() end
        -- the host's character is replicated by now (we spawn next to it); look again once for a late one.
        -- shortcut: a host character that becomes relevant later (far apart in a zone) stays invisible; hook its arrival in M3/M4
        -- (NotifyOnNewObject would fire on the loading thread)
        refreshBodies()
        ExecuteInGameThreadWithDelay(3000, function() pcall(refreshBodies) end)
    end)
    -- the save manager starts most native travel: remove the guest's character before the travel is even queued
    -- (removing it in the LoadMap pre-hook alone crashed the host's next map load, seen before the s:set heap fix;
    -- run travel (BaseRouteState::TravelTo) has only that fallback, untested)
    for _, f in ipairs({ "UserNewGame", "UserLoadGame", "LoadGame", "LoadFromCheckpoint", "Rinse", "LoadGameCmd", "LoadBookmarkCmd", "QuitToMenu" }) do
        hook("/Script/PenDriverPro.BaseSaveGameManager:" .. f, function()
            local w = world()
            if listening(w) then removeRemoteCharacters(w) end
            -- leaving on purpose ends the guest's session
            if f == "QuitToMenu" and common.netMode() == "client" and guestActive then
                guestActive = false
                if PTNative_SetRejoin then PTNative_SetRejoin("") end
                log("PT|session left")
            end
        end)
    end
end

RegisterLoadMapPreHook(function(engine, worldp, url, pending)
    local ok, err = pcall(function()
        local w = worldp:get()
        if not valid(pending:get()) and listening(w) then removeRemoteCharacters(w) end
        changed = {}
        if PTNative_MuteClear then PTNative_MuteClear() end
    end)
    if not ok then log("PT|error session loadmap pre %s", tostring(err)) end
end)

RegisterLoadMapPostHook(function(engine, worldp)
    local ok, err = pcall(function()
        hookAll()
        local m = mapOf(worldp:get())
        if JOIN and guestActive and m == MENU then ExecuteInGameThreadWithDelay(2000, join) end
    end)
    if not ok then log("PT|error session loadmap post %s", tostring(err)) end
end)

-- the native layer registers its functions only after the scripts started
ExecuteInGameThreadWithDelay(1000, function()
    hookAll()
    local host = JOIN == nil
    if host and not PTNative_SetAutoListen then log("PT|error session native layer missing, cannot host") end
    local patched = host and PTNative_SetAutoListen and PTNative_SetAutoListen(true)
    log("PT|session ready role=%s join=%s autolisten=%s game=%s build=%d", host and "host" or "guest", tostring(JOIN), tostring(patched), gameVersion(), gameBuild())
    if not host then
        -- the host's map changes drop us: go straight back to the host instead of through the menu (native Browse swap)
        StaticFindObject("/Script/OnlineSubsystemUtils.Default__IpNetDriver").ResolutionConnectionTimeout = CONNECT_TIMEOUT
        log("PT|session rejoin without menu=%s", tostring(PTNative_SetRejoin and PTNative_SetRejoin(JOIN)))
        join()
    end
end)

-- for overlay.lua
return { join = JOIN, wanted = function() return guestActive end }
